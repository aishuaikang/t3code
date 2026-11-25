import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
const read = p => readFileSync(new URL('../app/entry/src/main/ets/' + p, import.meta.url), 'utf8');
const load = s => import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(s)).toString('base64'));
const src = read('pages/Thread.ets');
const methods = src.slice(src.indexOf('  private async receiveImageComment('), src.indexOf('  private async pickImages(')).replaceAll('private ', '');
const { Fixture, mocks } = await load(`
${read('model/ImageEdits.ets')}
${read('model/QueuedDraft.ets').replace(/^import .*;$/gm,'')}
${read('model/MessageQuote.ets').replace(/^import .*;$/gm,'')}
export const mocks={params:{},deleted:[],sent:[],failSend:false};
const AttachmentDraftStore={open:async()=>({clear:async()=>{}})};
const EnvironmentSession={current:{descriptor:{environmentId:'env'},httpBaseUrl:'http://host'}};
const ImageEditRequests={send:async(...args)=>{mocks.sent.push(args);if(mocks.failSend)throw Error('receipt lost');}};
const router={getParams:()=>mocks.params},getContext=()=>({filesDir:'/private'}),fs={unlink:async uri=>mocks.deleted.push(uri)};
export class Fixture {
  active=true; readVisible=true; draftReady=true; imagesReady=true; journalReady=true; hasPendingSend=false; sending=false; pickingImage=false;
  draft='已有草稿'; draftTimer=-1; imageUpload=null; imageUris=[]; receivedImageComments=new Set(); receivingImageComment=false;
  params={environmentId:'env',threadId:'thread'}; uploads=0; saves=[];
  imageStore={images:[{uri:'existing'}],add:async (uri,name,replace)=>{const image={uri:'copy',name}; this.imageStore.images=this.imageStore.images.filter(i=>i.uri!==replace);this.imageStore.images.push(image);return image;},
    setUploaded:async(uri,uploaded)=>{this.imageStore.images.find(i=>i.uri===uri).uploaded=uploaded;},
    remove:async uri=>{this.imageStore.images=this.imageStore.images.filter(i=>i.uri!==uri);}};
  draftStore={save:async text=>this.saves.push(text)};
  loaded=true;rpc={};state={thread:{id:'thread'}};jumpToLatest(){}
  editingQueue=null; queueAttachments=[];
  attachmentCount(){return this.imageStore.images.length+this.queueAttachments.length;}
  uploadDraftImages(){this.uploads++;}
  ${methods}
}`);
const id='12345678-1234-1234-1234-123456789012';
const uri=`/private/image-edits/${id}.png`;
function reset() { mocks.deleted=[];mocks.sent=[];mocks.failSend=false; mocks.params={environmentId:'env',threadId:'thread',imageComment:JSON.stringify({id,uri,name:'标注.png',text:'请看这里'})}; }

test('image comments append to the existing draft, preserve attachments and are consumed once without sending', async () => {
  reset(); const page=new Fixture(); await page.receiveImageComment(); await page.receiveImageComment();
  assert.equal(page.draft,'已有草稿\n\n[图片评论：标注.png]\n请看这里');
  assert.deepEqual(page.imageUris,['existing','copy']); assert.equal(page.saves.length,1);
  assert.deepEqual(mocks.deleted,[uri]); assert.equal(page.uploads,1); assert.equal(page.draftReady,true);
});
test('comment import waits for the existing upload and cannot run concurrently', async () => {
  reset(); let release; const page=new Fixture(); page.imageUpload=new Promise(resolve=>{release=resolve;});
  const pending=page.receiveImageComment(); await page.receiveImageComment();
  assert.equal(page.draftReady,false); assert.equal(page.imageStore.images.length,1);
  release(); await pending; assert.equal(page.imageStore.images.length,2); assert.equal(page.saves.length,1);
});
test('failed draft persistence rolls back only the imported image and retains the comment source for retry', async () => {
  reset(); const page=new Fixture(); page.draftStore.save=async()=>{throw Error('disk full');};
  await page.receiveImageComment(); assert.equal(page.draft,'已有草稿'); assert.deepEqual(page.imageUris,['existing']);
  assert.equal(page.receivedImageComments.size,0); assert.deepEqual(mocks.deleted,[]); assert.match(page.operationError,/disk full/);
  page.draftStore.save=async()=>{}; await page.receiveImageComment(); assert.equal(page.receivedImageComments.size,1);
});
test('comments from other threads or environments never modify the active draft, nor does a pending send', async () => {
  for (const change of [{threadId:'other'},{environmentId:'other'}]) {
    reset(); Object.assign(mocks.params,change); const page=new Fixture(); await page.receiveImageComment();
    assert.equal(page.saves.length,0); assert.equal(page.imageStore.images.length,1);
  }
  reset(); const page=new Fixture(); page.hasPendingSend=true; await page.receiveImageComment(); assert.equal(page.saves.length,0);
});

test('direct image requests send once, preserve the main text and attachments, and delete temporary copies only after confirmation',async()=>{
 reset();const value=JSON.parse(mocks.params.imageComment);mocks.params.imageComment=JSON.stringify({...value,action:'send'});const page=new Fixture();
 await page.receiveImageComment();await page.receiveImageComment();assert.equal(mocks.sent.length,1);assert.equal(page.draft,'已有草稿');assert.equal(page.saves.length,0);assert.equal(page.imageStore.images.length,1);assert.deepEqual(mocks.deleted,[uri]);
});
test('unconfirmed image requests remain retryable without repeatedly resending on transcript updates',async()=>{
 reset();mocks.failSend=true;const value=JSON.parse(mocks.params.imageComment);mocks.params.imageComment=JSON.stringify({...value,action:'send'});const page=new Fixture();
 await page.receiveImageComment();page.resumeImageRequest();assert.equal(mocks.sent.length,1);assert.deepEqual(mocks.deleted,[]);assert.match(page.operationError,/receipt lost/);
 mocks.failSend=false;page.attemptedImageRequest='';await page.receiveImageComment();assert.equal(mocks.sent.length,2);assert.deepEqual(mocks.deleted,[uri]);
});
test('an image-edit request on an existing draft attachment adds its instruction without duplicating the image or sending',async()=>{
 reset();const value=JSON.parse(mocks.params.imageComment);mocks.params.imageComment=JSON.stringify({...value,action:'draft',target:'existing'});const page=new Fixture();
 await page.receiveImageComment();assert.equal(page.imageStore.images.length,1);assert.equal(mocks.sent.length,0);assert.equal(page.draft,'已有草稿\n\n请看这里');
});
test('replacing a local draft image keeps text unchanged and a mismatched queue scope cannot modify another draft',async()=>{
 reset();const target='/private/draft-images/original.img',value=JSON.parse(mocks.params.imageComment);mocks.params.imageComment=JSON.stringify({...value,action:'replace',target,text:''});const page=new Fixture();page.imageStore.images=[{uri:target}];
 await page.receiveImageComment();assert.deepEqual(page.imageUris,['copy']);assert.equal(page.draft,'已有草稿');assert.equal(page.saves.length,0);assert.equal(mocks.sent.length,0);
 reset();mocks.params.draftScope='other-run';const other=new Fixture();await other.receiveImageComment();assert.equal(other.saves.length,0);
});
test('image annotations and their explanation update the selected draft attachment only after text is safely persisted',async()=>{
 reset();const target='/private/draft-images/original.img',value=JSON.parse(mocks.params.imageComment);
 mocks.params.imageComment=JSON.stringify({...value,action:'replace',target,text:'标注说明'});const page=new Fixture();page.imageStore.images=[{uri:target}];
 page.draftStore.save=async()=>{throw Error('disk full');};await page.receiveImageComment();
 assert.equal(page.imageStore.images[0].uri,target);assert.equal(page.draft,'已有草稿');
 page.draftStore.save=async text=>page.saves.push(text);await page.receiveImageComment();
 assert.deepEqual(page.imageUris,['copy']);assert.equal(page.draft,'已有草稿\n\n标注说明');assert.equal(mocks.sent.length,0);
});
test('additional uploaded images join the existing draft and keep their upload receipt',async()=>{
 reset();const value=JSON.parse(mocks.params.imageComment),uploaded={type:'image',id:'picked',name:'补充.png',mimeType:'image/png',sizeBytes:20};
 mocks.params.imageComment=JSON.stringify({...value,action:'draft',target:'existing',attachmentDraftId:id,extras:[{uri:'/private/draft-images/'+id+'.img',name:'补充.png',uploaded}]});
 const page=new Fixture();await page.receiveImageComment();assert.equal(page.imageStore.images.length,2);assert.deepEqual(page.imageStore.images[1].uploaded,uploaded);assert.equal(page.draft,'已有草稿\n\n请看这里');
});

test('returning from a plain photo with no route result leaves live sync, the draft and the send journal alone', async () => {
  for (const result of [null, undefined]) {
    reset(); mocks.params=result; const page=new Fixture();
    await page.receiveImageComment(); page.resumeImageRequest();
    assert.equal(page.loaded,true);assert.equal(page.draft,'已有草稿');assert.deepEqual(mocks.sent,[]);assert.deepEqual(page.saves,[]);
  }
});
