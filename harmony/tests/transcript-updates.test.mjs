import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
const load = source => import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
const models = await load(readFileSync(new URL('../app/entry/src/main/ets/model/Models.ets', import.meta.url), 'utf8'));
const actions=await load(readFileSync(new URL('../app/entry/src/main/ets/model/MessageActions.ets',import.meta.url),'utf8').replace(/^import .*;$/gm,''));
const {TranscriptDataSource}=await load(readFileSync(new URL('../app/entry/src/main/ets/pages/TranscriptDataSource.ets',import.meta.url),'utf8').replace(/^import .*;$/gm,''));
const {TranscriptFollow}=await load(readFileSync(new URL('../app/entry/src/main/ets/model/TranscriptFollow.ets',import.meta.url),'utf8'));
globalThis.__transcriptUpdateModels = {...models,...actions,TranscriptFollow,TranscriptDataSource};
const source = readFileSync(new URL('../app/entry/src/main/ets/pages/Thread.ets', import.meta.url), 'utf8');
const methods = source.slice(source.indexOf('  private refreshTranscript():'), source.indexOf('  onDidBuild():')).replaceAll('private ', '');
const frame=source.slice(source.indexOf('class TranscriptFrame'),source.indexOf('@Entry'));
const scrollMethods=source.slice(source.indexOf('  onDidBuild():'),source.indexOf('  private stopElapsedTimer(')).replaceAll('private ','');
const { Page, PartialUpdatePage, EnvironmentSession } = await load(`
const {turnSubagents,queuedMessages,transcriptRows,reconcileTranscriptRows,pendingRequests,assistantActionIds,HistoryEditIndex,TranscriptFollow,TranscriptDataSource}=globalThis.__transcriptUpdateModels;
class FrameCallback{};const ScrollAlign={END:2};${frame}
const RequestDrafts={retain(){}};
const {WS,availableModels,interruptTurnCommand}=globalThis.__transcriptUpdateModels;const util={generateRandomUUID:()=>crypto.randomUUID()};
const fileUploadLimit=()=>0;const getContext=()=>({filesDir:'/private'});
const ClientCache={open:async()=>({threadEpoch:()=>0,threadSnapshotEpoch:()=>0,setCatalog(){},commands:()=>[]})};class EmptyPayload{}
const commandCatalog=()=>[];class RpcRemoteError extends Error{}
export const EnvironmentSession={current:null};
export class Page {
 resumeImageRequest() {} subscribeCheckoutBranch() {}
 active=true;rpc={};transcriptTimer=-1;loaded=true;params={environmentId:'e',threadId:'t'};
 rollbackProviders=[];historyEditIds=[];
 transcriptSource=new TranscriptDataSource();entries=[];queue=[];expandedRows=[];requests=[];running=false;stopping=null;
 state={thread:{id:'t',session:{status:'ready'}},messages:[],activities:[],checkpointCount:0,cursor:()=>this.sequence};
 sequence=0;cacheEpoch=0;builds=0;cached=[];cache={threadEpoch:()=>0,threadSnapshotEpoch:()=>0,setCatalog(){},commands:()=>[],shellSequence:()=>undefined,setThread:(...args)=>this.cached.push(args)};
 finishOlderHistory(){}
 scheduleFollowScroll(){}
 follow={update:()=>this.builds++};syncComposerMetadata(){}updateElapsed(){}uploadDraftImages(){}reconcilePending(){}
 ${methods}
 ${source.slice(source.indexOf('  private async stop():'),source.indexOf('  private async respond(')).replaceAll('private ','')}
 ${source.slice(source.indexOf('  private async subscribeFeed('),source.indexOf('  private async refreshWorkspaceCommands(')).replaceAll('private ','')}
}
export class PartialUpdatePage extends Page {
 follow=new TranscriptFollow();followQueued=false;followGeneration=0;showingHistory=false;
 frames=[];scrolls=[];scroller={scrollToIndex:(index)=>this.scrolls.push(index)};
 getUIContext(){return {postFrameCallback:callback=>this.frames.push(callback)}}needsThinking(){return false}
 ${scrollMethods}
}`);
const message = (id, text = id) => ({ id, role:'assistant',text,createdAt:'2026-11-15T00:00:00Z',updatedAt:'2026-11-15T00:00:00Z',attachments:[] });
test('a burst of replayed stream chunks builds the transcript once and keeps the latest data and cursor', t => {
 t.mock.timers.enable({apis:['setTimeout']});const page=new Page();
 page.state.messages=Array.from({length:500},(_,n)=>message(String(n)));
 for(let n=1;n<=100;n++){
   page.sequence=n;page.state.messages[499]=message('499','token-'+n);page.scheduleTranscriptRefresh();
 }
 assert.equal(page.builds,0);assert.equal(page.cached.length,0);
 t.mock.timers.tick(32);
 assert.equal(page.builds,1);assert.equal(page.entries.at(-1).text,'token-100');
 assert.equal(page.cached.length,1);assert.equal(page.cached[0][4],100);
});
test('streaming updates preserve every unchanged history row, including attachments, across resume', () => {
 const page=new Page();const images=[{type:'image',id:'photo',name:'photo.png',mimeType:'image/png',sizeBytes:20}];
 page.state.messages=[{...message('first'),attachments:images},message('last')];page.refreshTranscript();
 const old=page.entries.slice();
 page.state.messages=[structuredClone(page.state.messages[0]),message('last','new token')];page.refreshTranscript();
 assert.equal(page.entries[0],old[0]);assert.notEqual(page.entries[1],old[1]);
 const resumed=page.entries.slice();page.state.messages=structuredClone(page.state.messages);page.refreshTranscript();
 assert.ok(page.entries.every((row,n)=>row===resumed[n]));
});
test('unrelated shell tasks do not trigger a refresh of the open thread', () => {
 const state=new models.ThreadState();state.restoreCached({id:'t',title:'Task',messages:[],syncSequence:1});
 assert.equal(state.applyShell({kind:'thread-upserted',sequence:2,thread:{id:'other',title:'Other'}},'t'),false);
 assert.equal(state.applyShell({kind:'thread-upserted',sequence:3,thread:{id:'t',title:'Updated'}},'t'),true);
 assert.equal(state.thread.title,'Updated');
});
test('a delayed refresh cannot cache stale data after the connection is closed', t => {
 t.mock.timers.enable({apis:['setTimeout']});const page=new Page();page.scheduleTranscriptRefresh();page.rpc=null;
 t.mock.timers.tick(32);assert.equal(page.builds,0);assert.equal(page.cached.length,0);
 page.rpc={};page.scheduleTranscriptRefresh();page.flushTranscriptRefresh();assert.equal(page.builds,1);
 t.mock.timers.tick(32);assert.equal(page.builds,1);
});

test('live feed snapshot without a completion marker and later sent or synchronized messages render in the same open page',async t=>{
 t.mock.timers.enable({apis:['setTimeout']});
 const page=new Page();page.state=new models.ThreadState();page.loaded=false;page.cached=true;page.cache=null;
 const streams=new Map();page.rpc={call:async()=>({providers:[],environment:{capabilities:{}}}),callStream:async(method,request,onValues)=>{streams.set(method,onValues)}};
 await page.subscribeFeed(page.rpc);
 const feed=streams.get(models.WS.threadFeed);
 feed([{kind:'snapshot',snapshotSequence:1,projection:{thread:{id:'t',title:'Current'},messages:[message('old')],runs:[]}}]);
 assert.equal(page.loaded,true);assert.equal(page.cached,false);assert.equal(page.entries.at(-1).text,'old');
 feed([{kind:'event',sequence:2,event:{type:'message.updated',threadId:'t',payload:{...message('sent','刚刚发送'),role:'user'}}}]);
 t.mock.timers.tick(32);assert.equal(page.entries.at(-1).text,'刚刚发送');
 feed([{kind:'event',sequence:3,event:{type:'message.updated',threadId:'t',payload:message('reply','实时回复')}}]);
 feed([{kind:'synchronized',sequence:3}]);assert.equal(page.entries.at(-1).text,'实时回复');
 assert.equal(page.state.cursor(),3);assert.equal(page.transcriptTimer,-1);
});

test('a recent snapshot starting with a checkpoint renders metadata and keeps applying live replies without reopening', async t => {
 t.mock.timers.enable({apis:['setTimeout']});
 const page=new Page();page.state=new models.ThreadState();page.loaded=false;page.cache=null;
 page.syncComposerMetadata=()=>{page.composerThread=page.state.thread};
 const streams=new Map();page.rpc={call:async()=>({providers:[]}),callStream:async(method,request,callback)=>{streams.set(method,callback)}};
 await page.subscribeFeed(page.rpc);
 const base={threadId:'t',runId:'r',status:'completed',startedAt:'2026-11-15T00:00:00Z',updatedAt:'2026-11-15T00:00:00Z'};
 const items=[{...base,id:'checkpoint',type:'checkpoint',ordinal:0,files:[{path:'app.ets',additions:1,deletions:0}]},
  {...base,id:'user-item',type:'user_message',ordinal:1,messageId:'user',text:'Next request'},
  {...base,id:'reply-item',type:'assistant_message',ordinal:2,messageId:'reply',text:'First token',streaming:true}];
 const feed=streams.get(models.WS.threadFeed);
 feed([{kind:'snapshot',snapshotSequence:20,hasMoreHistory:true,historyCursor:'older',projection:{
  thread:{id:'t',title:'Recent history',modelSelection:{instanceId:'codex',model:'gpt-6.1-sol'}},messages:[],runs:[],turnItems:items,
  visibleTurnItems:items.map((item,position)=>({position,sourceThreadId:'t',sourceItemId:item.id,item}))}}]);
 assert.equal(page.entries.at(-1).text,'First token');assert.equal(page.hasMoreHistory,true);
 assert.equal(page.composerThread.modelSelection.model,'gpt-6.1-sol');assert.equal(page.loaded,true);
 const retained=page.entries[0];
 feed([{kind:'event',sequence:21,event:{threadId:'t',type:'message.updated',payload:{...message('reply','Latest live reply'),runId:'r'}}}]);
 t.mock.timers.tick(32);
 assert.equal(page.entries.at(-1).text,'Latest live reply');assert.equal(page.entries[0],retained);
 assert.equal(page.state.cursor(),21);
});

test('an HTTP snapshot renders immediately even when there are no missing socket events',async t=>{
 t.mock.timers.enable({apis:['setTimeout']});
 const page=new Page();page.state=new models.ThreadState();page.loaded=false;
 page.cache={threadEpoch:()=>0,threadSnapshotEpoch:()=>0,setCatalog(){},commands:()=>[],shellSequence:()=>undefined,setThread(){}};
 EnvironmentSession.current={descriptor:{environmentId:'e'},loadSnapshot:async()=>({snapshotSequence:7,
  projection:{thread:{id:'t',title:'Current'},messages:[message('http','HTTP history')],runs:[]}})};
 page.rpc={call:async()=>({providers:[],environment:{capabilities:{}}}),callStream:()=>new Promise(()=>{})};
 page.subscribeFeed(page.rpc);for(let i=0;i<20;i++)await Promise.resolve();
 try { assert.equal(page.loaded,true);assert.equal(page.entries.at(-1)?.text,'HTTP history');assert.equal(page.transcriptTimer,-1); }
 finally {page.active=false;page.flushTranscriptRefresh();EnvironmentSession.current=null;}
});

test('large-thread recovery requests a bounded snapshot and joins live events without downloading all history',async t=>{
 t.mock.timers.enable({apis:['setTimeout']});
 const page=new Page();page.state=new models.ThreadState();page.loaded=false;page.cache=null;page.cachedThreadLoad=Promise.resolve();
 page.threadNeedsSnapshot=true;
 let httpPath;const streams=new Map();
 EnvironmentSession.current={descriptor:{environmentId:'e'},loadSnapshot:async path=>{httpPath=path;return {
  snapshotSequence:40,hasMoreHistory:true,historyCursor:'older',projection:{thread:{id:'t',title:'Large task'},
  messages:[message('recent','Recent messages')],runs:[]}}}};
 const rpc={call:async()=>({providers:[],threadSnapshotPagination:true,threadResumeCompletionMarker:true}),
  callStream:async(method,request,callback)=>{streams.set(method,{request,callback})}};
 page.rpc=rpc;await page.subscribeFeed(rpc);
 try{
  assert.match(httpPath,/\/bounded/);
  const feed=streams.get(models.WS.threadFeed);assert.equal(feed.request.acceptBoundedSnapshot,true);
  assert.equal(feed.request.afterSequence,40);assert.equal(page.entries.at(-1)?.text,'Recent messages');
  feed.callback([{kind:'synchronized'},{kind:'event',sequence:41,event:{type:'message.updated',threadId:'t',payload:message('live','Live reply')}}]);
  t.mock.timers.tick(32);assert.equal(page.entries.at(-1)?.text,'Live reply');assert.equal(page.loaded,true);
 }finally{EnvironmentSession.current=null;}
});

test('partial UI updates reveal appended messages and streamed content without rebuilding or reopening the page', () => {
 const page=new PartialUpdatePage();
 const nextFrame=()=>page.frames.splice(0).forEach(frame=>frame.onFrame(1));
 page.state.messages=[message('first')];page.refreshTranscript();nextFrame();
 page.state.messages.push(message('sent','Sent from this page'));page.refreshTranscript();nextFrame();
 page.state.messages[1]=message('sent','Streamed tokens and reasoning updated');page.refreshTranscript();nextFrame();
 assert.deepEqual(page.scrolls,[0,1,1]);
 page.follow.pause();page.state.messages.push(message('later'));page.refreshTranscript();nextFrame();
 assert.deepEqual(page.scrolls,[0,1,1]);
});

test('500 streaming turns do no history edit indexing; edits reuse one index at rest and update with new checkpoints',()=>{
 const page=new Page(),N=500;page.rollbackProviders=['p'];const thread=page.state.thread;
 thread.turns=Array.from({length:N},(_,i)=>({turnId:'r'+i,userMessageId:'m'+i,ordinal:i+1,state:'completed'}));thread.providerThreads=[{id:'pt',providerInstanceId:'p'}];thread.activeProviderThreadId='pt';
 thread.rewindCheckpoints=[{id:'start',ordinalWithinScope:0,appRunOrdinal:null,status:'ready'}];page.state.messages=thread.turns.map((r,i)=>({...message('m'+i),role:'user',sourceThreadId:'t',turnId:r.turnId}));
 thread.session={activeTurnId:'r499',status:'running'};page.refreshTranscript();assert.deepEqual(page.historyEditIds,[]);assert.ok(page.historyEditIndex==null);
 thread.session={activeTurnId:null,status:'ready'};page.refreshTranscript();const index=page.historyEditIndex;assert.ok(index);assert.deepEqual(page.historyEditIds,['m0']);
 page.refreshTranscript();assert.equal(page.historyEditIndex,index);thread.rewindCheckpoints=[...thread.rewindCheckpoints,{id:'one',appRunOrdinal:1,ordinalWithinScope:1,status:'ready'}];
 page.refreshTranscript();assert.deepEqual(page.historyEditIds,['m0','m1']);assert.notEqual(page.historyEditIndex,index);
});

test('a new run can be stopped even if the previous interrupt reply is still in flight',async()=>{
 const page=new Page(), calls=[];page.rpc={call:async(_method,cmd)=>{const gate=Promise.withResolvers();calls.push({cmd,gate});return gate.promise;}};
 page.state.thread.session={status:'running',activeTurnId:'r1'};
 const first=page.stop();page.state.thread.session={status:'running',activeTurnId:'r2'};
 page.scheduleTranscriptRefresh();page.flushTranscriptRefresh();const second=page.stop();
 assert.deepEqual(calls.map(c=>c.cmd.runId),['r1','r2']);calls[0].gate.reject(Error('first run already ended'));await first;
 assert.equal(page.stopping.runId,'r2');assert.notEqual(page.operationError,'first run already ended');
 calls[1].gate.resolve();await second;page.state.thread.session={status:'ready'};page.scheduleTranscriptRefresh();page.flushTranscriptRefresh();
 assert.equal(page.stopping,null);
});
