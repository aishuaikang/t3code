import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runInNewContext } from 'node:vm';

const page = name => readFileSync(new URL(`../app/entry/src/main/ets/pages/${name}.ets`, import.meta.url), 'utf8');
const helpers = stripTypeScriptTypes(page('MenuIcon').replace(/^import .*;$/gm, '').replace(/^export /gm, ''));
for (const name of ['Index', 'Thread']) test(`${name} can build its context menus on systems without a haptic enum`, () => {
  const modes = [...page(name).matchAll(/hapticFeedbackMode:\s*([^,\n}]+)/g)].map(match => match[1]);
  assert.ok(modes.length > 0);
  for (const mode of modes) {
    for (const sdkApiVersion of [12, 17]) assert.equal(runInNewContext(`${helpers}\n${mode}`, { deviceInfo: { sdkApiVersion } }), undefined);
    assert.equal(runInNewContext(`${helpers}\n${mode}`, { deviceInfo: { sdkApiVersion: 18 }, HapticFeedbackMode: { ENABLED: 1 } }), 1);
  }
});
