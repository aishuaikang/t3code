import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const model = await import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(
  readFileSync(new URL('../app/entry/src/main/ets/model/Models.ets', import.meta.url), 'utf8')
)).toString('base64'));
const time = n => `2026-11-14T00:00:${String(n).padStart(2, '0')}Z`;
const item = (id, type, second, extra = {}) => ({ id, threadId: 't', runId: 'r', type, ordinal: second,
  status: 'completed', title: null, startedAt: time(second), completedAt: time(second + 1), updatedAt: time(second + 1), ...extra });
const message = (id, role, second, extra = {}) => ({ id, threadId: 't', runId: 'r', role, text: id,
  streaming: false, createdAt: time(second), updatedAt: time(second), attachments: [], ...extra });
const run = (id = 'r', extra = {}) => ({ id, ordinal: 1, status: 'completed', requestedAt: time(0),
  startedAt: time(1), completedAt: time(17), ...extra });
function snapshot(items, messages = [], runs = [run()]) {
  if (items.length === 0 && messages.length > 0) items = messages.map((m, n) => item(`${m.id}-item`, `${m.role}_message`, n,
    { messageId: m.id, text: m.text, streaming: m.streaming, runId: m.runId, startedAt: m.createdAt, updatedAt: m.updatedAt, attachments: m.attachments }));
  return { kind: 'snapshot', snapshotSequence: 10, projection: { thread: { id: 't', title: 'Task' }, messages, runs,
    turnItems: items, visibleTurnItems: items.map((i, position) => ({ position, sourceThreadId: i.threadId, sourceItemId: i.id, item: i })) } };
}
function rows(state, expanded = []) {
  return model.transcriptRows(state.messages, state.activities, state.thread.session,
    state.thread.latestTurn, expanded, state.thread.turns, state.thread.subagents);
}

test('current visible turn items restore tool details, reasoning, plans and notices without duplicate messages', () => {
  const state = new model.ThreadState();
  const items = [item('u-item', 'user_message', 0, { messageId: 'u', text: 'Question', attachments: [] }),
    item('thought', 'reasoning', 2, { text: 'Considering the result', streaming: false }),
    item('cmd', 'command_execution', 3, { input: 'node --test', outputOmitted: true }),
    item('edit', 'file_change', 4, { fileName: 'app.ets', additions: 3, deletions: 1 }),
    item('plan', 'todo_list', 5, { explanation: 'Verify the fix', steps: [{ id: 'test', text: 'Test', status: 'completed' }] }),
    item('compact', 'compaction', 6, { summary: 'Earlier context summarized' }),
    item('notice', 'system_notice', 7, { message: 'Provider reconnected' }),
    item('a-item', 'assistant_message', 16, { messageId: 'a', text: 'Done', streaming: false })];
  state.apply(snapshot(items, [message('u', 'user', 0, { text: 'Question' }), message('a', 'assistant', 16, { text: 'Done' })]));
  assert.equal(state.messages.filter(m => m.id === 'a').length, 1);
  assert.ok(state.messages.some(m => m.role === 'reasoning' && m.text === 'Considering the result'));
  const timeline = model.threadTimeline(state.messages, state.activities, null);
  assert.ok(timeline.some(r => r.text === 'node --test' && r.itemId === 'cmd'));
  assert.ok(timeline.some(r => r.text.includes('app.ets') && r.detail.includes('+3')));
  assert.ok(timeline.some(r => r.detail.includes('Test')));
  assert.ok(timeline.some(r => r.text.includes('上下文')));
  assert.ok(timeline.some(r => r.detail.includes('Provider reconnected') || r.text.includes('Provider reconnected')));
});

test('a completed HTML preview stays in the conversation when its work log is folded', () => {
  const state = new model.ThreadState();
  const reference = { attachmentId: 'preview.html', title: 'Preview', height: 473, heights: [[320, 211], [375, 246]] };
  const items = [item('u-item', 'user_message', 0, { messageId: 'u', text: 'Show the screenshot' }),
    item('cmd', 'command_execution', 3, { input: 'capture screenshot' }),
    item('preview', 'dynamic_tool', 6, { toolName: 't3-code.html_render', outputOmitted: true, output: { htmlRender: reference } }),
    item('a-item', 'assistant_message', 12, { messageId: 'a', text: '[查看原图](/work/screenshot.png)' })];
  state.apply(snapshot(items));
  const folded = rows(state);
  assert.deepEqual(folded.map(row => row.kind), ['message', 'turn', 'html-render', 'message']);
  assert.deepEqual(folded[2].htmlRender, reference);
  assert.equal(folded[2].originalImageHref, '/work/screenshot.png');
  assert.deepEqual(rows(state, [folded[1].id]).filter(row => row.kind === 'html-render').map(row => row.id), [folded[2].id]);
});

test('an original image link only attaches to an unambiguous preview in the same reply', () => {
  const reference = { attachmentId: 'preview.html', title: 'Preview', height: 400 };
  const tool = item('preview', 'dynamic_tool', 6, { toolName: 't3-code.html_render', output: { htmlRender: reference } });
  const reply = item('reply', 'assistant_message', 12, { messageId: 'a', text: '[查看原图](/work/screenshot.png)' });
  for (const items of [
    [tool, { ...tool, id: 'other-preview', ordinal: 7 }, reply],
    [tool, { ...reply, runId: 'different-run' }],
    [tool, { ...reply, threadId: 'different-thread' }],
    [tool, { ...reply, text: 'Interactive chart. [查看原图](/work/chart.png)' }],
  ]) {
    const state = new model.ThreadState();
    state.apply(snapshot(items));
    const previews = rows(state).filter(row => row.kind === 'html-render');
    assert.ok(previews.length > 0);
    assert.ok(previews.every(row => row.originalImageHref === undefined));
  }
});

test('adjacent agents in a provider turn form a live group with distinct child destinations', () => {
  const state = new model.ThreadState();
  const agent = (id, n, providerTurnId = 'provider-turn') => item(`item-${id}`, 'subagent', n, {
    subagentId: id, origin: 'provider_native', providerTurnId, title: 'Subagent',
    childThreadId: `child-${id}`, status: 'running', progress: 'Inspecting the workspace'
  });
  state.apply(snapshot([agent('a', 2), agent('b', 3), agent('c', 4, 'different-turn'),
    item('log', 'assistant_message', 6, { messageId: 'log', text: 'Progress' }), agent('d', 7)]));
  const before = rows(state).filter((row) => row.kind === 'subagents');
  assert.deepEqual(before.map((row) => row.subagents.map((agent) => agent.childThreadId)), [['child-a', 'child-b'], ['child-c'], ['child-d']]);
  state.apply({ kind: 'event', sequence: 11, event: { type: 'subagent.updated', threadId: 't',
    payload: { id: 'b', threadId: 't', runId: 'r', childThreadId: 'child-b', status: 'completed', result: 'Review complete', updatedAt: time(18) } } });
  const after = rows(state).filter((row) => row.kind === 'subagents');
  assert.equal(after[0].id, before[0].id);
  assert.deepEqual(after[0].subagents.map((agent) => agent.status), ['running', 'completed']);
  assert.equal(after[0].subagents[1].result, 'Review complete');
  assert.equal(after[0].subagents[1].origin, 'provider_native');
});

test('recorded model switches stay on their user rows through live updates, history pagination and cache resume', () => {
  const state = new model.ThreadState();
  const selection = (model) => ({ instanceId: 'codex', model });
  const modelSwitch = { from: selection('previous-model'), to: selection('next-model') };
  const earlierSwitch = { from: selection('initial-model'), to: selection('previous-model') };
  const prompt = item('prompt', 'user_message', 4, { messageId: 'latest', text: 'Continue' });
  const base = snapshot([prompt], [message('latest', 'user', 4, { text: 'Continue' })]);
  state.apply({ ...base, hasMoreHistory: true, historyCursor: 'before-latest' });
  const before = rows(state);
  assert.equal(before[0].modelSwitch, undefined);
  state.apply({ kind: 'event', sequence: 11, event: { threadId: 't', type: 'turn-item.updated', payload: { ...prompt, modelSwitch } } });
  const after = model.reconcileTranscriptRows(before, rows(state));
  assert.deepEqual(after[0].modelSwitch, modelSwitch);
  state.apply({ kind: 'event', sequence: 12, event: { threadId: 't', type: 'message.updated', payload: message('latest', 'user', 4, { text: 'Continue' }) } });
  const older = item('older', 'user_message', 1, { text: 'Start', modelSwitch: earlierSwitch });
  assert.equal(state.mergeHistory({ snapshotSequence: 12, items: [{ position: 0, sourceThreadId: 't', sourceItemId: older.id, item: older }],
    nextCursor: null, hasMoreHistory: false }, 'before-latest', state.historyVersion()), true);
  const cached = new model.ThreadState();
  cached.restoreCached({ ...state.thread, messages: state.messages, activities: state.activities, syncSequence: 12 });
  assert.equal(cached.cursor(), 12);
  assert.deepEqual(rows(cached).filter(row => row.role === 'user').map(row => [row.id, row.modelSwitch]),
    [['older', earlierSwitch], ['latest', modelSwitch]]);
});

test('scheduled prompts retain a one-line preview and full content through the live feed, history and cache', () => {
  const state = new model.ThreadState();
  const text = 'Check the build\n\nReport any failing check.';
  const attachments = [{ type: 'file', id: 'attachment', name: 'details.txt', mimeType: 'text/plain', sizeBytes: 12 }];
  const prompt = (id, n, extra = {}) => item(`${id}-item`, 'user_message', n, { messageId: id, text, ...extra });
  const live = prompt('live', 5, { attachments });
  const recent = snapshot([prompt('scheduled', 3), prompt('manual', 4), live], [message('scheduled', 'user', 3, { text, scheduledTaskId: 'task' })]);
  state.apply({ ...recent, hasMoreHistory: true, historyCursor: 'older' });
  const before = rows(state);
  assert.equal(before.find(row => row.id === 'scheduled').automationPreview, 'Check the build');
  assert.equal(before.find(row => row.id === 'manual').automationPreview, undefined);

  state.apply({ kind: 'event', sequence: 11, event: { threadId: 't', type: 'turn-item.updated', payload: { ...live, scheduledTaskId: 'task' } } });
  const after = model.reconcileTranscriptRows(before, rows(state));
  assert.notEqual(after.find(row => row.id === 'live'), before.find(row => row.id === 'live'));
  assert.equal(after.find(row => row.id === 'live').automationPreview, 'Check the build');
  state.apply({ kind: 'event', sequence: 12, event: { threadId: 't', type: 'message.updated', payload: message('live', 'user', 5, { text, attachments }) } });

  const older = prompt('earlier', 1, { scheduledTaskId: 'task' });
  assert.equal(state.mergeHistory({ snapshotSequence: 12, items: [{ position: 0, sourceThreadId: 't', sourceItemId: older.id, item: older }],
    nextCursor: null, hasMoreHistory: false }, 'older', state.historyVersion()), true);
  const cached = new model.ThreadState();
  cached.restoreCached({ ...state.thread, messages: state.messages, activities: state.activities, syncSequence: 12 });
  const cachedRows = rows(cached);
  assert.equal(cached.cursor(), 12);
  assert.deepEqual(cachedRows.filter(row => row.automationPreview !== undefined).map(row => row.id), ['earlier', 'scheduled', 'live']);
  assert.equal(cachedRows.find(row => row.id === 'live').text, text);
  assert.deepEqual(cachedRows.find(row => row.id === 'live').attachments, attachments);
});

test('legacy automation prefixes are hidden only for messages with a server-generated schedule ID', () => {
  const state = new model.ThreadState();
  const prefix = '[Triggered by schedule task: Nightly]\r\n\r\n';
  const text = `${prefix}Check the build\n\nReport any failing check.`;
  state.apply(snapshot([], [message('manual', 'user', 2, { text }), message('scheduled-task-message:task:12:scheduled', 'user', 4, { text })]));
  const messages = rows(state).filter(row => row.role === 'user');
  assert.equal(messages[0].automationPreview, undefined);
  assert.equal(messages[0].text, text);
  assert.equal(messages[1].automationPreview, 'Check the build');
  assert.equal(messages[1].text, 'Check the build\n\nReport any failing check.');
});

test('live turn-item updates replace tool state and expanded detail survives later abbreviated events', () => {
  const state = new model.ThreadState();
  state.apply(snapshot([item('cmd', 'command_execution', 2, { status: 'running', input: 'node --test' })]));
  const updated = item('cmd', 'command_execution', 2, { input: 'node --test', outputOmitted: true, exitCode: 0 });
  state.apply({ kind: 'event', sequence: 11, event: { threadId: 't', type: 'turn-item.updated', payload: updated } });
  assert.equal(state.activities.length, 1);
  state.applyTurnItemDetail({ ...updated, output: 'All checks passed', outputOmitted: undefined });
  state.apply({ kind: 'event', sequence: 12, event: { threadId: 't', type: 'turn-item.updated', payload: updated } });
  const tool = model.threadTimeline(state.messages, state.activities, null)[0];
  assert.equal(tool.status, 'completed');
  assert.equal(tool.detail, 'All checks passed');
});

test('a delayed detail response cannot replace newer live output or poison its detail cache', () => {
  const state = new model.ThreadState();
  const older = item('cmd', 'command_execution', 2, { status: 'running', input: 'node --test', output: 'Checking 1/10' });
  state.apply(snapshot([older]));
  const latest = { ...older, status: 'completed', outputOmitted: true, output: undefined, updatedAt: time(5) };
  state.apply({ kind: 'event', sequence: 11, event: { threadId: 't', type: 'turn-item.updated', payload: latest } });
  state.applyTurnItemDetail({ ...latest, output: 'All 10 tests passed', outputOmitted: false });
  state.applyTurnItemDetail(older);
  let row = model.threadTimeline(state.messages, state.activities, null)[0];
  assert.equal(row.status, 'completed');
  assert.equal(row.detail, 'All 10 tests passed');
  state.apply({ kind: 'event', sequence: 12, event: { threadId: 't', type: 'turn-item.updated', payload: latest } });
  row = model.threadTimeline(state.messages, state.activities, null)[0];
  assert.equal(row.detail, 'All 10 tests passed');
  assert.equal(row.detailOmitted, false);
});

test('a delayed running detail cannot overwrite completed output before its first expansion', () => {
  const state = new model.ThreadState();
  const older = item('cmd', 'command_execution', 2, { status: 'running', input: 'node --test', output: 'Checking 1/10' });
  state.apply(snapshot([older]));
  state.apply({ kind: 'event', sequence: 11, event: { threadId: 't', type: 'turn-item.updated',
    payload: { ...older, status: 'completed', output: 'All 10 tests passed', updatedAt: time(5) } } });
  state.applyTurnItemDetail(older);
  const row = model.threadTimeline(state.messages, state.activities, null)[0];
  assert.equal(row.status, 'completed');
  assert.equal(row.detail, 'All 10 tests passed');
});

test('PC thread context records survive snapshots, live messages, cached history and row reconciliation', () => {
  const context = { version: 1, records: [{ version: 1, kind: 'thread', contextId: 'thread_source',
    environmentId: 'source-machine', threadId: 'actual-source-id', label: 'Original task', title: 'Original task' }] };
  const text = '[Original task](t3-context://v1/thread/thread_source) 继续';
  const state = new model.ThreadState();
  state.apply(snapshot([], [message('u', 'user', 0, { text, context })]));
  const before = rows(state);
  assert.deepEqual(before[0].context, context);
  const changed = { ...context, records: [{ ...context.records[0], threadId: 'different-source-id' }] };
  state.apply({ kind: 'event', sequence: 11, event: { threadId: 't', type: 'message.updated',
    payload: message('u', 'user', 0, { text, context: changed }) } });
  const after = model.reconcileTranscriptRows(before, rows(state));
  assert.notEqual(after[0], before[0]);
  assert.deepEqual(after[0].context, changed);
  const cached = new model.ThreadState();
  cached.restoreCached({ ...state.thread, messages: state.messages, activities: state.activities, syncSequence: 11 });
  assert.deepEqual(rows(cached)[0].context, changed);
});

test('an old cache that discarded PC thread records stays visible while requesting a fresh snapshot', () => {
  const state = new model.ThreadState();
  const text = '[Original task](t3-context://v1/thread/thread_source) 继续';
  state.restoreCached({ id: 't', title: 'Cached', transcriptVersion: 2, syncSequence: 10,
    messages: [message('u', 'user', 0, { text })], activities: [] });
  assert.equal(rows(state)[0].text, text);
  assert.equal(state.cursor(), null, 'resuming old deltas alone cannot restore the discarded record');
  const context = { version: 1, records: [{ kind: 'thread', contextId: 'thread_source', environmentId: 'mac', threadId: 'source', title: 'Original task' }] };
  state.apply(snapshot([], [message('u', 'user', 0, { text, context })]));
  const resumed = new model.ThreadState();
  resumed.restoreCached({ ...state.thread, messages: state.messages, activities: state.activities, syncSequence: 10 });
  assert.equal(resumed.cursor(), 10);
  assert.deepEqual(rows(resumed)[0].context, context);
});

test('canonical visible history keeps inherited messages and omits invisible local work', () => {
  const state = new model.ThreadState();
  const visible = item('old-message', 'assistant_message', 2, { threadId: 'parent', messageId: 'old', text: 'Inherited', streaming: false });
  const s = snapshot([visible]);
  s.projection.messages.push(message('hidden-message', 'assistant', 3, { text: 'Hidden message' }));
  s.projection.turnItems.push(item('hidden', 'command_execution', 3, { input: 'hidden-command' }));
  state.apply(s);
  assert.ok(state.messages.some(m => m.id === 'old' && m.text === 'Inherited'));
  assert.ok(!state.activities.some(a => a.summary === 'hidden-command'));
  assert.ok(!state.messages.some(m => m.id === 'hidden-message'));
});

test('visible timeline order wins over misleading completion timestamps and survives message updates', () => {
  const state = new model.ThreadState();
  const command = item('cmd', 'command_execution', 1, { input: 'date', startedAt: null, updatedAt: time(10) });
  state.apply(snapshot([command, item('a-item', 'assistant_message', 2, { messageId: 'a', text: 'Done', streaming: false })], [message('a', 'assistant', 2)]));
  state.apply({ kind: 'event', sequence: 11, event: { threadId: 't', type: 'message.updated', payload: message('a', 'assistant', 2, { text: 'Updated' }) } });
  assert.deepEqual(model.threadTimeline(state.messages, state.activities, null).map(r => r.text), ['date', 'Updated']);
});

test('completed current runs show their own duration, including a single answer and interrupted work', () => {
  const state = new model.ThreadState();
  state.apply(snapshot([], [message('u', 'user', 0), message('a', 'assistant', 16),
    message('u2', 'user', 20, { runId: 'r2' }), message('a2', 'assistant', 25, { runId: 'r2' })],
    [run(), run('r2', { ordinal: 2, status: 'interrupted', startedAt: time(21), completedAt: time(26) })]));
  const rendered = rows(state);
  assert.ok(rendered.some(r => r.text === '工作了 16s'));
  assert.ok(rendered.some(r => r.text === '已中断 · 工作了 5s'));
  assert.ok(rendered.some(r => r.text === 'a2'));
});

for (const withMessages of [false, true]) test(`recent history can start with a checkpoint-only section (withMessages=${withMessages})`, () => {
  const state = new model.ThreadState();
  const files = [{ path: 'app.ets', additions: 3, deletions: 1 }];
  state.apply(snapshot([item('checkpoint', 'checkpoint', 1, { files }),
    ...(withMessages ? [item('u-item', 'user_message', 2, { messageId: 'u', text: 'Next request' }),
      item('a-item', 'assistant_message', 3, { messageId: 'a', text: 'Latest reply' })] : [])]));
  const rendered = rows(state);
  assert.deepEqual(rendered[0].changedFiles, files);
  assert.equal(rendered[0].kind, 'changes');
  assert.deepEqual(rendered.filter(row => row.kind === 'message').map(row => row.text),
    withMessages ? ['Next request', 'Latest reply'] : []);
});

for (const folded of [false, true]) test(`steered messages in one completed run have unique, stable section identities (folded=${folded})`, () => {
  const state = new model.ThreadState();
  const items = [item('u1-item', 'user_message', 0, {messageId:'u1',text:'First request'}),
    ...(folded ? [item('thought1', 'reasoning', 1, {text:'First process',streaming:false})] : []),
    item('a1-item', 'assistant_message', 2, {messageId:'a1',text:'First reply',streaming:false}),
    item('u2-item', 'user_message', 3, {messageId:'u2',text:'Follow-up in the same run'}),
    ...(folded ? [item('thought2', 'reasoning', 4, {text:'Second process',streaming:false})] : []),
    item('a2-item', 'assistant_message', 5, {messageId:'a2',text:'Second reply',streaming:false})];
  state.apply(snapshot(items, [message('u1','user',0),message('a1','assistant',2),
    message('u2','user',3),message('a2','assistant',5)], [run('r',{userMessageId:'u1',assistantMessageId:'a2'})]));
  const initial = rows(state), kind = folded ? 'turn' : 'duration';
  assert.equal(new Set(initial.map(row=>row.id)).size,initial.length,'every lazy-list row needs its own identity');
  const sections=initial.filter(row=>row.kind===kind);assert.equal(sections.length,2);
  if(folded){
    const expanded=rows(state,[sections[0].id]);
    assert.ok(expanded.some(row=>row.text==='First process'));
    assert.ok(!expanded.some(row=>row.text==='Second process'));
  }
  state.apply({kind:'event',sequence:11,event:{type:'message.updated',threadId:'t',
    payload:message('a2','assistant',5,{text:'Updated second reply'})}});
  const updated=model.reconcileTranscriptRows(initial,rows(state));
  assert.deepEqual(updated.filter(row=>row.kind===kind).map(row=>row.id),sections.map(row=>row.id));
  assert.equal(updated.find(row=>row.id===sections[0].id),sections[0]);
  assert.ok(updated.some(row=>row.text==='Updated second reply'));
});

test('consecutive current tool items summarize changed files and commands and expand independently', () => {
  const state = new model.ThreadState();
  state.apply(snapshot([item('cmd1', 'command_execution', 2, { input: 'first' }),
    item('cmd2', 'command_execution', 3, { input: 'second' }),
    item('edit1', 'file_change', 4, { fileName: 'app.ets' }),
    item('edit2', 'file_change', 5, { fileName: 'app.ets' })], [], [run('r', { status: 'running', completedAt: null })]));
  const group = rows(state).find(r => r.kind === 'tools');
  assert.equal(group.text, '修改了 1 个文件，运行了 2 条命令');
  assert.equal(rows(state, [group.id]).filter(r => r.kind === 'tool').length, 4);
});
test('tools and all following thoughts share one expandable process group like Android', () => {
  const state = new model.ThreadState();
  state.apply(snapshot([item('thought1', 'reasoning', 1, { text: 'Inspect schema' }),
    item('cmd1', 'command_execution', 2, { input: 'first' }),
    item('thought2', 'reasoning', 3, { text: 'Implement' }),
    item('edit', 'file_change', 4, { files: [{ path: 'a.ets' }, { path: 'b.ets' }] }),
    item('cmd2', 'command_execution', 5, { input: 'second' }),
    item('live', 'reasoning', 6, { text: 'Verify', status: 'running', streaming: true })], [],
    [run('r', { status: 'running', completedAt: null })]));
  const collapsed = rows(state);
  assert.deepEqual(collapsed.map(r => r.kind), ['tools']);
  assert.equal(collapsed[0].text, '思考中…');
  assert.equal(collapsed[0].icon, 'thinking');
  assert.equal(collapsed[0].streaming, true);
  const expanded = rows(state, [collapsed[0].id]);
  assert.deepEqual(expanded.filter(r => r.depth === 1).map(r => r.kind), ['thinking', 'tool', 'thinking', 'tool', 'tool', 'thinking']);
});

test('answered questions stay at their original position and replace only their synthetic answer bubble', () => {
  const state = new model.ThreadState();
  const requestId = 'request';
  const photo = { type: 'image', id: 'photo', name: 'answer.png', mimeType: 'image/png', sizeBytes: 20 };
  const request = item('question', 'user_input_request', 2, { requestId, responseMode: 'message',
    questions: [{ id: 'q', header: 'Device', question: 'Is the device ready?', options: [{value:'ready',label:'Ready',description:''}] }],
    questionAnswer: { requestId, questionTextById: { q: 'Is the device ready?' },
      answers: { q: { answers: ['ready'] } }, attachmentsByQuestionId: { q: [photo] } } });
  state.apply(snapshot([item('cmd1', 'command_execution', 1, {input:'first'}), request,
    item('cmd2', 'command_execution', 3, {input:'second'}),
    item('answer-item', 'user_message', 4, {messageId:'async-answer:request',text:'Is the device ready?\nReady'}),
    item('steer-item', 'user_message', 5, {messageId:'normal-steer',text:'Keep going'})],
    [message('async-answer:request','user',4),message('normal-steer','user',5)],
    [run('r', {status:'running',completedAt:null,userMessageId:'first-user'})]));
  const rendered = rows(state);
  assert.deepEqual(rendered.map(r=>r.kind), ['tools','question','tools','message']);
  const question = rendered.find(r=>r.kind==='question');
  assert.equal(question.text, 'Is the device ready?');
  assert.ok(question.detail.includes('Ready'));
  assert.ok(!question.detail.includes('[object Object]'));
  assert.deepEqual(question.attachments,[photo]);
  assert.equal(rendered.at(-1).id,'normal-steer');
  assert.equal(model.pendingRequests(state.activities).length,0);
  assert.equal(state.messages.filter(m=>m.role==='user').length,2); // No durable message is removed.
});

test('live question resolution and a fresh snapshot produce the same transcript', () => {
  const state = new model.ThreadState();
  const pending = item('question', 'user_input_request', 1, {requestId:'q',status:'waiting',
    questions:[{id:'one',header:'Ready',question:'Ready?',options:[]}]});
  state.apply(snapshot([pending], [], [run('r',{status:'running',completedAt:null})]));
  assert.equal(rows(state)[0]?.kind,'question');
  assert.equal(model.pendingRequests(state.activities).length,1);
  const answer = message('async-answer:q','user',4,{text:'Ready?\nYes'});
  const completed = {...pending,status:'completed',updatedAt:time(4),
    questionAnswer:{requestId:'q',questionTextById:{one:'Ready?'},answers:{one:'Yes'},attachmentsByQuestionId:{}}};
  state.apply({kind:'event',sequence:11,event:{threadId:'t',type:'turn-item.updated',payload:completed}});
  state.apply({kind:'event',sequence:12,event:{threadId:'t',type:'message.updated',payload:answer}});
  state.apply({kind:'event',sequence:13,event:{threadId:'t',type:'turn-item.updated',payload:item('answer-item','user_message',4,{messageId:answer.id,text:answer.text})}});
  const fresh = new model.ThreadState();
  fresh.apply(snapshot([completed,item('answer-item','user_message',4,{messageId:answer.id,text:answer.text})],[answer],[run('r',{status:'running',completedAt:null})]));
  assert.deepEqual(rows(state),rows(fresh));
  assert.equal(rows(state).length,1);
  assert.ok(rows(state)[0].detail.includes('Yes'));
  assert.equal(model.pendingRequests(state.activities).length,0);
});

test('completed turns keep answered questions visible below the work fold without duplicating them on expansion', () => {
  const state = new model.ThreadState();
  const question = (id, second, answer) => item(id, 'user_input_request', second, {
    requestId: id, questions: [{ id: 'ready', header: 'Device', question: '手机是否已解锁？',
      options: [{ value: 'ready', label: '已解锁并停留鸿蒙 T3', description: '' }] }],
    questionAnswer: { requestId: id, questionTextById: { ready: '手机是否已解锁？' },
      answers: { ready: { answers: [answer] } }, attachmentsByQuestionId: {} }
  });
  state.apply(snapshot([item('u-item', 'user_message', 0, { messageId: 'u', text: '继续' }),
    item('cmd', 'command_execution', 1, { input: 'verify' }), question('first', 2, 'ready'),
    question('second', 4, '已打开，保持亮屏'), item('a-item', 'assistant_message', 16, { messageId: 'a', text: '已核对' })],
    [message('u', 'user', 0), message('a', 'assistant', 16)]));
  const collapsed = rows(state);
  assert.deepEqual(collapsed.map(row => row.kind), ['message', 'turn', 'question', 'question', 'message']);
  const questions = collapsed.filter(row => row.kind === 'question');
  assert.deepEqual(questions.map(row => row.answerPreview), ['已解锁并停留鸿蒙 T3', '已打开，保持亮屏']);
  assert.equal(questions[0].detail, '手机是否已解锁？\n已解锁并停留鸿蒙 T3');
  const expanded = rows(state, [collapsed.find(row => row.kind === 'turn').id, 'question:first']);
  assert.equal(expanded.filter(row => row.kind === 'question').length, 2);
  assert.deepEqual(expanded.filter(row => row.kind === 'question'), questions);
  assert.ok(expanded.some(row => row.kind === 'tools'));
});

test('question previews keep multi-select answers and attachment-only replies across row reconciliation', () => {
  const photo = { id: 'photo', type: 'image', name: '手机截图.png' };
  const make = answer => item('question', 'user_input_request', 1, { requestId: 'request',
    questions: [{ id: 'q', header: 'Device', question: '请选择设备', options: [] }],
    questionAnswer: { requestId: 'request', questionTextById: { q: '请选择设备' },
      answers: { q: answer }, attachmentsByQuestionId: { q: [photo] } } });
  const state = new model.ThreadState();
  state.apply(snapshot([make({ answers: ['鸿蒙', '安卓'] })], [], [run('r', { status: 'running', completedAt: null })]));
  const before = rows(state);
  assert.equal(before[0].answerPreview, '鸿蒙, 安卓');
  state.apply({ kind: 'event', sequence: 11, event: { threadId: 't', type: 'turn-item.updated', payload: make('') } });
  const after = model.reconcileTranscriptRows(before, rows(state));
  assert.equal(after[0].answerPreview, '手机截图.png');
  assert.deepEqual(after[0].attachments, [photo]);
  assert.notEqual(after[0], before[0]);
});

test('tool summaries count viewed images as reads and do not split trailing thoughts from their tools', () => {
  const state = new model.ThreadState();
  state.apply(snapshot([item('cmd','command_execution',1,{input:'date'}),
    item('image','dynamic_tool',2,{toolName:'view_image',viewedImagePath:'/tmp/screen.png'}),
    item('thought1','reasoning',3,{text:'Check the screen'}),item('thought2','reasoning',4,{text:'Compare the result'}),
    item('comment','assistant_message',5,{messageId:'comment',text:'The check passed'})],
    [message('comment','assistant',5)], [run('r',{status:'running',completedAt:null})]));
  const rendered = rows(state);
  assert.deepEqual(rendered.map(r=>r.kind),['tools','message']);
  assert.equal(rendered[0].text,'运行了 1 条命令，读取了 1 个文件');
  const expanded = rows(state,[rendered[0].id]);
  assert.equal(expanded.filter(r=>r.kind==='thinking').length,1);
  assert.equal(expanded.find(r=>r.kind==='thinking').groupCount,2);
});

test('older caches stay readable but refresh discarded fields once before resuming deltas', () => {
  const state = new model.ThreadState();
  state.restoreCached({id:'t',title:'Cached',syncSequence:9,messages:[{id:'old',role:'user',text:'Saved answer'}]});
  assert.equal(state.messages[0].text,'Saved answer');
  assert.equal(state.cursor(),null);
  state.apply(snapshot([item('question','user_input_request',1,{requestId:'q',status:'waiting',
    questions:[{id:'one',header:'Question',question:'Ready?',options:[]}]})]));
  const cached = {...state.thread,messages:state.messages,activities:state.activities,syncSequence:state.cursor()};
  const resumed = new model.ThreadState();resumed.restoreCached(cached);
  assert.equal(resumed.cursor(),10);
  assert.deepEqual(rows(resumed),rows(state));
});

test('canonical live messages render only when attached to visible history, matching a fresh snapshot', () => {
  const state = new model.ThreadState();
  state.apply(snapshot([],[],[run('r',{status:'running',completedAt:null})]));
  const received=message('m','assistant',4,{text:'Live reply'});
  state.apply({kind:'event',sequence:11,event:{threadId:'t',type:'message.updated',payload:received}});
  assert.equal(state.messages.find(m=>m.id==='m').text,'Live reply');
  assert.deepEqual(rows(state),[]);
  const visible=item('m-item','assistant_message',4,{messageId:'m',text:'Live reply'});
  state.apply({kind:'event',sequence:12,event:{threadId:'t',type:'turn-item.updated',payload:visible}});
  assert.equal(rows(state).at(-1).text,'Live reply');
  state.apply({kind:'event',sequence:13,event:{threadId:'t',type:'message.updated',payload:{...received,text:'Updated'}}});
  const fresh=new model.ThreadState();fresh.apply(snapshot([visible],[{...received,text:'Updated'}],[run('r',{status:'running',completedAt:null})]));
  assert.deepEqual(rows(state),rows(fresh));
});

test('late reasoning and steering items keep canonical order across resume and live message replacement', () => {
  const state=new model.ThreadState();
  const earlier=item('thought','reasoning',1,{text:'Inspect first'});
  const later=item('steer-item','user_message',2,{messageId:'steer',text:'Then steer'});
  state.apply(snapshot([item('cmd','command_execution',0,{input:'start'})],[],[run('r',{status:'running',completedAt:null})]));
  state.apply({kind:'event',sequence:11,event:{threadId:'t',type:'message.updated',payload:message('steer','user',2)}});
  state.apply({kind:'event',sequence:12,event:{threadId:'t',type:'turn-item.updated',payload:later}});
  state.apply({kind:'event',sequence:13,event:{threadId:'t',type:'turn-item.updated',payload:earlier}});
  state.apply({kind:'event',sequence:14,event:{threadId:'t',type:'message.updated',payload:message('steer','user',2,{text:'Then steer'})}});
  const expected=['start','Inspect first','Then steer'];
  assert.deepEqual(model.threadTimeline(state.messages,state.activities,'r').map(r=>r.text),expected);
  const resumed=new model.ThreadState();resumed.restoreCached({...state.thread,messages:state.messages,activities:state.activities,syncSequence:14});
  assert.equal(resumed.cursor(),14);
  assert.deepEqual(model.threadTimeline(resumed.messages,resumed.activities,'r').map(r=>r.text),expected);
});

test('agent cards and the sheet agree on model, failure, stable destinations and running counts after replay', () => {
  const state = new model.ThreadState();
  const selection = { instanceId: 'custom', model: 'demo', options: [{ id: 'effort', value: 'max' }] };
  const failed = item('item-b', 'subagent', 4, { subagentId: 'b', childThreadId: 'child-b', status: 'failed', progress: 'Trying', result: '503 Service Unavailable', updatedAt: time(15) });
  const active = { id: 'a', runId: 'r', threadId: 't', status: 'running', startedAt: time(1), updatedAt: time(10), progress: 'Reading' };
  const base = snapshot([failed, item('other', 'subagent', 5, { threadId: 'parent', subagentId: 'foreign' })], [], [run('r', { status: 'running', completedAt: null }), run('old', { ordinal: 0 })]);
  base.projection.subagents = [active, { ...active, id: 'b', startedAt: time(4), childThreadId: 'child-b', driver: 'codex', providerInstanceId: 'custom', modelSelection: selection },
    { ...active, id: 'old', runId: 'old', status: 'completed' }];
  state.apply(base);
  const agents = () => model.turnSubagents(state.thread, state.activities);
  assert.deepEqual(agents().map(x => x.id), ['a','b']);
  assert.equal(model.subagentPillLabel(agents()), '1/2');
  const inline = rows(state).find(x => x.subagents?.[0].id === 'b').subagents[0];
  assert.deepEqual(inline.modelSelection, selection); assert.equal(inline.status, 'failed');
  assert.equal(model.subagentPreview(inline), '服务暂时不可用（503）');
  assert.equal(inline.result, '503 Service Unavailable');
  assert.equal(agents()[1].childThreadId, 'child-b'); assert.equal(model.subagentElapsed([agents()[1]], Date.parse(time(50))), '1s');
  state.apply({kind:'event', sequence:11, event:{type:'subagent.updated',threadId:'t', payload:{...active,status:'completed',result:'Finished',completedAt:time(12),updatedAt:time(12)}}});
  assert.equal(model.subagentPillLabel(agents()), '2 个已结束');
  const cache = new model.ThreadState(); cache.restoreCached(JSON.parse(JSON.stringify({ ...state.thread, messages:state.messages, activities:state.activities, syncSequence:11 })));
  assert.equal(cache.cursor(), 11); assert.deepEqual(model.turnSubagents(cache.thread, cache.activities), agents());
  state.apply({kind:'event',sequence:12,event:{type:'run.updated',threadId:'t',payload:run('next',{ordinal:2,status:'running',completedAt:null})}});
  assert.deepEqual(agents(), []);
});

const webSource = '\uE200cite\uE202turn12view0\uE202turn34search1\uE201';

test('reply, copyable row and agent preview omit opaque web sources but preserve links, code and the original message', () => {
  const prose = '核对了[官方文档](https://example.org/policy)。';
  const code = '`' + webSource + '`\n\n~~~text\n' + webSource + '\n~~~';
  const raw = prose + ' ' + webSource + '\n\n' + code + '\n\n字面量 cite turn12view0。';
  const state = new model.ThreadState(); state.apply(snapshot([], [message('a', 'assistant', 1, { text: raw }), message('u', 'user', 2, { text: raw })]));
  assert.equal(rows(state).find(r => r.id === 'a').text, prose + '\n\n' + code + '\n\n字面量 cite turn12view0。');
  assert.equal(rows(state).find(r => r.id === 'u').text, raw);
  assert.equal(state.messages.find(m => m.id === 'a').text, raw);
  assert.equal(model.subagentPreview({ status: 'completed', result: prose + ' ' + webSource }), prose);
  assert.equal(model.subagentPreview({ status: 'running', progress: '核对中' + webSource }), '核对中');
});

test('web-source delimiters never flash during streaming or occupy a message bubble on their own', () => {
  const display = (text, streaming) => model.threadTimeline([message('a', 'assistant', 1, { text, streaming })], [], 'r');
  for (let i = 1; i <= webSource.length; i++) assert.equal(display('答复。 ' + webSource.slice(0, i), true)[0].text, '答复。');
  assert.deepEqual(display(webSource, false), []);
  assert.equal(display('A ' + webSource + ' B', false)[0].text, 'A B');
  assert.equal(display('A ' + webSource + 'B', false)[0].text, 'A B');
  assert.equal(display('普通文字 turn12view0 及未知标记 \uE200other\uE201', false)[0].text, '普通文字 turn12view0 及未知标记 \uE200other\uE201');
});

test('only Markdown code protects source examples; a literal or unmatched backtick does not hide later prose', () => {
  const display = text => model.threadTimeline([message('a', 'assistant', 1, { text })], [], 'r')[0].text;
  const indented = '例子：\n\n    ' + webSource;
  assert.equal(display(indented + '\n\n结论。' + webSource), indented + '\n\n结论。');
  assert.equal(display('```' + webSource + '``` ' + webSource), '```' + webSource + '```');
  assert.equal(display('单个 ` 符号。' + webSource), '单个 ` 符号。');
  assert.equal(display('转义 \\` 符号。' + webSource), '转义 \\` 符号。');
});

test('child headers prefer the task label over a provider path while respecting named threads', () => {
  assert.equal(model.subagentDisplayTitle('/root/category_evidence', '核对上架资质'), '核对上架资质');
  assert.equal(model.subagentDisplayTitle('/root/category_evidence'), 'category evidence');
  assert.equal(model.subagentDisplayTitle('手动命名', '默认标题'), '手动命名');
});

test('a failed agent keeps the delivered diagnostic for details without using it as the card summary', () => {
  const error = 'unexpected status 503 Service Unavailable: Service temporarily unavailable, url: https://example.org/' + 'a'.repeat(260) + ', request id: fixture-id';
  const state = new model.ThreadState(); state.apply(snapshot([item('a', 'subagent', 1, { status: 'failed', result: error })]));
  const agent = model.turnSubagents(state.thread, state.activities)[0];
  assert.equal(model.subagentPreview(agent), '服务暂时不可用（503）'); assert.equal(agent.result, error);
  assert.equal(model.subagentPreview({ status: 'failed', result: '第 503 条记录缺少日期' }), '第 503 条记录缺少日期');
});

test('agent sheet includes item-only agents and keeps explicitly omitted bodies on live updates', () => {
  const state = new model.ThreadState(); const only = item('i', 'subagent', 2, { subagentId:'only', status:'running', progress:'Reading sources' });
  const base=snapshot([only]); base.projection.subagents=[{id:'s',threadId:'t',runId:'r',status:'completed',result:'Confirmed result',prompt:'Original prompt',updatedAt:time(4)}]; state.apply(base);
  state.apply({kind:'event',sequence:11,event:{type:'subagent.updated',threadId:'t',payload:{id:'s',threadId:'t',runId:'r',status:'completed',result:null,resultOmitted:true,prompt:'',promptOmitted:true,updatedAt:time(6)}}});
  const agents=model.turnSubagents(state.thread,state.activities); assert.deepEqual(agents.map(x=>x.id),['only','s']);
  assert.equal(agents[1].result,'Confirmed result'); assert.equal(agents[1].prompt,'Original prompt');
  const cache = JSON.parse(JSON.stringify({ ...state.thread, messages:state.messages, activities:state.activities,syncSequence:11 }));
  delete cache.subagents[0].model; delete cache.activities[0].payload.subagent.model;
  const restored=new model.ThreadState();restored.restoreCached(cache);assert.equal(restored.cursor(),null); assert.ok(restored.activities.length);
});

test('restarted agents clear an old failure when the new record explicitly resets the result',()=>{
 const s=new model.ThreadState(),base=snapshot([]);const a={id:'reused',threadId:'t',runId:'r',status:'failed',result:'Prior failure',updatedAt:time(4)};
 base.projection.subagents=[a];s.apply(base);s.apply({kind:'event',sequence:11,event:{type:'subagent.updated',threadId:'t',payload:{...a,status:'pending',result:null,updatedAt:time(7)}}});
 assert.equal(model.subagentPreview(s.thread.subagents[0]),'');
});

test('completed workflows and their compact children survive later turns, live updates and a cold restore',()=>{
 const state=new model.ThreadState(),base=snapshot([]),workflow={name:'Review',phases:[{index:0,title:'Read'}],agents:[{index:0,label:'reader',state:'completed',childThreadId:'child',prompt:'large script'}]};
 const entry={id:'wf',runId:'r',threadId:'t',updatedAt:time(4),status:'completed',workflow};base.projection.subagents=[entry,{...entry,workflow:undefined,id:'ordinary'}];state.apply(base);
 state.apply({kind:'event',sequence:11,event:{type:'subagent.updated',threadId:'t',payload:{...entry,workflow:undefined,updatedAt:time(6)}}});
 state.apply({kind:'event',sequence:12,event:{type:'run.created',threadId:'t',payload:run('next',{ordinal:2,status:'running',completedAt:null})}});
 const check=s=>{const rows=model.turnSubagents(s.thread,s.activities);assert.deepEqual(rows.map(x=>x.id),['wf']);assert.equal(rows[0].workflow.agents[0].childThreadId,'child');assert.equal(rows[0].workflow.agents[0].prompt,undefined);};check(state);
 const cold=new model.ThreadState(),saved={...state.thread,messages:state.messages,activities:state.activities,syncSequence:12};cold.restoreCached(structuredClone(saved));assert.equal(cold.cursor(),12);check(cold);
 const old=structuredClone(saved);for(const x of old.subagents)delete x.workflow;cold.restoreCached(old);assert.equal(cold.cursor(),null);
});
