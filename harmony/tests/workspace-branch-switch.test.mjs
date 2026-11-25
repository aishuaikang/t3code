import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const source = readFileSync(new URL('../app/entry/src/main/ets/pages/Thread.ets', import.meta.url), 'utf8');
const method = source.slice(source.indexOf('  private async chooseBranch('), source.indexOf('  private async updateComposerSetting(')).replaceAll('private ', '');
const { Page, EnvironmentSession } = await import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(`
const util={generateRandomUUID:()=> 'metadata-id'}, WS={threadStartTurn:'dispatch'};
export const EnvironmentSession={current:null};
export class Page {
 active=true;loaded=true;settingsBusy=false;running=false;sending=false;hasPendingSend=false;
 params={environmentId:'env',threadId:'t'};cwd='/repo';checkoutBranch='main';settingsError='';operationError='';rpc=null;
 state={thread:{id:'t',branch:'main',worktreePath:null}};restarts=0;connection={start:()=>this.restarts++};
 syncComposerMetadata(){this.composerThread={...this.state.thread}};scheduleTranscriptRefresh(){};
 ${method}
}
`)).toString('base64'));
function setup() {
 const page = new Page(), calls = [];
 const rpc = {call:async(tag,input)=>{calls.push({tag,...input});return {refName:'feature/ui'}}};
 page.rpc=rpc;
 EnvironmentSession.current={descriptor:{environmentId:'env'},rpc:{call(){throw Error('do not use the shell connection')}}};
 return {page,rpc,calls};
}
const ref={name:'origin/feature/ui',isRemote:true,current:false,worktreePath:null};
test('checkout uses the chat connection and persists the local branch returned by the server without reconnecting',async()=>{
 const {page,calls}=setup();await page.chooseBranch(ref);
 assert.equal(page.settingsError,'');assert.equal(calls[0].tag,'vcs.switchRef');
 assert.equal(calls[1].branch,'feature/ui');assert.equal(page.state.thread.branch,'feature/ui');
 assert.equal(page.composerThread.branch,'feature/ui');assert.equal(page.restarts,0);assert.equal(page.loaded,true);
});
test('failed checkout leaves the current thread usable and never changes its metadata',async()=>{
 const {page,rpc,calls}=setup();rpc.call=async()=>{throw Error('local changes would be overwritten')};
 await page.chooseBranch(ref);
 assert.match(page.operationError,/local changes/);assert.equal(page.settingsError,'');assert.equal(page.state.thread.branch,'main');
 assert.equal(calls.length,0);assert.equal(page.restarts,0);assert.equal(page.loaded,true);assert.equal(page.settingsBusy,false);
});
test('a late checkout receipt cannot update a different connection or hidden page',async()=>{
 for(const change of [page=>{page.active=false},page=>{page.rpc={}},()=>{EnvironmentSession.current={descriptor:{environmentId:'other'}}}]){
  const {page,rpc,calls}=setup();let resolve;
  rpc.call=(tag,input)=>{calls.push({tag,...input});return new Promise(yes=>{resolve=yes})};
  const pending=page.chooseBranch(ref);change(page);resolve({refName:'feature/ui'});await pending;
  assert.equal(calls.length,1);assert.equal(page.state.thread.branch,'main');assert.equal(page.restarts,0);
 }
});
test('choosing an existing worktree changes the thread context without checking it out in the old directory',async()=>{
 const {page,calls}=setup();await page.chooseBranch({name:'feature/worktree',current:false,worktreePath:'/worktree'});
 assert.equal(calls.length,1);assert.equal(calls[0].type,'thread.metadata.update');
 assert.equal(calls[0].worktreePath,'/worktree');assert.equal(page.state.thread.worktreePath,'/worktree');
});

test('a late metadata receipt cannot roll a newer PC branch event back',async()=>{
 const {page,rpc}=setup();let resolve;
 rpc.call=async(tag)=>tag==='vcs.switchRef'?{refName:'feature/ui'}:new Promise(yes=>{resolve=yes});
 const pending=page.chooseBranch(ref);await Promise.resolve();await Promise.resolve();
 page.state.thread.branch='newer-from-pc';page.checkoutBranch='newer-from-pc';resolve({});await pending;
 assert.equal(page.state.thread.branch,'newer-from-pc');assert.equal(page.checkoutBranch,'newer-from-pc');
});

test('a rejected metadata update after checkout reports the new working branch and preserves the thread branch',async()=>{
 const {page,rpc}=setup();rpc.call=async tag=>{if(tag==='vcs.switchRef')return {refName:'feature/ui'};throw Error('metadata refused')};
 await page.chooseBranch(ref);
 assert.equal(page.checkoutBranch,'feature/ui');assert.equal(page.state.thread.branch,'main');
 assert.match(page.operationError,/已切换到 feature\/ui/);assert.match(page.operationError,/会话/);assert.equal(page.settingsError,'');
});
test('a rejected worktree selection never claims the current directory was checked out',async()=>{
 const {page,rpc}=setup();rpc.call=async()=>{throw Error('refused')};
 await page.chooseBranch({name:'feature/worktree',worktreePath:'/other'});
 assert.equal(page.checkoutBranch,'main');assert.equal(page.state.thread.worktreePath,null);
 assert.match(page.operationError,/会话/);assert.doesNotMatch(page.operationError,/已切换到/);
});
