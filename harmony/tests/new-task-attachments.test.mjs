import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const source = readFileSync(new URL('../app/entry/src/main/ets/pages/NewTask.ets', import.meta.url), 'utf8');
const load = source => import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
const methods = source.slice(source.indexOf('  private async loadAttachments('), source.indexOf('  private async dismiss(')).replaceAll('private ', '');
const catalog = source.slice(source.indexOf('  private async refreshCatalog('), source.indexOf('  private async refreshWorkspaceCommands(')).replaceAll('private ', '');
globalThis.__newTaskAttachmentModels = await load(readFileSync(new URL('../app/entry/src/main/ets/model/Models.ets',import.meta.url),'utf8'));
globalThis.__newTaskAttachmentFiles = await load(readFileSync(new URL('../app/entry/src/main/ets/model/FileAttachments.ets',import.meta.url),'utf8'));
globalThis.__newTaskAttachmentMocks = {};
const { Page, environment } = await load(`
const mocks=globalThis.__newTaskAttachmentMocks;
const {availableModels,preferredModelIndex,WS}=globalThis.__newTaskAttachmentModels;
const {fileUploadLimit}=globalThis.__newTaskAttachmentFiles;
const buildCommandCatalog=()=>[];class EmptyPayload {}
const uploadImage=(...args)=>mocks.upload(...args);const deleteImageUpload=async(...args)=>mocks.deleted.push(args);
const AttachmentDraftStore={open:async(...args)=>mocks.open(...args)};const getContext=()=>({filesDir:'/private'});
const picker={DocumentViewPicker:class{async select(){return mocks.selected}}};
const photoAccessHelper={PhotoViewPicker:class{async select(){return {photoUris:mocks.selected}}},PhotoViewMIMETypes:{IMAGE_TYPE:1}};
const fileUri={FileUri:class{constructor(uri){this.name=uri.split('/').at(-1)}}};
export const environment={descriptor:{environmentId:'env'},rpc:{call:async()=>mocks.config??{providers:[],environment:{capabilities:{fileAttachments:{maxUploadBytes:1024}}}}},httpBaseUrl:'http://fixture'};const EnvironmentSession={current:environment};
export class Page {
 ${source.slice(source.indexOf('  private applyModelSelection('),source.indexOf('  private selectModel(')).replaceAll('private ','')}
 environmentId='env';
 ${source.slice(source.indexOf('  private currentConnection('),source.indexOf('  aboutToAppear(')).replaceAll('private ','')}

 draftReady=true;active=true;busy=false;pickingAttachment=false;pendingTurn=null;attachmentStore=null;attachmentUpload=null;
 attachments=[];attachmentsReady=false;maxFileBytes=1024;catalogLoaded=true;connectionState='connected';attachmentEnvironmentId='env';
 models=[];modelIndex=-1;restoredSelection=null;projects=[];projectIndex=0;cache=null;
 ${methods}
 ${catalog}
}`);

function store() {
  return { images: [], async addFile(uri, name, limit) { this.images.push({ uri, name, type: 'file', sizeBytes: 10 }); },
    async setUploaded(uri, uploaded) { this.images = this.images.map(row => row.uri === uri ? { ...row, uploaded } : row); },
    async remove(uri) { this.images = this.images.filter(row => row.uri !== uri); } };
}
const reference = name => ({ type: 'file', id: name, name, mimeType: 'application/pdf', sizeBytes: 10 });

test('selecting documents starts upload before sending and a later selection joins the same transfer', async () => {
  const mocks = globalThis.__newTaskAttachmentMocks, draft = store(), uploads = [];
  mocks.deleted = []; mocks.open = async (_dir, env, id) => { assert.equal(env, 'env'); assert.equal(id, 'new-task'); return draft; };
  let finish; mocks.upload = async (_rpc, _base, _uri, name, progress, type) => {
    uploads.push(name); assert.equal(type, 'file'); progress(50);
    if (uploads.length === 1) await new Promise(resolve => finish = resolve);
    return reference(name);
  };
  const page = new Page(); await page.loadAttachments();
  mocks.selected = ['private/one.pdf']; await page.pickAttachments(true);
  const pending = page.uploadAttachments(); assert.equal(pending, page.uploadAttachments());
  assert.equal(uploads.length, 1); assert.equal(page.attachments[0].progress, 50);
  mocks.selected = ['private/two.pdf']; await page.pickAttachments(true);
  assert.equal(uploads.length, 1); finish(); await pending;
  assert.deepEqual(uploads, ['one.pdf', 'two.pdf']); assert.ok(page.attachments.every(row => row.status === 'uploaded'));
  await page.removeAttachment('private/one.pdf');
  assert.equal(mocks.deleted[0][1], 'one.pdf'); assert.equal(draft.images[0].name, 'two.pdf');
});

test('failed document upload stays in the draft and explicit retry replaces its failure state', async () => {
  const mocks = globalThis.__newTaskAttachmentMocks, page = new Page(), draft = store();
  mocks.open = async () => draft; mocks.selected = ['private/retry.pdf']; mocks.upload = async () => { throw new Error('offline'); };
  await page.loadAttachments(); await page.pickAttachments(true); await page.uploadAttachments();
  assert.equal(page.attachments[0].status, 'failed'); assert.match(page.error, /offline/); assert.equal(draft.images.length, 1);
  mocks.upload = async () => reference('retry.pdf'); await page.uploadAttachments();
  assert.equal(page.attachments[0].status, 'uploaded'); assert.equal(draft.images[0].uploaded.id, 'retry.pdf');
});

test('new-task documents stay local while reconnecting and upload automatically after fresh file capabilities arrive', async () => {
  const mocks=globalThis.__newTaskAttachmentMocks,draft=store(),uploads=[];
  mocks.open=async()=>draft;mocks.selected=['private/offline.pdf'];
  mocks.config={providers:[],environment:{capabilities:{fileAttachments:{maxUploadBytes:1024}}}};
  mocks.upload=async(_rpc,_base,_uri,name,_progress,type,limit)=>{
    uploads.push(name);assert.equal(type,'file');assert.equal(limit,1024);return reference(name);
  };
  const page=new Page();page.connectionState='reconnecting';page.catalogLoaded=false;page.maxFileBytes=0;
  await page.loadAttachments();await page.pickAttachments(true);await page.uploadAttachments();
  assert.deepEqual(uploads,[]);assert.equal(draft.images[0].name,'offline.pdf');assert.equal(page.attachments[0].status,'waiting');
  page.connectionState='connected';page.resumeAttachmentUploads();
  for(let i=0;i<12;i++)await Promise.resolve();
  await page.uploadAttachments();
  assert.deepEqual(uploads,['offline.pdf']);assert.equal(page.attachments[0].status,'uploaded');assert.equal(page.maxFileBytes,1024);
});

test('waiting for file capabilities does not block photo uploads in a restored new-task draft',async()=>{
  const mocks=globalThis.__newTaskAttachmentMocks,draft=store(),uploads=[];
  draft.images=[{uri:'file',name:'later.pdf',type:'file'},{uri:'photo',name:'ready.png',type:'image'}];
  mocks.open=async()=>draft;mocks.upload=async(_rpc,_base,_uri,name)=>{uploads.push(name);return reference(name);};
  const page=new Page();page.catalogLoaded=false;page.maxFileBytes=0;
  await page.loadAttachments();await page.uploadAttachments();
  assert.deepEqual(uploads,['ready.png']);assert.equal(page.attachments[0].status,'waiting');
  await page.refreshCatalog(environment);await page.uploadAttachments();
  assert.deepEqual(uploads,['ready.png','later.pdf']);assert.ok(page.attachments.every(row=>row.status==='uploaded'));
});
test('reconnecting waits for the interrupted transfer before retrying its retained document',async()=>{
  const mocks=globalThis.__newTaskAttachmentMocks,draft=store(),uploads=[];
  let failTransfer;mocks.open=async()=>draft;mocks.selected=['private/interrupted.pdf'];
  mocks.upload=async(_rpc,_base,_uri,name)=>{
    uploads.push(name);if(uploads.length===1)await new Promise((_resolve,reject)=>failTransfer=reject);return reference(name);
  };
  const page=new Page();await page.loadAttachments();await page.pickAttachments(true);
  page.connectionState='reconnecting';page.resumeAttachmentUploads();
  page.connectionState='connected';page.resumeAttachmentUploads();
  for(let i=0;i<12;i++)await Promise.resolve();
  failTransfer(new Error('connection closed'));
  for(let i=0;i<24;i++)await Promise.resolve();
  assert.deepEqual(uploads,['interrupted.pdf','interrupted.pdf']);assert.equal(page.attachments[0].status,'uploaded');
});
test('a configuration response from the previous socket cannot authorize an upload after reconnecting',async()=>{
  const mocks=globalThis.__newTaskAttachmentMocks,draft=store(),uploads=[],rpc=environment.rpc;
  draft.images=[{uri:'pending',name:'pending.pdf',type:'file'}];mocks.open=async()=>draft;
  mocks.upload=async(_rpc,_base,_uri,name)=>{uploads.push(name);return reference(name);};
  let finish;environment.rpc={call:()=>new Promise(resolve=>finish=resolve)};
  try {
    const page=new Page();page.catalogLoaded=false;await page.loadAttachments();
    const stale=page.refreshCatalog(environment);
    environment.rpc=rpc;finish({providers:[],environment:{capabilities:{fileAttachments:{maxUploadBytes:1}}}});await stale;
    assert.equal(page.catalogLoaded,false);assert.deepEqual(uploads,[]);
    await page.refreshCatalog(environment);await page.uploadAttachments();assert.deepEqual(uploads,['pending.pdf']);
  } finally {environment.rpc=rpc;}
});

test('a local attachment in the cold new-task draft can be restored and removed without a connection',async()=>{
 const page=new Page(),draft=store();page.environmentId='offline';page.connectionState='offline';draft.images=[{uri:'local-draft',name:'Notes.pdf',type:'file'}];
 const previous=environment.descriptor;environment.descriptor={environmentId:'elsewhere'};
 const calls=[];globalThis.__newTaskAttachmentMocks.open=async(...args)=>{calls.push(args);return draft};
 try{await page.loadAttachments();assert.deepEqual(calls,[['/private','offline','new-task']]);assert.equal(page.attachments[0].uri,'local-draft');
 await page.removeAttachment('local-draft');assert.deepEqual(page.attachments,[]);}finally{environment.descriptor=previous;}
});
