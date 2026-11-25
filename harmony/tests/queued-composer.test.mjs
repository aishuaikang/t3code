import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
const read = p => readFileSync(new URL('../app/entry/src/main/ets/' + p, import.meta.url), 'utf8');
const load=s=>import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(s)).toString('base64'));
const models=await load(read('model/Models.ets'));globalThis.__queueModels=models;
const src=read('pages/Thread.ets');
const methods=src.slice(src.indexOf('  private async beginQueueEdit('),src.indexOf('  private async queueAction(')).replaceAll('private ','');
const remove=src.slice(src.indexOf('  private async removeImage('),src.indexOf('  private async receiveImageComment(')).replaceAll('private ','');
const { Page, mocks }=await load(`
const {queuedMessageCommand,WS}=globalThis.__queueModels;
${read('model/QueuedDraft.ets').replace(/^import .*;$/gm,'')}
${read('model/MessageQuote.ets').replace(/^import .*;$/gm,'')}
export const mocks={stores:new Map(),images:new Map(),deleted:[],next:0};
const getContext=()=>({filesDir:'/private'}),util={generateRandomUUID:()=> 'command-'+ ++mocks.next},EnvironmentSession={current:{descriptor:{environmentId:'env'}}};
const DraftStore={open:async(dir,env,scope)=>{if(!mocks.stores.has(scope))mocks.stores.set(scope,{text:'',save:async function(text){this.text=text;},load:async function(){return this.text;}});return mocks.stores.get(scope);}};
const AttachmentDraftStore={open:async(dir,env,scope)=>{if(!mocks.images.has(scope))mocks.images.set(scope,{images:[],clear:async function(){this.images=[];},remove:async function(uri){this.images=this.images.filter(i=>i.uri!==uri);}});return mocks.images.get(scope);}};
const deleteImageUpload=async(rpc,id)=>mocks.deleted.push(id);
export class Page {
 editingQueue=null;queueAttachments=[];mainDraft=null;pendingQueueEdit=null;active=true;readVisible=true;loaded=true;queueBusy=false;sending=false;hasPendingSend=false;pickingImage=false;draftReady=true;imagesReady=true;
 params={threadId:'thread',environmentId:'env'};draft='主草稿';draftQuote=null;draftTimer=-1;draftStatus='草稿已保存';imageProgress=[{uri:'original'}];imageUris=['original'];imageUpload=null;removingImages=new Set();
 draftStore={text:'主草稿',save:async function(text){this.text=text;}};
 imageStore={images:[{uri:'original',uploaded:{id:'original-upload'}}]};
 state=null;queue=[];calls=[];failAck=false;failUpload=false;operationError='';
 rpc={call:async(method,command)=>{this.calls.push(command);if(this.failAck)throw Error('receipt lost');}};
 cancelPaths(){} imagesUploaded(){return this.imageStore.images.every(i=>i.uploaded);}
 uploadDraftImages(){if(!this.failUpload)for(const image of this.imageStore.images)image.uploaded??={type:'image',id:image.uri,name:'new.png'};return Promise.resolve();}
 async saveDraft(){await this.draftStore.save(queuedDraftText(this.editingQueue,quotedMessageText(this.draft,this.draftQuote),this.queueAttachments));}
 ${methods}
 ${remove}
}
`);
function fixture() {
 const state=new models.ThreadState();
 state.apply({kind:'snapshot',snapshotSequence:1,projection:{thread:{id:'thread'},runs:[{id:'queued',threadId:'thread',userMessageId:'message',ordinal:1,status:'queued',requestedAt:'now'}],
  messages:[{id:'message',runId:'queued',role:'user',text:'待发送',attachments:[{type:'image',id:'remote',name:'remote.png'}]}],visibleTurnItems:[]}});
 const p=new Page();p.state=state;p.queue=models.queuedMessages(state.thread,state.messages);
 mocks.stores.clear();mocks.images.clear();mocks.deleted=[];return p;
}
test('queue editing uses the main composer and cancel restores its exact original text and attachment store',async()=>{
 const p=fixture(),original=p.imageStore,main=p.draftStore;await p.beginQueueEdit(p.queue[0]);
 assert.equal(p.draft,'待发送');assert.equal(p.queueAttachments[0].id,'remote');assert.notEqual(p.imageStore,original);assert.equal(main.text,'主草稿');
 p.draft='修改内容';p.imageStore.images.push({uri:'new'});await p.cancelQueueEdit();
 assert.equal(p.draft,'主草稿');assert.equal(p.imageStore,original);assert.equal(p.draftStore,main);assert.deepEqual(p.imageUris,['original']);assert.equal(p.editingQueue,null);assert.deepEqual(mocks.deleted,[]);
});
test('removing retained attachments is local until save, which explicitly replaces the remote list',async()=>{
 const p=fixture();await p.beginQueueEdit(p.queue[0]);await p.removeImage('queued:remote');assert.deepEqual(mocks.deleted,[]);
 p.draft='新的排队内容';p.imageStore.images.push({uri:'new'});await p.saveQueueEdit();
 assert.equal(p.calls.length,1);assert.equal(p.calls[0].type,'queued-run.edit');assert.equal(p.calls[0].text,'新的排队内容');assert.deepEqual(p.calls[0].attachments.map(i=>i.id),['new']);assert.equal(p.draft,'主草稿');
});
test('image-only queue edits save retained or newly uploaded images and restore the main draft',async()=>{
 for(const replace of [false,true]) {
  const p=fixture(),original=p.imageStore;await p.beginQueueEdit(p.queue[0]);p.draft='';
  if(replace) {await p.removeImage('queued:remote');p.imageStore.images.push({uri:'new'});p.imageUris=['new'];}
  assert.equal(p.canSaveQueueEdit(),true);await p.saveQueueEdit();
  assert.equal(p.calls.length,1);assert.equal(p.calls[0].text,'');
  assert.deepEqual(p.calls[0].attachments.map(i=>i.id),[replace?'new':'remote']);
  assert.equal(p.draft,'主草稿');assert.equal(p.imageStore,original);assert.equal(p.editingQueue,null);
 }
});
test('removing the final image from an empty queue edit disables save without sending a command',async()=>{
 const p=fixture();await p.beginQueueEdit(p.queue[0]);p.draft='';await p.removeImage('queued:remote');
 assert.equal(p.canSaveQueueEdit(),false);await p.saveQueueEdit();assert.equal(p.calls.length,0);assert.ok(p.editingQueue);
});
test('upload failure retains queue edits and a later retry saves the same text without touching the main draft',async()=>{
 const p=fixture();await p.beginQueueEdit(p.queue[0]);p.draft='未丢失';p.imageStore.images.push({uri:'new'});p.failUpload=true;
 await p.saveQueueEdit();assert.match(p.operationError,/上传未完成/);assert.equal(p.draft,'未丢失');assert.equal(p.calls.length,0);assert.equal(p.mainDraft.text,'主草稿');
 p.failUpload=false;await p.saveQueueEdit();assert.equal(p.calls.length,1);assert.equal(p.draft,'主草稿');
});
test('retrying an unconfirmed edit reuses its command and never deletes an upload it may already reference',async()=>{
 const p=fixture();await p.beginQueueEdit(p.queue[0]);p.draft='修改';p.imageStore.images.push({uri:'new'});p.failAck=true;
 await p.saveQueueEdit();await p.saveQueueEdit();assert.equal(p.calls.length,2);assert.equal(p.calls[0].commandId,p.calls[1].commandId);assert.ok(p.editingQueue);
 await p.removeImage('new');assert.deepEqual(mocks.deleted,[]);assert.deepEqual(p.imageUris,[]);
});
test('changes on another device or a run leaving the queue prevent stale edits from overwriting server state',async()=>{
 const p=fixture();await p.beginQueueEdit(p.queue[0]);p.draft='本机修改';p.queue=[{...p.queue[0],text:'其他设备修改'}];
 await p.saveQueueEdit();assert.match(p.operationError,/其他设备/);assert.equal(p.calls.length,0);assert.equal(p.draft,'本机修改');
 p.queue=[];assert.equal(p.canSaveQueueEdit(),false);await p.saveQueueEdit();assert.equal(p.calls.length,0);assert.ok(p.editingQueue);
});
test('saved queue drafts restore only when the original remote message still matches',async()=>{
 const p=fixture();await p.beginQueueEdit(p.queue[0]);p.draft='跨页面保留';await p.saveDraft();
 const original=p.mainDraft;p.editingQueue=null;p.mainDraft=null;p.draft=original.text;p.draftStore=original.store;p.imageStore=original.images;
 await p.beginQueueEdit(p.queue[0]);assert.equal(p.draft,'跨页面保留');
});

test('queue editing restores its own quote and saving or cancelling preserves the main draft quote',async()=>{
 const quote={environmentId:'env',threadId:'thread',messageId:'source',role:'assistant',text:'原回复'};
 const {quotedMessageText,parseQuotedMessage}=await load(read('model/MessageQuote.ets').replace(/^import .*;$/gm,''));
 const p=fixture();p.draftQuote=quote;
 const remote={...p.queue[0],text:quotedMessageText('排队回复',{...quote,messageId:'own',role:'user'})};
 p.state.messages[0].text=remote.text;p.queue=[remote];
 await p.beginQueueEdit(remote);assert.equal(p.draft,'排队回复');assert.equal(p.draftQuote.role,'user');
 p.draft='修改后的回复';await p.saveQueueEdit();
 assert.equal(parseQuotedMessage(p.calls[0].text).text,'修改后的回复');assert.equal(parseQuotedMessage(p.calls[0].text).quote.role,'user');
 assert.deepEqual(p.draftQuote,quote);assert.equal(p.draft,'主草稿');
 await p.beginQueueEdit(remote);p.draftQuote=null;await p.cancelQueueEdit();assert.deepEqual(p.draftQuote,quote);
});
