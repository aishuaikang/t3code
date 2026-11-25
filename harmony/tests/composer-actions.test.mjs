import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
const model = await import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(readFileSync(
  new URL('../app/entry/src/main/ets/model/Models.ets', import.meta.url), 'utf8'))).toString('base64'));
const thread = { id: 't', runtimeMode: 'auto', interactionMode: 'default' };
const start = text => model.startTurnCommand(thread, text, 'command', 'message', '2026-11-14T00:00:00Z');
test('clear marks a fresh session without sending its control token or losing the original draft', () => {
  const command = start('/clear Explain this');
  assert.equal(command.message.text, 'Explain this'); assert.equal(command.freshContext, true);
  assert.equal(command.composerText, '/clear Explain this'); assert.equal(command.message.messageId, 'message');
  assert.equal(start('Please explain /clear').freshContext, undefined);
});
test('side and btw retain stable fork and send identities across journal retries', () => {
  for (const text of ['/side Quick question', '/btw Quick question']) {
    const first = start(text), retry = start(text);
    assert.deepEqual(first, retry); assert.equal(first.message.text, 'Quick question');
    assert.equal(first.threadId, 't'); assert.ok(first.sideThreadId); assert.ok(first.sideForkCommandId);
    assert.equal(first.composerText, text);
  }
});
test('a working conversation queues follow-up messages without interrupting its active run', () => {
  const active = { ...thread, session: { status: 'running', activeTurnId: 'active-run' } };
  const first = model.startTurnCommand(active, 'Follow up', 'next-command', 'next-message', 'now');
  assert.equal(first.dispatchMode.type, 'queue_after_active'); assert.equal(first.message.text, 'Follow up');
  assert.equal(first.threadId, active.id); assert.equal(active.session.activeTurnId, 'active-run');
  assert.equal(start('Idle message').dispatchMode, undefined);
  assert.equal(model.startTurnCommand(active, '/side Independent question', 'c', 'm', 'now').dispatchMode, undefined);
});
const source = readFileSync(new URL('../app/entry/src/main/ets/pages/Thread.ets', import.meta.url), 'utf8');
test('immediate follow-ups target the active run, while queue, clear, and side retain their own delivery rules', () => {
  const active = { ...thread, session: { status: 'running', activeTurnId: 'active-run' } };
  const send = text => model.startTurnCommand(active, text, 'c', 'm', 'now', 'steer');
  assert.deepEqual(send('Correction').dispatchMode, { type: 'steer_active', targetRunId: 'active-run' });
  assert.deepEqual(send('/clear New context').dispatchMode, { type: 'queue_after_active' });
  assert.equal(send('/side Side question').dispatchMode, undefined);
  assert.equal(model.startTurnCommand(thread, 'Idle', 'c', 'm', 'now', 'steer').dispatchMode, undefined);
});
const dispatch = source.slice(source.indexOf('  private async dispatchPending('), source.indexOf('  private reconcilePending(')).replaceAll('private ', '');
const finish = source.slice(source.indexOf('  private async finishPending('), source.indexOf('  private async dispatchPending(')).replaceAll('private ', '');
const { Fixture } = await import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(`
const WS={threadStartTurn:'dispatch'}; const router={pushUrl:p=>globalThis.__sideNavigation=p};
${readFileSync(new URL('../app/entry/src/main/ets/model/MessageQuote.ets',import.meta.url),'utf8').replace(/^import .*;$/gm,'')}
export class Fixture { active=true; calls=[]; params={environmentId:'e'}; state={thread:{worktreePath:'/work'}};
 draftQuote=null;
 imageUris=['image']; imageStore={clear:async()=>{}}; draftStore={save:async text=>{this.savedDraft=text}};
 journal={pending:null,clear:async()=>{this.journal.pending=null}}; rpc={call:async(tag,payload)=>{this.calls.push(payload)}};
 ${dispatch} ${finish}
}`)).toString('base64'));
test('side question forks before sending and retries the same two commands after a lost response', async () => {
  const page = new Fixture(), command = start('/side Quick question');
  page.rpc.call = async (tag, payload) => { page.calls.push(structuredClone(payload)); if (page.calls.length === 2) throw new Error('response lost'); };
  await assert.rejects(page.dispatchPending(command), /response lost/);
  await page.dispatchPending(command);
  assert.equal(page.calls[0].type, 'thread.fork'); assert.equal(page.calls[0].sideChat, true);
  assert.equal(page.calls[0].targetThreadId, command.sideThreadId);
  assert.deepEqual(page.calls.slice(0, 2), page.calls.slice(2));
  page.draft = '/side Quick question'; page.journal.pending = command;
  await page.finishPending(); assert.equal(page.savedDraft, ''); assert.equal(page.draft, '');
  assert.equal(globalThis.__sideNavigation.params.threadId, command.sideThreadId);
});
test('finishing a local command preserves any newer edited draft', async () => {
  const page = new Fixture(); page.journal.pending = start('/clear Old question'); page.draft = 'New question'; page.sendError = 'receipt lost';
  await page.finishPending(); assert.equal(page.draft, 'New question'); assert.equal(page.savedDraft, undefined);
  assert.equal(page.sendError, '');
});
