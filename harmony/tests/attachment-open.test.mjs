import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
const source = readFileSync(new URL('../app/entry/src/main/ets/pages/AttachmentText.ets', import.meta.url), 'utf8');
const body = source.slice(source.indexOf('export struct AttachmentText {'), source.indexOf('  build()'))
  .replace('export struct AttachmentText {', 'export class AttachmentText {')
  .replace(/@(Prop|State|(?:StorageLink|Watch)\([^)]*\))\s+/g, '') + '\n}';
const routes = [];
globalThis.__attachmentRoutes = routes;
const fixture = `const routes=globalThis.__attachmentRoutes;const router={pushUrl:route=>routes.push(route)};
const resolveTypography=()=>({baseFontSize:16});const attachmentGallery=items=>items.filter(item=>item.type==='image');\n${body}`;
const { AttachmentText } = await import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(fixture)).toString('base64'));

test('file cards open the downloadable attachment with its original environment, identity and metadata', () => {
  routes.length = 0;
  const card = new AttachmentText();
  card.environmentId = 'origin'; card.threadId = 'thread';
  card.attachments = [{ id: 'file.pdf', type: 'file', name: '中文文档.pdf', mimeType: 'application/pdf', sizeBytes: 163840 }];
  card.open('file.pdf');
  assert.deepEqual(routes, [{ url: 'pages/Files', params: { environmentId: 'origin', threadId: 'thread', attachmentId: 'file.pdf', name: '中文文档.pdf', mimeType: 'application/pdf' } }]);
});

test('opening file cards does not disturb image lightbox navigation', () => {
  routes.length = 0;
  const card = new AttachmentText(); card.threadId = 'thread';
  card.attachments = [{ id: 'one', type: 'image', name: 'one.png', mimeType: 'image/png' }, { id: 'file', type: 'file', name: 'file.pdf' }, { id: 'two', type: 'image', name: 'two.jpg', mimeType: 'image/jpeg' }];
  card.open('two');
  assert.equal(routes[0].url, 'pages/ImagePreview');
  assert.equal(routes[0].params.imageIndex, '1');
  assert.equal(JSON.parse(routes[0].params.gallery).length, 2);
  card.open('missing'); assert.equal(routes.length, 1);
});
