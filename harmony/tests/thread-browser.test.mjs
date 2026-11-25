import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';

const read=path=>readFileSync(new URL(path,import.meta.url),'utf8');
const load=source=>import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
const {BrowserSessions}=await load(read('../app/entry/src/main/ets/model/BrowserSessions.ets'));
globalThis.__threadBrowserSessions=BrowserSessions;
const source=read('../app/entry/src/main/ets/pages/Thread.ets');
const method=source.slice(source.indexOf('  private async subscribeBrowser('),source.indexOf('  private resumeImageRequest(')).replaceAll('private ','');
const {Page}=await load(`
const BrowserSessions=globalThis.__threadBrowserSessions;
class EmptyPayload{}
export class Page {
 active=true;params={threadId:'thread'};rpc=null;browserTabs=[];
 ${method}
}
`);
const tab=(tabId,threadId='thread',runtime='server')=>({tabId,threadId,runtime,navStatus:{_tag:'Success'},updatedAt:'1'});
const peer=()=>({
 callStream(method,payload,receive){this.receive=(...values)=>receive(values);return new Promise(()=>{});},
 call(method,payload){assert.equal(method,'preview.list');assert.deepEqual(payload,{threadId:'thread'});return new Promise(resolve=>this.finish=resolve);}
});

test('reconnecting discards an old browser entry until the current session confirms its tabs',async()=>{
 const page=new Page(),rpc=peer();page.rpc=rpc;page.browserTabs=[tab('stale')];
 const subscribed=page.subscribeBrowser(rpc);
 assert.deepEqual(page.browserTabs,[]);
 rpc.finish({sessions:[tab('desktop','thread','desktop'),tab('other','elsewhere')],serverEpoch:'a',revision:1});
 await subscribed;assert.deepEqual(page.browserTabs,[]);
 rpc.receive({type:'opened',threadId:'thread',tabId:'new',snapshot:tab('new'),serverEpoch:'a',revision:2});
 assert.deepEqual(page.browserTabs.map(t=>t.tabId),['new']);
 rpc.receive({type:'closed',threadId:'thread',tabId:'new',serverEpoch:'a',revision:3});
 assert.deepEqual(page.browserTabs,[]);
});

test('late browser lists and events from an old connection cannot restore its entry',async()=>{
 const page=new Page(),old=peer(),current=peer();page.rpc=old;
 const oldSubscription=page.subscribeBrowser(old);page.rpc=current;
 const currentSubscription=page.subscribeBrowser(current);
 current.finish({sessions:[],serverEpoch:'b',revision:1});await currentSubscription;
 old.finish({sessions:[tab('stale')],serverEpoch:'a',revision:1});await oldSubscription;
 old.receive({type:'opened',threadId:'thread',tabId:'stale',snapshot:tab('stale'),serverEpoch:'a',revision:2});
 assert.deepEqual(page.browserTabs,[]);
});
