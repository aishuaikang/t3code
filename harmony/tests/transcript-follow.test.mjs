import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
const { TranscriptFollow } = await import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(readFileSync(
  new URL('../app/entry/src/main/ets/model/TranscriptFollow.ets', import.meta.url), 'utf8'))).toString('base64'));
test('initial cache, authoritative history and streaming text each follow the newest content', () => {
  const f = new TranscriptFollow();
  for (const content of ['cached', 'live', 'live-token']) {
    f.update(content); f.viewport(false); assert.equal(f.takeRequest(), true);
    f.viewport(true); assert.equal(f.following, true); assert.equal(f.takeRequest(), false);
  }
});
test('reading history suppresses stream and image/keyboard layout jumps until explicitly resumed', () => {
  const f = new TranscriptFollow(); f.update('initial'); f.takeRequest(); f.viewport(true);
  f.pause(); f.viewport(false); f.update('new response'); f.resized();
  assert.equal(f.takeRequest(), false); assert.equal(f.following, false);
  f.jump(); assert.equal(f.takeRequest(), true); f.viewport(true);
  f.resized(); assert.equal(f.takeRequest(), true);
});
test('a new request at the bottom follows like a message and a user gesture cancels pending programmatic scrolling', () => {
  const f = new TranscriptFollow(); f.update('message'); f.takeRequest(); f.viewport(true);
  f.update('message/request-id'); f.viewport(false); assert.equal(f.takeRequest(), true);
  f.pause(); assert.equal(f.takeRequest(), false);
  f.viewport(true, true); f.update('request-answered'); assert.equal(f.takeRequest(), true);
});
test('a drag from the bottom cannot reattach following before the finger leaves the viewport', () => {
  const f = new TranscriptFollow(); f.update('initial'); f.takeRequest(); f.viewport(true);
  f.touchStart(); f.viewport(true); f.update('stream while finger is still at bottom'); f.resized();
  assert.equal(f.takeRequest(), false);
  f.viewport(false, true); f.touchEnd(); f.update('long last row is partially visible');
  assert.equal(f.following, false); assert.equal(f.takeRequest(), false);
  f.viewport(true, true); f.update('back at the actual bottom'); assert.equal(f.takeRequest(), true);
});
test('layout events at the bottom cannot reattach following after expanding or reading history', () => {
  const f = new TranscriptFollow(); f.update('initial'); f.takeRequest(); f.viewport(true);
  f.pause(); f.viewport(true); f.resized(); f.update('stream while reading expanded reasoning');
  assert.equal(f.following, false); assert.equal(f.takeRequest(), false);
  f.viewport(true, true); f.update('user returned to bottom'); assert.equal(f.takeRequest(), true);
});

test('resting a finger never enters history and holds streaming updates until release', () => {
  const f = new TranscriptFollow(); f.update('initial'); f.takeRequest(); f.viewport(true);
  f.touchStart();
  assert.equal(f.following, true);
  f.update('while held'); f.resized(); f.viewport(false);
  assert.equal(f.takeRequest(), false);
  f.touchEnd();
  assert.equal(f.following, true); assert.equal(f.takeRequest(), true);
});
test('changing the keyboard or composer height cannot be mistaken for scrolling into history', () => {
  const f = new TranscriptFollow(); f.update('initial'); f.takeRequest(); f.viewport(true);
  f.viewport(false); f.resized();
  assert.equal(f.following, true); assert.equal(f.takeRequest(), true);
  f.viewport(false, true); f.touchStart(); f.viewport(true); f.touchEnd();
  f.update('while reading history'); assert.equal(f.following, false); assert.equal(f.takeRequest(), false);
});
