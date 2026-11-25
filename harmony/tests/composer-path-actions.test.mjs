import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const source=readFileSync(process.env.T3_THREAD_SOURCE??new URL('../app/entry/src/main/ets/pages/Thread.ets',import.meta.url),'utf8');
const model=readFileSync(new URL('../app/entry/src/main/ets/model/ComposerPath.ets',import.meta.url),'utf8');
const commands=readFileSync(new URL('../app/entry/src/main/ets/model/ComposerCommands.ets',import.meta.url),'utf8');
const start=source.indexOf('  private cancelPaths('),end=source.indexOf('  private async loadDraft(');
assert.ok(start>=0 && end>start,'Thread must implement cursor-aware remote path completion');
const body=`${model}\n${commands}
let timers=new Map(),timerId=0;
function setTimeout(callback){timers.set(++timerId,callback);return timerId;}
function clearTimeout(id){timers.delete(id);}
export function flush(){const pending=[...timers.values()];timers.clear();for(const callback of pending)callback();}
class Fixture {
 active=true;loaded=true;draftReady=true;hasPendingSend=false;sending=false;cwd='/own';draft='@old';pathRevision=0;pathTimer=-1;pathEntries=[];pathStatus='';pathStart=4;pathEnd=4;pathTrigger=null;
 rpc=null;state={thread:null};params={threadId:'self'};composerController={caretPosition(){}};
 editDraft(text){this.draft=text;}
 ${source.slice(start,end).replaceAll('private ','')}
}
export default Fixture;
`;
const {default:Fixture,flush}=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(body)).toString('base64'));
const tick=()=>new Promise(resolve=>queueMicrotask(resolve));
function setup(){const requests=[];const page=new Fixture();page.rpc={call:(tag,payload)=>new Promise((resolve,reject)=>requests.push({tag,payload,resolve,reject}))};return {page,requests};}
test('new query wins when older server response arrives last',async()=>{
 const {page,requests}=setup();page.updatePathSearch(4,4);flush();
 page.draft='@new';page.updatePathSearch(4,4);flush();
 assert.equal(requests.length,2);assert.equal(requests[1].payload.query,'new');
 requests[1].resolve({entries:[{path:'new.txt',kind:'file'}],truncated:false});await tick();
 requests[0].resolve({entries:[{path:'old.txt',kind:'file'}],truncated:false});await tick();
 assert.deepEqual(page.pathEntries,[{path:'new.txt',kind:'file'}]);
});
test('leaving the page clears suggestions and invalidates in-flight results',async()=>{
 const {page,requests}=setup();page.updatePathSearch(4,4);flush();page.cancelPaths();
 requests[0].resolve({entries:[{path:'old.txt',kind:'file'}],truncated:false});await tick();
 assert.deepEqual(page.pathEntries,[]);assert.equal(page.pathStatus,'');
});
test('invalid and selected queries never reach the server',()=>{
 const {page,requests}=setup();
 for(const text of ['email@host','@'+'a'.repeat(257)]){page.draft=text;page.updatePathSearch(text.length,text.length);flush();}
 page.draft='@file';page.updatePathSearch(0,5);flush();assert.equal(requests.length,0);
});
test('bare mention lists the active worktree and Chinese queries preserve Unicode and cap visible results',async()=>{
 const {page,requests}=setup();page.state.thread={worktreePath:'/工作树'};page.draft='＠';page.updatePathSearch(1,1);flush();
 assert.deepEqual({tag:requests[0].tag,payload:requests[0].payload},{tag:'projects.listEntries',payload:{cwd:'/工作树'}});
 requests[0].resolve({entries:Array.from({length:25},(_,i)=>({path:'目录/'+i,kind:'file'}))});await tick();assert.equal(page.pathEntries.length,20);
 page.draft='@文档';page.updatePathSearch(3,3);flush();
 assert.deepEqual(requests[1].payload,{cwd:'/工作树',query:'文档',limit:20});
 requests[1].resolve({entries:[{path:'文档/说明.md',kind:'file'}]});await tick();assert.equal(page.pathEntries[0].path,'文档/说明.md');
});
test('selection cannot replace a newer draft with a stale suggestion',()=>{
 const {page}=setup();page.updatePathSearch(4,4);page.pathEntries=[{path:'old.txt',kind:'file'}];page.draft='keep this';page.selectPath({path:'old.txt',kind:'file'});assert.equal(page.draft,'keep this');
});
test('selection inserts the actual path and keeps the suffix',()=>{
 const {page}=setup();page.draft='Read @src then explain';page.updatePathSearch(9,9);
 page.pathEntries=[{path:'src/a b.txt',kind:'file'}];page.selectPath(page.pathEntries[0]);assert.equal(page.draft,'Read [a b.txt](src/a%20b.txt)  then explain');assert.deepEqual(page.pathEntries,[]);
});

test('duplicate caret notifications preserve results and do not restart the same query',async()=>{
 const {page,requests}=setup();page.updatePathSearch(4,4);flush();
 requests[0].resolve({entries:[{path:'old.txt',kind:'file'}]});await tick();
 page.updatePathSearch(4,4);flush();
 assert.equal(requests.length,1);assert.equal(page.pathEntries[0].path,'old.txt');
});

test('disconnecting before a debounced search stops the loading indicator',()=>{
 const {page,requests}=setup();page.updatePathSearch(4,4);assert.equal(page.pathLoading,true);
 page.rpc=null;flush();assert.equal(requests.length,0);assert.equal(page.pathLoading,false);assert.match(page.pathStatus,/连接已断开/);
});

test('cached thread mentions remain available without a connection and insert a real thread link',()=>{
 const {page}=setup();page.loaded=false;page.rpc=null;
 page.cache={shell:()=>({threads:[{id:'other',title:'旧任务',updatedAt:'2026-11-15'}]})};
 page.draft='@旧';page.updatePathSearch(2,2);flush();
 assert.equal(page.pathEntries[0].label,'旧任务');assert.equal(page.pathLoading,false);
 page.selectPath(page.pathEntries[0]);assert.equal(page.draft,'[旧任务](t3-thread://v1/other) ');
});

test('a connection change during file lookup stops loading and preserves cached thread candidates',async()=>{
 const {page,requests}=setup();page.updatePathSearch(4,4);flush();
 page.pathEntries=[{path:'cached-thread',kind:'thread',label:'旧任务'}];page.rpc=null;
 requests[0].resolve({entries:[{path:'old.txt',kind:'file'}]});await tick();
 assert.equal(page.pathLoading,false);assert.equal(page.pathEntries[0].kind,'thread');
});

const newSource=readFileSync(new URL('../app/entry/src/main/ets/pages/NewTask.ets',import.meta.url),'utf8');
const newSearch=newSource.slice(newSource.indexOf('  private async searchPaths('),newSource.indexOf('  private selectPath(')).replaceAll('private ','');
const {NewFixture,environment}=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(`
${model}
export const environment={current:null};const EnvironmentSession=environment;
export class NewFixture {
 active=true;pathRevision=1;pathLoading=true;pathStatus='';worktreePath=null;
 pathEntries=[{path:'cached-thread',kind:'thread',label:'旧任务'}];
 ${newSearch}
}
`)).toString('base64'));
test('a disconnected new-task search does not leave a permanent loading indicator',async()=>{
 const page=new NewFixture();let calls=0;const connection={rpc:{call:async()=>{calls++;return {entries:[]}}}};
 environment.current=null;
 await page.searchPaths({query:'file'},1,{workspaceRoot:'/work'},connection);
 assert.equal(calls,0);assert.equal(page.pathLoading,false);assert.equal(page.pathEntries[0].kind,'thread');
});
test('new-task lookup discards a response from the previous connection and stops loading',async()=>{
 const page=new NewFixture();let resolve;const connection={rpc:{call:()=>new Promise(done=>{resolve=done})}};
 environment.current=connection;
 const search=page.searchPaths({query:'file'},1,{workspaceRoot:'/work'},connection);
 environment.current=null;resolve({entries:[{path:'stale.txt',kind:'file'}]});await search;
 assert.equal(page.pathLoading,false);assert.equal(page.pathEntries[0].kind,'thread');
});
