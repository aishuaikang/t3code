import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
const m = await import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(readFileSync(
  new URL('../app/entry/src/main/ets/model/Models.ets', import.meta.url), 'utf8'))).toString('base64'));
const attachment = { type: 'image', id: 'image', name: 'photo.png', mimeType: 'image/png', sizeBytes: 12 };
const run = (id, ordinal, extra = {}) => ({ id, threadId: 't', userMessageId: `m-${id}`, ordinal, status: 'queued',
  requestedAt: '2026-11-15T00:00:00Z', startedAt: null, completedAt: null, ...extra });
const message = (run, extra = {}) => ({ id: run.userMessageId, runId: run.id, role: 'user', text: run.id,
  streaming: false, attachments: [attachment], ...extra });
function fixture(runs = [run('one', 1), run('two', 2)], messages = runs.map(r => message(r))) {
  const state = new m.ThreadState();
  state.apply({ kind: 'snapshot', snapshotSequence: 1, projection: { thread: { id: 't' }, runs, messages,
    visibleTurnItems: [] } });
  return state;
}
const queue = s => m.queuedMessages(s.thread, s.messages);
const command = (s, id, action, text) => m.queuedMessageCommand(s.thread, s.messages, id, action, 'stable-command', text);

test('queue survives an abbreviated visible transcript and follows server queue positions', () => {
  const s = fixture([run('one', 1, { queuePosition: 2 }), run('two', 2, { queuePosition: 1 })]);
  assert.deepEqual(queue(s).map(q => q.runId), ['two', 'one']);
  assert.deepEqual(queue(s)[0].attachments, [attachment]);
  assert.deepEqual(m.transcriptRows(s.messages, [], s.thread.session, s.thread.latestTurn, [], s.thread.turns), []);
});
test('send now promotes into an active run and starts the selected run when stopped', () => {
  const s = fixture();
  assert.deepEqual(command(s, 'two', 'send'), { type: 'queued-run.start', commandId: 'stable-command', threadId: 't', runId: 'two' });
  s.apply({ kind: 'event', sequence: 2, event: { type: 'run.created', threadId: 't', payload: run('active', 3, { status: 'running', startedAt: 'now' }) } });
  assert.deepEqual(command(s, 'two', 'send'), { type: 'queued-message.promote-to-steer', commandId: 'stable-command', threadId: 't', queuedRunId: 'two', targetRunId: 'active' });
});
test('edit preserves remote attachment/context data by leaving it out of the edit command', () => {
  const s = fixture();
  assert.deepEqual(command(s, 'one', 'edit', 'Revised'), { type: 'queued-run.edit', commandId: 'stable-command', threadId: 't', runId: 'one', text: 'Revised' });
  assert.deepEqual(command(s, 'one', 'edit', '  '), { type: 'queued-run.edit', commandId: 'stable-command', threadId: 't', runId: 'one', text: '  ' });
  s.apply({ kind: 'event', sequence: 2, event: { type: 'message.updated', threadId: 't', payload: message(run('one', 1), { text: 'Revised' }) } });
  assert.equal(queue(s)[0].text, 'Revised'); assert.deepEqual(queue(s)[0].attachments, [attachment]);
});
test('cancelled queue entries disappear and stale actions cannot run against an already started message', () => {
  const s = fixture();
  assert.equal(command(s, 'one', 'delete').type, 'queued-run.cancel');
  s.apply({ kind: 'event', sequence: 2, event: { type: 'run.updated', threadId: 't', payload: run('one', 1, { status: 'cancelled', completedAt: 'now' }) } });
  assert.deepEqual(queue(s).map(q => q.runId), ['two']);
  assert.equal(command(s, 'one', 'send'), null);
  s.apply({ kind: 'event', sequence: 3, event: { type: 'run.updated', threadId: 't', payload: run('two', 2, { status: 'running', startedAt: 'now' }) } });
  assert.equal(queue(s).length, 0); assert.equal(command(s, 'two', 'edit', 'Too late'), null);
  assert.deepEqual(m.transcriptRows(s.messages, [], s.thread.session, s.thread.latestTurn, [], s.thread.turns).map(r => r.id), ['m-two']);
});
test('fresh sessions cannot steer and automatic or guest queue messages cannot be edited', () => {
  const runs = [run('fresh', 1, { freshContext: true }), run('auto', 2), run('guest', 3), run('active', 4, { status: 'running' })];
  const s = fixture(runs, [message(runs[0]), message(runs[1], { delegatedCompletion: {} }), message(runs[2], { context: { guest: {} } })]);
  assert.equal(command(s, 'fresh', 'send'), null);
  assert.equal(command(s, 'auto', 'edit', 'Changed'), null); assert.equal(command(s, 'auto', 'send'), null);
  assert.equal(command(s, 'guest', 'edit', 'Changed'), null); assert.equal(command(s, 'guest', 'delete').type, 'queued-run.cancel');
});

test('queue edit can replace or clear all attachments, rejects the ninth and preserves the source message',()=>{
 const s=fixture();const changed=[{...attachment,id:'replacement'}];
 assert.deepEqual(m.queuedMessageCommand(s.thread,s.messages,'one','edit','stable','Changed',changed).attachments,changed);
 assert.deepEqual(m.queuedMessageCommand(s.thread,s.messages,'one','edit','stable','Changed',[]).attachments,[]);
 assert.equal(m.queuedMessageCommand(s.thread,s.messages,'one','edit','stable','Changed',Array(9).fill(attachment)),null);
 assert.deepEqual(queue(s)[0].attachments,[attachment]);
});
test('queue edit accepts image-only content but rejects empty text when no attachments remain',()=>{
 const s=fixture(),changed=[{...attachment,id:'replacement'}];
 assert.deepEqual(m.queuedMessageCommand(s.thread,s.messages,'one','edit','stable','',changed),
  {type:'queued-run.edit',commandId:'stable',threadId:'t',runId:'one',text:'',attachments:changed});
 assert.equal(m.queuedMessageCommand(s.thread,s.messages,'one','edit','stable','  ',[]),null);
 const r=run('text',1),textOnly=fixture([r],[message(r,{attachments:[]})]);
 assert.equal(command(textOnly,'text','edit','  '),null);
});
