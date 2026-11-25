import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const load = source => import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
const read = path => readFileSync(new URL(path, import.meta.url), 'utf8');
const { BranchChangeNotice, checkoutBranchMismatch } = await load(read('../app/entry/src/main/ets/model/BranchChange.ets').replace(/^import .*;\n/gm, ''));
const thread = { id: 't', branch: 'feature/original', worktreePath: null };
const input = { environmentId: 'notice-env', cwd: '/repo', thread, currentBranch: 'main', hasContent: false };

test('only a confirmed local branch mismatch needs a notice', () => {
  assert.deepEqual(checkoutBranchMismatch(thread, 'main'), { threadBranch: 'feature/original', currentBranch: 'main' });
  for (const [value, branch] of [[null, 'main'], [thread, ''], [thread, thread.branch], [{ ...thread, branch: null }, 'main'], [{ ...thread, worktreePath: '/worktree' }, 'main']]) {
    assert.equal(checkoutBranchMismatch(value, branch), null);
  }
});

test('typing or attachments reveal the notice, which stays after clearing the draft', () => {
  const notice = new BranchChangeNotice();
  assert.equal(notice.update(input), null);
  assert.equal(notice.update({ ...input, hasContent: true }).threadBranch, thread.branch);
  assert.equal(notice.update(input).currentBranch, 'main');
  assert.equal(notice.update({ ...input, currentBranch: thread.branch }), null);
  assert.equal(notice.update(input), null);
});

test('dismissal is limited to this environment, directory, thread and branch pair', () => {
  const notice = new BranchChangeNotice(), withDraft = { ...input, hasContent: true };
  const shown = notice.update(withDraft);
  notice.dismiss(shown.key);
  assert.equal(notice.update(withDraft), null);
  assert.equal(new BranchChangeNotice().update(withDraft), null);
  for (const change of [{ environmentId: 'other' }, { cwd: '/other' }, { thread: { ...thread, id: 'other' } }, { currentBranch: 'new-branch' }]) {
    assert.ok(notice.update({ ...withDraft, ...change }));
  }
});

const source = read('../app/entry/src/main/ets/pages/Thread.ets');
function method(start, end) {
  const from = source.indexOf(start), to = source.indexOf(end, from);
  assert.ok(from >= 0 && to > from, `Missing ${start}`);
  return source.slice(from, to).replaceAll('private ', '');
}
globalThis.__branchChangeModel = { BranchChangeNotice, checkoutBranchMismatch };
const { Page, EnvironmentSession } = await load(`
const { BranchChangeNotice, checkoutBranchMismatch } = globalThis.__branchChangeModel;
const util={generateRandomUUID:()=> 'metadata-id'}, WS={threadStartTurn:'dispatch'};
export const EnvironmentSession={current:null};
export class Page {
 active=true;loaded=true;running=false;settingsBusy=false;sending=false;hasPendingSend=false;restoringBranch=false;
 params={environmentId:'env',threadId:'t'};cwd='/repo';checkoutBranch='main';settingsError='';operationError='';draft='reply';imageUris=[];draftQuote=null;editingQueue=null;
 state={thread:{id:'t',branch:'feature/original',worktreePath:null}};composerThread=this.state.thread;
 branchNotice=new BranchChangeNotice();branchChange=null;rpc=null;
 ${method('  private updateBranchNotice(', '  private async chooseMachine(')}
}
`);
function setup() {
  const page = new Page(), calls = [];
  const rpc = { call: async (tag, payload) => { calls.push({ tag, ...payload }); return { refName: payload.refName }; } };
  EnvironmentSession.current = { descriptor: { environmentId: 'env' } };
  page.rpc = rpc;
  page.updateBranchNotice();
  return { page, rpc, calls };
}
const deferred = () => { let resolve; const promise = new Promise(yes => { resolve = yes; }); return { promise, resolve }; };

test('restore switches the original checkout without sending a message or restarting the connection', async () => {
  const { page, calls } = setup();
  await page.restoreThreadBranch();
  assert.deepEqual(calls, [{ tag: 'vcs.switchRef', cwd: '/repo', refName: thread.branch }]);
  assert.equal(page.checkoutBranch, thread.branch);
  page.updateBranchNotice();
  assert.equal(page.branchChange, null);
  assert.equal(page.settingsBusy, false);
});

test('restore failure preserves the notice and exposes the real checkout error', async () => {
  const { page, rpc } = setup();
  rpc.call = async () => { throw new Error('local changes would be overwritten'); };
  await page.restoreThreadBranch();
  assert.match(page.operationError, /local changes would be overwritten/);
  assert.equal(page.settingsError, '');
  assert.equal(page.checkoutBranch, 'main');
  assert.equal(page.branchChange.threadBranch, thread.branch);
  assert.equal(page.settingsBusy, false);
});

test('a late checkout receipt cannot overwrite a newer live branch or another connection', async () => {
  const { page, rpc } = setup(), result = deferred();
  rpc.call = () => result.promise;
  const restoring = page.restoreThreadBranch();
  page.checkoutBranch = 'new-live-branch';
  result.resolve({ refName: thread.branch });
  await restoring;
  assert.equal(page.checkoutBranch, 'new-live-branch');
  const other = setup(), pending = deferred();
  other.rpc.call = () => pending.promise;
  const late = other.page.restoreThreadBranch();
  other.page.rpc = {};
  pending.resolve({ refName: thread.branch });
  await late;
  assert.equal(other.page.checkoutBranch, 'main');
});

test('restore is unavailable while running, disconnected, sending, or viewing a worktree', async () => {
  for (const change of [{ running: true }, { loaded: false }, { sending: true }, { hasPendingSend: true }, { settingsBusy: true }, { state: { thread: { ...thread, worktreePath: '/worktree' } } }]) {
    const { page, calls } = setup();
    Object.assign(page, change);
    await page.restoreThreadBranch();
    assert.equal(calls.length, 0);
  }
});

test('branch subscription uses passive local updates and ignores events from old sockets', async () => {
  const { page, rpc } = setup();
  let receive;
  rpc.callStream = (tag, payload, callback) => {
    assert.equal(tag, 'subscribeVcsBranch');
    assert.deepEqual(payload, { cwd: '/repo' });
    receive = callback;
    return new Promise(() => {});
  };
  page.subscribeCheckoutBranch(rpc);
  receive([{ refName: 'from-pc', isRepo: true }]);
  assert.equal(page.checkoutBranch, 'from-pc');
  receive([{ refName: null, isRepo: true }]);
  assert.equal(page.checkoutBranch, '');
  page.rpc = {};
  receive([{ refName: 'stale' }]);
  assert.equal(page.checkoutBranch, '');
});

test('continuing on the changed branch updates metadata without discarding the draft', async () => {
  const { page, rpc, calls } = setup();
  await page.syncCheckoutBranch(rpc);
  assert.deepEqual(calls, [{ tag: 'dispatch', type: 'thread.metadata.update', commandId: 'metadata-id', threadId: 't', branch: 'main', worktreePath: null }]);
  assert.equal(page.draft, 'reply');
  page.state.thread = { ...thread, worktreePath: '/worktree' };
  await page.syncCheckoutBranch(rpc);
  assert.equal(calls.length, 1);
});
