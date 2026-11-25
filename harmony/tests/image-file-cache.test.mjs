import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { stripTypeScriptTypes } from 'node:module';
const files=new Map();let downloads=0,revision=0,failWrites=false,response=null;
const fs={OpenMode:{CREATE:1,WRITE_ONLY:2,TRUNC:4},accessSync:p=>files.has(p),readTextSync:p=>files.get(p).data.toString(),mkdirSync:p=>files.set(p,{directory:true}),
 statSync:p=>{const file=files.get(p);if(!file)throw Error('missing');return {size:file.size??file.data?.length??0,mtime:file.time??0}},
 utimes:(p,time)=>{files.get(p).time=time/1000},open:async p=>{files.set(p,{data:Buffer.alloc(0),time:Date.now()/1000});return {fd:p}},
 write:async(p,bytes)=>{if(failWrites)throw Error('disk full');files.get(p).data=Buffer.concat([files.get(p).data,Buffer.from(bytes)]);return bytes.byteLength},
 close:async()=>{},rename:async(from,to)=>{files.set(to,files.get(from));files.delete(from)},unlink:async p=>{files.delete(p)},unlinkSync:p=>{files.delete(p)},
 listFile:async root=>[...files.keys()].filter(p=>p.startsWith(root+'/')&&!p.slice(root.length+1).includes('/')).map(p=>p.slice(root.length+1))};
const http={RequestMethod:{GET:'GET'},HttpDataType:{ARRAY_BUFFER:'bytes'},createHttp:()=>({destroy(){},async request(...args){downloads++;if(response)return response(...args);return {responseCode:200,result:new Uint8Array([1,2,3]).buffer}}})};
const cryptoFramework={createMd:()=>{const hash=createHash('sha256');return {update:async({data})=>hash.update(data),digest:async()=>({data:hash.digest()})}}};
const util={TextEncoder:class {encodeInto(text){return new TextEncoder().encode(text)}}};
globalThis.__imageFileCacheDeps={fs,http,cryptoFramework,util};
async function runtime(){const source=readFileSync(new URL('../app/entry/src/main/ets/connection/ImageFileCache.ets',import.meta.url),'utf8').replace(/^import .*;\n/gm,'');return import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes('const {fs,http,cryptoFramework,util}=globalThis.__imageFileCacheDeps;\n'+source)+`\n// ${++revision}`).toString('base64'))}
const drain=async()=>{for(let n=0;n<20;n++)await Promise.resolve()};
test('downloaded bytes survive a restart and load offline without a signed URL or environment connection',async()=>{
 const {ImageFileCache}=await runtime();const source=await ImageFileCache.source('/offline','env','photo',async()=> 'http://fixture/signed');
 assert.match(source,/^file:\/\/\/offline\/image-cache\/[a-f0-9]{64}\.img$/);
 const fresh=await runtime();const before=downloads;
 assert.equal(await fresh.ImageFileCache.source('/offline','env','photo',async()=>{throw Error('offline')}),source);
 assert.equal(downloads,before);assert.equal(await fresh.ImageFileCache.cached('/offline','other','photo'),'');
});
test('inline image and full-screen viewer share a single transfer and failures are retryable',async()=>{
 const {ImageFileCache}=await runtime();let finish;const before=downloads;
 response=()=>new Promise(resolve=>finish=resolve);
 const one=ImageFileCache.source('/concurrent','env','photo',async()=> 'http://fixture/signed');
 const two=ImageFileCache.source('/concurrent','env','photo',async()=> 'http://fixture/signed');await drain();
 finish({responseCode:200,result:new Uint8Array([4]).buffer});
 const sources=await Promise.all([one,two]);assert.equal(downloads,before+1);assert.equal(sources[0],sources[1]);
 response=async()=>({responseCode:401,result:new ArrayBuffer(0)});
 await assert.rejects(ImageFileCache.source('/retry','env','photo',async()=> 'http://fixture/expired'),/下载失败/);
 assert.equal(await ImageFileCache.cached('/retry','env','photo'),'');response=null;
 assert.match(await ImageFileCache.source('/retry','env','photo',async()=> 'http://fixture/fresh'),/^file:/);
});
test('disk failure cleans up temporary bytes while keeping the online image usable',async()=>{
 const {ImageFileCache}=await runtime();failWrites=true;
 try{assert.equal(await ImageFileCache.source('/full','env','photo',async()=> 'http://fixture/online'),'http://fixture/online')}
 finally{failWrites=false}
 assert.equal([...files.keys()].some(p=>p.startsWith('/full/')&&p.endsWith('.tmp')),false);
 assert.equal(await ImageFileCache.cached('/full','env','photo'),'');
});
test('quota eviction retains recently viewed bytes and never removes drafts or unrelated files',async()=>{
 const {ImageFileCache}=await runtime();const source=await ImageFileCache.source('/quota','env','viewed',async()=> 'http://fixture/viewed');
 const viewed=source.slice('file://'.length);files.get(viewed).size=40*1024*1024;files.get(viewed).time=1;
 const old='/quota/image-cache/'+ '0'.repeat(64)+'.img';files.set(old,{size:50*1024*1024,time:2});
 const draft='/quota/image-cache/draft.txt';files.set(draft,{size:100,time:0});
 await ImageFileCache.cached('/quota','env','viewed');
 await ImageFileCache.source('/quota','env','new',async()=> 'http://fixture/new');await drain();
 assert.ok(files.has(viewed));assert.equal(files.has(old),false);assert.ok(files.has(draft));
});

test('mutable files revalidate after a restart, reuse 304 bytes and get a new bitmap URI when the same path changes',async()=>{
 let tag='"1"',bytes=[1];const headers=[];response=async(_url,opts)=>{headers.push(opts.header);assert.equal(opts.usingCache,false);
   if(opts.header['If-None-Match']===tag)return {responseCode:304};return {responseCode:200,header:{etag:tag},result:Uint8Array.from(bytes).buffer};};
 const source=c=>c.source('/mutable','env','docs/plot.png',async()=>'/asset',false,true);
 try {let {ImageFileCache:c}=await runtime();const v1=await source(c);assert.equal(files.get(v1.slice(7)).data[0],1);c=(await runtime()).ImageFileCache;
   assert.equal(await c.cached('/mutable','env','docs/plot.png'),v1);assert.equal(await source(c),v1);assert.equal(headers.at(-1)['If-None-Match'],'"1"');
   tag='"2"';bytes=[2];const v2=await source(c);assert.notEqual(v1,v2);assert.equal(files.get(v2.slice(7)).data[0],2);
   assert.equal(await (await runtime()).ImageFileCache.cached('/mutable','env','docs/plot.png'),v2);
   assert.equal(await c.cached('/mutable','other','docs/plot.png'),'');
 } finally {response=null;}
});

test('revalidation recovers when an already validated copy is evicted before its 304 arrives',async()=>{
 const {ImageFileCache:c}=await runtime();let round=0,old='';const options=[];
 response=async(_url,opts)=>{round++;options.push({...opts.header});if(round===2){files.delete(old);return {responseCode:304};}
   return {responseCode:200,header:{'Last-Modified':'Mon, 23 Nov 2026 00:00:00 GMT'},result:Uint8Array.of(round).buffer};};
 try{const get=()=>c.source('/evicted','env','figure',async()=>'/asset',false,true);old=(await get()).slice(7);const renewed=(await get()).slice(7);
  assert.equal(round,3);assert.ok(options[1]['If-Modified-Since']);assert.deepEqual(options[2],{});assert.equal(files.get(renewed).data[0],3);
 }finally{response=null;}
});
