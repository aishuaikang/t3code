import {test} from 'node:test';import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';import {stripTypeScriptTypes} from 'node:module';
const source=readFileSync(new URL('../app/entry/src/main/ets/pages/Thread.ets',import.meta.url),'utf8');
const reconnectSource=readFileSync(new URL('../app/entry/src/main/ets/connection/ReconnectingRpc.ets',import.meta.url),'utf8').replace(/^import .*;\n/gm,'');
const {ReconnectingRpc}=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(reconnectSource)).toString('base64'));
globalThis.__loadingRpc=ReconnectingRpc;
const followSource=readFileSync(new URL('../app/entry/src/main/ets/model/TranscriptFollow.ets',import.meta.url),'utf8');
globalThis.__loadingFollow=(await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(followSource)).toString('base64'))).TranscriptFollow;
const body=`const ReconnectingRpc=globalThis.__loadingRpc;const router={getParams:()=>({environmentId:'a',threadId:'t',title:'Known title'})};const SwiftBridge={ensure(){throw new Error('no native bridge in test')}};const KeyboardAvoidMode={RESIZE:1};
export const EnvironmentSession={current:{descriptor:{environmentId:'a'},rpc:{openScope:()=>null}}};
export class Fixture{follow=new globalThis.__loadingFollow();active=false;editingQueue=null;previousKeyboardAvoidMode=null;connection=null;state={thread:null};loadCachedThread(){};loadDraft(){};loadModelDraft(){};loadImages(){};loadJournal(){};receiveImageComment(){};getUIContext(){return {getKeyboardAvoidMode:()=>0,setKeyboardAvoidMode(){}}};
cancelQuoteNavigation(){}flushTranscriptRefresh(){}cancelFollowScroll(){}stopElapsedTimer(){}restoreKeyboardAvoidMode(){}cancelPaths(){}saveDraft(){}updateElapsed(){}subscribeFeed(){return new Promise(()=>{})}
${source.slice(source.indexOf('  aboutToAppear():'),source.indexOf('  private restoreKeyboardAvoidMode(')).replaceAll('private ','')}
${source.slice(source.indexOf('  onPageHide():'),source.indexOf('  aboutToDisappear():')).replaceAll('private ','')}
}`;
const {Fixture,EnvironmentSession}=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(body)).toString('base64'));
test('entering a thread starts only one connection across both appearance callbacks',()=>{
 let opens=0;EnvironmentSession.current.rpc.openScope=()=>{opens++;return null};
 const page=new Fixture();page.aboutToAppear();page.onPageShow();assert.equal(opens,1);page.connection.stop();
});

test('hiding and showing a retained chat keeps its live stream and synchronized state',async t=>{
 let opens=0;const peer={closed:false,close(){this.closed=true;},probe(){return !this.closed;}};
 EnvironmentSession.current.rpc.openScope=()=>{opens++;return peer;};
 const page=new Fixture();page.aboutToAppear();t.after(()=>page.connection.stop());page.onPageShow();
 for(let i=0;i<12;i++)await Promise.resolve();page.connection.healthy();page.loaded=true;
 page.follow.update('new content');page.follow.touchStart();assert.equal(page.follow.takeRequest(),false);
 page.onPageHide();assert.equal(page.follow.takeRequest(),true);assert.equal(page.readVisible,false);page.onPageShow();
 for(let i=0;i<12;i++)await Promise.resolve();
 assert.equal(opens,1);assert.equal(peer.closed,false);assert.equal(page.loaded,true);assert.equal(page.readVisible,true);
});

const models=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(readFileSync(new URL('../app/entry/src/main/ets/model/Models.ets',import.meta.url),'utf8'))).toString('base64'));
globalThis.__cachedThreadModels=models;
const cacheBody=`const {ThreadState}=globalThis.__cachedThreadModels;const ClientCache={open:(...args)=>globalThis.__threadCacheOpen(...args)};const getContext=()=>({filesDir:'/private'});
export class CachedPage {active=true;catalogLoaded=false;loaded=false;cached=false;models=[];commandCatalog=[];params={environmentId:'a',threadId:'t'};state=new ThreadState();
refreshTranscript(){this.entries=this.state.messages}syncComposerMetadata(){this.composerThread=this.state.thread}
${source.slice(source.indexOf('  private async loadCachedThread('),source.indexOf('  private selectCommand(')).replaceAll('private ','')}
}`;
const {CachedPage}=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(cacheBody)).toString('base64'));
test('cached messages render without authorizing sends, and late cache reads cannot overwrite live data',async()=>{
 const cached={id:'t',title:'Cached title',messages:[{id:'old',text:'Cached message'}]};let saved;
 const cache={threadEpoch:()=>0,shell:()=>null,models:()=>[{model:'old'}],commands:()=>[],thread:()=>structuredClone(cached),setThread:thread=>saved=thread};
 globalThis.__threadCacheOpen=async(dir,env)=>{assert.equal(env,'a');return cache};
 const first=new CachedPage();await first.loadCachedThread();assert.equal(first.entries[0].text,'Cached message');assert.equal(first.loaded,false);assert.equal(first.cached,true);
 let finish;globalThis.__threadCacheOpen=()=>new Promise(resolve=>finish=resolve);
 const page=new CachedPage();const loading=page.loadCachedThread();
 page.state.apply({kind:'snapshot',snapshotSequence:9,projection:{thread:{id:'t',title:'Live title'},messages:[{id:'live',text:'Live message'}],runs:[]}});
 page.loaded=true;page.catalogLoaded=true;page.models=[];finish(cache);await loading;
 assert.equal(page.state.thread.title,'Live title');assert.equal(page.state.messages[0].text,'Live message');
 assert.deepEqual(page.models,[]);assert.equal(saved.title,'Live title');
});

test('opening a quoted conversation without a route directory recovers its project root for branch status',async()=>{
 const page=new CachedPage();
 const cached={id:'t',projectId:'project',messages:[]};
 globalThis.__threadCacheOpen=async()=>({threadEpoch:()=>0,models:()=>[],commands:()=>[],thread:()=>cached,
  shell:()=>({projects:[{id:'project',title:'Project',workspaceRoot:'/repo'}]})});
 await page.loadCachedThread();
 assert.equal(page.cwd,'/repo');assert.equal(page.projectTitle,'Project');
});
