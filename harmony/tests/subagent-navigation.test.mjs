import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
const read = file => readFileSync(new URL(`../app/entry/src/main/ets/${file}.ets`, import.meta.url), 'utf8');
const load = text => import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(text)).toString('base64'));
const models = await load(read('model/Models')); const source = read('pages/Thread');
const methods = (a,b) => source.slice(source.indexOf(a), source.indexOf(b,source.indexOf(a))).replaceAll('private ','');
globalThis.__agentNavigation = {models, pushed:[], back:0, routes:[], known:[]};
const {Page} = await load(`const io=globalThis.__agentNavigation, {subagentTitle}=io.models;
const router={pushUrl:async route=>{io.pushed.push(route)},back:()=>{io.back++}};
const loadEnvironments=async()=>io.known; const openThreadReference=async ref=>{io.routes.push(ref)};
export class Page {
 active=true;readVisible=true;foreground=true;selectingMessages=false;agentsOpen=true;params={environmentId:'home',threadId:'parent'};
 state={thread:{worktreePath:'/work'}};projectTitle='Project';composerThread={title:'Parent'};elapsedTimer=-1;running=true;
 ticks=0;activeWorkLabel(){return String(++this.ticks)}
 ${methods('  private openSubagent(', '  private async rewindMessage(')}
 ${methods('  private stopElapsedTimer(', '  private activeWorkLabel(')}
}`);
test('an agent sheet row opens its child and the parent control returns through the same stack',()=>{
 const io=globalThis.__agentNavigation,p=new Page();io.pushed=[];io.back=0;
 p.openSubagent({id:'a',title:'A',threadId:'parent',childThreadId:'child',origin:'provider_native'});
 assert.equal(p.agentsOpen,false);const route=io.pushed[0];assert.equal(route.url,'pages/Thread');
 assert.equal(route.params.threadId,'child');assert.equal(route.params.nativeSubagent,'true');assert.equal(route.params.parentTitle,'Parent');
 Object.assign(p,route.params);p.params=route.params;p.openParentThread();assert.equal(io.back,1);assert.equal(io.pushed.length,1);
});
test('unlinked agents cannot navigate and a linked remote child never opens against the current server',async()=>{
 const io=globalThis.__agentNavigation,p=new Page();io.pushed=[];io.routes=[];io.known=[];
 p.openSubagent({id:'none'});assert.deepEqual(io.pushed,[]);
 const a={id:'x',title:'Remote agent',threadId:'parent',remoteChild:{environmentId:'other',threadId:'remote-child'}};
 p.openSubagent(a);await new Promise(setImmediate);assert.equal(io.routes.length,0);assert.match(p.operationError,/先添加/);
 io.known=[{environmentId:'other'}];p.openSubagent(a);await new Promise(setImmediate);
 assert.equal(io.routes[0].environmentId,'other');assert.equal(io.routes[0].threadId,'remote-child');assert.deepEqual(io.pushed,[]);
});
test('background stream updates cannot restart the visible work clock until returning',t=>{
 t.mock.timers.enable({apis:['setInterval']});const p=new Page();p.updateElapsed();t.mock.timers.tick(1000);assert.equal(p.ticks,2);
 p.readVisible=false;p.stopElapsedTimer();p.updateElapsed();const ticks=p.ticks;t.mock.timers.tick(2000);assert.equal(p.ticks,ticks);
 p.readVisible=true;p.foreground=false;p.updateElapsed();assert.equal(p.elapsedTimer,-1);p.foreground=true;p.updateElapsed();const shown=p.ticks;
 t.mock.timers.tick(1000);assert.equal(p.ticks,shown+1);p.stopElapsedTimer();
});
