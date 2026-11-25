import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const source = readFileSync(new URL('../app/entry/src/main/ets/pages/WorkStatus.ets', import.meta.url), 'utf8');
const methods = source.slice(source.indexOf('  aboutToAppear()'), source.indexOf('  build()')).replaceAll('private ', '');
const { Fixture, timers, runNext } = await import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(`
export const timers = new Map(); let next = 0;
const setTimeout = (callback, delay) => { timers.set(++next, {callback, delay}); return next; };
const clearTimeout = id => timers.delete(id);
export const runNext = () => { const [id, timer] = timers.entries().next().value; timers.delete(id); timer.callback(); };
const Curve = {Linear: 'linear'};
export class Fixture {
  mounted = false; visible = true; active = true; foreground = true; reduceMotion = false;
  availableWidth = 240; revision = 0; timer = -1; sweep = -56; animations = [];
  getUIContext() { return {animateTo: (options, update) => { this.animations.push(options); update(); }}; }
  ${methods}
}
`)).toString('base64'));

function fixture() { timers.clear(); const page = new Fixture(); page.aboutToAppear(); return page; }
test('visible thinking sweeps natively and rests between sweeps', () => {
  const page = fixture(); page.updateAnimation(); runNext();
  const sweep = page.animations.at(-1);
  assert.equal(sweep.duration, 1350); assert.equal(page.sweep, 240);
  sweep.onFinish();
  assert.equal(page.sweep, -56);
  assert.equal(timers.values().next().value.delay, 1450);
  runNext(); assert.equal(page.sweep, 240);
  page.aboutToDisappear();
});
test('backgrounding cancels animation and ignores an old native completion', () => {
  const page = fixture(); page.updateAnimation(); runNext();
  const completion = page.animations.at(-1).onFinish;
  page.foreground = false; page.updateAnimation();
  completion();
  assert.equal(timers.size, 0); assert.equal(page.sweep, -56);
  page.foreground = true; page.updateAnimation();
  assert.equal(timers.size, 1);
  page.aboutToDisappear();
});
test('offscreen, stopped and reduced-motion rows remain still', () => {
  for (const [key, value] of [['visible', false], ['active', false], ['reduceMotion', true]]) {
    const page = fixture(); page[key] = value; page.updateAnimation();
    assert.equal(timers.size, 0); assert.equal(page.sweep, -56);
    page.aboutToDisappear();
  }
});
test('leaving the conversation clears a scheduled sweep and invalidates its callback', () => {
  const page = fixture(); page.updateAnimation();
  const callback = timers.values().next().value.callback;
  page.aboutToDisappear(); const count = page.animations.length;
  callback();
  assert.equal(timers.size, 0); assert.equal(page.animations.length, count);
});
