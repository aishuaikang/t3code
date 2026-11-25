import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const read = name => readFileSync(new URL('../app/entry/src/main/ets/' + name, import.meta.url), 'utf8');
const load = source => import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
const models = await load(read('model/Models.ets'));
const at = '2026-11-16T04:00:00Z';
const imageItem = (id, path, threadId = 'source') => ({ id, threadId, runId: 'run', ordinal: 1,
  type: 'dynamic_tool', toolName: 'view_image', viewedImagePath: path, status: 'completed', updatedAt: at });
function stateFor(items) {
  const state = new models.ThreadState();
  state.apply({ kind: 'snapshot', snapshotSequence: 1, projection: {
    thread: { id: 'thread' }, messages: [], runs: [], turnItems: items
  } });
  return state;
}
const rowsFor = (state, expanded = []) => models.transcriptRows(state.messages, state.activities,
  { status: 'running', activeTurnId: 'run' }, null, expanded);

test('collapsed tool summaries retain read-image previews with source-thread identity and deduplicate repeated reads', () => {
  const state = stateFor([imageItem('one', '/workspace/first.jpeg'), imageItem('repeat', '/workspace/first.jpeg'),
    imageItem('two', '/workspace/second.png'), imageItem('inherited', '/workspace/first.jpeg', 'other-source')]);
  const rows = rowsFor(state), group = rows.find(row => row.kind === 'tools');
  assert.match(group.text, /读取了 4 个文件/);
  assert.deepEqual(group.viewedImages, [
    { path: '/workspace/first.jpeg', threadId: 'source' },
    { path: '/workspace/second.png', threadId: 'source' },
    { path: '/workspace/first.jpeg', threadId: 'other-source' }
  ]);
  assert.equal(rows.filter(row => row.kind === 'tool').length, 0);
  const expanded = rowsFor(state, [group.id]);
  assert.equal(expanded.filter(row => row.kind === 'tool').length, 4);
  assert.equal(expanded.flatMap(row => row.viewedImages ?? []).length, 3);
});

test('native image-view items and legacy imagePath payloads keep a visible image without treating arbitrary output as one', () => {
  const state = stateFor([{ ...imageItem('native', 'screens/手机.png'), type: 'image_view' }]);
  assert.equal(rowsFor(state)[0].kind, 'tools');
  assert.deepEqual(rowsFor(state)[0].viewedImages, [{ path: 'screens/手机.png', threadId: 'source' }]);
  const activities = [{ id: 'legacy', turnId: 'run', kind: 'tool.completed', summary: 'Read file', createdAt: at,
    payload: { itemType: 'image_view', threadId: 'legacy-thread', data: { imagePath: 'C:\\screens\\reference.webp' } } }];
  const rows = models.transcriptRows([], activities, { status: 'running', activeTurnId: 'run' }, null, []);
  assert.deepEqual(rows[0].viewedImages, [{ path: 'C:\\screens\\reference.webp', threadId: 'legacy-thread' }]);
  const invalid = stateFor([imageItem('text', '/workspace/readme.txt'), imageItem('multiline', '/a.png\n/b.png'),
    { ...imageItem('command', undefined), type: 'command_execution', output: '/workspace/printed.png' }]);
  assert.equal(rowsFor(invalid).flatMap(row => row.viewedImages ?? []).length, 0);
});

test('an image arriving in a later tool update refreshes its summary while unchanged summaries retain identity', () => {
  const state = stateFor([imageItem('late', undefined)]), before = rowsFor(state);
  state.apply({ kind: 'event', sequence: 2, event: { type: 'turn-item.updated', threadId: 'thread',
    payload: imageItem('late', '/workspace/new.png') } });
  const after = models.reconcileTranscriptRows(before, rowsFor(state));
  assert.notEqual(after[0], before[0]);
  assert.deepEqual(after[0].viewedImages, [{ path: '/workspace/new.png', threadId: 'source' }]);
  assert.equal(models.reconcileTranscriptRows(after, rowsFor(state))[0], after[0]);
});

const { ImageAssets } = await load(read('connection/ImageAssets.ets').replace(/^import .*;$/gm, ''));
test('host image reads request media assets and share URLs without mixing source threads, uploads or environments', async () => {
  const calls = [];
  const rpc = { async call(method, payload) { calls.push({ method, payload });
    return { relativeUrl: '/assets/read-image', expiresAt: Date.now() + 60000 }; } };
  const args = [rpc, 'env', 'http://host', 'source', '/workspace/screenshot.png'];
  const [one, two] = await Promise.all([ImageAssets.mediaSource(...args), ImageAssets.mediaSource(...args)]);
  assert.equal(one, two); assert.equal(calls.length, 1);
  assert.deepEqual(calls[0], { method: 'assets.createUrl', payload: {
    resource: { _tag: 'media-file', threadId: 'source', path: '/workspace/screenshot.png' }
  } });
  await ImageAssets.mediaSource(...args); assert.equal(calls.length, 1);
  await ImageAssets.mediaSource(rpc, 'env', 'http://host', 'another-thread', '/workspace/screenshot.png');
  await ImageAssets.mediaSource(rpc, 'another-environment', 'http://host', 'source', '/workspace/screenshot.png');
  assert.equal(calls.length, 3);
  assert.notEqual(ImageAssets.mediaId('source', '/workspace/screenshot.png'), ImageAssets.mediaId('another-thread', '/workspace/screenshot.png'));
  await ImageAssets.mediaSource(...args, true); assert.equal(calls.length, 4);
  await ImageAssets.source(rpc, 'env', 'http://host', { id: '/workspace/screenshot.png', name: 'screenshot.png', mimeType: 'image/png' });
  assert.equal(calls.at(-1).payload.resource._tag, 'attachment');
});

const previewSource = read('pages/ImagePreview.ets');
const gallerySource = read('model/ImageGallery.ets').replace(/^import .*;$/gm, '');
const editsSource = read('model/ImageEdits.ets');
const { PreviewPage, preview } = await load(`
${gallerySource}
${editsSource}
export const preview = { params: { environmentId: 'env', mediaThreadId: 'source', mediaPath: '/workspace/screenshot.png', name: 'screenshot.png' },
  cached: '', cacheIds: [], mediaCalls: [], attachmentCalls: [], opens: 0, environment: null };
const util={generateRandomUUID:()=> 'preview'};
const router = { getParams: () => preview.params }, getContext = () => ({ filesDir: '/private' });
const EnvironmentSession = { get current() { return preview.environment; } };
const ImageAssets = { mediaId: (thread, path) => JSON.stringify(['media-file', thread, path]),
  cached: async (_dir, _env, id) => { preview.cacheIds.push(id); return typeof preview.cached === 'function' ? preview.cached(id) : preview.cached; },
  mediaSource: async (...args) => { preview.mediaCalls.push(args); return 'file:///private/image-cache/media.img'; },
  source: async (...args) => { preview.attachmentCalls.push(args); return preview.download ? preview.download(args[0],args[3]) : 'file:///private/image-cache/attachment.img'; } };
export class PreviewPage {
  active=true; loading=false; busy=false; panel=''; annotating=false; error=''; name=''; source=''; rpc=null; revision=0;
  environmentId="env"; gallery=previewGallery(preview.params).images; gallerySources=[]; imageIndex=0; documents=new Map(); imageDrafts=new Map(); resetZoom(){}
  restoreKeyboardAvoidMode(){} discardExtras(){return Promise.resolve();}
  ${previewSource.slice(previewSource.indexOf('  aboutToAppear():'),previewSource.indexOf('  onPageShow():'))}
  ${previewSource.slice(previewSource.indexOf('  aboutToDisappear():'),previewSource.indexOf('  private restoreKeyboardAvoidMode('))}
  ${previewSource.slice(previewSource.indexOf('  private edits('), previewSource.indexOf('  private resetZoom(')).replaceAll('private ', '')}
}
`);

test('opening a read-image thumbnail loads its media resource and the cached full-size image remains available offline', async () => {
  const rpc = {close() {throw new Error('borrowed RPC closed');}};
  preview.environment = { descriptor: { environmentId: 'env' }, httpBaseUrl: 'http://host', rpc,
    openRpc: async () => { preview.opens++; return { close() {} }; } };
  const page = new PreviewPage(); await page.reload();
  assert.equal(page.error, ''); assert.equal(preview.mediaCalls.length, 1); assert.equal(preview.attachmentCalls.length, 0);
  assert.equal(preview.mediaCalls[0][0],rpc); assert.equal(preview.mediaCalls[0][3], 'source'); assert.equal(preview.mediaCalls[0][4], '/workspace/screenshot.png');
  preview.environment = null; preview.cached = page.source;
  const offline = new PreviewPage(); await offline.reload();
  assert.equal(offline.source, page.source); assert.equal(offline.error, ''); assert.equal(preview.opens, 0);
  assert.equal(preview.cacheIds.at(-1), JSON.stringify(['media-file', 'source', '/workspace/screenshot.png']));
});

test('a slow previous image never replaces the selected image after a fast gallery switch', async () => {
  let release;
  const slow = new Promise(resolve => { release = resolve; });
  preview.cached = id => id.includes('first') ? slow : 'file:///second.png';
  const page = new PreviewPage();
  page.gallery = [{ name: 'first.png', attachmentId: 'first' }, { name: 'second.png', attachmentId: 'second' }];
  const first = page.reload();
  page.imageIndex = 1; await page.reload();
  assert.equal(page.source, 'file:///second.png');
  release('file:///first.png'); await first;
  assert.equal(page.source, 'file:///second.png'); assert.equal(page.loading, false); assert.equal(page.name, 'second.png');
  preview.cached = '';
});

test('a cached commentable image opens and closes without contacting the environment', async () => {
  preview.params.commentThreadId='chat'; preview.cached='file:///cached.png'; preview.environment=null;
  const page = new PreviewPage(); let extras=0;page.prepareExtraRpc=async()=>{extras++;};
  page.aboutToAppear(); await new Promise(resolve=>setImmediate(resolve));assert.equal(page.source,preview.cached);
  page.aboutToDisappear();assert.equal(extras,0);delete preview.params.commentThreadId;
});

test('switching uncached images and closing during a late download leaves the environment connected', async () => {
  let releases=[],closed=0; const clients=[]; const rpc={close(){closed++;}};
  preview.cached='';preview.environment={descriptor:{environmentId:'env'},rpc,openRpc:async()=>{throw new Error('unexpected new socket');}};
  preview.download=(client,attachment)=>{clients.push(client); return new Promise(resolve=>releases.push(()=>resolve('file:///'+attachment.id)));};
  try {
    const page=new PreviewPage();page.gallery=[{name:'one',attachmentId:'one'},{name:'two',attachmentId:'two'}];
    const first=page.reload();await new Promise(resolve=>setImmediate(resolve));page.imageIndex=1;
    const next=page.reload();await new Promise(resolve=>setImmediate(resolve));releases[1]();await next;
    assert.equal(page.source,'file:///two');page.aboutToDisappear();releases[0]();await first;
    assert.deepEqual(clients,[rpc,rpc]);assert.equal(closed,0);assert.equal(page.source,'file:///two');
  } finally {preview.download=null;}
});
