import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
const read=p=>readFileSync(new URL('../app/entry/src/main/ets/'+p,import.meta.url),'utf8').replace(/^import .*;$/gm,'');
const load=s=>import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(s)).toString('base64'));
const models=await load(read('model/Models.ets'));globalThis.__imageRequestModels=models;
const rpcSource=read('connection/Rpc.ets');
const { ImageEditRequests, RpcRemoteError, mocks }=await load(`
const {startTurnCommand,WS}=globalThis.__imageRequestModels;
export const mocks={drafts:new Map(),keys:[],uploads:[],uploadOptions:[],deletes:[],expired:new Set(),ids:0,failSave:false,failUpload:0};
const util={generateRandomUUID:()=> 'image-command-'+(++mocks.ids)};
const DraftStore={open:async(dir,env,key)=>{mocks.keys.push(key);return{load:async()=>mocks.drafts.get(key)||'',save:async text=>{if(mocks.failSave)throw Error('disk full');mocks.drafts.set(key,text);}};}};
const uploadImage=async(rpc,base,uri,name,progress,kind='image',maxBytes)=>{mocks.uploads.push(uri);mocks.uploadOptions.push({kind,maxBytes});if(mocks.failUpload===mocks.uploads.length)throw Error('upload failed');return{type:kind,id:'asset-'+mocks.uploads.length,name,mimeType:kind==='file'?'application/pdf':'image/png',sizeBytes:100};};
const imageUploadExists=async(rpc,id)=>!mocks.expired.has(id);
const deleteImageUpload=async(rpc,id)=>mocks.deletes.push(id);
${rpcSource.slice(0,rpcSource.indexOf('export interface RpcMessage'))}
${read('connection/SendJournal.ets')}
${read('connection/ImageEditRequests.ets')}
`);
const thread={id:'thread',runtimeMode:'full-access',interactionMode:'default',modelSelection:{instanceId:'codex',model:'gpt-5'}};
const request={id:'stable-id',uri:'/private/image-edits/image.png',maskUri:'/private/image-edits/mask.png',name:'编辑.png',text:'移除选区'};
function reset(){mocks.drafts.clear();mocks.keys=[];mocks.uploads=[];mocks.uploadOptions=[];mocks.deletes=[];mocks.expired.clear();mocks.ids=0;mocks.failSave=false;mocks.failUpload=0;}
test('an image request uploads the original and mask and sends through an isolated journal without replacing the main composer draft',async()=>{
 reset();mocks.drafts.set('send:thread','existing-send');const calls=[];const rpc={call:async(method,command)=>calls.push(command)};
 await ImageEditRequests.send(rpc,'/private','env','http://host',thread,request);
 assert.deepEqual(mocks.uploads,[request.uri,request.maskUri]);assert.equal(calls.length,1);
 assert.equal(calls[0].message.text,request.text);assert.equal(calls[0].message.messageId,'stable-id');assert.notEqual(calls[0].commandId,'stable-id');assert.equal(calls[0].message.attachments.length,2);
 assert.equal(mocks.drafts.get('send:thread'),'existing-send');assert.equal(mocks.drafts.get('send:image-edit:thread:stable-id'),'');
});
test('lost receipts retry the exact saved command without uploading or deleting any attachment a second time',async()=>{
 reset();const calls=[];let fail=true;const rpc={call:async(method,command)=>{calls.push(command);if(fail)throw Error('receipt lost');}};
 await assert.rejects(ImageEditRequests.send(rpc,'/private','env','http://host',thread,request),/receipt lost/);
 assert.ok(mocks.drafts.get('send:image-edit:thread:stable-id'));assert.deepEqual(mocks.deletes,[]);
 fail=false;await ImageEditRequests.send(rpc,'/private','env','http://host',thread,{...request,text:'should not replace an uncertain command'});
 assert.deepEqual(calls[0],calls[1]);assert.equal(mocks.uploads.length,2);
});
test('a definitive rejection after a lost receipt recovers with a new command and refreshes expired extra files',async()=>{
 reset();const calls=[],attachment={type:'file',id:'picked-pdf',name:'说明.pdf',mimeType:'application/pdf',sizeBytes:12*1024*1024};
 const extra={uri:'/private/draft-images/extra.file',name:attachment.name,type:'file',uploaded:attachment};
 const value={...request,extras:[extra]};
 const rejected=new RpcRemoteError(models.WS.threadStartTurn,{cause:[{_tag:'Fail',error:{_tag:'OrchestrationDispatchCommandError',
   message:"Attachment 'picked-pdf' cannot be sent: attachment not found (removed or expired)."}}]});
 assert.equal(rejected.definitivelyRejected,true);
 const rpc={call:async(method,command)=>{
   calls.push(command);if(calls.length===1)throw Error('receipt lost');if(calls.length===2)throw rejected;
 }};
 await assert.rejects(ImageEditRequests.send(rpc,'/private','env','http://host',thread,value),/receipt lost/);
 assert.ok(mocks.drafts.get('send:image-edit:thread:stable-id'));assert.deepEqual(mocks.deletes,[]);
 await assert.rejects(ImageEditRequests.send(rpc,'/private','env','http://host',thread,value),/attachment not found/);
 assert.deepEqual(calls[0],calls[1]);assert.equal(mocks.drafts.get('send:image-edit:thread:stable-id'),'');
 assert.deepEqual(mocks.deletes,['asset-1','asset-2']);
 mocks.expired.add(attachment.id);
 await ImageEditRequests.send(rpc,'/private','env','http://host',thread,value);
 assert.notEqual(calls[2].commandId,calls[1].commandId);assert.equal(calls[2].message.messageId,'stable-id');
 assert.deepEqual(mocks.uploads,[request.uri,request.maskUri,request.uri,request.maskUri,extra.uri]);
 assert.equal(calls[2].message.attachments.at(-1).type,'file');assert.equal(calls[2].message.attachments.at(-1).id,'asset-5');
 assert.deepEqual(mocks.uploadOptions.at(-1),{kind:'file',maxBytes:attachment.sizeBytes});
 assert.equal(mocks.deletes.includes(attachment.id),false);
});
test('partial upload or journal persistence failure cleans only newly uploaded assets and never dispatches a message',async()=>{
 for(const saveFailure of [false,true]) {
  reset();mocks.failSave=saveFailure;mocks.failUpload=saveFailure?0:2;let calls=0;const rpc={call:async()=>calls++};
  await assert.rejects(ImageEditRequests.send(rpc,'/private','env','http://host',thread,request),saveFailure?/disk full/:/upload failed/);
  assert.equal(calls,0);assert.deepEqual(mocks.deletes,saveFailure?['asset-1','asset-2']:['asset-1']);assert.equal(mocks.drafts.size,0);
 }
});
test('the image composer includes already uploaded attachments without reuploading them on send or retry',async()=>{
 reset();const calls=[],attachment={type:'file',id:'picked-pdf',name:'说明.pdf',mimeType:'application/pdf',sizeBytes:500};
 const value={...request,extras:[{uri:'/private/draft-images/extra.file',name:attachment.name,type:'file',uploaded:attachment}]};
 await ImageEditRequests.send({call:async(method,command)=>calls.push(command)},'/private','env','http://host',thread,value);
 assert.equal(mocks.uploads.length,2);assert.deepEqual(calls[0].message.attachments.at(-1),attachment);
 reset();mocks.failSave=true;
 await assert.rejects(ImageEditRequests.send({call:async()=>{}},'/private','env','http://host',thread,value),/disk full/);
 assert.deepEqual(mocks.deletes,['asset-1','asset-2']);
});

test('image instructions beginning with composer commands remain verbatim in the current thread, including active steering',async()=>{
 for(const prefix of ['/side','/btw','/clear']) for(const active of [false,true]) {
  reset();const sent=[],rpc={call:async(_,cmd)=>sent.push(cmd)};const text=prefix+' crop this photo';
  await ImageEditRequests.send(rpc,'/private','env','host',{...thread,session:active?{activeTurnId:'run'}:null},{...request,text,maskUri:null});
  assert.equal(sent.length,1);const [cmd]=sent;assert.equal(cmd.threadId,thread.id);assert.equal(cmd.message.text,text);
  assert.equal(cmd.sideThreadId,undefined);assert.equal(cmd.freshContext,undefined);assert.equal(cmd.dispatchMode?.type,active?'steer_active':undefined);
 }
});
