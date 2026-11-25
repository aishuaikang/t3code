import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
const source = readFileSync(new URL('../app/entry/src/main/ets/pages/Thread.ets', import.meta.url), 'utf8');
const methods = source.slice(source.indexOf('  private async removeImage('), source.indexOf('  private async send('))
  .replace(/  @Builder\n  private attachmentMenu\(\) \{[\s\S]*?\n  \}\n/, '').replaceAll('private ', '');
const body = `
const photoAccessHelper={PhotoViewPicker:class{async select(){return {photoUris:['chosen-photo']}}},PhotoViewMIMETypes:{IMAGE_TYPE:'image'}};
const fileUri={FileUri:class{constructor(uri){this.name=uri==='chosen-photo'?'original.png':'说明.pdf';}}};
const picker={DocumentViewPicker:class{async select(){return ['chosen-file'];}}};
const uploadImage=(...args)=>globalThis.__eagerUpload(...args);
const deleteImageUpload=async(rpc,id)=>{globalThis.__deletedUploads.push(id)};
const EnvironmentSession={current:{descriptor:{environmentId:'e'},httpBaseUrl:'http://fixture'}};
export class Fixture {
 active=true;loaded=true;journalReady=true;hasPendingSend=false;imagesReady=true;pickingImage=false;sending=false;catalogLoaded=true;maxFileBytes=1024;
 imageUris=[];imageProgress=[];imageUpload=null;removingImages=new Set();params={environmentId:'e'};rpc={};
 imageStore={images:[],add:async(uri,name)=>{this.imageStore.images.push({uri,name})},
 addFile:async(uri,name)=>{this.imageStore.images.push({uri,name,type:'file',sizeBytes:10})},
 setUploaded:async(uri,uploaded)=>{this.imageStore.images=this.imageStore.images.map(i=>i.uri===uri?{...i,uploaded}:i)},
 remove:async(uri)=>{this.imageStore.images=this.imageStore.images.filter(i=>i.uri!==uri)}};
 ${methods}
}`;
const { Fixture } = await import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(body)).toString('base64'));
const uploaded = { type: 'image', id: 'server-image', name: 'original.png', mimeType: 'image/png', sizeBytes: 8 };
function deferred() { let resolve, reject; const promise = new Promise((yes, no) => { resolve = yes; reject = no; }); return { promise, resolve, reject }; }

test('selecting a photo begins uploading before send, exposes progress and reuses the completed reference', async () => {
  globalThis.__deletedUploads = [];
  const page = new Fixture(), transfer = deferred(), finished = deferred(); let calls = 0;
  globalThis.__eagerUpload = async (rpc, base, uri, name, progress) => {
    calls++; assert.equal(uri, 'chosen-photo'); assert.equal(name, 'original.png'); progress(37);
    return transfer.promise;
  };
  const persist = page.imageStore.setUploaded;
  page.imageStore.setUploaded = async (...args) => { await persist(...args); finished.resolve(); };
  await page.pickImages();
  assert.equal(calls, 1); assert.equal(page.imageItems()[0].progress, 37); assert.equal(page.imagesUploaded(), false);
  transfer.resolve(uploaded); await finished.promise;
  assert.equal(page.imagesUploaded(), true); assert.deepEqual(page.imageStore.images[0].uploaded, uploaded);
  await page.uploadDraftImages(); assert.equal(calls, 1); assert.deepEqual(globalThis.__deletedUploads, []);
});
test('deleting a photo while bytes are in flight discards the upload without restoring the local draft', async () => {
  globalThis.__deletedUploads = [];
  const page = new Fixture(), transfer = deferred(), deleted = deferred();
  globalThis.__eagerUpload = () => transfer.promise;
  await page.pickImages(); await page.removeImage('chosen-photo');
  assert.deepEqual(page.imageUris, []); assert.deepEqual(page.imageStore.images, []);
  const persist = page.imageStore.setUploaded;
  page.imageStore.setUploaded = async (...args) => { await persist(...args); deleted.resolve(); };
  transfer.resolve(uploaded); await deleted.promise;
  await Promise.resolve(); await Promise.resolve();
  assert.deepEqual(globalThis.__deletedUploads, ['server-image']); assert.deepEqual(page.imageStore.images, []);
});
test('failed uploads preserve selected files and retry only when requested', async () => {
  globalThis.__deletedUploads = [];
  const page = new Fixture(); let calls = 0;
  globalThis.__eagerUpload = async () => { calls++; throw new Error('offline'); };
  await page.pickImages();
  await Promise.resolve();
  assert.equal(page.imageItems()[0].status, 'failed'); assert.equal(page.imageUris.length, 1);
  await page.uploadDraftImages(); assert.equal(calls, 1);
  globalThis.__eagerUpload = async () => { calls++; return uploaded; };
  page.retryImage('chosen-photo');
  await Promise.resolve(); await Promise.resolve(); await Promise.resolve();
  assert.equal(calls, 2); assert.equal(page.imagesUploaded(), true);
});
test('a pending journal prevents background uploads from changing the attachments under retry', async () => {
  const page = new Fixture(); page.hasPendingSend = true; let calls = 0;
  page.imageStore.images = [{ uri: 'retained-photo' }];
  globalThis.__eagerUpload = async () => { calls++; return uploaded; };
  await page.uploadDraftImages(); assert.equal(calls, 0);
});
test('documents can be selected while the thread is offline and upload with fresh limits once connected',async()=>{
  globalThis.__deletedUploads=[];const page=new Fixture(),uploads=[];
  page.loaded=false;page.rpc=null;page.maxFileBytes=0;page.catalogLoaded=false;
  globalThis.__eagerUpload=async(_rpc,_base,uri,name,_progress,type,limit)=>{
    uploads.push({uri,name,type,limit});return {...uploaded,type:'file',name};
  };
  await page.pickFiles();assert.equal(page.imageUris.length,1);assert.deepEqual(uploads,[]);
  assert.equal(page.imageItems()[0].name,'说明.pdf');assert.equal(page.imageItems()[0].status,'waiting');
  page.loaded=true;page.rpc={};page.catalogLoaded=true;page.maxFileBytes=2048;await page.uploadDraftImages();
  assert.deepEqual(uploads,[{uri:'chosen-file',name:'说明.pdf',type:'file',limit:2048}]);assert.equal(page.imagesUploaded(),true);
});
test('a document waiting for the catalog does not hold up later photos in the same thread draft',async()=>{
  globalThis.__deletedUploads=[];const page=new Fixture(),uploads=[];page.catalogLoaded=false;page.maxFileBytes=0;
  page.imageStore.images=[{uri:'file',name:'later.pdf',type:'file'},{uri:'photo',name:'ready.png'}];page.imageUris=['file','photo'];
  globalThis.__eagerUpload=async(_rpc,_base,uri)=>{uploads.push(uri);return {...uploaded,id:uri};};
  await page.uploadDraftImages();assert.deepEqual(uploads,['photo']);assert.equal(page.imageItems()[0].status,'waiting');
  page.catalogLoaded=true;page.maxFileBytes=1024;await page.uploadDraftImages();
  assert.deepEqual(uploads,['photo','file']);assert.equal(page.imagesUploaded(),true);
});
