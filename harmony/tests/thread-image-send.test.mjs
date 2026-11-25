import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const source = readFileSync(new URL('../app/entry/src/main/ets/pages/Thread.ets', import.meta.url), 'utf8');
const methods = source.slice(source.indexOf('  private async removeImage('), source.indexOf('  @Builder\n  messageMenu(')).replace(/  @Builder\n  private attachmentMenu\(\) \{[\s\S]*?\n  \}\n/, '').replaceAll('private ', '');
const models = await import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(readFileSync(
  new URL('../app/entry/src/main/ets/model/Models.ets', import.meta.url), 'utf8'))).toString('base64'));
globalThis.__startImageTurn = models.startTurnCommand;
const { Fixture, environment } = await import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(`
const startTurnCommand=globalThis.__startImageTurn;
${readFileSync(new URL('../app/entry/src/main/ets/model/MessageQuote.ets', import.meta.url),'utf8').replace(/^import .*;$/gm,'')}
const util={generateRandomUUID:()=> 'stable-id'};
const uploadImage=(...args)=>globalThis.__sendUpload(...args);
const imageUploadExists=async()=>true;
const deleteImageUpload=async()=>{};
export const environment={descriptor:{environmentId:'e'},httpBaseUrl:'http://fixture'};
const EnvironmentSession={current:environment};
export class Fixture {
 active=true;loaded=true;modelDraftReady=true;journalReady=true;hasPendingSend=false;imagesReady=true;draftReady=true;pickingImage=false;sending=false;running=false;interrupted=false;
 draft='Follow up with this photo';draftQuote=null;imageUris=['photo'];imageProgress=[];uploadingImages=false;imageUpload=null;removingImages=new Set();
 params={environmentId:'e'};rpc={};threadStatus='';calls=[];errors=[];
 state={thread:{id:'t',runtimeMode:'full-access',interactionMode:'default',session:{status:'running',activeTurnId:'active'}}};
 journal={pending:null,save:async command=>{this.journal.pending=command}};
 imageStore={images:[{uri:'photo',name:'photo.png'}],setUploaded:async(uri,uploaded)=>{
   this.imageStore.images=this.imageStore.images.map(i=>i.uri===uri?{...i,uploaded}:i);
 }};
 cancelPaths(){} jumpToLatest(){} reconcilePending(){} editDraft(value){this.draft=value;} async syncCheckoutBranch(){}
 async dispatchPending(command){this.calls.push(command)}
 async finishPending(){this.draft='';this.imageUris=[];this.journal.pending=null;this.hasPendingSend=false}
 async handleSendError(error){this.errors.push(error.message)}
 ${source.slice(source.indexOf('  private canSend()'),source.indexOf('  private messageTime(')).replace('private ','')}
 ${methods}
}`)).toString('base64'));
const image = { type: 'image', id: 'uploaded-photo', name: 'photo.png', mimeType: 'image/png', sizeBytes: 128 };
function deferred() { let resolve; const promise = new Promise(yes => { resolve = yes; }); return { promise, resolve }; }
const pendingNoticeCondition = source.match(/\n      if \((this\.hasPendingSend[^\n]*?)\) \{/)[1];
const pendingNotice = new Function('page', `return ${pendingNoticeCondition.replaceAll('this.', 'page.')}`);

// ArkUI only invalidates an element for @State values read while that element renders.
function mountSendButton(page) {
  const state = new Set(Array.from(source.matchAll(/^  @State(?: @Watch\('[^']+'\))? (\w+):/gm), m => m[1]));
  const reads = new Set();
  const view = new Proxy(page, { get(target, key) {
    if (state.has(key)) reads.add(key);
    return Reflect.get(target, key);
  } });
  const render = () => { reads.clear(); return view.canSend(); };
  let enabled = render();
  return {
    get enabled() { return enabled; },
    update(changes) {
      const dirty = Object.keys(changes).some(key => reads.has(key) && !Object.is(page[key], changes[key]));
      Object.assign(page, changes);
      if (dirty) enabled = render();
    },
  };
}

for (const networkFirst of [false, true]) test(`an initially grey send button follows restored drafts and reconnects (network first: ${networkFirst})`, async () => {
  const page = new Fixture();
  page.imageStore.images[0].uploaded = image;
  const online = { rpc: page.rpc, state: page.state, loaded: true };
  const local = { journal: page.journal, imageStore: page.imageStore, journalReady: true, imagesReady: true, draftReady: true, modelDraftReady: true };
  Object.assign(page, { rpc: null, state: {thread: null}, journal: null, imageStore: null, loaded: false, journalReady: false,
    imagesReady: false, draftReady: false, modelDraftReady: false, draft: '', imageUris: [] });
  const button = mountSendButton(page);
  button.update(networkFirst ? online : { ...local, draft: 'restored caption', imageUris: ['photo'] });
  assert.equal(button.enabled, false);
  button.update(networkFirst ? local : online);
  assert.equal(button.enabled, !networkFirst, 'a restored caption and photo become sendable as soon as the connection returns');
  button.update({draft: '   ', imageUris: []});
  assert.equal(button.enabled, false, 'whitespace alone cannot be sent');
  button.update({draft: 'send with photo'});
  assert.equal(button.enabled, true, 'the first edit after connecting must activate the existing button');
  button.update({imageUris: ['photo']}); button.update({draft: ''});
  assert.equal(button.enabled, true, 'an attachment alone is enough');
  button.update({rpc: null, loaded: false});
  assert.equal(button.enabled, false);
  button.update(online);
  assert.equal(button.enabled, true, 'the existing attachment can be sent after reconnect without retyping');
  button.update({draft: 'send with photo'});
  await Promise.all([page.send(), page.send()]);
  assert.equal(page.calls.length, 1);
  assert.equal(page.calls[0].message.text, 'send with photo');
  assert.deepEqual(page.calls[0].message.attachments, [image]);
});

test('a journaled send waiting for its receipt shows progress without offering a retry', async () => {
  const page = new Fixture(), receipt = deferred(), dispatched = deferred();
  page.imageStore.images[0].uploaded = image;
  page.dispatchPending = async command => { page.calls.push(command); dispatched.resolve(); await receipt.promise; };
  const sending = page.send();
  await dispatched.promise;
  assert.equal(page.hasPendingSend, true);
  assert.equal(page.sending, true);
  const visibleWhileSending = pendingNotice(page);
  receipt.resolve();
  await sending;
  assert.equal(visibleWhileSending, false);
  assert.equal(pendingNotice(page), false);
});
test('a lost receipt offers a retry while preserving the original message and attachments', async () => {
  const page = new Fixture();
  page.imageStore.images[0].uploaded = image;
  page.dispatchPending = async command => { page.calls.push(command); throw new Error('receipt lost'); };
  await page.send();
  assert.equal(pendingNotice(page), true);
  assert.equal(page.sending, false);
  assert.equal(page.journal.pending, page.calls[0]);
  assert.deepEqual(page.journal.pending.message.attachments, [image]);
});

test('send during a background upload waits, reuses that transfer, and queues once after the active turn', async () => {
  const page = new Fixture(), transfer = deferred(); let uploads = 0;
  globalThis.__sendUpload = async () => { uploads++; return transfer.promise; };
  const background = page.uploadDraftImages();
  const sending = page.send('queue');
  assert.equal(page.calls.length, 0);
  transfer.resolve(image);
  await Promise.all([background, sending]);
  assert.equal(uploads, 1);
  assert.equal(page.calls.length, 1);
  assert.deepEqual(page.calls[0].message.attachments, [image]);
  assert.equal(page.calls[0].dispatchMode.type, 'queue_after_active');
  assert.equal(page.draft, '');
});
test('upload failure keeps text and photos, explains the failure, and sends nothing', async () => {
  const page = new Fixture();
  globalThis.__sendUpload = async () => { throw new Error('network interrupted'); };
  await page.send();
  assert.equal(page.calls.length, 0);
  assert.match(page.errors[0] ?? '', /上传失败/);
  assert.equal(page.draft, 'Follow up with this photo');
  assert.deepEqual(page.imageUris, ['photo']);
  assert.equal(page.journal.pending, null);
});

test('restoring a checkout blocks both send and continue until it completes', async () => {
  const page = new Fixture();
  page.settingsBusy = true;
  await page.send();
  assert.equal(page.calls.length, 0);
  assert.equal(page.draft, 'Follow up with this photo');
  page.interrupted = true; page.draft = ''; page.imageUris = []; page.imageStore.images = [];
  assert.equal(page.canContinue(), false);
});

test('failed branch metadata alignment retains text and attachments without journaling or dispatching a message', async () => {
  const page = new Fixture();
  page.imageStore.images[0].uploaded = image;
  page.syncCheckoutBranch = async () => { throw new Error('branch metadata denied'); };
  await page.send();
  assert.equal(page.calls.length, 0);
  assert.equal(page.journal.pending, null);
  assert.equal(page.draft, 'Follow up with this photo');
  assert.equal(page.imageUris.length, 1);
  assert.match(page.errors[0], /branch metadata denied/);
});

test('quoting either role preserves queue and steer delivery, local commands, and the original reply draft in the journal', async () => {
  const {parseQuotedMessage}=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(readFileSync(
    new URL('../app/entry/src/main/ets/model/MessageQuote.ets',import.meta.url),'utf8').replace(/^import .*;$/gm,''))).toString('base64'));
  for(const role of ['user','assistant']) for(const delivery of ['steer','queue']) {
    const page=new Fixture();page.imageUris=[];page.imageStore.images=[];
    page.draft='回复内容';page.draftQuote={environmentId:'e',threadId:'t',messageId:'source',role,text:'/clear 这是被引用的正文'};
    await page.send(delivery);assert.equal(page.calls.length,1);
    const sent=parseQuotedMessage(page.calls[0].message.text);
    assert.equal(sent.text,'回复内容');assert.equal(sent.quote.role,role);assert.equal(sent.quote.messageId,'source');
    assert.equal(page.calls[0].freshContext,undefined);
    assert.equal(page.calls[0].dispatchMode.type,delivery==='steer'?'steer_active':'queue_after_active');
    assert.equal(parseQuotedMessage(page.calls[0].composerText).text,'回复内容');
  }
  const page=new Fixture();page.imageUris=[];page.imageStore.images=[];page.draft='/clear 新问题';
  page.draftQuote={environmentId:'e',threadId:'t',messageId:'source',role:'assistant',text:'原回复'};
  await page.send();assert.equal(page.calls[0].freshContext,true);
  assert.equal(parseQuotedMessage(page.calls[0].message.text).text,'新问题');
  assert.equal(parseQuotedMessage(page.calls[0].composerText).text,'/clear 新问题');
});

test('a quoted message with a lost receipt retains its original quote and command for an idempotent retry', async () => {
  const page=new Fixture();page.imageUris=[];page.imageStore.images=[];
  page.draftQuote={environmentId:'e',threadId:'t',messageId:'source',role:'user',text:'我原来的问题'};
  page.dispatchPending=async command=>{page.calls.push(command);throw Error('receipt lost');};
  await page.send();const pending=page.journal.pending;
  await page.send();assert.equal(page.calls.length,1);assert.equal(page.journal.pending,pending);
  assert.equal(page.draftQuote.text,'我原来的问题');assert.equal(page.hasPendingSend,true);
});
test('switching environment during upload preserves the draft and cannot dispatch on the other machine', async () => {
  const page = new Fixture(), transfer = deferred();
  globalThis.__sendUpload = () => transfer.promise;
  const sending = page.send();
  environment.descriptor.environmentId = 'other';
  transfer.resolve(image);
  try { await sending; } finally { environment.descriptor.environmentId = 'e'; }
  assert.equal(page.calls.length, 0);
  assert.equal(page.draft, 'Follow up with this photo');
  assert.equal(page.imageUris.length, 1);
});

test('continue starts a new turn in the interrupted conversation with its existing modes', async () => {
  const page = new Fixture();
  page.interrupted = true; page.draft = ''; page.imageUris = []; page.imageStore.images = [];
  page.state.thread.session = { status: 'ready', activeTurnId: null };
  page.state.thread.interactionMode = 'plan';
  await page.continueInterrupted();
  assert.equal(page.calls.length, 1);
  assert.equal(page.calls[0].threadId, 't');
  assert.equal(page.calls[0].message.text, 'Continue where you left off.');
  assert.equal(page.calls[0].runtimeMode, 'full-access');
  assert.equal(page.calls[0].interactionMode, 'plan');
  assert.deepEqual(page.calls[0].message.attachments, []);
  assert.equal(page.calls[0].freshContext, undefined);
});

test('continue preserves existing drafts and attachments and rejects inactive or pending states', async () => {
  for (const changed of [{draft:'keep my draft'}, {imageUris:['photo']}, {running:true}, {loaded:false}, {active:false}, {hasPendingSend:true}, {sending:true}, {interrupted:false}]) {
    const page = new Fixture();
    Object.assign(page, {interrupted:true, draft:'', imageUris:[]}, changed);
    const text = page.draft, images = page.imageUris.slice();
    await page.continueInterrupted();
    assert.equal(page.calls.length, 0);
    assert.equal(page.draft, text);
    assert.deepEqual(page.imageUris, images);
  }
});

test('continue journals one command during a lost receipt and prevents a second click', async () => {
  const page = new Fixture(), receipt = deferred(), dispatched = deferred();
  Object.assign(page, {interrupted:true, draft:'', imageUris:[]});
  page.state.thread.session = {status:'ready'};
  page.dispatchPending = async command => { page.calls.push(command); dispatched.resolve(); await receipt.promise; throw new Error('receipt lost'); };
  const continuing = page.continueInterrupted();
  await dispatched.promise;
  await page.continueInterrupted();
  receipt.resolve(); await continuing;
  assert.equal(page.calls.length, 1);
  assert.equal(page.journal.pending, page.calls[0]);
  assert.equal(page.hasPendingSend, true);
});

test('a picked provider is journaled for the next turn and cannot steer the current provider',async()=>{
 const page=new Fixture();page.imageUris=[];page.imageStore.images=[];
 page.state.thread.modelSelection={instanceId:'codex',model:'model-a'};
 page.pendingModelSelection={instanceId:'claude',model:'model-b',options:[{id:'effort',value:'max'},{id:'ultracode',value:true}]};
 await page.send('steer');
 assert.equal(page.calls.length,1);
 assert.deepEqual(page.calls[0].modelSelection,page.pendingModelSelection);
 assert.equal(page.calls[0].dispatchMode.type,'queue_after_active');
 assert.equal(page.state.thread.modelSelection.instanceId,'codex');
});

test('send waits for pending settings and uses receipted modes before the feed catches up',async()=>{
 const page=new Fixture();page.settingsPending=true;page.imageStore.images[0].uploaded=image;page.pendingModelSelection=null;
 await page.send();assert.equal(page.calls.length,0);assert.equal(page.canSend(),false);page.settingsPending=false;
 page.state.composerMetadataSequence=()=>12;page.params.threadId='t';page.outbox={receipts:(id,seq)=>{assert.equal(id,'t');assert.equal(seq,12);return [{runtimeMode:'approval-required'},{interactionMode:'plan'}]}};
 await page.send();assert.equal(page.calls.length,1);assert.equal(page.calls[0].runtimeMode,'approval-required');assert.equal(page.calls[0].interactionMode,'plan');assert.equal(page.calls[0].dispatchMode.type,'steer_active');
});

test('an early live replay waits for file limits without blocking text or an already uploaded legacy attachment',async()=>{
  const page=new Fixture();page.catalogLoaded=false;page.maxFileBytes=0;page.fileLimitsPending=true;
  page.imageStore.images=[{uri:'report',type:'file',name:'report.txt'}];page.imageUris=['report'];
  const button=mountSendButton(page);assert.equal(button.enabled,false);
  button.update({imageUris:[]});assert.equal(button.enabled,true);
  button.update({imageUris:['report']});assert.equal(button.enabled,false);
  // A legacy peer may lack a catalog; a draft attachment the server already holds can still be sent.
  page.imageStore.images[0].uploaded={...image,type:'file',name:'report.txt'};
  button.update({fileLimitsPending:false});assert.equal(button.enabled,true);
  await page.send();assert.equal(page.calls.length,1);assert.equal(page.calls[0].message.attachments[0].name,'report.txt');
});
