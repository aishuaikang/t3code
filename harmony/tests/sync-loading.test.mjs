import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const read = path => readFileSync(new URL(path, import.meta.url), 'utf8');
const load = source => import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
const { ReconnectingRpc: LiveReconnectingRpc } = await load(read('../app/entry/src/main/ets/connection/ReconnectingRpc.ets').replace(/^import .*;$/gm, ''));
const models = await load(read('../app/entry/src/main/ets/model/Models.ets'));
globalThis.__syncModels = models;
const thread = read('../app/entry/src/main/ets/pages/Thread.ets');
const index = read('../app/entry/src/main/ets/pages/Index.ets');
const method = (source, start, end) => {
  const from = source.indexOf(start), to = source.indexOf(end, from);
  assert.ok(from >= 0 && to > from, `Missing source boundary: ${start} → ${end}`);
  return source.slice(from, to).replaceAll('private ', '');
};
const prelude = `
const { ThreadState, ShellState, WS, availableModels } = globalThis.__syncModels;
class EmptyPayload {}
export class RpcRemoteError extends Error {}
const commandCatalog=()=>[];
const getContext = () => ({filesDir:'/private'});
const fileUploadLimit = value => value ?? 0;
export const EnvironmentSession = {current:null};
export const cache = {shell:()=>null,shellSequence:()=>undefined,threadEpoch:()=>0,threadSnapshotEpoch:()=>0,setCatalog(){},commands:()=>[],setThread(){},setShell(){}};
const ClientCache = {open:async()=>cache};
const ComposerOutbox={connected(){},disconnected(){}};export const readiness=[];const AppStorage={setOrCreate:(key,value)=>{if(key==='onlineEnvironmentId')readiness.push(value);if(key==='rpcEnvironmentId')globalThis.__transportReady?.(value);}};
const TaskNotifications = {observe(){}};
class ReconnectingRpc {
 constructor(open,subscribe,status){Object.assign(this,{open,subscribe,status});}
 start(){this.status('connecting');this.run=this.open().then(this.subscribe);}
 stop(){} healthy(){} progress(){}
}
`;
const { ThreadPage, IndexPage, EnvironmentSession, RpcRemoteError, cache, readiness } = await load(prelude + `
export class ThreadPage {
 active=true;params={environmentId:'a',threadId:'t'};state=new ThreadState();cachedThreadLoad=null;
 cache=cache;cacheEpoch=0;connection={healthy(){},progress(){}};catalogLoaded=false;loaded=false;cached=false;
 uploadDraftImages(){} subscribeCheckoutBranch(){} scheduleTranscriptRefresh(){this.rendered=this.state.messages.map(m=>m.text);}
 flushTranscriptRefresh(){this.scheduleTranscriptRefresh();} resumeImageRequest(){}
 ${thread.slice(thread.indexOf('  private async subscribeFeed('),thread.indexOf('  private async refreshWorkspaceCommands(')).replaceAll('private ','')}
}
export class IndexPage {
 pageGeneration=1;isHome(id){return this.pageGeneration===id && id!==0;}
 ${method(index,'  private alternateRoutes(', '  private restoreVisibilityChanged(')}
 connected=null;shell=new ShellState();subscription=null;projects=[];live=false;cached=false;
 refreshThreads(){this.rendered=this.shell.threads.map(t=>t.title);}openNotification(){}loadArchive(){}newTask(){}
 ${method(index, '  private async loadThreads(', '  @Builder\n  private projectSheet(')}
 ${index.slice(index.indexOf('  private async loadCachedEnvironment('),index.indexOf('  private forget(')).replaceAll('private ','')}
}
`);
globalThis.__syncLifecycle = {ThreadPage, EnvironmentSession, ReconnectingRpc: LiveReconnectingRpc};
const {LifecyclePage} = await load(`
const {ThreadPage, EnvironmentSession, ReconnectingRpc}=globalThis.__syncLifecycle;
const router={getParams:()=>({environmentId:'a',threadId:'t'})};
const SwiftBridge={ensure(){throw new Error('no native bridge in test')}};
const KeyboardAvoidMode={RESIZE:1};
export class LifecyclePage extends ThreadPage {
 loadCachedThread(){return this.cachedThreadLoad;}
 loadDraft(){} loadImages(){} loadJournal(){} loadModelDraft(){} receiveImageComment(){}
 updateElapsed(){}
 getUIContext(){return {getKeyboardAvoidMode:()=>0,setKeyboardAvoidMode(){}};}
 ${method(thread,'  aboutToAppear():','  private restoreKeyboardAvoidMode(')}
}
`);
const drain = async () => { for (let i=0;i<24;i++) await Promise.resolve(); };
class Peer {
  constructor(config={}) { this.config={providers:[],environment:{},...config}; this.streams=new Map(); }
  async call() { return this.config; }
  callStream(method,payload,onChunk) { this.streams.set(method,{payload,onChunk});return new Promise(()=>{}); }
  receive(method,...values) { this.streams.get(method).onChunk(values); }
  close() { this.closed=true; }
}
class ClosingPeer extends Peer {
  callStream(method,payload,onChunk) {
    return new Promise((resolve,reject)=>this.streams.set(method,{payload,onChunk,reject}));
  }
  close() {
    if(this.closed) return;
    this.closed=true;
    for(const stream of this.streams.values()) stream.reject(new Error('connection closed'));
  }
}
function liveThreadPage(t,loadSnapshot) {
  const page=new LifecyclePage(),peers=[];
  page.state.restoreCached({id:'t',title:'Cached',syncSequence:10,transcriptVersion:6,messages:[{id:'m',text:'Cached'}]});
  EnvironmentSession.current={descriptor:{environmentId:'a'},loadSnapshot,rpc:{openScope:()=>{
    const rpc=new ClosingPeer({threadResumeCompletionMarker:true});peers.push(rpc);return rpc;
  }}};
  page.aboutToAppear();t.after(()=>page.connection.stop());page.onPageShow();
  return {page,peers};
}
test('a stalled cursor resume refreshes the snapshot in the same page and preserves visible messages',async t=>{
  t.mock.timers.enable({apis:['setTimeout','Date']});
  let finish;const paths=[];
  const {page,peers}=liveThreadPage(t,path=>{paths.push(path);return new Promise(resolve=>finish=resolve);});
  await drain();assert.equal(peers[0].streams.get(models.WS.threadFeed).payload.afterSequence,10);
  t.mock.timers.tick(30000);await drain();
  t.mock.timers.tick(250);await drain();
  assert.deepEqual(paths,['/api/orchestration/threads/t']);
  assert.deepEqual(page.state.messages.map(m=>m.text),['Cached']);assert.equal(page.loaded,false);
  finish({snapshotSequence:12,thread:{id:'t',title:'Current',messages:[{id:'m',text:'Updated'}]}});
  await drain();assert.equal(peers[1].streams.get(models.WS.threadFeed).payload.afterSequence,12);
  peers[1].receive(models.WS.threadFeed,{kind:'synchronized'});
  assert.equal(page.loaded,true);assert.deepEqual(page.rendered,['Updated']);
  t.mock.timers.tick(30000);await drain();assert.equal(peers.length,2);
});
test('a timed-out resume recovers over the socket when HTTP is unavailable and rejects old callbacks',async t=>{
  t.mock.timers.enable({apis:['setTimeout','Date']});let fetches=0;
  const {page,peers}=liveThreadPage(t,async()=>{fetches++;return null;});await drain();
  t.mock.timers.tick(30000);await drain();t.mock.timers.tick(250);await drain();
  assert.equal(fetches,1);
  assert.equal(peers[1].streams.get(models.WS.threadFeed).payload.afterSequence,undefined);
  assert.equal(peers[1].streams.get(models.WS.threadsList).payload.afterSequence,undefined);
  peers[1].receive(models.WS.threadFeed,{kind:'synchronized'});
  assert.equal(page.loaded,false,'a completion marker cannot authorize a send before the replacement snapshot');
  peers[1].receive(models.WS.threadFeed,{kind:'snapshot',snapshotSequence:12,
    projection:{thread:{id:'t',title:'Current'},messages:[{id:'m',text:'Recovered'}],runs:[]}});
  peers[0].receive(models.WS.threadFeed,{kind:'snapshot',snapshotSequence:99,
    projection:{thread:{id:'t',title:'Late'},messages:[],runs:[]}});
  assert.equal(page.loaded,true);assert.deepEqual(page.rendered,['Recovered']);assert.equal(page.state.cursor(),12);
  peers[1].close();await drain();t.mock.timers.tick(250);await drain();
  assert.equal(fetches,1);assert.equal(peers[2].streams.get(models.WS.threadFeed).payload.afterSequence,12);
});
test('a brief disconnect during resume keeps incremental catch-up instead of downloading history',async t=>{
  t.mock.timers.enable({apis:['setTimeout','Date']});let fetches=0;
  const {page,peers}=liveThreadPage(t,async()=>{fetches++;return null;});await drain();
  peers[0].close();await drain();t.mock.timers.tick(250);await drain();
  assert.equal(peers[1].streams.get(models.WS.threadFeed).payload.afterSequence,10);assert.equal(fetches,0);
  peers[1].receive(models.WS.threadFeed,{kind:'synchronized'});assert.equal(page.loaded,true);
});
test('repeated subscription failures recover the snapshot without leaving the page and continue live updates',async t=>{
  t.mock.timers.enable({apis:['setTimeout','Date']});let fetches=0;
  const {page,peers}=liveThreadPage(t,async()=>{fetches++;return {snapshotSequence:12,
    thread:{id:'t',title:'Current',messages:[{id:'m',role:'assistant',text:'Recovered'}]}};});
  await drain();
  for(let attempt=0;attempt<3;attempt++){
    assert.equal(peers[attempt].streams.get(models.WS.threadFeed).payload.afterSequence,10);
    peers[attempt].streams.get(models.WS.threadFeed).reject(new Error('resume failed'));await drain();
    assert.deepEqual(page.state.messages.map(m=>m.text),['Cached']);
    t.mock.timers.tick(250*2**attempt);await drain();
  }
  assert.equal(fetches,1);assert.equal(peers[3].streams.get(models.WS.threadFeed).payload.afterSequence,12);
  peers[3].receive(models.WS.threadFeed,{kind:'synchronized'});assert.equal(page.loaded,true);
  peers[3].receive(models.WS.threadFeed,{kind:'event',sequence:13,event:{type:'message.updated',threadId:'t',
    payload:{id:'m',role:'assistant',text:'Live update after recovery',attachments:[]}}});
  assert.deepEqual(page.rendered,['Live update after recovery']);
});
for(const kind of ['empty','duplicate']) test(`${kind} chunks cannot keep an incomplete synchronization alive forever`,async t=>{
  t.mock.timers.enable({apis:['setTimeout','Date']});
  const {peers}=liveThreadPage(t,async()=>null);await drain();
  for(let step=0;step<2;step++){
    t.mock.timers.tick(10000);await drain();
    if(kind==='empty') peers[0].receive(models.WS.threadFeed);
    else peers[0].receive(models.WS.threadFeed,{kind:'event',sequence:10,event:{type:'message.updated',threadId:'t',
      payload:{id:'m',role:'assistant',text:'Cached',attachments:[]}}});
  }
  t.mock.timers.tick(10000);await drain();assert.equal(peers[0].closed,true);
});
test('new transcript events extend the synchronization deadline while replay catches up',async t=>{
  t.mock.timers.enable({apis:['setTimeout','Date']});
  const {page,peers}=liveThreadPage(t,async()=>null);await drain();
  t.mock.timers.tick(20000);await drain();
  peers[0].receive(models.WS.threadFeed,{kind:'event',sequence:11,event:{type:'message.updated',threadId:'t',
    payload:{id:'m',role:'assistant',text:'New replay content',attachments:[]}}});
  t.mock.timers.tick(20000);await drain();assert.notEqual(peers[0].closed,true);
  peers[0].receive(models.WS.threadFeed,{kind:'synchronized'});
  assert.equal(page.loaded,true);assert.deepEqual(page.rendered,['New replay content']);
  t.mock.timers.tick(30000);await drain();assert.equal(peers.length,1);
});
function threadPage(config={},cached=true) {
  const page=new ThreadPage();page.rpc=new Peer(config);let fetches=0;
  EnvironmentSession.current={descriptor:{environmentId:'a'},loadSnapshot:async()=>{fetches++;return null;}};
  if(cached) page.state.restoreCached({id:'t',title:'Cached',syncSequence:10,transcriptVersion:6,messages:[{id:'m',text:'Cached'}]});
  page.subscribeFeed(page.rpc);return {page,get fetches(){return fetches;}};
}
test('cached thread resumes only missing events and old servers need no completion marker',async()=>{
  const fixture=threadPage();await drain();
  assert.deepEqual(fixture.page.rpc.streams.get(models.WS.threadFeed).payload,{threadId:'t',afterSequence:10});
  assert.equal(fixture.fetches,0);assert.equal(fixture.page.loaded,true);assert.equal(fixture.page.connectionState,'connected');
});
test('the file attachment capability supplies its limit without requiring the optional legacy upload flag',async()=>{
  const {page}=threadPage({environment:{capabilities:{fileAttachments:{maxUploadBytes:2048}}}});
  await drain();assert.equal(page.maxFileBytes,2048);assert.equal(page.catalogLoaded,true);
});
test('capable servers keep cached thread synchronizing until the completion marker',async()=>{
  const {page}=threadPage({threadResumeCompletionMarker:true,reasoningMessages:true});await drain();
  assert.deepEqual(page.rpc.streams.get(models.WS.threadFeed).payload,
    {threadId:'t',afterSequence:10,requestCompletionMarker:true,reasoningMessages:true});
  assert.equal(page.loaded,false);
  page.rpc.receive(models.WS.threadFeed,{kind:'synchronized',sequence:10});
  assert.equal(page.loaded,true);assert.deepEqual(page.rendered,['Cached']);
});
test('cold thread loads its HTTP snapshot then subscribes from that cursor',async()=>{
  const {page}=threadPage({},false);const paths=[];
  EnvironmentSession.current.loadSnapshot=async path=>{paths.push(path);return {snapshotSequence:20,thread:{id:'t',title:'HTTP',messages:[{id:'m',text:'HTTP'}]}};};
  await drain();assert.deepEqual(paths,['/api/orchestration/threads/t']);
  assert.equal(page.rpc.streams.get(models.WS.threadFeed).payload.afterSequence,20);
  assert.equal(page.loaded,true);assert.deepEqual(page.rendered,['HTTP']);
});
test('current protocol HTTP projections render before the socket resumes',async()=>{
  const {page}=threadPage({},false);
  EnvironmentSession.current.loadSnapshot=async()=>({snapshotSequence:20,projection:{thread:{id:'t',title:'HTTP'},
    messages:[{id:'m',role:'assistant',text:'Current HTTP',runId:'r'}],runs:[]}});
  await drain();assert.equal(page.rpc.streams.get(models.WS.threadFeed).payload.afterSequence,20);
  assert.equal(page.loaded,true);assert.deepEqual(page.rendered,['Current HTTP']);
});
test('failed HTTP thread load falls back to a complete socket snapshot',async()=>{
  const {page}=threadPage({},false);await drain();
  assert.deepEqual(page.rpc.streams.get(models.WS.threadFeed).payload,{threadId:'t'});assert.equal(page.loaded,false);
  page.rpc.receive(models.WS.threadFeed,{kind:'snapshot',snapshotSequence:4,projection:{thread:{id:'t',title:'WS'},messages:[],runs:[]}});
  assert.equal(page.loaded,true);
});
for (const pagination of [false, true]) test(`a stalled HTTP recovery yields to the live socket within five seconds (pagination=${pagination})`,async t=>{
  t.mock.timers.enable({apis:['setTimeout','Date']});
  const page=new ThreadPage(),rpc=new Peer({threadSnapshotPagination:pagination}),paths=[];page.threadNeedsSnapshot=true;
  page.rpc=rpc;
  EnvironmentSession.current={descriptor:{environmentId:'a'},loadSnapshot:(path,timeout=20000)=>{
    paths.push(path);return new Promise(resolve=>setTimeout(()=>resolve(null),timeout));
  }};
  page.connection=new LiveReconnectingRpc(async()=>rpc,peer=>page.subscribeFeed(peer),()=>{});
  t.after(()=>page.connection.stop());page.connection.start();await drain();
  t.mock.timers.tick(5000);await drain();
  assert.equal(rpc.closed,undefined);
  assert.ok(rpc.streams.has(models.WS.threadFeed),'HTTP timeout must not prevent the socket subscription');
  assert.equal(paths.length,1);
  rpc.receive(models.WS.threadFeed,{kind:'snapshot',snapshotSequence:4,projection:{thread:{id:'t',title:'WS'},messages:[],runs:[]}});
  assert.equal(page.loaded,true);
  t.mock.timers.tick(30000);await drain();assert.equal(rpc.closed,undefined);
});
test('bounded and legacy HTTP endpoints share the same five-second prefetch budget',async t=>{
  t.mock.timers.enable({apis:['setTimeout','Date']});
  const page=new ThreadPage(),rpc=new Peer({threadSnapshotPagination:true}),budgets=[];page.threadNeedsSnapshot=true;
  page.rpc=rpc;
  EnvironmentSession.current={descriptor:{environmentId:'a'},loadSnapshot:(path,timeout=20000)=>{
    budgets.push(timeout);return new Promise(resolve=>setTimeout(()=>resolve(null),path.includes('/bounded?compactTurnItems=1')?3000:timeout));
  }};
  page.connection=new LiveReconnectingRpc(async()=>rpc,peer=>page.subscribeFeed(peer),()=>{});
  t.after(()=>page.connection.stop());page.connection.start();await drain();
  t.mock.timers.tick(3000);await drain();
  t.mock.timers.tick(2000);await drain();
  assert.ok(rpc.streams.has(models.WS.threadFeed),'legacy fallback must not restart the HTTP budget');
  assert.deepEqual(budgets,[5000,2000]);assert.equal(rpc.closed,undefined);
});
test('a bounded HTTP response cannot silently replace complete history',async()=>{
  const {page}=threadPage({},false);
  EnvironmentSession.current.loadSnapshot=async()=>({snapshotSequence:20,hasMoreHistory:true,
    projection:{thread:{id:'t',title:'Window'},messages:[],runs:[]}});
  await drain();assert.equal(page.rpc.streams.get(models.WS.threadFeed).payload.afterSequence,undefined);
  assert.equal(page.loaded,false);
});
test('a stale shell cursor recovers without discarding the cached conversation',async()=>{
  const {page}=threadPage();page.cache={threadEpoch:()=>0,threadSnapshotEpoch:()=>0,setCatalog(){},commands:()=>[],shellSequence:()=>15};await drain();
  assert.equal(page.rpc.streams.get(models.WS.threadsList).payload.afterSequence,15);
  page.rpc.receive(models.WS.threadsList,{kind:'snapshot-required'});assert.equal(page.rpc.closed,true);
  page.rpc=new Peer();page.subscribeFeed(page.rpc);await drain();
  assert.equal(page.rpc.streams.get(models.WS.threadsList).payload.afterSequence,undefined);
  assert.equal(page.state.messages[0].text,'Cached');
});
test('a late HTTP thread result cannot replace a newer session',async()=>{
  const {page}=threadPage({},false);let finish;
  EnvironmentSession.current.loadSnapshot=()=>new Promise(resolve=>finish=resolve);await drain();
  const old=page.rpc;page.rpc=new Peer();finish({snapshotSequence:20,thread:{id:'t',title:'stale',messages:[]}});await drain();
  assert.equal(page.state.thread,null);assert.equal(old.streams.size,0);
});
test('new task-list session refreshes HTTP authority before resuming its socket',async()=>{
  const page=new IndexPage();const rpc=new Peer({shellResumeCompletionMarker:true});const paths=[];
  page.connected={descriptor:{environmentId:'a'},rpc,loadSnapshot:async path=>{paths.push(path);return {snapshotSequence:12,threads:[{id:'t',title:'Updated'}],projects:[]};}};
  page.shell.apply({kind:'snapshot',snapshot:{snapshotSequence:10,threads:[{id:'t',title:'Cached'}],projects:[]}});
  await page.loadThreads();await drain();
  assert.deepEqual(paths,['/api/orchestration/shell']);assert.deepEqual(page.rendered,['Updated']);
  assert.deepEqual(rpc.streams.get(models.WS.threadsList).payload,{afterSequence:12,requestCompletionMarker:true});
  rpc.receive(models.WS.threadsList,{kind:'synchronized',sequence:12});assert.equal(page.live,true);
});
test('an already synchronized task list reconnects from its cursor and refreshes HTTP only when that cursor expires',async()=>{
 const page=new IndexPage(),peers=[new Peer({shellResumeCompletionMarker:true})];let fetches=0;
 page.connected={descriptor:{environmentId:'a'},rpc:peers[0],
  loadSnapshot:async()=>{fetches++;return {snapshotSequence:12,threads:[{id:'t',title:'Current'}],projects:[]};},
  openRpc:async()=>{const peer=new Peer({shellResumeCompletionMarker:true});peers.push(peer);return peer;}};
 await page.loadThreads();await drain();peers[0].receive(models.WS.threadsList,{kind:'synchronized'});
 const reconnect=async()=>{page.subscription.status('reconnecting');page.subscription.subscribe(await page.subscription.open());await drain();};
 await reconnect();assert.equal(fetches,1);assert.equal(page.live,false);
 assert.equal(peers[1].streams.get(models.WS.threadsList).payload.afterSequence,12);
 peers[1].receive(models.WS.threadsList,{kind:'thread-upserted',sequence:13,thread:{id:'t',title:'Only the missing change'}});
 peers[1].receive(models.WS.threadsList,{kind:'synchronized'});
 assert.equal(page.live,true);assert.deepEqual(page.rendered,['Only the missing change']);
 await reconnect();assert.equal(peers[2].streams.get(models.WS.threadsList).payload.afterSequence,13);assert.equal(fetches,1);
 peers[2].receive(models.WS.threadsList,{kind:'snapshot-required'});assert.equal(peers[2].closed,true);
 await reconnect();assert.equal(fetches,2);
});
test('failed HTTP task-list refresh requests a full snapshot instead of trusting partial cache',async()=>{
  const page=new IndexPage();const rpc=new Peer();
  page.connected={descriptor:{environmentId:'a'},rpc,loadSnapshot:async()=>null};
  page.shell.apply({kind:'snapshot',snapshot:{snapshotSequence:10,threads:[{id:'t',title:'Cached'}],projects:[]}});
  await page.loadThreads();await drain();assert.deepEqual(rpc.streams.get(models.WS.threadsList).payload,{});
});
test('a stalled task-list HTTP refresh yields to the socket within five seconds and keeps cached tasks visible',async t=>{
  t.mock.timers.enable({apis:['setTimeout','Date']});
  const page=new IndexPage(),rpc=new Peer();
  page.shell.apply({kind:'snapshot',snapshot:{snapshotSequence:10,threads:[{id:'t',title:'Cached'}],projects:[]}});
  page.connected={descriptor:{environmentId:'a'},rpc,loadSnapshot:(path,timeout=20000)=>
    new Promise(resolve=>setTimeout(()=>resolve(null),timeout))};
  await page.loadThreads();await drain();
  t.mock.timers.tick(5000);await drain();
  assert.ok(rpc.streams.has(models.WS.threadsList),'the optional HTTP request must not block the live subscription');
  assert.deepEqual(rpc.streams.get(models.WS.threadsList).payload,{});
  assert.deepEqual(page.rendered,['Cached']);assert.equal(page.live,false);
  rpc.receive(models.WS.threadsList,{kind:'snapshot',snapshot:{snapshotSequence:12,threads:[{id:'t',title:'Updated'}],projects:[]}});
  assert.equal(page.live,true);assert.deepEqual(page.rendered,['Updated']);
});
test('old servers with an HTTP task snapshot become ready without waiting for a marker',async()=>{
  const page=new IndexPage();const rpc=new Peer();
  page.connected={descriptor:{environmentId:'a'},rpc,loadSnapshot:async()=>({snapshotSequence:12,threads:[],projects:[]})};
  await page.loadThreads();await drain();assert.equal(page.live,true);assert.equal(page.connectionState,'connected');
});
test('a shell snapshot-required marker triggers recovery rather than waiting forever',async()=>{
  const page=new IndexPage(),rpc=new Peer();
  page.connected={descriptor:{environmentId:'a'},rpc,loadSnapshot:async()=>null};
  await page.loadThreads();await drain();rpc.receive(models.WS.threadsList,{kind:'snapshot-required'});
  assert.equal(rpc.closed,true);
});
test('restoring cached tasks preserves the saved sequence',async()=>{
  cache.shell=()=>({snapshotSequence:15,threads:[{id:'t',title:'Cached'}],projects:[]});
  const page=new IndexPage();await page.loadCachedEnvironment({environmentId:'a',label:'Machine'});
  assert.equal(page.shell.cursor(),15);assert.equal(page.cached,true);
});

test('media readiness follows the live shell, including losing the connection and finishing the next replay',async()=>{
 const page=new IndexPage(),a=new Peer({shellResumeCompletionMarker:true}),b=new Peer({shellResumeCompletionMarker:true});readiness.length=0;
 page.connected={descriptor:{environmentId:'a'},rpc:a,openRpc:async()=>b,loadSnapshot:async()=>({snapshotSequence:4,threads:[],projects:[]})};
 await page.loadThreads();await drain();assert.deepEqual(readiness,['']);a.receive(models.WS.threadsList,{kind:'synchronized'});assert.equal(readiness.at(-1),'a');
 page.subscription.status('reconnecting');assert.equal(readiness.at(-1),'');page.subscription.subscribe(await page.subscription.open());await drain();
 a.receive(models.WS.threadsList,{kind:'synchronized'});assert.equal(readiness.at(-1),'');b.receive(models.WS.threadsList,{kind:'synchronized'});assert.equal(readiness.at(-1),'a');
});

for (const http of [true,false]) test(`the first live task list replaces a cached cursor ahead of the server (HTTP=${http})`,async()=>{
 const page=new IndexPage(), rpc=new Peer({shellResumeCompletionMarker:true});
 const fresh={snapshotSequence:4,projects:[],threads:[{id:'new',title:'Restored server'}]};
 page.shell.apply({kind:'snapshot',snapshot:{snapshotSequence:80,projects:[],threads:[{id:'old',title:'Cached'}]}});
 page.connected={descriptor:{environmentId:'a'},rpc,loadSnapshot:async()=>http?fresh:null};
 await page.loadThreads();await drain();
 if(http) assert.equal(rpc.streams.get(models.WS.threadsList).payload.afterSequence,4);
 else {
  rpc.receive(models.WS.threadsList,{kind:'snapshot',resolvedRepositoryIdentityRoots:[],snapshot:{snapshotSequence:82,projects:[],threads:[]}});
  rpc.receive(models.WS.threadsList,{kind:'synchronized'});
  assert.equal(page.live,false);assert.deepEqual(page.rendered,['Cached']);
  rpc.receive(models.WS.threadsList,{kind:'snapshot',snapshot:fresh});
 }
 rpc.receive(models.WS.threadsList,{kind:'synchronized'});
 rpc.receive(models.WS.threadsList,{kind:'thread.updated',sequence:5,thread:{id:'new',title:'Live change'}});
 assert.equal(page.live,true);assert.equal(page.shell.cursor(),5);assert.deepEqual(page.rendered,['Live change']);
});

test('a replacement detail snapshot on a newly opened socket can reset an ahead-of-server cursor',async()=>{
 const {page}=threadPage({threadResumeCompletionMarker:true});await drain();const rpc=page.rpc;
 rpc.receive(models.WS.threadFeed,{kind:'snapshot',snapshotSequence:4,projection:{thread:{id:'t',title:'Restored server'},messages:[{id:'new',text:'Restored reply'}],runs:[]}});
 assert.equal(page.loaded,true);assert.equal(page.state.cursor(),4);assert.deepEqual(page.rendered,['Restored reply']);
 rpc.receive(models.WS.threadFeed,{kind:'event',sequence:5,event:{threadId:'t',type:'message.updated',payload:{id:'new',text:'Live change'}}});
 rpc.receive(models.WS.threadFeed,{kind:'snapshot',snapshotSequence:3,projection:{thread:{id:'t'},messages:[],runs:[]}});
 assert.equal(page.state.cursor(),5);assert.deepEqual(page.rendered,['Live change']);
});

const {ClientCache: SharedCache}=await load(`const DraftStore={open:async()=>({load:async()=>'',save:async()=>{}})},availableModels=()=>[],commandCatalog=()=>[];
${read('../app/entry/src/main/ets/connection/ClientCache.ets').replace(/^import .*;$/gm,'')}`);
for(const viaHttp of [true,false]) test(`a pre-restore ${viaHttp?'HTTP':'socket'} response is discarded and the page rejoins the current timeline`,async()=>{
 const cache=await SharedCache.open('/timeline',String(viaHttp)),gate=Promise.withResolvers();let nextDownload=gate.promise;
 const snapshot=(n,text)=>({snapshotSequence:n,projection:{thread:{id:'t',title:'Restored'},messages:[{id:'m',text}],runs:[]}});
 EnvironmentSession.current={descriptor:{environmentId:'a'},loadSnapshot:()=>nextDownload};
 const pages=[new ThreadPage(),new ThreadPage()];for(const p of pages){p.rpc=new Peer();p.cache=cache;p.state.restoreCached({id:'t',syncSequence:80,transcriptVersion:6,messages:[{id:'m',text:'before'}]});
   p.flushTranscriptRefresh=()=>{if(p.loaded)cache.setThread(p.state.thread,p.state.messages,[],0,p.state.cursor(),true,p.cacheEpoch);};}
 const [a,b]=pages;b.threadNeedsSnapshot=viaHttp;a.subscribeFeed(a.rpc);b.subscribeFeed(b.rpc);await drain();
 a.rpc.receive(models.WS.threadFeed,{kind:'snapshot',...snapshot(4,'restored')});assert.equal(cache.threadSequence('t'),4);
 if(viaHttp){gate.resolve(snapshot(81,'stale'));await drain();}else b.rpc.receive(models.WS.threadFeed,{kind:'snapshot',...snapshot(81,'stale')});
 assert.equal(b.rpc.closed,true);assert.notEqual(b.state.messages[0].text,'stale');assert.equal((await cache.thread('t')).messages[0].text,'restored');
 nextDownload=Promise.resolve(snapshot(5,'new'));b.rpc=new Peer();b.subscribeFeed(b.rpc);await drain();assert.equal(b.rpc.streams.get(models.WS.threadFeed).payload.afterSequence,5);
 assert.equal(b.cacheEpoch,a.cacheEpoch);assert.equal(cache.threadSequence('t'),5);assert.equal((await cache.thread('t')).messages[0].text,'new');await cache.flush();
});

test('a connected environment starts a bounded live thread before another catalog or HTTP response', async () => {
  const page = new ThreadPage(), rpc = new Peer(), config = {providers:[], environment:{capabilities:{fileAttachments:{maxUploadBytes:1024}}}, threadSnapshotPagination:true, threadResumeCompletionMarker:true};
  let release; rpc.call = () => new Promise(resolve => { release = resolve; }); page.rpc = rpc;
  const paths = [];
  EnvironmentSession.current = {descriptor:{environmentId:'a'}, liveConfig:config, loadSnapshot:async p=>{paths.push(p);return null;}};
  page.subscribeFeed(rpc); await drain();
  assert.deepEqual(rpc.streams.get(models.WS.threadFeed)?.payload,{threadId:'t',acceptBoundedSnapshot:true,acceptCompactTurnItems:true,requestCompletionMarker:true});
  assert.equal(page.loaded,false); assert.deepEqual(paths,[]);
  rpc.receive(models.WS.threadFeed,{kind:'synchronized'}); assert.equal(page.loaded,false);
  rpc.receive(models.WS.threadFeed,{kind:'snapshot',snapshotSequence:12,projection:{thread:{id:'t'},messages:[],runs:[]}});
  assert.equal(page.loaded,true); assert.equal(page.maxFileBytes,1024,'a queued file can send before the catalog refresh');
  release({...config,environment:{capabilities:{fileAttachments:{maxUploadBytes:2048}}}});
  await drain(); assert.equal(page.maxFileBytes,2048);
});

test('cold chat requests the bounded socket snapshot as soon as the server advertises it', async () => {
  const page=new ThreadPage(), rpc=new Peer({threadSnapshotPagination:true,threadResumeCompletionMarker:true});
  const http=Promise.withResolvers(); let fetches=0; page.rpc=rpc;
  EnvironmentSession.current={descriptor:{environmentId:'a'},loadSnapshot:()=>{fetches++;return http.promise;}};
  page.subscribeFeed(rpc);await drain();
  assert.ok(rpc.streams.has(models.WS.threadFeed),'the slow optional HTTP read must not hold a capable socket');
  assert.equal(fetches,0);assert.equal(page.loaded,false);
  rpc.receive(models.WS.threadFeed,{kind:'snapshot',snapshotSequence:12,projection:{thread:{id:'t'},messages:[],runs:[]}});
  assert.equal(page.loaded,true);
});

test('opening chat during environment restore shares the config download without waiting for the task list',async()=>{
  const home=new IndexPage(),page=new ThreadPage(),root=new Peer(),scope=new Peer();
  const config=Promise.withResolvers(),list=Promise.withResolvers();let rootCalls=0,scopeCalls=0;
  root.call=()=>{rootCalls++;return config.promise;};scope.call=()=>{scopeCalls++;return new Promise(()=>{});};
  const environment={descriptor:{environmentId:'a'},rpc:root,loadSnapshot:()=>list.promise};
  EnvironmentSession.current=home.connected=environment;page.rpc=scope;
  await home.loadThreads();await drain();page.subscribeFeed(scope);await drain();
  assert.equal(scope.streams.has(models.WS.threadFeed),false,'a page without a valid cursor negotiates its initial snapshot');
  config.resolve({providers:[],environment:{},threadSnapshotPagination:true,threadResumeCompletionMarker:true});await drain();
  assert.equal(rootCalls,1);assert.equal(scopeCalls,0);assert.equal(home.live,false);
  assert.equal(scope.streams.get(models.WS.threadFeed)?.payload.acceptBoundedSnapshot,true);
  assert.equal(page.loaded,false);scope.receive(models.WS.threadFeed,{kind:'snapshot',snapshotSequence:12,projection:{thread:{id:'t'},messages:[],runs:[]}});
  assert.equal(page.loaded,true);list.resolve(null);await drain();
});

test('a cached chat wakes on its own restored transport before the next backoff, and still needs an authoritative reply',async t=>{
  t.mock.timers.enable({apis:['setTimeout','Date']});
  const page=new LifecyclePage(),rpc=new ClosingPeer({threadResumeCompletionMarker:true,threadSnapshotPagination:true});
  const home=new IndexPage(),root=new Peer({threadResumeCompletionMarker:true,threadSnapshotPagination:true});let dials=0,scopes=0;
  const environment={descriptor:{environmentId:'a'},rpc:root,openRpc:()=>{dials++;return new Promise(()=>{});},loadSnapshot:()=>new Promise(()=>{})};
  root.openScope=()=>{scopes++;return rpc;};
  EnvironmentSession.current=null;page.aboutToAppear();t.after(()=>page.connection.stop());page.onPageShow();await drain();
  for(const delay of [250,500,1000,2000,4000]) {t.mock.timers.tick(delay);await drain();}
  page.rpcEnvironmentId='b';page.transportAvailable?.();await drain();assert.equal(scopes,0);
  globalThis.__transportReady=id=>{page.rpcEnvironmentId=id;page.transportAvailable?.();};t.after(()=>delete globalThis.__transportReady);
  home.connected=EnvironmentSession.current=environment;
  await home.loadThreads();await drain();
  assert.ok(rpc.streams.has(models.WS.threadFeed),'restoring the environment must wake the chat without advancing the 8-second retry');
  assert.equal(scopes,1);assert.equal(dials,0);assert.equal(page.loaded,false);
  rpc.receive(models.WS.threadFeed,{kind:'snapshot',snapshotSequence:5,projection:{thread:{id:'t'},messages:[],runs:[]}});
  assert.equal(page.loaded,true);
});

test('a dropped live SSH route only hands off to its own standby for transport failures',async()=>{
 for(const reason of ['tcp connect failed','SSH socket error during sign-in','SSH authentication failed','SSH host fingerprint mismatch','环境请求失败（HTTP 401）']){
  const page=new IndexPage(),rpc=new Peer(),a={environmentId:'a',connectionId:'a-main',ssh:{}},b={environmentId:'a',connectionId:'a-backup',ssh:{}};
  page.foreground=true;page.saved=[a,{environmentId:'different',connectionId:'other',ssh:{}},b];const restored=[];page.restore=async saved=>restored.push(saved);
  page.connected={descriptor:{environmentId:'a'},rpc,matchesSaved:r=>r===a,openRpc:async()=>{throw Error(reason)},loadSnapshot:async()=>null};
  await page.loadThreads();await drain();await assert.rejects(page.subscription.open(),e=>e.message===reason);
  assert.deepEqual(restored,['tcp connect failed','SSH socket error during sign-in'].includes(reason)?[b]:[]);
  if(!restored.length){assert.equal(page.connectionState,'failed');assert.ok(page.status.includes(reason));}
 }
});

function restoringThread(rpc = new Peer()) {
  const page = new ThreadPage(), config = Promise.withResolvers();
  const paths = [];
  EnvironmentSession.current = {descriptor:{environmentId:'a'}, pendingConfig:config.promise,
    loadSnapshot:async path=>{paths.push(path);return {snapshotSequence:14,thread:{id:'t',messages:[{id:'m',text:'Authoritative legacy reply'}]}};}};
  page.state.restoreCached({id:'t', syncSequence:10, transcriptVersion:6, messages:[{id:'m',text:'On disk'}]});
  page.rpc = rpc; const feed = page.subscribeFeed(rpc); return {page,rpc,config,paths,feed};
}
const replayText = (sequence,text) => ({kind:'event',sequence,event:{type:'message.updated',threadId:'t',payload:{id:'m',role:'assistant',text}}});
test('a cached thread streams missed messages and confirms readiness while the environment catalog is still loading', async()=>{
  const {page,rpc,config,paths}=restoringThread(); await drain();
  const request=rpc.streams.get(models.WS.threadFeed)?.payload;
  assert.equal(request?.afterSequence,10); assert.equal(request.requestCompletionMarker,true);
  assert.equal(request.reasoningMessages,true); assert.equal(page.loaded,false);
  rpc.receive(models.WS.threadFeed,replayText(11,'First network update'));
  assert.deepEqual(page.rendered,['First network update']); assert.equal(page.loaded,false);
  rpc.receive(models.WS.threadFeed,replayText(11,'Duplicate'),replayText(12,'Second network update'),{kind:'synchronized'});
  assert.deepEqual(page.rendered,['Second network update']); assert.equal(page.loaded,true); assert.equal(page.catalogLoaded,false);
  config.resolve({providers:[],environment:{},threadResumeCompletionMarker:true,threadSnapshotPagination:true,reasoningMessages:true}); await drain();
  assert.equal(page.catalogLoaded,true); assert.equal(page.loaded,true); assert.deepEqual(paths,[]); assert.equal(rpc.closed,undefined);
});
test('a markerless peer cannot enable sending from a speculative cursor; it recovers from a verified baseline',async()=>{
  const {page,rpc,config,paths}=restoringThread(); await drain();
  assert.ok(rpc.streams.has(models.WS.threadFeed));
  rpc.receive(models.WS.threadFeed,replayText(11,'Partial replay')); config.resolve({providers:[],environment:{}}); await drain();
  assert.equal(page.loaded,false); assert.equal(rpc.closed,true); assert.deepEqual(page.rendered,['Partial replay']);
  const fresh=page.rpc=new Peer();page.subscribeFeed(fresh);await drain();
  assert.deepEqual(paths,['/api/orchestration/threads/t']); assert.equal(fresh.streams.get(models.WS.threadFeed).payload.afterSequence,14);
  assert.equal(page.loaded,true);assert.deepEqual(page.rendered,['Authoritative legacy reply']);
  rpc.receive(models.WS.threadFeed,replayText(15,'From the old socket'));assert.deepEqual(page.rendered,['Authoritative legacy reply']);
});
test('a peer rejecting an early subscription retries with negotiated options and a verified snapshot',async()=>{
  const {page,rpc,config,paths,feed}=restoringThread(new ClosingPeer()); await drain();
  const failed=assert.rejects(feed,/unsupported option/);
  rpc.streams.get(models.WS.threadFeed).reject(new RpcRemoteError('unsupported option')); await failed;
  assert.equal(page.loaded,false); const next=page.rpc=new Peer();page.subscribeFeed(next);await drain();
  assert.equal(next.streams.has(models.WS.threadFeed),false);
  config.resolve({providers:[],environment:{}});await drain();
  assert.deepEqual(paths,['/api/orchestration/threads/t']);assert.deepEqual(next.streams.get(models.WS.threadFeed).payload,{threadId:'t',afterSequence:14});
  assert.equal(page.loaded,true);assert.deepEqual(page.rendered,['Authoritative legacy reply']);
});
test('compact thread snapshots preserve visible records, pending requests and overlapping history exactly once',async()=>{
  const {page}=threadPage({threadSnapshotPagination:true,threadResumeCompletionMarker:true},false);await drain();
  const request=page.rpc.streams.get(models.WS.threadFeed).payload;
  assert.equal(request.acceptCompactTurnItems,true);
  const base={threadId:'t',runId:'r',ordinal:1,status:'completed',updatedAt:'2026-01-01T00:00:00Z'};
  const local={...base,id:'reply',messageId:'m',type:'assistant_message',text:'Local'};
  const inherited={...local,id:'fork-item',messageId:'fork',threadId:'parent',text:'Inherited'};
  const question={...base,id:'q',type:'user_input_request',status:'pending',requestId:'q',questions:[{id:'one',header:'Q',question:'Continue?',options:[]}]};
  const row=(item,position)=>({position,sourceThreadId:item.threadId,sourceItemId:item.id,item});
  page.rpc.receive(models.WS.threadFeed,{kind:'snapshot',snapshotSequence:20,hasMoreHistory:true,historyCursor:'older',turnItemsOmitLocalVisible:true,
    projection:{thread:{id:'t'},messages:[],runs:[],visibleTurnItems:[row(inherited,1),row(local,2)],turnItems:[question]}});
  assert.deepEqual(page.rendered,['Inherited','Local']); assert.equal(models.pendingRequests(page.state.activities).length,1);
  page.rpc.receive(models.WS.threadFeed,replayText(21,'Live local'));
  assert.equal(page.state.mergeHistory({snapshotSequence:20,nextCursor:null,hasMoreHistory:false,items:[row(question,0),row(local,2)]},'older',page.state.historyVersion()),true);
  assert.deepEqual(page.state.messages.map(m=>m.text),['Inherited','Live local']);assert.equal(page.state.activities.length,1);assert.equal(page.state.cursor(),21);
});

test('a superseded environment cannot publish its late replay or catalog in an open cached page',async()=>{
  const {page,rpc,config}=restoringThread();await drain();
  EnvironmentSession.current={descriptor:{environmentId:'a'}}; // Same environment, different SSH route.
  rpc.receive(models.WS.threadFeed,replayText(11,'Stale reply'),{kind:'synchronized'});
  config.resolve({providers:[],environment:{capabilities:{fileAttachments:{maxUploadBytes:4096}}},threadResumeCompletionMarker:true});await drain();
  assert.equal(page.loaded,false);assert.equal(page.catalogLoaded,false);assert.notEqual(page.maxFileBytes,4096);
  assert.deepEqual(page.state.messages.map(m=>m.text),['On disk']);
});
