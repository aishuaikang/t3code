import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const model=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(
 readFileSync(new URL('../app/entry/src/main/ets/model/Models.ets',import.meta.url),'utf8'))).toString('base64'));
const item=(id,ordinal,text=id)=>({id,threadId:'t',runId:'r',type:'assistant_message',ordinal,text,
 status:'completed',streaming:false,updatedAt:'2026-11-15T00:00:00Z'});
const visible=(value,position)=>({position,sourceThreadId:'t',sourceItemId:value.id,item:value});
function snapshot(sequence=100){return {kind:'snapshot',snapshotSequence:sequence,hasMoreHistory:true,historyCursor:'older',
 projection:{thread:{id:'t',title:'Task'},messages:[],runs:[],visibleTurnItems:[visible(item('recent',3),0)]}};}
test('a bounded snapshot keeps the history cursor when cached and resumed',()=>{
 const state=new model.ThreadState();state.apply(snapshot());
 assert.equal(state.thread.historyCursor,'older');assert.equal(state.thread.hasMoreHistory,true);
 const resumed=new model.ThreadState();resumed.restoreCached({...state.thread,messages:state.messages,syncSequence:100});
 assert.equal(resumed.thread.historyCursor,'older');assert.equal(resumed.cursor(),100);
});
test('older pages prepend once, preserve live records and never advance the live event cursor',()=>{
 const state=new model.ThreadState();state.apply(snapshot());const epoch=state.historyVersion();
 const page={snapshotSequence:100,items:[visible(item('old',1),0),visible(item('recent',3,'stale copy'),1)],nextCursor:null,hasMoreHistory:false};
 assert.equal(state.mergeHistory(page,'older',epoch),true);
 assert.deepEqual(model.threadTimeline(state.messages,state.activities,null).map(row=>row.text),['old','recent']);
 assert.equal(state.cursor(),100);assert.equal(state.thread.hasMoreHistory,false);
 assert.equal(state.mergeHistory(page,'older',epoch),false);
});
test('a history response waits for live catch-up and is discarded after a replacement snapshot',()=>{
 const state=new model.ThreadState();state.apply(snapshot());const epoch=state.historyVersion();
 const page={snapshotSequence:105,items:[visible(item('old',1),0)],nextCursor:'even-older',hasMoreHistory:true};
 assert.equal(state.mergeHistory(page,'older',epoch),false);assert.equal(state.messages.length,1);
 state.apply({kind:'event',sequence:105,event:{type:'thread.visited',threadId:'t',payload:{}}});
 assert.equal(state.mergeHistory(page,'older',epoch),true);assert.equal(state.thread.historyCursor,'even-older');
 state.apply(snapshot(106));assert.equal(state.mergeHistory(page,'older',epoch),false);
 assert.deepEqual(state.messages.map(row=>row.text),['recent']);
});

test('a recent window retains an older pending question without inserting it among new messages',()=>{
 const state=new model.ThreadState();const value=snapshot();
 const question={...item('request',1),type:'user_input_request',status:'pending',requestId:'q',
  questions:[{id:'one',header:'Device',question:'Ready?',options:[]}]};
 value.projection.turnItems=[question];state.apply(value);
 assert.equal(model.pendingRequests(state.activities).length,1);
 assert.deepEqual(model.threadTimeline(state.messages,state.activities,null).map(row=>row.text),['recent']);
 assert.equal(state.mergeHistory({snapshotSequence:100,items:[visible(question,0)],nextCursor:null,hasMoreHistory:false},'older',state.historyVersion()),true);
 assert.equal(state.activities.filter(row=>row.id==='request').length,1);
 assert.equal(model.threadTimeline(state.messages,state.activities,null)[0].kind,'question');
});

const pageSource=readFileSync(new URL('../app/entry/src/main/ets/pages/Thread.ets',import.meta.url),'utf8');
const historyStart=pageSource.indexOf('  private async pullOlderHistory(');
const historyMethods=historyStart<0?'':pageSource.slice(historyStart,pageSource.indexOf('  private refreshTranscript(',historyStart)).replaceAll('private ','');
const {HistoryPage}=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(`
const EnvironmentSession={current:null};
export class HistoryPage {
 active=true;loaded=true;historyLoading=false;hasMoreHistory=true;refreshingHistory=true;historyError='';
 params={environmentId:'env',threadId:'t'};rpc={};entries=[{id:'recent'}];firstVisibleIndex=1;
 pendingHistory=null;pendingHistoryCursor='';pendingHistoryEpoch=0;historyAnchor='';showingHistory=false;refreshes=0;
 follow={following:true,pause(){this.following=false}};
 constructor(state,environment){this.state=state;EnvironmentSession.current=environment;}
 refreshTranscript(){this.refreshes++;}
 ${historyMethods}
}
`)).toString('base64'));
const historyPage=()=>({snapshotSequence:100,items:[visible(item('old',1),0)],nextCursor:null,hasMoreHistory:false});
function pageWith(loadSnapshot){
 const state=new model.ThreadState();state.apply(snapshot());
 return new HistoryPage(state,{descriptor:{environmentId:'env'},loadSnapshot});
}

test('pulling a transcript shorter than its viewport loads history without any scroll event and preserves its reading anchor',async()=>{
 const requests=[];
 const page=pageWith(async path=>{requests.push(path);return historyPage();});
 await page.pullOlderHistory();
 assert.deepEqual(requests,['/api/orchestration/threads/t/history?cursor=older']);
 assert.deepEqual(model.threadTimeline(page.state.messages,page.state.activities,null).map(row=>row.text),['old','recent']);
 assert.equal(page.follow.following,false);assert.equal(page.showingHistory,true);
 assert.equal(page.historyAnchor,'recent');assert.equal(page.refreshes,1);assert.equal(page.refreshingHistory,false);
});

test('a pull during automatic history loading shares the in-flight page rather than fetching or merging twice',async()=>{
 let finish,calls=0;
 const page=pageWith(()=>{calls++;return new Promise(resolve=>finish=resolve);});
 const automatic=page.loadOlderHistory();await page.pullOlderHistory();
 assert.equal(calls,1);assert.equal(page.refreshingHistory,false);assert.equal(page.historyLoading,true);
 finish(historyPage());await automatic;
 assert.equal(page.refreshes,1);assert.equal(page.historyLoading,false);
 assert.deepEqual(model.threadTimeline(page.state.messages,page.state.activities,null).map(row=>row.text),['old','recent']);
});

test('history pulls end their indicator after failure, disconnection or exhaustion and retain current messages',async()=>{
 let calls=0;
 const page=pageWith(async()=>{calls++;return null;});
 await page.pullOlderHistory();assert.match(page.historyError,/重试/);assert.equal(page.refreshingHistory,false);
 assert.equal(page.state.cursor(),100);assert.deepEqual(page.state.messages.map(row=>row.text),['recent']);
 for(const field of ['loaded','hasMoreHistory']){
  const next=pageWith(async()=>{calls++;return historyPage();});next[field]=false;
  await next.pullOlderHistory();assert.equal(next.refreshingHistory,false);assert.equal(next.refreshes,0);
 }
 assert.equal(calls,1);
});
