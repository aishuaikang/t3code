import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
const source = readFileSync(new URL('../app/entry/src/main/ets/connection/ImageAssets.ets', import.meta.url), 'utf8').replace(/^import .*;\n/gm, '');
const { ImageAssets } = await import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
const attachment = { id: 'photo', type: 'image', name: 'photo.jpg', mimeType: 'image/jpeg' };
test('inline images share in-flight and unexpired URLs while separating environments and transports', async () => {
  let calls = 0;
  const rpc = { async call(method, payload) { calls++; assert.equal(method, 'assets.createUrl');
    assert.equal(payload.resource.attachmentId, 'photo');
    return { relativeUrl: '/assets/photo?signature=safe', expiresAt: Date.now() + 60000 }; } };
  const urls = await Promise.all([ImageAssets.source(rpc, 'a', 'http://a', attachment), ImageAssets.source(rpc, 'a', 'http://a', attachment)]);
  assert.equal(calls, 1); assert.equal(urls[0], urls[1]);
  await ImageAssets.source(rpc, 'a', 'http://a', attachment); assert.equal(calls, 1);
  await ImageAssets.source(rpc, 'b', 'http://a', attachment); assert.equal(calls, 2);
  await ImageAssets.source(rpc, 'a', 'http://new-transport', attachment); assert.equal(calls, 3);
  await ImageAssets.source(rpc, 'a', 'http://a', attachment, true); assert.equal(calls, 4);
});
test('expired image URLs refresh and failed requests remain retryable', async () => {
  let calls = 0;
  const rpc = { async call() { calls++; if (calls === 1) throw new Error('offline');
    return { relativeUrl: '/assets/retry', expiresAt: 0 }; } };
  await assert.rejects(ImageAssets.source(rpc, 'retry', 'http://a', attachment), /offline/);
  await ImageAssets.source(rpc, 'retry', 'http://a', attachment);
  await ImageAssets.source(rpc, 'retry', 'http://a', attachment); assert.equal(calls, 3);
});
test('image URL responses cannot change the signed asset origin', async () => {
  for (const relativeUrl of ['https://elsewhere/image', '//elsewhere/image', '/\\elsewhere/image', '/bad\npath']) {
    await assert.rejects(ImageAssets.source({ call: async () => ({ relativeUrl, expiresAt: 0 }) }, relativeUrl, 'http://a', attachment), /图片地址无效/);
  }
});

test('document images outside a thread resolve against the selected workspace and reuse its cache key',async()=>{
 let calls=0;
 const rpc={async call(method,payload){calls++;assert.deepEqual(payload.resource,{_tag:'draft-workspace-file',cwd:'/repo',path:'docs/figure.svg'});return {relativeUrl:'/assets/figure',expiresAt:Date.now()+60000};}};
 assert.equal(await ImageAssets.workspaceSource(rpc,'workspace-image','http://server','/repo','docs/figure.svg'),'http://server/assets/figure');
 await ImageAssets.workspaceSource(rpc,'workspace-image','http://server','/repo','docs/figure.svg');assert.equal(calls,1);
 assert.notEqual(ImageAssets.workspaceId('/repo','figure.svg'),ImageAssets.workspaceId('/other','figure.svg'));
});
