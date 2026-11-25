import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const read = path => readFileSync(new URL('../app/entry/src/main/ets/' + path, import.meta.url), 'utf8');
const withoutImports = source => source.replace(/^import .*;$/gm, '');
const source = read('pages/ImagePreview.ets');
const methods = source.slice(source.indexOf('  private async prepareExtraRpc('), source.indexOf('  private sendEdits(')).replaceAll('private ', '');
const disappear = source.slice(source.indexOf('  aboutToDisappear('), source.indexOf('  private restoreKeyboardAvoidMode('));
const { Page, mocks, EnvironmentSession, RpcClient } = await import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(`
export const mocks = { clients: [], sockets: [], config: {}, calls: [], photoUris: ['photo://first.png'], configWait: null, configRequested: null, dropNextUpload: false };
class Socket {
  handlers = new Map();
  on(name, callback) { this.handlers.set(name, callback); }
  off(name) { this.handlers.delete(name); }
  connect(_url, callback) { callback(null); this.handlers.get('open')?.(); }
  close() { this.handlers.get('close')?.(); return Promise.resolve(true); }
  receive(frame) { this.handlers.get('message')?.(null, JSON.stringify(frame)); }
  async send(text) {
    const frame = JSON.parse(text);
    if (frame._tag === 'Ping') { this.receive({ _tag: 'Pong' }); return true; }
    if (frame._tag !== 'Request') return true;
    mocks.calls.push(frame);
    if (frame.tag === 'server.getConfig') mocks.configRequested?.();
    if (frame.tag === 'server.getConfig' && mocks.configWait) await mocks.configWait;
    if (frame.tag === 'attachments.createUploadUrl' && mocks.dropNextUpload) {
      mocks.dropNextUpload = false; this.close(); return true;
    }
    this.receive({ _tag: 'Exit', requestId: frame.id, exit:
      { _tag: 'Success', value: frame.tag === 'server.getConfig' ? mocks.config :
        { attachmentId: 'attachment-' + mocks.calls.length, relativeUrl: '/upload/image' } } });
    return true;
  }
}
const webSocket = { createWebSocket() { const socket = new Socket(); mocks.sockets.push(socket); return socket; } };
const util = { TextDecoder: { create: encoding => ({ decodeToString: bytes => new TextDecoder(encoding).decode(bytes) }) } };
const fs = { OpenMode: { READ_ONLY: 0 }, open: async uri => ({ fd: uri }), stat: async () => ({ size: 4 }),
  read: async (_fd, buffer) => { new Uint8Array(buffer).set([0x89, 0x50, 0x4e, 0x47]); return 4; }, close: async () => {} };
const http = { RequestMethod: { POST: 'POST' }, createHttp: () => ({ on() {}, destroy() {},
  request: async () => { mocks.uploadRequested?.(); if (mocks.uploadWait) await mocks.uploadWait; return {responseCode:200}; } }) };
${withoutImports(read('connection/Rpc.ets'))}
${read('model/FileAttachments.ets')}
${withoutImports(read('connection/ImageAttachment.ets'))}
export const EnvironmentSession = { current: { descriptor: { environmentId: 'env' }, httpBaseUrl: 'http://fixture', rpc:null,
  openRpc() { throw new Error('image previews must reuse the environment connection'); } } };
const WS = { serverGetConfig: 'server.getConfig' };
const photoAccessHelper = { PhotoViewMIMETypes: { IMAGE_TYPE: 'image' }, PhotoViewPicker: class { async select() { return { photoUris: mocks.photoUris }; } } };
const picker = { DocumentViewPicker: class { async select() { return ['document://notes.pdf']; } } };
const fileUri = { FileUri: class { constructor(uri) { this.name = uri.split('/').at(-1); } } };
const getContext = () => ({ filesDir: '/private' });
export class Page {
  active = true; environmentId = 'env'; extraRpc = null; extraConnection = null; maxFileBytes = 0;
  busy = false; extrasBusy = false; erasing = false; error = ''; extraImages = [];
  revision = 0; rpc = null; handedOff = false; imageDrafts = new Map();
  restoreKeyboardAvoidMode() {}
  extraStore = { images: [],
    async add(uri, name) { this.images.push({ uri, name }); },
    async addFile(uri, name) { this.images.push({ uri, name, type: 'file' }); },
    async setUploaded(uri, uploaded) { this.images.find(image => image.uri === uri).uploaded = uploaded; },
    async remove(uri) { this.images = this.images.filter(image => image.uri !== uri); },
    async clear() { this.images = []; } };
  ${methods}
  ${disappear}
}
`)).toString('base64'));

async function reconnect() {
  const rpc = new RpcClient(); await rpc.connect('ws://fixture'); mocks.clients.push(rpc); EnvironmentSession.current.rpc = rpc;
}
async function fixture(t) {
  mocks.clients = []; mocks.sockets = []; mocks.calls = []; mocks.photoUris = ['photo://first.png'];
  mocks.configWait = null; mocks.configRequested = null; mocks.dropNextUpload = false; mocks.uploadRequested = null; mocks.uploadWait = null; EnvironmentSession.current.liveConfig = null;
  mocks.config = { environment: { capabilities: { attachmentUploads: true, fileAttachments: { maxUploadBytes: 1024 } } } };
  t.after(() => mocks.clients.forEach(client => client.close()));
  await reconnect(); return new Page();
}

test('image editor can add and upload another attachment after its cached connection closes', async t => {
  const page = await fixture(t);
  await page.pickExtra(false);
  assert.ok(page.extraStore.images[0].uploaded);
  mocks.sockets[0].close(); await reconnect();
  mocks.photoUris = ['photo://second.png'];
  await page.pickExtra(false);
  assert.equal(page.error, '');
  assert.ok(page.extraStore.images[1].uploaded);
});

test('image editor accepts file attachments without the optional legacy upload flag', async t => {
  const page = await fixture(t);
  mocks.config = { environment: { capabilities: { fileAttachments: { maxUploadBytes: 1024 } } } };
  await page.pickExtra(true);
  assert.equal(page.error, '');
  assert.equal(page.extraStore.images[0].uploaded.type, 'file');
  assert.equal(page.extraStore.images[0].uploaded.name, 'notes.pdf');
});

test('retrying an interrupted upload preserves its local attachment and uploads it on a new connection', async t => {
  const page = await fixture(t);
  mocks.dropNextUpload = true;
  await page.pickExtra(false);
  assert.equal(page.extraImages[0].status, 'failed');
  assert.equal(page.extraStore.images.length, 1);
  await reconnect(); await page.retryExtras();
  assert.equal(page.error, '');
  assert.equal(page.extraStore.images.length, 1);
  assert.ok(page.extraStore.images[0].uploaded);
  assert.equal(page.extraImages[0].status, 'uploaded');
});

test('file selection waits for the pending connection to finish loading its capabilities', async t => {
  const page = await fixture(t);
  let release;
  mocks.configWait = new Promise(resolve => { release = resolve; });
  const requested = new Promise(resolve => { mocks.configRequested = resolve; });
  const connection = page.prepareExtraRpc();
  await requested;
  const selection = page.pickExtra(true);
  assert.equal(page.extraStore.images.length, 0);
  release();
  await Promise.all([connection, selection]);
  assert.equal(page.error, '');
  assert.equal(page.extraStore.images[0].uploaded.type, 'file');
  assert.equal(mocks.sockets.length, 1); assert.equal(mocks.calls.filter(f => f.tag === 'server.getConfig').length, 1);
});

test('an environment without file attachment support still accepts images and rejects files', async t => {
  const page = await fixture(t);
  mocks.config = { environment: { capabilities: {} } };
  await page.pickExtra(true);
  assert.equal(page.error, '当前环境暂不支持文件附件');
  assert.equal(page.extraStore.images.length, 0);
  await page.pickExtra(false);
  assert.equal(page.error, '');
  assert.equal(page.extraStore.images[0].uploaded.type, 'image');
});

test('closing the image editor during connection setup cannot add attachments after it disappears', async t => {
  const page = await fixture(t);
  let release;
  mocks.configWait = new Promise(resolve => { release = resolve; });
  const requested = new Promise(resolve => { mocks.configRequested = resolve; });
  const selection = page.pickExtra(false);
  await requested;
  page.aboutToDisappear();
  release();
  await selection;
  assert.equal(page.extraStore.images.length, 0);
});


test('leaving during an upload removes its remote file and keeps the shared connection usable', async t => {
  const page = await fixture(t); let finish;
  const started = new Promise(resolve => { mocks.uploadRequested = resolve; });
  mocks.uploadWait = new Promise(resolve => { finish = resolve; });
  const adding = page.pickExtra(false); await started; page.aboutToDisappear(); finish(); await adding;
  assert.equal(page.extraStore.images.length,0);
  assert.equal(mocks.calls.filter(f=>f.tag==='attachments.delete').length,1);
  assert.equal(EnvironmentSession.current.rpc.isOpen(),true);
});

test('a late capability reply cannot replace the file limit from the reconnected environment', async t => {
  const page = await fixture(t); let finish;
  const started = new Promise(resolve => { mocks.configRequested=resolve; });
  mocks.configWait = new Promise(resolve => {finish=resolve;});
  const stale = page.prepareExtraRpc(); await started; await reconnect();
  EnvironmentSession.current.liveConfig={environment:{capabilities:{fileAttachments:{maxUploadBytes:4096}}}};
  await page.prepareExtraRpc(); finish(); await assert.rejects(stale,/切换/);
  assert.equal(page.maxFileBytes,4096); assert.equal(mocks.calls.filter(f=>f.tag==='server.getConfig').length,1);
});

for (const sent of [true, false]) test(`leaving a gallery cleans only unused reference uploads (sent: ${sent})`, async t => {
  const page = await fixture(t);
  const draft = id => {
    const cleared = Promise.withResolvers();
    return { images: [{ uploaded: { id } }], cleared: cleared.promise, async clear() { this.images = []; cleared.resolve(); } };
  };
  const old = draft('ref-A'), current = draft('ref-B');
  page.imageDrafts.set(0, { store: old }); page.extraStore = current; page.handedOff = sent;
  page.aboutToDisappear(); await old.cleared; if (!sent) await current.cleared;
  assert.deepEqual(mocks.calls.filter(f => f.tag === 'attachments.delete').map(f => f.payload.attachmentId).sort(), sent ? ['ref-A'] : ['ref-A', 'ref-B']);
  assert.equal(current.images.length, sent ? 1 : 0);
});
