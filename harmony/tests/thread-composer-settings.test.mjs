import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const read = path => readFileSync(new URL('../app/entry/src/main/ets/' + path, import.meta.url), 'utf8');
const src = read('pages/Thread.ets');
function methods(first, next) {
  const start = src.indexOf(first), end = src.indexOf(next, start);
  assert.ok(start >= 0 && end > start); return src.slice(start, end).replaceAll('private ', '');
}
const disk = new Map(), readFailures = new Map(), writeFailures = new Map();
const storeKey = (dir, env, id) => JSON.stringify([dir, env, id]);
globalThis.__settingsDisk = { open: async (dir, env, id) => {
  const key = storeKey(dir, env, id);
  return { load: async () => { if (readFailures.has(key)) return readFailures.get(key)(); return disk.get(key) ?? ''; },
    save: async text => { if (writeFailures.has(key)) return writeFailures.get(key)(); if (text) disk.set(key, text); else disk.delete(key); } };
} };
const code = `const DraftStore=globalThis.__settingsDisk;const getContext=p=>({filesDir:p.dir});
const quotedMessageText=text=>text;const WS={threadStartTurn:'dispatch'};let serial=0;const util={generateRandomUUID:()=>String(++serial)};
export const EnvironmentSession={current:null};export class RpcRemoteError extends Error {definitivelyRejected=true;}
${read('connection/ComposerOutbox.ets').replace(/^import .*;$/gm, '')}
export class Page {
 active=true;loaded=true;modelDraftReady=false;modelDraft=null;pendingModelSelection=null;outbox=null;settingsBusy=false;settingsPending=false;sending=false;hasPendingSend=false;settingsError='';
 journalReady=true;journal={};rpc={};imageStore={};draft='keep my message';draftReady=true;imagesReady=true;imageUris=['photo'];
 models=[{instanceId:'p',model:'m'},{instanceId:'p',model:'other'},{instanceId:'claude',model:'next'}];
 constructor(dir,env,id,thread){this.dir=dir;this.params={environmentId:env,threadId:id};this.state={thread,composerMetadataSequence:()=>0};}
 reconciled=0;reconcilePending(){this.reconciled++} get visible(){return this.composerThread?.modelSelection}
 cancelQuoteNavigation(){}flushTranscriptRefresh(){}cancelFollowScroll(){}stopElapsedTimer(){}restoreKeyboardAvoidMode(){}cancelPaths(){}saveDraft(){}composerInstance=null;
 ${methods('  aboutToDisappear():','  private async loadCachedThread(')}
 ${methods('  private async loadModelDraft(', '  private editDraft(')}
 ${methods('  private syncComposerMetadata()', '  private updateBranchNotice()')}
 ${methods('  private async updateComposerSetting(', '  private async copyMessage(')}
 ${methods('  private async finishPending(', '  private async dispatchPending(')}
 ${methods('  private canSend()', '  private messageTime(')}
}`;
let serial=0;
const runtime = () => import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(code)+`\n// runtime ${++serial}\n//# sourceURL=harmony-settings-fixture-${serial}.mjs`).toString('base64'));
const gate = () => Promise.withResolvers();
const pump = () => new Promise(resolve => setImmediate(resolve));
const staged = {instanceId:'claude',model:'next'}, other = {instanceId:'p',model:'other'};
async function fixture({env='env', id='t', dir=`/test/${++serial}`, online=true, ready=true, rt=undefined}={}) {
  rt ??= await runtime();
  const thread = {id,modelSelection:{instanceId:'p',model:'m',options:[{id:'effort',value:'high'},{id:'fast',value:false}]},runtimeMode:'full-access',interactionMode:'default'};
  const shell = {threads:[thread],cursor:()=>0}, calls=[];
  const rpc = {call:async(tag,command)=>{assert.equal(tag,'dispatch');return {sequence:calls.push(command)}}};
  const connect = (peer=rpc,environmentId=env) => {rt.EnvironmentSession.current={rpc:peer,descriptor:{environmentId}};rt.ComposerOutbox.connected(dir,environmentId,peer,shell)};
  const disconnect = () => {rt.ComposerOutbox.disconnected(rt.EnvironmentSession.current?.rpc);rt.EnvironmentSession.current=null};
  const page = new rt.Page(dir,env,id,thread);page.rpc={close(){}};
  const key=storeKey(dir,env,`model:${id}`), journalKey=storeKey(dir,env,'composer-settings-v1');
  if(online)connect();if(ready)await page.loadModelDraft();
  return {rt,env,id,dir,page,thread,shell,rpc,calls,connect,disconnect,key,journalKey};
}

test('permission and interaction changes send only their own typed metadata',async()=>{
 const {page,calls}=await fixture();await page.updateComposerSetting('runtime','approval-required');await page.updateComposerSetting('interaction','plan');
 assert.deepEqual(calls.map(c=>[c.type,c.runtimeMode,c.interactionMode]),[['thread.runtime-mode.set','approval-required',undefined],['thread.interaction-mode.set',undefined,'plan']]);
 assert.equal(page.composerThread.runtimeMode,'approval-required');assert.equal(page.composerThread.interactionMode,'plan');
});
test('selecting the active model preserves its options and changing model resets them',async()=>{
 const {page,calls,thread}=await fixture();await page.updateComposerSetting('model','',thread.modelSelection);assert.equal(calls.length,0);
 await page.updateComposerSetting('model','',other);assert.deepEqual(calls[0].modelSelection,other);assert.equal(calls[0].type,'thread.model-selection.set');
});
test('cross-provider models and their options are staged for the next message and can be cancelled',async()=>{
 const {page,thread,calls,key}=await fixture();page.running=true;thread.session={activeTurnId:'run'};
 await page.updateComposerSetting('model','',staged);assert.deepEqual(page.pendingModelSelection,staged);
 const options={...staged,options:[{id:'effort',value:'max'},{id:'fastMode',value:false}]};
 await page.updateComposerSetting('options','',options);assert.deepEqual(JSON.parse(disk.get(key)),options);assert.deepEqual(page.visible,options);
 await page.updateComposerSetting('model','',{instanceId:'p',model:'m'});assert.equal(page.pendingModelSelection,null);assert.ok(!disk.has(key));assert.equal(calls.length,0);assert.equal(thread.modelSelection.options.length,2);
});
test('a failed local model write preserves the old pick and never replaces the active provider',async()=>{
 const {page,calls,key}=await fixture();writeFailures.set(key,()=>{throw Error('disk full')});await page.updateComposerSetting('model','',staged);
 assert.equal(page.pendingModelSelection,null);assert.equal(calls.length,0);assert.match(page.settingsError,/disk full/);assert.equal(page.settingsPending,false);
});
test('an unknown model, an invalid mode, a branch operation or a foreign active environment cannot submit settings',async()=>{
 const {page,calls,connect,rt}=await fixture();await page.updateComposerSetting('runtime','oops');await page.updateComposerSetting('model','',{instanceId:'none',model:'unknown'});
 page.settingsBusy=true;await page.updateComposerSetting('interaction','plan');page.settingsBusy=false;
 connect({call:()=>assert.fail('wrong environment')},'other');await page.updateComposerSetting('runtime','auto');assert.equal(calls.length,0);assert.deepEqual(page.outbox.pending('t'),[]);
 rt.EnvironmentSession.current=null;
});
test('a rejected save rolls the displayed setting back without sending a message',async()=>{
 const {page,rpc,rt}=await fixture();rpc.call=async()=>{throw new rt.RpcRemoteError('denied')};await page.updateComposerSetting('runtime','auto');
 assert.match(page.settingsError,/denied/);assert.equal(page.settingsPending,false);assert.equal(page.composerThread.runtimeMode,'full-access');assert.equal(page.draft,'keep my message');
});
test('confirmed delivery consumes only a matching staged model and leaves a different draft message intact',async()=>{
 const {page,key}=await fixture({ready:false});disk.set(key,JSON.stringify(staged));await page.loadModelDraft();assert.equal(page.reconciled,1);
 assert.deepEqual(page.pendingModelSelection,staged);page.journal={pending:{modelSelection:other,message:{text:'sent'}},clear:async()=>{page.journal.pending=null}};
 page.imageStore={clear:async()=>{}};page.hasPendingSend=true;await page.finishPending();assert.deepEqual(page.pendingModelSelection,staged);
 page.journal.pending={modelSelection:staged,message:{text:'sent'}};await page.finishPending();assert.equal(page.pendingModelSelection,null);assert.ok(!disk.has(key));assert.equal(page.draft,'keep my message');assert.equal(page.hasPendingSend,false);
});
test('a late draft load cannot update a departed page',async()=>{
 const {page,key}=await fixture({ready:false});const read=gate();readFailures.set(key,()=>read.promise);
 const loading=page.loadModelDraft();page.aboutToDisappear();read.resolve(JSON.stringify(staged));await loading;assert.equal(page.modelDraftReady,false);assert.equal(page.pendingModelSelection,null);
});
test('four rapid efforts send the in-flight choice and the last; independent modes stay ordered and Send uses the final state',async()=>{
 const {page,rpc,calls,thread}=await fixture();const entered=gate(),receipt=gate();
 rpc.call=async(_,c)=>{calls.push(c);if(calls.length===1){entered.resolve();await receipt.promise}return {sequence:calls.length}};
 const pick=v=>({...other,options:[{id:'effort',value:v}]});const first=page.updateComposerSetting('options','',pick('low'));await entered.promise;
 await page.updateComposerSetting('options','',pick('medium'));await page.updateComposerSetting('interaction','plan');await page.updateComposerSetting('options','',pick('high'));
 const last=page.updateComposerSetting('options','',pick('max'));assert.deepEqual(page.visible,pick('max'));await last;assert.equal(page.canSend(),false);assert.equal(calls.length,1);
 receipt.resolve();await first;assert.deepEqual(calls.map(c=>c.modelSelection?.options[0].value??c.interactionMode),['low','plan','max']);assert.equal(page.canSend(),true);
 thread.modelSelection=pick('low');page.state.composerMetadataSequence=()=>1;page.syncComposerMetadata();assert.deepEqual(page.visible,pick('max'));
 thread.modelSelection=pick('max');thread.interactionMode='plan';page.state.composerMetadataSequence=()=>3;page.syncComposerMetadata();assert.deepEqual(page.outbox.receipts('t',3),[]);
});
test('leaving and reopening while a receipt is pending preserves the last choice and only one writer',async()=>{
 const {page,rt,dir,env,id,thread,rpc,calls}=await fixture();const entered=gate(),receipt=gate();rpc.call=async(_,c)=>{calls.push(c);if(calls.length===1){entered.resolve();await receipt.promise}return {sequence:calls.length}};
 const writing=page.updateComposerSetting('runtime','auto');await entered.promise;await page.updateComposerSetting('interaction','plan');page.aboutToDisappear();
 const reopened=new rt.Page(dir,env,id,thread);await reopened.loadModelDraft();assert.equal(reopened.composerThread.interactionMode,'plan');assert.equal(reopened.settingsPending,true);
 receipt.resolve();await writing;assert.deepEqual(calls.map(c=>c.type),['thread.runtime-mode.set','thread.interaction-mode.set']);assert.equal(reopened.settingsPending,false);assert.equal(reopened.composerThread.interactionMode,'plan');
});
test('a cold cached route accepts a tap immediately and its journal is delivered after restart without reopening the page',async()=>{
 const f=await fixture({online:false});f.page.loaded=false;const writing=f.page.updateComposerSetting('model','',other);assert.deepEqual(f.page.visible,other);await writing;
 assert.equal(f.calls.length,0);const id=JSON.parse(disk.get(f.journalKey))[0].command.commandId;f.page.aboutToDisappear();
 const restarted=await fixture({dir:f.dir,env:'elsewhere'});await pump();assert.equal(restarted.calls.length,0);
 restarted.connect(restarted.rpc,f.env);await pump();assert.equal(restarted.calls.length,1);assert.equal(restarted.calls[0].commandId,id);assert.deepEqual(restarted.calls[0].modelSelection,other);assert.ok(!disk.has(f.journalKey));
});
test('an ambiguous transport failure retries the original command id on the next socket',async()=>{
 const f=await fixture();let attempted;f.rpc.call=async(_,c)=>{attempted=c.commandId;throw Error('lost receipt')};await f.page.updateComposerSetting('runtime','auto');
 assert.equal(f.page.settingsPending,true);assert.match(f.page.settingsError,/lost receipt/);f.disconnect();
 f.connect({call:async(_,c)=>{assert.equal(c.commandId,attempted);return {sequence:4}}});await pump();assert.equal(f.page.settingsPending,false);assert.equal(f.page.settingsError,'');assert.equal(f.page.composerThread.runtimeMode,'auto');
});
test('a rejected same-provider change retains the previously staged provider on disk, after reopening, and on screen',async()=>{
 const f=await fixture();await f.page.updateComposerSetting('model','',staged);f.rpc.call=async()=>{throw new f.rt.RpcRemoteError('rejected')};
 await f.page.updateComposerSetting('model','',other);assert.deepEqual(f.page.pendingModelSelection,staged);assert.deepEqual(f.page.visible,staged);assert.deepEqual(JSON.parse(disk.get(f.key)),staged);
 f.page.aboutToDisappear();const reopened=await fixture({dir:f.dir,rt:f.rt});assert.deepEqual(reopened.page.visible,staged);assert.match(reopened.page.settingsError,/rejected/);
});
for(const raw of ['{bad','null',JSON.stringify({...staged,options:[{id:'x',value:17}]})])test(`invalid model data recovers without touching text or attachments: ${raw}`,async()=>{
 const f=await fixture({ready:false});disk.set(f.key,raw);assert.equal(f.page.canSend(),false);await f.page.loadModelDraft();
 assert.equal(f.page.modelDraftReady,true);assert.equal(f.page.pendingModelSelection,null);assert.ok(!disk.has(f.key));assert.equal(f.page.draft,'keep my message');assert.deepEqual(f.page.imageUris,['photo']);assert.match(f.page.settingsError,/已恢复/);assert.equal(f.page.canSend(),true);
});
test('a transient draft read error disables Send, offers retry, and preserves a valid stored selection',async()=>{
 const f=await fixture({ready:false});disk.set(f.key,JSON.stringify(staged));readFailures.set(f.key,()=>{throw Error('I/O')});await f.page.loadModelDraft();
 assert.equal(f.page.canSend(),false);assert.match(f.page.settingsError,/重试/);assert.deepEqual(JSON.parse(disk.get(f.key)),staged);
 readFailures.delete(f.key);await f.page.loadModelDraft();assert.equal(f.page.canSend(),true);assert.deepEqual(f.page.visible,staged);
});

test('a late receipt only updates its own thread, and a different environment cannot drain the remaining work',async()=>{
 const f=await fixture(),receipt=gate(),entered=gate();f.rpc.call=async(_,c)=>{f.calls.push(c);if(f.calls.length===1){entered.resolve();await receipt.promise}return {sequence:f.calls.length}};
 const writing=f.page.updateComposerSetting('runtime','auto');await entered.promise;await f.page.updateComposerSetting('interaction','plan');
 const sibling=new f.rt.Page(f.dir,f.env,'sibling',{...f.thread,id:'sibling'});await sibling.loadModelDraft();assert.equal(sibling.settingsPending,false);assert.equal(sibling.composerThread.interactionMode,'default');
 f.connect({call:()=>assert.fail('foreign write')},'different');receipt.resolve();await writing;assert.equal(f.calls.length,1);assert.equal(f.page.settingsPending,true);
 f.connect();await pump();assert.deepEqual(f.calls.map(c=>c.threadId),['t','t']);assert.equal(f.page.settingsPending,false);assert.equal(sibling.composerThread.runtimeMode,'full-access');
});
test('restoring an ambiguous write after a process restart replays its original command ID before later choices',async()=>{
 const f=await fixture(),entered=gate(),lost=gate();f.rpc.call=async(_,c)=>{f.calls.push(c);entered.resolve();await lost.promise;throw Error('lost receipt')};
 const writing=f.page.updateComposerSetting('runtime','auto');await entered.promise;await f.page.updateComposerSetting('runtime','approval-required');f.disconnect();lost.resolve();await writing;f.page.aboutToDisappear();
 const restarted=await fixture({dir:f.dir,ready:false});await pump();assert.deepEqual(restarted.calls.map(c=>c.runtimeMode),['auto','approval-required']);assert.equal(restarted.calls[0].commandId,f.calls[0].commandId);assert.notEqual(restarted.calls[0].commandId,restarted.calls[1].commandId);
});
test('an unreadable settings journal is repaired without discarding a valid staged model or a message',async()=>{
 const f=await fixture({ready:false,online:false});disk.set(f.journalKey,'broken');disk.set(f.key,JSON.stringify(staged));await f.page.loadModelDraft();
 assert.equal(f.page.modelDraftReady,true);assert.deepEqual(f.page.visible,staged);assert.match(f.page.settingsError,/损坏/);assert.equal(f.page.draft,'keep my message');assert.ok(!disk.has(f.journalKey));
});

test('a send receipt from another page cannot consume a newer model choice while it is being saved',async()=>{
 const f=await fixture();await f.page.updateComposerSetting('model','',staged);
 const next={...staged,options:[{id:'effort',value:'high'}]},entered=gate(),finish=gate();
 const draft=await f.page.outbox.draft('t'),save=draft.store.save;let writes=Promise.resolve();
 draft.store.save=text=>writes=writes.then(async()=>{if(text){entered.resolve();await finish.promise}await save(text)});
 const saving=f.page.updateComposerSetting('options','',next);await entered.promise;
 const consuming=f.page.outbox.consume('t',staged);await pump();finish.resolve();await Promise.all([saving,consuming]);
 assert.deepEqual((await f.page.outbox.draft('t')).value,next);assert.deepEqual(JSON.parse(disk.get(f.key)),next);
});

test('restoring an older server snapshot drops already acknowledged settings while retaining a local model draft',async()=>{
 const f=await fixture();f.rpc.call=async()=>({sequence:80});await f.page.updateComposerSetting('runtime','auto');
 await f.page.updateComposerSetting('model','',staged);assert.equal(f.page.outbox.receipts('t',4).length,1);
 f.rt.ComposerOutbox.connected(f.dir,f.env,f.rpc,f.shell,true);await pump();f.page.syncComposerMetadata();
 assert.deepEqual(f.page.outbox.receipts('t',4),[]);assert.equal(f.page.composerThread.runtimeMode,'full-access');assert.deepEqual(f.page.pendingModelSelection,staged);
});
