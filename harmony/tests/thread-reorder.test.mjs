import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const read = file => readFileSync(new URL('../app/entry/src/main/ets/' + file, import.meta.url), 'utf8');
const load = source => import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
const models = await load(read('model/Models.ets'));
globalThis.__reorderModels = models;
const presentation = await load('const {taskStatus}=globalThis.__reorderModels;\n' + read('model/TaskPresentation.ets').replace(/^import .*;$/gm, ''));
globalThis.__reorderPresentation = presentation;
const ordering = await load('const {taskStatus}=globalThis.__reorderModels;const {sortPinnedThreads}=globalThis.__reorderPresentation;\n' +
  read('model/ThreadOrdering.ets').replace(/^import .*;$/gm, ''));
globalThis.__reorder = ordering;
const source = read('pages/Index.ets');
const start = source.indexOf('  private canOrder(');
const methods = start < 0 ? '' : source.slice(start, source.indexOf('  private deleteTask(', start)).replaceAll('private ', '');
const { Page } = await load(`
const {ShellState,WS}=globalThis.__reorderModels;
const {sortTaskThreads,inThreadOrderGroup,planThreadReorder}=globalThis.__reorder;
let nextId=0;const util={generateRandomUUID:()=>String(++nextId)};
export class Page {
 shell=new ShellState();threads=[];live=true;actionBusy=false;pinReorderSupported=true;activeReorderSupported=true;
 orderOpen=false;orderRows=[];orderPinned=false;orderError='';orderMovedIds=[];orderOriginalIds=[];orderConnection=null;
 calls=[];connected={descriptor:{environmentId:'env'},rpc:{call:async(method,command)=>this.calls.push({method,command})}};
 ${methods}
}
`);
const thread = (id, extra = {}) => ({ id, title: id, projectId: 'p', status: 'idle',
  createdAt: '2026-11-16T01:00:00Z', updatedAt: '2026-11-16T01:00:00Z', ...extra });
const ids = threads => threads.map(thread => thread.id);
function pageWith(threads) {
  const page = new Page();
  page.shell.apply({ kind: 'snapshot', snapshot: { snapshotSequence: 1, projects: [], threads } });
  page.threads = threads.map(value => ({ ...value, pinned: !!value.pinnedAt, archived: !!value.archivedAt,
    settled: models.taskStatus(value) === 'completed' }));
  return page;
}
function applyAssignments(threads, assignments, pinned) {
  const keys = new Map(assignments.map(value => [value.id, value.orderKey]));
  return threads.map(thread => keys.has(thread.id) ? { ...thread, [pinned ? 'pinOrderKey' : 'activeOrderKey']: keys.get(thread.id) } : thread);
}

test('active server keys match PC order, with newly created or restored unkeyed tasks above the manual run', () => {
  const input = [thread('b', { activeOrderKey: 't' }), thread('old'), thread('a', { activeOrderKey: 'g' }),
    thread('restored', { unsettledAt: '2026-11-16T02:00:00Z' }), thread('pin', { pinnedAt: 'now', pinOrderKey: 'n' }),
    thread('done', { status: 'completed' })];
  const before = structuredClone(input);
  assert.deepEqual(ids(ordering.sortTaskThreads(input)), ['pin', 'restored', 'old', 'a', 'b', 'done']);
  assert.deepEqual(input, before);
});

test('fractional keys handle both boundaries, adjacent prefixes, invalid keys and repeated insertions', () => {
  const between = ordering.threadOrderKeyBetween;
  assert.equal(between(null, null), 'n');assert.equal(between('g', 't'), 'n');
  for (const [before, after] of [[null, 'b'], ['z', null], ['ab', 'ac'], ['b', 'bb']]) {
    const key = between(before, after);
    assert.ok(key && (!before || before < key) && (!after || key < after));
    assert.match(key, /^[a-z]*[b-z]$/);
  }
  for (const pair of [['a', 'b'], ['B', null], ['t', 'g'], ['n', 'n']]) assert.equal(between(...pair), null);
  let after = 'b';
  for (let i = 0; i < 50; i++) { const key = between(null, after);assert.ok(key < after);after = key; }
});

test('normal dragging writes only the moved thread and avoids hidden retained keys', () => {
  const threads = [thread('left', { pinnedAt: 'now', pinOrderKey: 'g' }), thread('right', { pinnedAt: 'now', pinOrderKey: 't' }),
    thread('moved', { pinnedAt: 'now', pinOrderKey: 'z' }), thread('hidden', { pinnedAt: 'now', pinOrderKey: 'n' })];
  const plan = ordering.planThreadReorder(threads, ['left', 'moved', 'right'], ['moved'], true);
  assert.equal(plan.length, 1);assert.equal(plan[0].id, 'moved');
  assert.ok('g' < plan[0].orderKey && plan[0].orderKey < 't');assert.notEqual(plan[0].orderKey, 'n');
});

test('concurrent PC reordering cannot silently change the final order chosen in the mobile sorting panel', () => {
  const threads = [thread('a', { activeOrderKey: 'g' }), thread('b', { activeOrderKey: 'f' }), thread('c', { activeOrderKey: 't' })];
  const plan = ordering.planThreadReorder(threads, ['c', 'a', 'b'], ['c'], false);
  assert.deepEqual(ids(ordering.sortTaskThreads(applyAssignments(threads, plan, false))), ['c', 'a', 'b']);
});

test('first reorder, corrupt neighbors and multiple moves receive unique PC-compatible keys without changing hidden rows', () => {
  for (const pinned of [false, true]) {
    const extra = pinned ? { pinnedAt: 'now' } : {};
    const threads = ['a', 'b', 'c', 'hidden'].map(id => thread(id, extra));
    threads.at(-1)[pinned ? 'pinOrderKey' : 'activeOrderKey'] = ordering.spreadThreadOrderKeys(4)[0];
    for (const moved of [['c'], ['a', 'c']]) {
      const plan = ordering.planThreadReorder(threads, ['c', 'a', 'b'], moved, pinned);
      assert.equal(plan.length, 3);assert.ok(!plan.some(value => value.id === 'hidden'));
      assert.equal(new Set(plan.map(value => value.orderKey)).size, 3);
      assert.ok(plan.every(value => value.orderKey !== threads.at(-1)[pinned ? 'pinOrderKey' : 'activeOrderKey']));
      assert.deepEqual(ids(ordering.sortTaskThreads(applyAssignments(threads.slice(0, 3), plan, pinned))), ['c', 'a', 'b']);
    }
  }
  const corrupt = ['a', 'b', 'c'].map(id => thread(id, { pinnedAt: 'now', pinOrderKey: 'INVALID' }));
  assert.equal(ordering.planThreadReorder(corrupt, ['c', 'a', 'b'], ['c'], true).length, 3);
});

test('archived, settled, cross-group and duplicate targets cannot produce reorder commands', () => {
  const threads = [thread('a'), thread('b'), thread('p', { pinnedAt: 'now' }),
    thread('done', { status: 'completed' }), thread('archived', { archivedAt: 'now' })];
  for (const order of [['a', 'p'], ['a', 'done'], ['a', 'archived'], ['a', 'missing'], ['a', 'a']]) {
    assert.deepEqual(ordering.planThreadReorder(threads, order, ['a'], false), []);
  }
});

test('long-press sorting uses a stable filtered snapshot and dragging changes no server data until saving', async () => {
  const page = pageWith([thread('a'), thread('b'), thread('c'), thread('pin', { pinnedAt: 'now' })]);
  page.threads = page.threads.filter(value => value.id !== 'b');
  page.startOrder(page.threads[0]);
  assert.equal(page.orderOpen, true);assert.deepEqual(ids(page.orderRows), ['a', 'c']);
  page.moveOrder(1, 0);assert.deepEqual(ids(page.orderRows), ['c', 'a']);assert.equal(page.orderDirty(), true);
  assert.equal(page.calls.length, 0);assert.deepEqual(ids(page.shell.threads), ['a', 'b', 'c', 'pin']);
  page.shell.apply({ kind: 'thread-upserted', sequence: 2, thread: thread('b', { title: 'Streaming title' }) });
  assert.deepEqual(ids(page.orderRows), ['c', 'a']);
});

test('saving pinned and active orders sends the correct shared command with unique IDs and waits for all receipts', async () => {
  for (const pinned of [false, true]) {
    const page = pageWith(['a', 'b', 'c'].map(id => thread(id, pinned ? { pinnedAt: 'now' } : {})));
    page.startOrder(page.threads[0]);page.moveOrder(2, 0);
    let release;
    page.connected.rpc.call = async (method, command) => {
      page.calls.push({ method, command });
      if (page.calls.length === 1) await new Promise(resolve => { release = resolve; });
      const current = page.shell.threads.find(thread => thread.id === command.threadId);
      page.shell.apply({ kind: 'thread-upserted', sequence: page.calls.length + 1,
        thread: { ...current, [pinned ? 'pinOrderKey' : 'activeOrderKey']: command.orderKey } });
    };
    const saving = page.saveOrder();
    assert.equal(page.actionBusy, true);assert.equal(page.orderOpen, true);
    await page.saveOrder();assert.equal(page.calls.length, 1);
    release();await saving;
    assert.equal(page.orderOpen, false);assert.equal(page.actionBusy, false);assert.equal(page.calls.length, 3);
    assert.ok(page.calls.every(call => call.method === models.WS.threadStartTurn &&
      call.command.type === (pinned ? 'thread.pin.reorder' : 'thread.active.reorder')));
    assert.equal(new Set(page.calls.map(call => call.command.commandId)).size, 3);
    assert.deepEqual(ids(ordering.sortTaskThreads(page.shell.threads)), ['c', 'a', 'b']);
  }
});

test('dragging back, cancelling, unsupported capability and offline states never write to the server', async () => {
  const page = pageWith([thread('a'), thread('b')]);
  page.activeReorderSupported = false;page.startOrder(page.threads[0]);assert.equal(page.orderOpen, false);
  page.activeReorderSupported = true;page.live = false;page.startOrder(page.threads[0]);assert.equal(page.orderOpen, false);
  page.live = true;page.startOrder(page.threads[0]);page.moveOrder(1, 0);page.moveOrder(0, 1);
  assert.equal(page.orderDirty(), false);await page.saveOrder();assert.equal(page.calls.length, 0);
  page.startOrder(page.threads[0]);page.moveOrder(1, 0);page.orderOpen = false;await page.saveOrder();assert.equal(page.calls.length, 0);
});

test('failed saving keeps the draft for retry; reconnecting or changing the environment stops further writes', async () => {
  const page = pageWith([thread('a'), thread('b'), thread('c')]);
  page.startOrder(page.threads[0]);page.moveOrder(2, 0);
  page.connected.rpc.call = async () => { throw new Error('Network lost'); };
  await page.saveOrder();assert.equal(page.orderOpen, true);assert.equal(page.actionBusy, false);
  assert.deepEqual(ids(page.orderRows), ['c', 'a', 'b']);assert.match(page.orderError, /Network lost/);
  page.connected.rpc.call = async (method, command) => { page.calls.push({ method, command });page.connected = { descriptor: { environmentId: 'other' } }; };
  await page.saveOrder();assert.equal(page.calls.length, 1);
  assert.equal(page.orderOpen, true);assert.equal(page.actionBusy, false);
});

test('a thread settled or unpinned while the sorting panel is open cannot receive stale reorder writes', async () => {
  for (const pinned of [false, true]) {
    const page = pageWith(['a', 'b'].map(id => thread(id, pinned ? { pinnedAt: 'now' } : {})));
    page.startOrder(page.threads[0]);page.moveOrder(1, 0);
    page.shell.apply({ kind: 'thread-upserted', sequence: 2, thread: thread('a', { status: 'completed' }) });
    await page.saveOrder();assert.equal(page.calls.length, 0);assert.equal(page.orderOpen, true);
    assert.ok(page.orderError);
  }
});

test('a reconnect during multi-command saving stops old-socket writes and preserves the unsaved draft', async () => {
  const page = pageWith([thread('a'), thread('b'), thread('c')]);
  page.startOrder(page.threads[0]);page.moveOrder(2, 0);
  page.connected.rpc.call = async (method, command) => {
    page.calls.push({ method, command });page.connected.rpc = { call: async () => assert.fail('new socket must not receive old writes') };
  };
  await page.saveOrder();assert.equal(page.calls.length, 1);assert.equal(page.orderOpen, true);
  assert.match(page.orderError, /连接已变化/);assert.deepEqual(ids(page.orderRows), ['c', 'a', 'b']);
  assert.equal(page.actionBusy, false);
});

test('multiple local drags save the final permutation and invalid native drag indexes leave it unchanged', async () => {
  const page = pageWith([thread('a'), thread('b'), thread('c'), thread('d')]);
  page.startOrder(page.threads[0]);page.moveOrder(3, 0);page.moveOrder(1, 3);
  for (const [from, to] of [[-1, 1], [0, 4], [5, 0], [0, 0]]) page.moveOrder(from, to);
  assert.deepEqual(ids(page.orderRows), ['d', 'b', 'c', 'a']);assert.equal(page.calls.length, 0);
  await page.saveOrder();
  assert.deepEqual(ids(ordering.sortTaskThreads(applyAssignments(page.shell.threads,
    page.calls.map(({ command }) => ({ id: command.threadId, orderKey: command.orderKey })), false))), ['d', 'b', 'c', 'a']);
});
