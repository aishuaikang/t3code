import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
const read = name => readFileSync(new URL('../app/entry/src/main/ets/' + name, import.meta.url), 'utf8');
const load = source => import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
const { workDuration, taskStatus } = await load(read('model/Models.ets'));
globalThis.__taskWorkDuration = workDuration;
globalThis.__taskStatusForClock = taskStatus;
const presentation = await load("const taskStatus = globalThis.__taskStatusForClock;\n" + read('model/TaskPresentation.ets').replace(/^import .*;$/gm, ''));
const source = read('pages/TaskWorkTime.ets');
const methods = source.slice(source.indexOf('  aboutToAppear():'), source.indexOf('  build()')).replaceAll('private ', '');
const { Page, timers } = await load(`
const workDuration = globalThis.__taskWorkDuration;
export const timers = new Map(); let next = 0;
const setInterval = callback => {timers.set(++next, callback); return next;};
const clearInterval = id => timers.delete(id);
export class Page {
  turn = {turnId: 'r', state: 'running', startedAt: '2026-11-16T00:00:00Z'};
  label = ''; mounted = false; visible = true; foreground = true; timer = -1;
  ${methods}
}`);

test('task duration uses the current turn clock and updates only while the row is visible in the foreground', t => {
  t.mock.timers.enable({apis: ['Date'], now: Date.parse('2026-11-16T00:01:05Z')});
  timers.clear(); const page = new Page(); page.aboutToAppear();
  assert.equal(page.label, '工作中 1m 5s'); assert.equal(timers.size, 1);
  t.mock.timers.tick(1000); [...timers.values()][0]();
  assert.equal(page.label, '工作中 1m 6s');
  page.visible = false; page.updateClock(); assert.equal(timers.size, 0);
  page.visible = true; page.foreground = false; page.updateClock(); assert.equal(timers.size, 0);
  t.mock.timers.tick(60000); page.foreground = true; page.updateClock();
  assert.equal(page.label, '工作中 2m 6s'); assert.equal(timers.size, 1);
  page.aboutToDisappear(); assert.equal(timers.size, 0);
});

test('current server task clocks and unread revisions use run fields when latestTurn is absent', async () => {
  const current = { id: 't', status: 'running', latestRunId: 'r', activeRunId: 'r',
    latestRunRequestedAt: '2026-11-16T00:00:00Z', latestRunStartedAt: '2026-11-16T00:00:01Z',
    latestRunCompletedAt: null, activityRunStartedAt: '2026-11-16T00:00:01Z', activityRunStatus: 'running' };
  const turn = presentation.taskLatestTurn(current);
  assert.equal(turn.turnId, 'r');
  assert.equal(workDuration(presentation.taskWorkTurn(current), '2026-11-16T00:01:02Z'), '工作了 1m 1s');
  const { threadReadRevision } = await load(read('model/ThreadReadState.ets').replace(/^import .*;$/gm, ''));
  assert.equal(threadReadRevision(turn), threadReadRevision({turnId: 'r', state: 'running', startedAt: current.latestRunStartedAt}));
  const done = { ...current, status: 'completed', activeRunId: null, activityRunStatus: null, activityRunStartedAt: null, latestRunCompletedAt: '2026-11-16T00:01:02Z' };
  assert.equal(presentation.taskWorkTurn(done), null);
  assert.notEqual(threadReadRevision(presentation.taskLatestTurn(done)), threadReadRevision(turn));
});

test('an active run keeps its own work time when a newer follow-up is queued, and legacy turn clocks still work', () => {
  const thread = {id: 't', status: 'running', latestRunId: 'queued', latestRunRequestedAt: '2026-11-16T00:01:00Z',
    activityRunStatus: 'running', activeRunId: 'active', activityRunStartedAt: '2026-11-16T00:00:00Z'};
  assert.equal(presentation.taskLatestTurn(thread).turnId, 'queued');
  assert.equal(workDuration(presentation.taskWorkTurn(thread), '2026-11-16T00:01:05Z'), '工作了 1m 5s');
  const legacy = {latestTurn: {turnId: 'legacy', state: 'running', startedAt: '2026-11-16T00:00:00Z'}, session: {status: 'running'}};
  assert.equal(presentation.taskLatestTurn(legacy), legacy.latestTurn);
  assert.equal(workDuration(presentation.taskWorkTurn(legacy), '2026-11-16T00:01:05Z'), '工作了 1m 5s');
  assert.equal(presentation.taskLatestTurn({id: 'empty'}), null);
  assert.equal(presentation.taskWorkTurn({id: 'empty'}), null);
});
