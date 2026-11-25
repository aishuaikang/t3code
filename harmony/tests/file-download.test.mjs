import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, openSync, closeSync, writeSync, existsSync, unlinkSync, readdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { stripTypeScriptTypes } from 'node:module';

const source = readFileSync(new URL('../app/entry/src/main/ets/connection/FileDownload.ets', import.meta.url), 'utf8').replace(/^import .*;\n/gm, '');
const resource = { _tag: 'media-file', threadId: 'thread', path: '/workspace/output/中文报告.pdf', disposition: 'attachment' };
const pdf = Buffer.concat([Buffer.from('%PDF-1.7\n'), Buffer.from([0, 255, 128, 10, 0]), Buffer.from('%%EOF')]);
let revision = 0;
async function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 't3-file-download-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const pending = [], waiters = [], clients = [], calls = [];
  let writeFailure = false;
  const fs = {
    OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 },
    open: async path => ({ fd: openSync(path, 'w') }),
    write: async (fd, bytes) => {
      if (writeFailure) throw new Error('ENOSPC');
      // Real writes deliberately split each chunk, exercising short-write handling.
      return writeSync(fd, Buffer.from(bytes), 0, Math.min(bytes.byteLength, 3));
    },
    close: async file => closeSync(file.fd),
    copyFile: async (path, fd) => { writeSync(fd, readFileSync(path)); },
    accessSync: existsSync,
    unlink: async path => unlinkSync(path)
  };
  const http = { RequestMethod: { GET: 'GET' }, createHttp() {
    const events = new Map();
    let rejectResponse;
    const client = {
      destroyed: false,
      on(type, callback) { events.set(type, callback); },
      off(type) { events.delete(type); },
      emit(type, value) { events.get(type)?.(value); },
      destroy() { client.destroyed = true; rejectResponse?.(new Error('destroyed')); },
      requestInStream(url, options) {
        client.url = url; client.options = options;
        const result = new Promise((resolve, reject) => { client.resolve = resolve; client.reject = rejectResponse = reject; });
        const waiter = waiters.shift(); if (waiter) waiter(client); else pending.push(client);
        return result;
      }
    };
    clients.push(client); return client;
  } };
  const util = { generateRandomUUID: () => `fixture-${++revision}` };
  globalThis.__fileDownload = { fs, http, util };
  const body = `const {fs,http,util}=globalThis.__fileDownload;\n${source}\n// ${++revision}`;
  const { FileDownload } = await import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(body)).toString('base64'));
  const rpc = { async call(method, payload) {
    calls.push([method, payload]);
    return { relativeUrl: `/assets/file?signature=${calls.length}` };
  } };
  const next = () => pending.length ? Promise.resolve(pending.shift()) : new Promise(resolve => waiters.push(resolve));
  const complete = (client, status = 200, chunks = [pdf]) => {
    for (const chunk of chunks) client.emit('dataReceive', Uint8Array.from(chunk).buffer);
    client.emit('dataEnd'); client.resolve(status);
  };
  return { FileDownload, root, rpc, calls, clients, next, complete, failWrites() { writeFailure = true; } };
}

test('streamed PDF saves exact original bytes after both HTTP completion and all short writes finish', async t => {
  const f = await fixture(t), download = new f.FileDownload();
  let finished = false;
  const fetch = download.fetch(f.rpc, 'https://relay/prefix/', resource, f.root).then(() => { finished = true; });
  const request = await f.next();
  assert.equal(request.url, 'https://relay/prefix/assets/file?signature=1');
  assert.equal(request.options.usingCache, false);
  assert.deepEqual(f.calls, [['assets.createUrl', { resource }]]);
  request.resolve(200);
  await Promise.resolve(); await Promise.resolve();
  assert.equal(finished, false);
  f.complete(request, 200, [pdf.subarray(0, 2), pdf.subarray(2, 8), pdf.subarray(8)]);
  await fetch;
  const target = join(f.root, '中文报告.pdf');
  await download.save(target); await download.dispose();
  assert.deepEqual(readFileSync(target), pdf);
  assert.deepEqual(readdirSync(f.root), ['中文报告.pdf']);
  assert.ok(request.destroyed);
});

test('expired download URL is freshly signed once before retrying the original resource', async t => {
  const f = await fixture(t), download = new f.FileDownload();
  const fetch = download.fetch(f.rpc, 'http://host', resource, f.root);
  f.complete(await f.next(), 401, [Buffer.from('unauthorized')]);
  const retry = await f.next();
  assert.equal(retry.url, 'http://host/assets/file?signature=2');
  assert.equal(f.calls.length, 2);
  assert.deepEqual(f.calls[1][1], { resource });
  f.complete(retry); await fetch;
  const target = join(f.root, 'report.pdf'); await download.save(target); await download.dispose();
  assert.deepEqual(readFileSync(target), pdf);
});

test('persistent authorization failure stops after two requests and removes temporary data', async t => {
  const f = await fixture(t), download = new f.FileDownload();
  const result = assert.rejects(download.fetch(f.rpc, 'http://host', resource, f.root), /凭证已过期/);
  f.complete(await f.next(), 403, []); f.complete(await f.next(), 403, []);
  await result;
  assert.equal(f.calls.length, 2); assert.deepEqual(readdirSync(f.root), []);
});

test('missing file is reported without retrying it or retaining a corrupt download', async t => {
  const f = await fixture(t), download = new f.FileDownload();
  const result = assert.rejects(download.fetch(f.rpc, 'http://host', resource, f.root), /文件不存在或已移动/);
  f.complete(await f.next(), 404, []); await result;
  assert.equal(f.calls.length, 1); assert.deepEqual(readdirSync(f.root), []);
});

test('a broken transfer removes partial bytes and a later user retry can succeed', async t => {
  const f = await fixture(t), broken = new f.FileDownload();
  const failure = assert.rejects(broken.fetch(f.rpc, 'http://host', resource, f.root), /下载中断/);
  const first = await f.next(); first.emit('dataReceive', Uint8Array.from(pdf.subarray(0, 7)).buffer);
  first.reject(new Error('network lost')); await failure;
  assert.deepEqual(readdirSync(f.root), []);
  const retry = new f.FileDownload();
  const success = retry.fetch(f.rpc, 'http://host', resource, f.root);
  f.complete(await f.next()); await success; await retry.dispose();
  assert.deepEqual(readdirSync(f.root), []);
});

test('HTTP 200 login or proxy HTML is not saved as a PDF', async t => {
  const f = await fixture(t), download = new f.FileDownload();
  const result = assert.rejects(download.fetch(f.rpc, 'http://host', resource, f.root), /有效的 PDF/);
  f.complete(await f.next(), 200, [Buffer.from('<html>login required</html>')]); await result;
  assert.deepEqual(readdirSync(f.root), []);
});

test('signed responses cannot redirect the downloader to another origin', async t => {
  const f = await fixture(t);
  for (const relativeUrl of ['https://elsewhere/file', '//elsewhere/file', '/\\elsewhere/file', '/bad\npath']) {
    const download = new f.FileDownload();
    await assert.rejects(download.fetch({ call: async () => ({ relativeUrl }) }, 'http://host', resource, f.root), /地址无效/);
  }
  assert.equal(f.clients.length, 0); assert.deepEqual(readdirSync(f.root), []);
});

test('leaving the page aborts the request and removes its temporary file', async t => {
  const f = await fixture(t), download = new f.FileDownload();
  const result = assert.rejects(download.fetch(f.rpc, 'http://host', resource, f.root), /取消/);
  const request = await f.next(); request.emit('dataReceive', Uint8Array.from(pdf).buffer);
  download.cancel(); await result;
  assert.ok(request.destroyed); assert.deepEqual(readdirSync(f.root), []);
});

test('cancelling while waiting for the signed URL prevents starting a transfer', async t => {
  const f = await fixture(t), download = new f.FileDownload();
  let mint; const result = assert.rejects(download.fetch({ call: () => new Promise(resolve => { mint = resolve; }) }, 'http://host', resource, f.root), /取消/);
  download.cancel(); mint({ relativeUrl: '/assets/file' }); await result;
  assert.equal(f.clients.length, 0); assert.deepEqual(readdirSync(f.root), []);
});

test('disk failure terminates the stream without saving an incomplete document', async t => {
  const f = await fixture(t), download = new f.FileDownload(); f.failWrites();
  const result = assert.rejects(download.fetch(f.rpc, 'http://host', resource, f.root), /手机剩余空间/);
  const request = await f.next(); request.emit('dataReceive', Uint8Array.from(pdf).buffer);
  await result;
  assert.ok(request.destroyed); assert.deepEqual(readdirSync(f.root), []);
});

test('disk failure after the response ends still reports a readable error and deletes partial data', async t => {
  const f = await fixture(t), download = new f.FileDownload(); f.failWrites();
  const result = assert.rejects(download.fetch(f.rpc, 'http://host', resource, f.root), /手机剩余空间/);
  f.complete(await f.next()); await result;
  assert.deepEqual(readdirSync(f.root), []);
});
