import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const read = path => readFileSync(new URL(path, import.meta.url), 'utf8').replace(/^import .*;\n/gm, '');
const load = source => import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
const model = await load(read('../app/entry/src/main/ets/model/ThreadReferences.ets'));
const shell = { threads: [{ id: 'known', title: 'Current title', projectId: 'p' }],
  projects: [{ id: 'p', title: 'uav_defender_web', workspaceRoot: '/repo' }] };
const calls = [];
const EnvironmentSession = { current: null };
const ClientCache = { open: async (_path, environmentId) => ({ shell: () => environmentId === 'mac' ? shell : null }) };
globalThis.__referenceRuntime = { ...model, ClientCache, EnvironmentSession };
const { loadThreadReferences } = await load(`const {threadReferenceTarget,threadReferenceIds,presentThreadReference,ClientCache,EnvironmentSession}=globalThis.__referenceRuntime;\n` +
  read('../app/entry/src/main/ets/connection/ThreadReferences.ets'));

test('reference loading uses cached titles and batches only omitted thread metadata', async () => {
  calls.length = 0;
  EnvironmentSession.current = { descriptor: { environmentId: 'mac' }, rpc: { call: async (tag, input) => {
    calls.push({ tag, input });
    return { archived: { title: 'Archived task', projectId: 'p' } };
  } } };
  const references = await loadThreadReferences('/cache', 'mac', [
    { href: 't3-thread://v2/mac/known', label: 'Old title' },
    { href: 't3-thread://v2/mac/archived', label: 'Older title' }
  ]);
  assert.deepEqual(calls, [{ tag: 'orchestration.getThreadLinkMetadata', input: { threadIds: ['archived'] } }]);
  assert.deepEqual(references.map(reference => reference.title), ['Current title', 'Archived task']);
  assert.equal(references[1].iconText, 'UW');
});

test('a context record on another machine never queries a same-named local thread', async () => {
  calls.length = 0;
  const context = { records: [{ kind: 'thread', contextId: 'record', environmentId: 'other', threadId: 'known', title: 'Remote task' }] };
  const references = await loadThreadReferences('/cache', 'mac', [{ href: 't3-context://v1/thread/record', label: 'Written title' }], context);
  assert.equal(references[0].environmentId, 'other');
  assert.equal(references[0].title, 'Remote task');
  assert.equal(references[0].projectTitle, '');
  assert.equal(calls.length, 0);
});

test('an older server or an offline connection keeps the saved reference readable', async () => {
  EnvironmentSession.current = { descriptor: { environmentId: 'mac' }, rpc: { call: async () => { throw Error('unknown method'); } } };
  const references = await loadThreadReferences('/cache', 'mac', [{ href: 't3-thread://v2/mac/archived', label: 'Saved title' }]);
  assert.equal(references[0].title, 'Saved title');
  assert.equal(references[0].available, true);
});

const pushed = [], routed = [];
const router = { pushUrl: async route => pushed.push(route), back: route => routed.push(route) };
const storage = new Map();
globalThis.__referenceNavigation = { router, EnvironmentSession, util: { generateRandomUUID: () => 'request' },
  AppStorage: { setOrCreate: (key, value) => storage.set(key, value) } };
const { openThreadReference } = await load(`const {router,EnvironmentSession,util,AppStorage}=globalThis.__referenceNavigation;\n` +
  read('../app/entry/src/main/ets/pages/ThreadReferenceNavigation.ets'));

test('opening a local reference keeps the target identity and worktree without dispatching a turn', async () => {
  pushed.length = 0;
  EnvironmentSession.current = { descriptor: { environmentId: 'mac' } };
  const reference = { environmentId: 'mac', threadId: 'target', title: 'Task', cwd: '/worktree', projectTitle: 'Project', available: true };
  await openThreadReference(reference, 'mac', 'source');
  assert.deepEqual(pushed, [{ url: 'pages/Thread', params: { environmentId: 'mac', threadId: 'target', title: 'Task', cwd: '/worktree', projectTitle: 'Project' } }]);
  await openThreadReference(reference, 'mac', 'target');
  assert.equal(pushed.length, 1);
  await openThreadReference(reference, 'another-environment', 'target');
  assert.equal(pushed.length, 2, 'equal thread ids in different environments are different targets');
});

test('opening another environment delegates saved-connection restoration to the home page', async () => {
  routed.length = 0;
  await openThreadReference({ environmentId: 'remote', threadId: 'target', title: 'Remote task', cwd: '', projectTitle: '', available: true }, 'mac', 'source');
  assert.deepEqual(routed, [{ url: 'pages/Index' }]);
  assert.equal(JSON.parse(storage.get('notificationRoute')).environmentId, 'remote');
  await assert.rejects(openThreadReference({ available: false }, 'mac', 'source'), /原始记录/);
});
