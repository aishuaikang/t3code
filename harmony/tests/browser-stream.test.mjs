import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import vm from 'node:vm';
const root=new URL('../app/',import.meta.url),read=path=>readFileSync(new URL(path,root),'utf8');
const { createPreviewStreamClient, sockets }=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(`
export const sockets=[];
class WebSocket {
 static OPEN=1;readyState=1;handlers={};messages=[];
 constructor(url){this.url=url;sockets.push(this);}
 addEventListener(type,fn){this.handlers[type]=fn;}
 send(value){this.messages.push(JSON.parse(value));}
 close(){}
}
${read('preview-stream/hubAccess.ts')}
${read('preview-stream/serverBrowserStream.ts').replace(/^import .*;$/gm,'')}
`)).toString('base64'));
const target={access:{httpBase:'http://host/api/preview-stream',wsBase:'ws://host/api/preview-stream',query:{wsTicket:'media'},credentials:false},threadId:'thread',tabId:'tab',maxWidth:400,maxHeight:800,interactive:false};
test('the adapted Android transport authenticates the stream, acknowledges frames and enforces control ownership',()=>{
 const frames=[],client=createPreviewStreamClient(target,{onFrame:frame=>frames.push(frame),onConnectedChange(){},onUnauthorized(){}}),socket=sockets.at(-1);
 const query=new URL(socket.url).searchParams;assert.equal(query.get('interactive'),'false');assert.equal(query.get('wsTicket'),'media');
 assert.equal(client.send({type:'navigate',url:'https://example.com'}),false);
 socket.handlers.message({data:JSON.stringify({type:'control',canOperate:true,controller:'agent',generation:1,dialog:null})});
 assert.equal(client.send({type:'navigate',url:'https://example.com'}),false);assert.equal(client.send({type:'takeControl'}),true);
 socket.handlers.message({data:JSON.stringify({type:'control',canOperate:true,controller:'you',generation:2,dialog:null})});
 assert.equal(client.send({type:'navigate',url:'https://example.com'}),true);
 const frame=new ArrayBuffer(3);socket.handlers.message({data:frame});assert.equal(frames[0],frame);assert.deepEqual(socket.messages.at(-1),{type:'ack'});
 client.stop();
});
test('the packaged browser document exposes the stream entry points and waits for native authenticated configuration',()=>{
 const html=read('entry/src/main/resources/rawfile/preview-stream.html'),messages=[];
 const context={window:{addEventListener(){}},HarmonyBrowser:{postMessage:value=>messages.push(value)}};
 vm.runInNewContext(html.match(/<script>([\s\S]*?)<\/script>/)[1],context);
 assert.equal(typeof context.window.T3PreviewStream.start,'function');assert.equal(typeof context.window.T3PreviewStream.stop,'function');
 assert.deepEqual(messages,[]);
});
