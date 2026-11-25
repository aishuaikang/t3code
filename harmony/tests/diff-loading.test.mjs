import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';

const moduleSource=path=>readFileSync(new URL(path,import.meta.url),'utf8');
const importSource=source=>import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
const rows=await importSource(moduleSource('../app/entry/src/main/ets/model/DiffRows.ets'));
const scope=await importSource(moduleSource('../app/entry/src/main/ets/model/DiffScope.ets'));
globalThis.__diffRows=rows;globalThis.__diffScope=scope;
const page=moduleSource('../app/entry/src/main/ets/pages/Diff.ets');
const method=page.slice(page.indexOf('  private async load():'),page.indexOf('  private async addComment():')).replace('private async load','async load');
const {Page}=await importSource(`
const {parseDiffRows}=globalThis.__diffRows;
const {diffScopes,projectionCheckpoints,checkpointRequest}=globalThis.__diffScope;
const router={getParams:()=>globalThis.__params};
const EnvironmentSession={get current(){return globalThis.__environment}};
export class Page {
 active=true;loading=false;rpc=null;initialScope=true;selectedId='all';ignoreWhitespace=false;
 rows=[];files=[];scopes=[];errorText='';notice='';ready=false;collapsedFiles=[];viewedFiles=[];
 rebuildRows(){};refreshRows(){};
 ${method}
}`);
const fixture='diff --git a/AGENTS.md b/AGENTS.md\n@@ -1 +1 @@\n-old\n+new\n';
function setup(){
 const calls=[];
 const rpc={close(){},async call(method,payload){
  calls.push({method,payload});
  if(method==='orchestration.getThreadProjection')return {checkpoints:[{appRunOrdinal:7,status:'ready',scopeId:'root',runId:'r7'}]};
  return {diff:fixture};
 }};
 globalThis.__params={threadId:'t',runId:'r7',toTurnCount:'7'};
 globalThis.__environment={openRpc:async()=>rpc};
 return {page:new Page(),calls};
}
test('opens the requested checkpoint using native list rows even when no Swift library is available',async()=>{
 const {page,calls}=setup();
 await page.load();
 assert.equal(page.errorText,'');assert.equal(page.ready,true);assert.equal(page.loading,false);
 assert.equal(page.selectedId,'turn:7');assert.equal(page.rows[0].filePath,'AGENTS.md');
 assert.deepEqual(calls[1],{method:'orchestration.getTurnDiff',payload:{threadId:'t',fromTurnCount:6,toTurnCount:7,ignoreWhitespace:false}});
});
test('ignoring whitespace reaches the actual checkpoint request',async()=>{
 const {page,calls}=setup();page.ignoreWhitespace=true;await page.load();
 assert.equal(calls[1].payload.ignoreWhitespace,true);
});
test('an unavailable requested checkpoint stays an explicit error across refreshes',async()=>{
 const {page,calls}=setup();globalThis.__params.toTurnCount='8';
 await page.load();assert.match(page.errorText,/快照|范围|就绪/);assert.equal(page.ready,false);
 await page.load();assert.match(page.errorText,/快照|范围|就绪/);assert.equal(page.ready,false);
 assert.equal(calls.filter(c=>c.method!=='orchestration.getThreadProjection').length,0);
});

test('a new task with no checkpoint opens its working-tree diff',async()=>{
 const {page,calls}=setup();globalThis.__params={threadId:'t',cwd:'/repo',toTurnCount:'0'};
 globalThis.__environment={openRpc:async()=>({close(){},async call(method,payload){
  calls.push({method,payload});
  return method==='orchestration.getThreadProjection' ? {checkpoints:[]} : {sources:[{kind:'working-tree',diff:fixture}]};
 }})};
 await page.load();assert.equal(page.errorText,'');assert.equal(page.ready,true);assert.equal(page.selectedId,'workspace');
 assert.deepEqual(calls[1],{method:'review.getDiffPreview',payload:{cwd:'/repo',ignoreWhitespace:false}});
});

test('workspace panel opens the branch comparison rather than the latest turn or working-tree diff',async()=>{
 const {page,calls}=setup();globalThis.__params={threadId:'t',cwd:'/repo',scope:'branch',toTurnCount:'7'};
 globalThis.__environment={openRpc:async()=>({close(){},async call(method,payload){
  calls.push({method,payload});
  return method==='orchestration.getThreadProjection' ? {checkpoints:[]} :
   {sources:[{kind:'working-tree',diff:''},{kind:'branch-range',diff:fixture}]};
 }})};
 await page.load();assert.equal(page.errorText,'');assert.equal(page.ready,true);assert.equal(page.selectedId,'branch');
 assert.deepEqual(calls[1],{method:'review.getDiffPreview',payload:{cwd:'/repo',ignoreWhitespace:false,sourceKind:'branch-range'}});
});

test('initial native list load waits for a rendered frame before scrolling bound native controllers',async()=>{
 const frame=page.slice(page.indexOf('class DiffScrollFrame'),page.indexOf('@Entry'));
 const methods=page.slice(page.indexOf('  private scrollTo('),page.indexOf('  private viewChanged')).replaceAll('private ','');
 const {View}=await importSource(`
  class FrameCallback{};const ScrollAlign={START:0};
  ${frame}
  const diffDisplayRows=rows=>rows;const diffAnchorIndex=()=>0;
  export class View {
   active=true;ready=false;commentRow=null;scrollRevision=0;visibleIndex=0;viewportWidth=360;wrap=true;rows=[];collapsedFiles=[];split=false;
   frames=[];scrolls=0;
   dataSource={getData:()=>undefined,update:()=>{}};
   horizontalScroller={scrollTo:()=>{if(!this.ready)throw Error('unbound');this.scrolls++}};
   scroller={scrollToIndex:()=>{if(!this.ready)throw Error('unbound');this.scrolls++}};
   getUIContext(){return {postFrameCallback:frame=>this.frames.push(frame)}}
   ${methods}
  }
 `);
 const view=new View();view.rebuildRows(true);assert.equal(view.scrolls,0);
 view.ready=true;view.frames.forEach(frame=>frame.onFrame());assert.equal(view.scrolls,2);
});
