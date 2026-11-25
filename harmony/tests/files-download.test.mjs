import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const entries = readFileSync(new URL('../app/entry/src/main/ets/model/FileEntries.ets', import.meta.url), 'utf8');
const source = readFileSync(new URL('../app/entry/src/main/ets/pages/Files.ets', import.meta.url), 'utf8');
const page = source.slice(source.indexOf('struct FilesPage {'), source.indexOf('  @Builder'))
  .replace('struct FilesPage {', 'export class FilesPage {')
  .replace(/@(State|StorageLink\([^)]*\))\s+/g, '') + '\n}';
const calls = [];
let chosen = ['content://documents/report.pdf'];
let transfer = async () => {};
const rpc = { close() {}, async call(method, payload) {
  calls.push([method, payload]);
  return { relativePath: payload.relativePath, contents: 'source code', byteLength: 11, truncated: false };
} };
const EnvironmentSession = { current: { descriptor: { environmentId: 'env' }, httpBaseUrl: 'http://host:3773', async openRpc() { return rpc; } } };
class FileDownload {
  cancel() { calls.push(['cancel']); }
  async fetch(...args) { calls.push(['fetch', ...args.slice(0, 4)]); await transfer(); }
  async save(uri) { calls.push(['save', uri]); }
  async dispose() { calls.push(['dispose']); }
}
const picker = { DocumentViewPicker: class { async save(options) { calls.push(['picker', options]); return chosen; } } };
globalThis.__filesDownload = { EnvironmentSession, FileDownload, picker, calls };
const fixture = `const {EnvironmentSession,FileDownload,picker,calls}=globalThis.__filesDownload;
const resolveTypography=()=>({baseFontSize:16});const scaledFontSize=size=>size;
const getContext=()=>({cacheDir:'/cache'});const promptAction={showToast:options=>calls.push(['toast',options])};
const router={back(){}};\n${entries}\n${page}`;
const { FilesPage } = await import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(fixture)).toString('base64'));
function setup(path = 'output/pdf/2023010557张英霄.pdf') {
  calls.length = 0; chosen = ['content://documents/report.pdf']; transfer = async () => {};
  const result = new FilesPage();
  Object.assign(result, { active: true, cwd: '/workspace', selectedPath: path, threadId: 'thread', environmentId: 'env' });
  return result;
}

test('location resolves the open directory or file on its host and treats an attachment as a filename', () => {
  const page = setup(''); page.cwd = '/workspace/project/';
  assert.equal(page.location(), '/workspace/project/');
  page.directory = 'docs'; assert.equal(page.location(), '/workspace/project/docs');
  page.selectedPath = 'docs/资料.md'; assert.equal(page.location(), '/workspace/project/docs/资料.md');
  page.cwd = 'D:\\工作区\\'; assert.equal(page.location(), 'D:\\工作区\\docs\\资料.md');
  page.attachmentId = 'upload'; page.attachmentName = '讲义.pdf'; assert.equal(page.location(), '讲义.pdf');
});

test('generated PDF opens as a downloadable file without sending binary bytes through projects.readFile', async () => {
  const page = setup();
  await page.reload();
  assert.equal(calls.some(([method]) => method === 'projects.readFile'), false);
  assert.equal(page.downloadOnly, true);
  assert.equal(page.error, '');
});

test('source files retain their text preview and source positions', async () => {
  const page = setup('src/code.ts'); page.initialLine = 27;
  await page.reload();
  assert.equal(page.file.contents, 'source code');
  assert.equal(page.initialLine, 27);
  assert.equal(calls[0][0], 'projects.readFile');
});

test('download uses the originating thread and preserves the Chinese file name in the system save picker', async () => {
  const page = setup();
  await page.saveFile();
  const fetch = calls.find(([method]) => method === 'fetch');
  assert.deepEqual(fetch.slice(1), [rpc, 'http://host:3773', { _tag: 'media-file', threadId: 'thread', path: '/workspace/' + page.selectedPath, disposition: 'attachment' }, '/cache']);
  assert.deepEqual(calls.find(([method]) => method === 'picker')[1], { newFileNames: ['2023010557张英霄.pdf'] });
  assert.ok(calls.some(([method, uri]) => method === 'save' && uri === chosen[0]));
  assert.equal(page.saving, false);
});

test('uploaded file cards can download the attachment without a workspace directory', async () => {
  const page = setup('');
  Object.assign(page, { cwd: '', attachmentId: 'uploaded', attachmentName: '资料.docx', mimeType: 'application/octet-stream' });
  await page.saveFile();
  assert.deepEqual(calls.find(([method]) => method === 'fetch')[3], {
    _tag: 'attachment', attachmentId: 'uploaded', fileName: '资料.docx', mimeType: 'application/octet-stream'
  });
});

test('downloads cannot silently switch to another connected environment', async () => {
  const page = setup(); page.environmentId = 'other';
  await page.saveFile();
  assert.match(page.error, /文件所在的环境/);
  assert.equal(calls.some(([method]) => method === 'fetch' || method === 'picker'), false);
});

test('leaving a file during download does not open the picker or save the next file', async () => {
  const page = setup();
  let finish; transfer = () => new Promise(resolve => { finish = resolve; });
  const saving = page.saveFile();
  for (let step = 0; step < 20 && !finish; step++) await Promise.resolve();
  assert.ok(finish);
  page.back(); finish(); await saving;
  assert.equal(calls.some(([method]) => method === 'picker' || method === 'save'), false);
  assert.ok(calls.some(([method]) => method === 'dispose'));
});

test('cancelling the system picker releases the temporary download without an error', async () => {
  const page = setup(); chosen = [];
  await page.saveFile();
  assert.equal(calls.some(([method]) => method === 'save' || method === 'toast'), false);
  assert.ok(calls.some(([method]) => method === 'dispose'));
  assert.equal(page.error, '');
});
