import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
const src=readFileSync(new URL('../app/entry/src/main/ets/pages/Browser.ets',import.meta.url),'utf8');
const methods=src.slice(src.indexOf('  private updateTabs('),src.indexOf('  @Builder\n  private icon(')).replaceAll('private ','');
const { Page, state }=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(`
export const state={scripts:[],access:0};
const setTimeout=(fn,ms)=>{const timer=globalThis.setTimeout(fn,ms);timer.unref();return timer;};
const EnvironmentSession={current:{descriptor:{environmentId:'env'},openPreviewAccess:async()=>{state.access++;return{httpBase:'http://host/api/preview-stream',query:{wsTicket:'media-'+state.access},credentials:false};}}};
export class Page {
 active=true;visible=true;webReady=true;threadId='thread';environmentId='env';tabId='one';interactive=false;pendingTakeControl=false;
 tabs=[{threadId:'thread',tabId:'one',navStatus:{url:'https://example.com'},runtime:'server',updatedAt:'1'},{threadId:'thread',tabId:'two',navStatus:{url:'https://two.example'},runtime:'server',updatedAt:'2'}];
 streamVersion=0;authRetry=-1;authFailures=0;connected=false;controller='';canOperate=false;dialog=null;dialogOpen=false;promptText='';
 web={runJavaScript:async script=>{state.scripts.push(script);}};
 color(){return '#fff';}
 ${methods}
}
`)).toString('base64'));
const drain=async()=>{await new Promise(resolve=>setImmediate(resolve));};
const config=()=>JSON.parse(state.scripts.findLast(s=>s.includes('T3PreviewStream.start(')).match(/T3PreviewStream.start\((\{.+\})\);/)[1]);
test('browser opens passively, takes control only on request, and rejects events from a previously selected tab',async()=>{
 state.scripts=[];const page=new Page();await page.startStream();assert.equal(config().interactive,false);
 assert.equal(state.scripts.some(s=>s.includes('"type":"takeControl"')),false);
 page.takeControl();await drain();assert.equal(config().interactive,true);
 page.receive(JSON.stringify({type:'control',viewerId:page.streamVersion,controller:'agent',canOperate:true}));
 assert.equal(state.scripts.filter(s=>s.includes('"type":"takeControl"')).length,1);
 const old=page.streamVersion;page.selectTab('two');await drain();assert.equal(config().tabId,'two');assert.equal(config().interactive,false);
 page.receive(JSON.stringify({type:'control',viewerId:old,controller:'you',canOperate:true}));assert.equal(page.controller,'');
 page.visible=false;const calls=state.scripts.length;await page.startStream();assert.equal(state.scripts.length,calls);
});
test('navigation stays read only until control is acquired and accepts server ports without accepting script URLs',()=>{
 const page=new Page();state.scripts=[];page.address='localhost:5173';page.navigate();assert.equal(state.scripts.length,0);
 page.controller='you';page.navigate();assert.ok(state.scripts.at(-1).includes('http://localhost:5173'));
 page.address='dev.example:3000/path';page.navigate();assert.ok(state.scripts.at(-1).includes('http://dev.example:3000/path'));
 const before=state.scripts.length;page.address='javascript:alert(1)';page.navigate();assert.equal(state.scripts.length,before);assert.match(page.error,/http/);
});
test('repeated control updates preserve a partially typed prompt and reconnect clears actionable stale controls',()=>{
 const page=new Page(),message={type:'control',viewerId:0,controller:'you',canOperate:true,dialog:{type:'prompt',message:'Name?',defaultValue:'old'}};
 page.receive(JSON.stringify(message));page.promptText='正在输入';page.receive(JSON.stringify(message));assert.equal(page.promptText,'正在输入');
 page.receive(JSON.stringify({type:'status',viewerId:0,status:'connecting'}));assert.equal(page.controller,'');assert.equal(page.canOperate,false);assert.equal(page.dialogOpen,false);
});
