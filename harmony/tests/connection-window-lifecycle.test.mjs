import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const read = file => readFileSync(new URL('../app/entry/src/main/ets/' + file, import.meta.url), 'utf8');
const stripImports = source => source.replace(/^import .*;$/gm, '');
const { default: EntryAbility, ReconnectingRpc, storage } = await import('data:text/javascript;base64,' +
  Buffer.from(stripTypeScriptTypes(`
${stripImports(read('connection/ReconnectingRpc.ets'))}
export const storage = new Map();
const AppStorage = { setOrCreate: (key, value) => storage.set(key, value) };
class UIAbility {}
const hilog = { info() {} };
const accessibility = { isAnimationReduceEnabledSync: () => false };
const ThemeRuntime = { detachWindow() {} };
${stripImports(read('entryability/EntryAbility.ets'))}
`)).toString('base64'));

const drain = async () => { for (let i = 0; i < 16; i++) await Promise.resolve(); };
function fixture(t) {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const listeners = new Map();
  const mainWindow = { isWindowShowing: () => true,
    on: (event, callback) => listeners.set(event, callback),
    off: (event, callback) => { if (listeners.get(event) === callback) listeners.delete(event); } };
  const ability = new EntryAbility();
  ability.loadWindow = async () => {};
  ability.onWindowStageCreate({ getMainWindowSync: () => mainWindow });
  ability.onForeground();
  const peers = [];
  const session = new ReconnectingRpc(async () => {
    const peer = { closed: false, close() { this.closed = true; this.reject?.(new Error('closed')); },
      setForeground() {}, probe() { return !this.closed; } };
    peers.push(peer);
    return peer;
  }, peer => { session.healthy(); return new Promise((_, reject) => { peer.reject = reject; }); }, () => {});
  t.after(() => { session.stop(); ReconnectingRpc.setForeground(true); });
  session.start();
  return { ability, peers, visibility: visible => listeners.get('windowVisibilityChange')?.(visible), listeners };
}

test('a visible T3 window keeps reconnecting when a video overlay backgrounds its ability', async t => {
  const { ability, peers } = fixture(t);
  await drain();
  ability.onBackground();
  peers[0].close();
  await drain();
  t.mock.timers.tick(250);
  await drain();
  assert.equal(peers.length, 2);
  assert.equal(storage.get('appForeground'), true);
});

test('a fully hidden window pauses retries and showing it resumes even while the ability is backgrounded', async t => {
  const { ability, peers, visibility } = fixture(t);
  await drain();
  visibility(false);
  ability.onBackground();
  peers[0].close();
  await drain();
  t.mock.timers.tick(120000);
  await drain();
  assert.equal(peers.length, 1);
  assert.equal(storage.get('appForeground'), false);
  visibility(true);
  await drain();
  assert.equal(peers.length, 2);
  assert.equal(storage.get('appForeground'), true);
});

test('covering part of a visible window does not close or replace a healthy connection', async t => {
  const { ability, peers, visibility } = fixture(t);
  await drain();
  ability.onBackground();
  visibility(true);
  ability.onForeground();
  await drain();
  assert.equal(peers.length, 1);
  assert.equal(peers[0].closed, false);
});

test('destroying the window removes its visibility listener and pauses retries', async t => {
  const { ability, peers, listeners } = fixture(t);
  await drain();
  ability.onWindowStageDestroy();
  peers[0].close();
  await drain();
  t.mock.timers.tick(120000);
  await drain();
  assert.equal(listeners.has('windowVisibilityChange'), false);
  assert.equal(peers.length, 1);
  assert.equal(storage.get('appForeground'), false);
});
