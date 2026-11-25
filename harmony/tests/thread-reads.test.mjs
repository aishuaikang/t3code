import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const read = name => readFileSync(new URL('../app/entry/src/main/ets/' + name, import.meta.url), 'utf8');
const load = source => import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
const modelSource = read('model/ThreadReadState.ets').replace(/^import .*;$/gm, '');
const model = await load(modelSource);
globalThis.__threadReadModel = model;
const revision = (state = 'running', id = 'run') => model.threadReadRevision({ turnId: id, state });
let fixtureId = 0;
async function fixture(initial = '') {
  const store = { text: initial, writes: 0, fail: false, blocked: null,
    async load() { return this.text; },
    async save(text) {
      if (this.blocked) await this.blocked;
      if (this.fail) throw Error('disk full');
      this.text = text; this.writes++;
    }
  };
  globalThis.__threadReadStore = { async open() { return store; } };
  globalThis.AppStorage = { values: new Map(), SetOrCreate(key, value) { this.values.set(key, value); } };
  const source = read('connection/ThreadReads.ets')
    .replace("import { DraftStore } from './DraftStore';", 'const DraftStore = globalThis.__threadReadStore;')
    .replace(/^import .*ThreadReadState.*;$/gm, 'const {threadReadKey, threadIsUnread} = globalThis.__threadReadModel;');
  const { ThreadReads } = await load(source + `\n// fixture ${++fixtureId}`);
  return { reads: ThreadReads, store };
}

test('unread revisions distinguish new work and completion without treating renames or streaming metadata as replies', () => {
  const turn = { turnId: 'run', state: 'running', requestedAt: '2026-11-16T00:00:00Z' };
  const thread = { title: 'Old', latestTurn: turn };
  const seen = model.threadReadRevision(thread.latestTurn);
  const mark = { revision: seen, unread: false };
  assert.equal(model.threadIsUnread(undefined, seen), true);
  assert.equal(model.threadIsUnread(undefined, ''), false);
  thread.title = 'Renamed'; thread.updatedAt = 'later';
  assert.equal(model.threadIsUnread(mark, model.threadReadRevision(thread.latestTurn)), false);
  assert.equal(model.threadIsUnread(mark, revision('running', 'new-run')), true);
  assert.equal(model.threadIsUnread(mark, revision('completed')), true);
  assert.equal(model.threadIsUnread(mark, revision('interrupted')), true);
  assert.equal(model.threadReadRevision({ ...turn, startedAt: '2026-11-16T00:00:01Z', assistantMessageId: 'reply' }), seen);
  assert.equal(revision('waiting'), seen);
  assert.equal(revision('failed'), revision('error'));
  assert.equal(revision('cancelled'), revision('interrupted'));
});

test('local read and manual unread marks survive restart and remain isolated by environment and thread', async () => {
  const { reads, store } = await fixture(); await reads.initialize('/files');
  const rev = revision();
  await reads.mark('env-a', 'thread', rev);
  assert.equal(reads.unread('env-a', 'thread', rev), false);
  assert.equal(reads.unread('env-b', 'thread', rev), true);
  assert.equal(reads.unread('env-a', 'other', rev), true);
  await reads.mark('env-a', 'thread', rev, true);
  await reads.initialize('/files');
  assert.equal(reads.unread('env-a', 'thread', rev), true);
  assert.ok(store.text.includes('revision'));
  await reads.mark('env-a', 'thread', rev);
  await reads.initialize('/files');
  assert.equal(reads.unread('env-a', 'thread', rev), false);
  assert.notEqual(model.threadReadKey('a:b', 'c'), model.threadReadKey('a', 'b:c'));
});

test('concurrent marks preserve both threads, publish after persistence and skip unchanged marks', async () => {
  const { reads, store } = await fixture(); await reads.initialize('/files');
  let release; store.blocked = new Promise(resolve => { release = resolve; });
  const previousVersion = AppStorage.values.get('threadReadVersion');
  const first = reads.mark('env', 'a', revision());
  const second = reads.mark('env', 'b', revision());
  assert.equal(reads.unread('env', 'a', revision()), true);
  assert.equal(AppStorage.values.get('threadReadVersion'), previousVersion);
  release(); await Promise.all([first, second]); store.blocked = null;
  await reads.initialize('/files');
  assert.equal(reads.unread('env', 'a', revision()), false);
  assert.equal(reads.unread('env', 'b', revision()), false);
  assert.equal(store.writes, 2);
  await reads.mark('env', 'a', revision()); assert.equal(store.writes, 2);
});

test('a failed write keeps the previous marks and stored data; a later retry can succeed', async () => {
  const { reads, store } = await fixture(); await reads.initialize('/files');
  await reads.mark('env', 'a', revision());
  const saved = store.text, version = AppStorage.values.get('threadReadVersion');
  store.fail = true;
  await assert.rejects(reads.mark('env', 'a', revision(), true), /disk full/);
  assert.equal(reads.unread('env', 'a', revision()), false);
  assert.equal(store.text, saved);
  assert.equal(AppStorage.values.get('threadReadVersion'), version);
  assert.match(AppStorage.values.get('threadReadError'), /保存失败/);
  store.fail = false;
  await reads.mark('env', 'a', revision(), true);
  assert.equal(reads.unread('env', 'a', revision()), true);
  assert.equal(AppStorage.values.get('threadReadError'), '');
});

test('malformed storage is not overwritten and startup can retry after a failed read', async () => {
  for (const raw of ['null', '[]', '1', '{"bad":{"unread":false}}']) {
    const { reads, store } = await fixture(raw);
    await assert.rejects(reads.initialize('/files'));
    assert.equal(store.text, raw); assert.equal(store.writes, 0);
    store.text = '{}'; await reads.initialize('/files');
    await reads.mark('env', 'a', revision());
    assert.equal(reads.unread('env', 'a', revision()), false);
  }
});

test('mark all read persists every supplied thread once, clears manual unread and preserves other environments', async () => {
  const {reads, store} = await fixture(); await reads.initialize('/files');
  await reads.mark('env', 'a', revision(), true);
  await reads.mark('other-env', 'a', revision(), true);
  const writes = store.writes, version = AppStorage.values.get('threadReadVersion');
  await reads.markAll('env', [{threadId: 'a', revision: revision()}, {threadId: 'b', revision: revision('completed')}]);
  assert.equal(store.writes, writes + 1);
  assert.equal(AppStorage.values.get('threadReadVersion'), version + 1);
  assert.equal(reads.unread('env', 'a', revision()), false);
  assert.equal(reads.unread('env', 'b', revision('completed')), false);
  assert.equal(reads.unread('other-env', 'a', revision()), true);
  assert.equal(reads.unread('env', 'new-task', revision()), true);
  assert.equal(reads.unread('env', 'a', revision('completed')), true);
  await reads.initialize('/files');
  assert.equal(reads.unread('env', 'b', revision('completed')), false);
  await reads.markAll('env', [{threadId: 'a', revision: revision()}, {threadId: 'b', revision: revision('completed')}]);
  await reads.markAll('env', []);
  assert.equal(store.writes, writes + 1);
});

test('failed bulk persistence leaves every task unread and the next manual mark is still saved', async () => {
  const {reads, store} = await fixture(); await reads.initialize('/files');
  store.fail = true;
  await assert.rejects(reads.markAll('env', [{threadId: 'a', revision: revision()}, {threadId: 'b', revision: revision()}]));
  assert.equal(reads.unread('env', 'a', revision()), true);
  assert.equal(reads.unread('env', 'b', revision()), true);
  assert.equal(store.writes, 0);
  store.fail = false;
  const all = reads.markAll('env', [{threadId: 'a', revision: revision()}, {threadId: 'b', revision: revision()}]);
  const manual = reads.mark('env', 'a', revision(), true);
  await Promise.all([all, manual]);
  assert.equal(reads.unread('env', 'a', revision()), true);
  assert.equal(reads.unread('env', 'b', revision()), false);
});

const pageSource = read('pages/Thread.ets');
const frame = pageSource.slice(pageSource.indexOf('class TranscriptFrame'), pageSource.indexOf('@Entry'));
const methods = pageSource.slice(pageSource.indexOf('  onDidBuild():'), pageSource.indexOf('  private stopElapsedTimer(')).replaceAll('private ', '');
const { TranscriptFollow } = await load(read('model/TranscriptFollow.ets'));
globalThis.__threadReadFollow = TranscriptFollow;
const { Page, calls } = await load(`
class FrameCallback {} const ScrollAlign = {END: 2}; ${frame}
const TranscriptFollow = globalThis.__threadReadFollow;
const {threadReadRevision} = globalThis.__threadReadModel;
export const calls = [];
const ThreadReads = { mark(...args) {calls.push(args); return Promise.resolve();} };
export class Page {
  active = true; readVisible = true; foreground = true; showingHistory = false;
  params = {environmentId: 'env', threadId: 't'};
  state = {thread: {id: 't', latestTurn: {turnId: 'r', state: 'completed'}}};
  entries = [{id: 'answer'}]; requests = []; follow = new TranscriptFollow();
  followQueued = false; followGeneration = 0; frames = []; atEnd = false;
  scroller = {isAtEnd: () => this.atEnd, scrollToIndex: () => {this.atEnd = true;}};
  getUIContext() {return {postFrameCallback: frame => this.frames.push(frame)};}
  needsThinking() {return false;}
  cancelQuoteNavigation() {}
  render() {this.onDidBuild(); this.frames.splice(0).forEach(frame => frame.onFrame(1));}
  ${methods}
}`);

test('reaching the visible latest reply marks it read and jumping back to latest resumes reading', () => {
  calls.length = 0; const page = new Page();
  page.follow.update('reply'); page.render();
  assert.deepEqual(calls[0], ['env', 't', model.threadReadRevision(page.state.thread.latestTurn)]);
  calls.length = 0; page.follow.pause(); page.atEnd = false; page.render();
  assert.equal(calls.length, 0);
  page.jumpToLatest(); page.render();
  assert.equal(calls.length, 1);
});

test('history reading, hidden routes, backgrounding and empty transcripts never consume unread marks', () => {
  for (const scenario of ['history', 'hidden', 'background', 'inactive', 'empty', 'not-at-end']) {
    calls.length = 0; const page = new Page(); page.atEnd = true;
    if (scenario === 'history') page.follow.pause();
    if (scenario === 'hidden') page.readVisible = false;
    if (scenario === 'background') page.foreground = false;
    if (scenario === 'inactive') page.active = false;
    if (scenario === 'empty') page.entries = [];
    if (scenario === 'not-at-end') page.atEnd = false;
    page.markCurrentRead(); assert.equal(calls.length, 0, scenario);
  }
});

const {taskStatus} = await load(read('model/Models.ets'));
globalThis.__markAllTaskStatus = taskStatus;
const {taskLatestTurn} = await load('const taskStatus = globalThis.__markAllTaskStatus;\n' + read('model/TaskPresentation.ets').replace(/^import .*;$/gm, ''));
globalThis.__markAllTurn = taskLatestTurn;
const indexSource = read('pages/Index.ets');
const allReadMethod = indexSource.slice(indexSource.indexOf('  private async markAllRead('), indexSource.indexOf('  @Builder\n  private floatingNavigation(')).replaceAll('private ', '');
const {Index, batches, hold} = await load(`
const {threadReadRevision} = globalThis.__threadReadModel;
const taskLatestTurn = globalThis.__markAllTurn;
export const batches = [], hold = {promise: Promise.resolve()};
const ThreadReads = {markAll(...args) {batches.push(args); return hold.promise;}};
export class Index {
  markingAllRead = false; connected = {descriptor: {environmentId: 'env'}}; cacheEnvironmentId = 'cached-env';
  shell = {threads: [{id: 'a', latestRunId: 'current', status: 'running'}, {id: 'hidden-by-filter', latestRunId: 'done', status: 'completed'}]};
  threads = [{id: 'a'}];
  archivedSnapshot = {threads: [{id: 'a', latestRunId: 'old', status: 'completed'}], archivedThreads: [{id: 'archived', latestRunId: 'archive-run', status: 'completed'}]};
  ${allReadMethod}
}`);

test('the all-read action includes filtered-out tasks and loaded archives, preferring live revisions and preventing double clicks', async () => {
  batches.length = 0; const page = new Index(); let release;
  hold.promise = new Promise(resolve => {release = resolve;});
  const first = page.markAllRead(); await page.markAllRead();
  assert.equal(page.markingAllRead, true); assert.equal(batches.length, 1);
  assert.equal(batches[0][0], 'env');
  assert.deepEqual(batches[0][1].map(t => t.threadId).sort(), ['a','archived','hidden-by-filter']);
  assert.equal(batches[0][1].find(t => t.threadId === 'a').revision, revision('running', 'current'));
  release(); await first; assert.equal(page.markingAllRead, false);
  hold.promise = Promise.resolve(); page.connected = null; await page.markAllRead();
  assert.equal(batches[1][0], 'cached-env');
});
