import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const model = await import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(
  readFileSync(new URL('../app/entry/src/main/ets/model/Models.ets', import.meta.url), 'utf8')
)).toString('base64'));
const time = second => `2026-11-17T00:00:${String(second).padStart(2, '0')}Z`;
const item = (id, type, ordinal, extra = {}) => ({ id, type, ordinal, threadId: 'thread', runId: 'run',
  status: 'completed', startedAt: time(ordinal), updatedAt: time(ordinal), ...extra });
const message = (id, ordinal, extra = {}) => ({ id, threadId: 'thread', runId: 'run', role: 'user',
  text: 'Continue', streaming: false, createdAt: time(ordinal), updatedAt: time(ordinal), ...extra });
function snapshot(items, messages = [], run = {}) {
  return { kind: 'snapshot', snapshotSequence: 1, projection: { thread: { id: 'thread' }, messages,
    runs: [{ id: 'run', ordinal: 1, status: 'completed', requestedAt: time(0), startedAt: time(0), completedAt: time(20), ...run }],
    turnItems: items, visibleTurnItems: items.map((entry, position) => ({ position, sourceThreadId: entry.threadId,
      sourceItemId: entry.id, item: entry })) } };
}
function rows(state) {
  return model.transcriptRows(state.messages, state.activities, state.thread.session,
    state.thread.latestTurn, [], state.thread.turns);
}

test('MCP startup warnings display the retained message and severity instead of a generic title', () => {
  const state = new model.ThreadState();
  const diagnostic = 'MCP client for `computer-use` failed to start: MCP startup failed: No such file or directory (os error 2)';
  state.apply(snapshot([item('mcp', 'system_notice', 1, { title: 'MCP server computer-use failed to start', message: diagnostic })]));
  const [row] = rows(state);
  assert.equal(row.kind, 'notice');
  assert.equal(row.text, 'MCP「computer-use」启动失败');
  assert.equal(row.detail, diagnostic);
  assert.equal(row.tone, 'warning');
  assert.equal(row.icon, 'warning');
});

test('completed work keeps warnings visible and separate from adjacent command groups', () => {
  const state = new model.ThreadState();
  state.apply(snapshot([item('u', 'user_message', 0, { messageId: 'u', text: 'Check' }),
    item('before', 'command_execution', 1, { input: 'first command' }),
    item('notice', 'system_notice', 2, { message: 'MCP startup failed' }),
    item('after', 'command_execution', 3, { input: 'second command' }),
    item('a', 'assistant_message', 4, { messageId: 'a', text: 'Done' })]));
  assert.deepEqual(rows(state).map(row => row.kind), ['message', 'tools', 'notice', 'tools', 'message', 'duration']);
  assert.ok(rows(state).some(row => row.detail === 'MCP startup failed'));
});

test('server restart and stop notices show their actual message with independent severity', () => {
  const state = new model.ThreadState();
  state.apply(snapshot([
    item('restart', 'system_notice', 1, { title: 'Server restarted',
      message: 'Cancelled because the server restarted before the provider work completed.' }),
    item('info', 'system_notice', 2, { title: 'Notice', message: 'Provider connected', level: 'info' }),
    item('stop', 'run_interrupt_result', 3, { title: 'Interrupted', message: 'Stopped by user' })
  ]));
  const rendered = rows(state).filter(row => row.kind === 'notice');
  assert.deepEqual(rendered.map(row => row.text), ['服务重启，任务执行已中断', 'Provider connected', '任务已停止']);
  assert.deepEqual(rendered.map(row => row.tone), ['warning', 'info', 'info']);
  assert.equal(rendered[2].detail, 'Stopped by user');
});

test('restart continuation notifications remain a system row in snapshots and live updates', () => {
  const resume = item('resume', 'notification', 1, { source: { kind: 'system' }, outcome: 'updated',
    summary: 'T3 Code restarted and resumed this turn', detail: 'The previous turn was interrupted.' });
  const internal = message('internal-resume', 1, { notification: resume, text: 'Continue where you left off.' });
  const fresh = new model.ThreadState();
  fresh.apply(snapshot([resume], [internal]));
  const live = new model.ThreadState();
  live.apply(snapshot([{ ...resume, summary: 'Resumed thread', detail: undefined }], [internal]));
  live.apply({ kind: 'event', sequence: 2, event: { threadId: 'thread', type: 'turn-item.updated', payload: resume } });
  assert.deepEqual(rows(live), rows(fresh));
  assert.equal(rows(fresh)[0].kind, 'notice');
  assert.equal(rows(fresh)[0].text, 'T3 Code 已重启并恢复此轮任务');
  assert.equal(rows(fresh)[0].tone, 'info');
  assert.ok(rows(fresh)[0].detail.includes(resume.detail));
  assert.equal(rows(fresh).filter(row => row.kind === 'message').length, 0);
});

test('provider retries retain the full error and refresh their row when recovery arrives', () => {
  const state = new model.ThreadState();
  const error = item('error', 'error', 1, { title: 'Provider retry', status: 'running',
    failure: { class: 'transport_error', message: 'Response stream disconnected', retryable: true },
    retry: { attempt: 2, maxAttempts: 5, retryDelayMs: 1500 } });
  state.apply(snapshot([error], [], { status: 'running', completedAt: null }));
  const before = rows(state);
  assert.equal(before[0].kind, 'notice');
  assert.equal(before[0].tone, 'warning');
  assert.ok(before[0].text.includes('2/5'));
  assert.ok(before[0].detail.includes('Response stream disconnected'));
  assert.ok(before[0].detail.includes('1.5s'));
  state.apply({ kind: 'event', sequence: 2, event: { threadId: 'thread', type: 'turn-item.updated',
    payload: { ...error, status: 'completed', updatedAt: time(5) } } });
  const after = model.reconcileTranscriptRows(before, rows(state));
  assert.notEqual(after[0], before[0]);
  assert.equal(after[0].tone, 'success');
  assert.equal(after[0].icon, 'check');
  assert.ok(after[0].text.includes('已恢复'));
  assert.equal(after[0].detail, error.failure.message);
});

test('usage limits are warnings and other provider failures retain their complete diagnostic', () => {
  const state = new model.ThreadState();
  const detail = 'Detailed provider error. '.repeat(200);
  state.apply(snapshot([item('limit', 'error', 1, { status: 'failed', failure: { class: 'usage_limit', message: 'Usage limit reached' } }),
    item('failure', 'error', 2, { status: 'failed', failure: { class: 'provider_error', message: detail } })]));
  const rendered = rows(state).filter(row => row.kind === 'notice');
  assert.equal(rendered[0].tone, 'warning');
  assert.equal(rendered[0].text, '已达到使用额度上限');
  assert.equal(rendered[1].tone, 'error');
  assert.equal(rendered[1].detail, detail);
});

test('legacy runtime warnings and errors keep payload messages while empty SDK noise is omitted', () => {
  const state = new model.ThreadState();
  state.apply({ kind: 'snapshot', snapshot: { snapshotSequence: 1, thread: { id: 'thread', messages: [], activities: [
    { id: 'warning', kind: 'runtime.warning', summary: 'Runtime warning', createdAt: time(1), payload: { message: 'Warning detail' } },
    { id: 'error', kind: 'runtime.error', summary: 'Runtime error', createdAt: time(2), payload: { message: 'Error detail' } },
    { id: 'noise', kind: 'runtime.warning', summary: 'commands_changed (no displayable text content)', createdAt: time(3) }
  ] } } });
  assert.deepEqual(rows(state).map(row => [row.kind, row.text, row.detail, row.tone]), [
    ['notice', 'Warning detail', 'Warning detail', 'warning'], ['notice', 'Error detail', 'Error detail', 'error']
  ]);
});

test('severity-only changes invalidate cached rows and unrelated tool messages stay tool output', () => {
  const state = new model.ThreadState();
  const notice = item('notice', 'system_notice', 1, { message: 'Connection changed', level: 'info' });
  state.apply(snapshot([notice, item('tool', 'dynamic_tool', 2, { toolName: 'read_file', output: { message: 'file text' } })]));
  const before = model.threadTimeline(state.messages, state.activities, null);
  state.apply({ kind: 'event', sequence: 2, event: { threadId: 'thread', type: 'turn-item.updated',
    payload: { ...notice, level: 'warning' } } });
  const after = model.reconcileTranscriptRows(before, model.threadTimeline(state.messages, state.activities, null));
  assert.notEqual(after[0], before[0]);
  assert.equal(after[0].tone, 'warning');
  assert.equal(after[1].kind, 'tool');
  assert.equal(after[1], before[1]);
});

test('older notice caches stay visible while requesting one snapshot to restore lost diagnostics', () => {
  const state = new model.ThreadState();
  state.restoreCached({ id: 'thread', transcriptVersion: 2, syncSequence: 10, messages: [], activities: [
    { id: 'warning', kind: 'timeline.updated', summary: 'MCP server computer-use failed to start', createdAt: time(1),
      payload: { itemType: 'system_notice', itemId: 'warning', title: 'MCP server computer-use failed to start' } }
  ] });
  assert.equal(state.cursor(), null);
  assert.equal(state.activities.length, 1);
  state.apply({ ...snapshot([item('warning', 'system_notice', 1, { message: 'MCP client for `computer-use` failed to start: missing executable' })]), snapshotSequence: 11 });
  assert.equal(state.cursor(), 11);
  assert.ok(rows(state)[0].detail.includes('missing executable'));
});

test('adapted notice caches and ordinary conversation caches retain incremental resume', () => {
  for (const activities of [[], [{ id: 'warning', kind: 'timeline.updated', tone: 'warning', summary: 'Warning', createdAt: time(1),
    payload: { itemType: 'system_notice', title: 'Warning', detail: 'Full diagnostic' } }]]) {
    const live = new model.ThreadState();
    live.apply({ kind: 'snapshot', snapshot: { snapshotSequence: 10, thread: { id: 'thread', messages: [], activities } } });
    const state = new model.ThreadState();
    state.restoreCached({ ...live.thread, syncSequence: live.cursor() });
    assert.equal(state.cursor(), 10);
    assert.deepEqual(rows(state), rows(live));
  }
});
