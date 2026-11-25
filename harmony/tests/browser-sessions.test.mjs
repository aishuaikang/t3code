import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
const src=readFileSync(new URL('../app/entry/src/main/ets/model/BrowserSessions.ets',import.meta.url),'utf8');
const { BrowserSessions }=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(src)).toString('base64'));
const tab=(id,time='1',runtime='server')=>({threadId:'thread',tabId:id,runtime,updatedAt:time,navStatus:{_tag:'Success',url:'https://example.com',title:id},canGoBack:false,canGoForward:false});
const event=(revision,snapshot,type='opened',epoch='a')=>({type,threadId:'thread',tabId:snapshot.tabId,snapshot,revision,serverEpoch:epoch});
test('late list results retain newer navigation and closed tabs while recovering untouched tabs',()=>{
 const state=new BrowserSessions('thread');state.event(event(3,tab('new','3')));state.event(event(4,tab('closed'),'closed'));
 assert.equal(state.list({sessions:[tab('old'),tab('closed')],revision:2,serverEpoch:'a'}),true);
 assert.deepEqual(state.tabs().map(t=>t.tabId),['old','new']);
 state.event(event(5,tab('old','5'),'navigated'));assert.equal(state.list({sessions:[tab('old')],revision:2,serverEpoch:'a'}),false);
 assert.equal(state.tabs().find(t=>t.tabId==='old').updatedAt,'5');
});
test('the browser counter excludes desktop-only tabs and other conversations and safely accepts a server restart',()=>{
 const state=new BrowserSessions('thread');state.list({sessions:[tab('server'),tab('desktop','2','desktop'),{...tab('other'),threadId:'elsewhere'}],revision:9,serverEpoch:'a'});
 assert.deepEqual(state.tabs().map(t=>t.tabId),['server']);state.event(event(1,tab('restarted'),'opened','b'));
 assert.equal(state.list({sessions:[tab('stale')],revision:10,serverEpoch:'a'}),false);
 assert.deepEqual(state.tabs().map(t=>t.tabId),['restarted']);
});
