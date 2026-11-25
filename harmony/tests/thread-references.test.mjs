import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const source = readFileSync(new URL('../app/entry/src/main/ets/model/ThreadReferences.ets', import.meta.url), 'utf8').replace(/^import .*;\n/gm, '');
const { threadReferenceTarget, threadReferenceIds, presentThreadReference } = await import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
const context = { version: 1, records: [{ kind: 'thread', contextId: 'thread_hashed_record',
  environmentId: 'mac', threadId: 'real-thread-id', title: 'Original title', label: 'Original title' }] };
const href = 't3-context://v1/thread/thread_hashed_record';
const project = { id: 'p', title: 'uav_defender_web', workspaceRoot: '/repo', faviconPath: 'icon.png' };

test('a PC context reference resolves its record rather than guessing the id from its context key', () => {
  assert.deepEqual(threadReferenceTarget(href, 'phone-environment', context), {
    environmentId: 'mac', threadId: 'real-thread-id', title: 'Original title'
  });
  const missing = threadReferenceTarget(href, 'mac', { records: [] });
  assert.equal(missing.threadId, '');
  assert.equal(presentThreadReference(href, 'Original title', missing, [], [], {}).available, false);
});

test('old local links, scoped links and PC copied links keep their environment and exact ids', () => {
  assert.equal(threadReferenceTarget('t3-thread://v1/old%3Aid', 'local')?.threadId, 'old%3Aid');
  assert.equal(threadReferenceTarget('t3-thread://v1/old%3Aid', 'local')?.environmentId, 'local');
  assert.deepEqual(threadReferenceIds('old%3Aid'), ['old%3Aid', 'old:id']);
  assert.equal(threadReferenceTarget('t3-thread://v2/remote/thread:a/b%3A1', 'local')?.environmentId, 'remote');
  assert.equal(threadReferenceTarget('t3-thread://v2/remote/thread:a/b%3A1', 'local')?.threadId, 'thread:a/b%3A1');
  assert.equal(threadReferenceTarget('https://app.t3.codes/threads/remote/thread%3Aa%2Fb%253A1', 'local')?.threadId, 'thread:a/b%3A1');
  for (const value of ['t3-thread://v1/', 't3-thread://v2/env/', 't3-thread://v2//id', 'https://other.test/threads/e/t', 't3-context://v1/image/img']) {
    assert.equal(threadReferenceTarget(value, 'local', context), null);
  }
});

test('the chip shows the current title and project while its navigation keeps the referenced worktree', () => {
  const target = threadReferenceTarget(href, 'local', context);
  const view = presentThreadReference(href, 'Written title', target,
    [{ id: 'real-thread-id', title: 'Renamed task', projectId: 'p', worktreePath: '/worktree' }], [project], {});
  assert.equal(view.title, 'Renamed task');
  assert.equal(view.projectTitle, 'uav_defender_web');
  assert.equal(view.cwd, '/worktree');
  assert.equal(view.environmentId, 'mac');
  assert.equal(view.threadId, 'real-thread-id');
  assert.equal(view.available, true);
  assert.equal(view.iconText, 'UW');
  assert.equal(view.iconColor, 'red');
});

test('project monogram and emoji overrides match the PC reference marker', () => {
  const target = threadReferenceTarget(href, 'local', context);
  const threads = [{ id: 'real-thread-id', title: 'Task', projectId: 'p' }];
  let view = presentThreadReference(href, 'Written title', target, threads,
    [{ ...project, projectIcon: { kind: 'monogram', text: 'T3', color: 'violet' } }], {});
  assert.equal(view.iconText, 'T3');
  assert.equal(view.iconColor, 'violet');
  view = presentThreadReference(href, 'Written title', target, threads,
    [{ ...project, projectIcon: { kind: 'emoji', emoji: '🦊' } }], {});
  assert.equal(view.iconText, '🦊');
});

test('archived and omitted threads use the metadata lookup and preserve literal percent ids before decoded fallbacks', () => {
  const target = threadReferenceTarget('t3-thread://v1/t%3A1', 'mac');
  let view = presentThreadReference('link', 'Old title', target, [], [project], { 't:1': { title: 'Archived task', projectId: 'p' } });
  assert.equal(view.threadId, 't:1');
  assert.equal(view.title, 'Archived task');
  assert.equal(view.cwd, '/repo');
  view = presentThreadReference('link', 'Old title', target,
    [{ id: 't%3A1', title: 'Literal id', projectId: 'p' }, { id: 't:1', title: 'Other task', projectId: 'p' }], [project], {});
  assert.equal(view.threadId, 't%3A1');
  assert.equal(view.title, 'Literal id');
});
