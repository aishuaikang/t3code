import {test} from 'node:test';import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';import {stripTypeScriptTypes} from 'node:module';
const attachmentFunctions=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(readFileSync(new URL('../app/entry/src/main/ets/model/FileAttachments.ets',import.meta.url),'utf8'))).toString('base64'));
globalThis.__fileAttachmentFunctions=attachmentFunctions;

const files=new Map([['gallery-uri',Buffer.from('owned image')]]),metadata=new Map();let next=0;
const fs={OpenMode:{READ_ONLY:0},accessSync:p=>files.has(p),mkdirSync:p=>files.set(p,null),open:async p=>({fd:p}),close:async()=>{},stat:async p=>({size:files.get(p).length}),copyFile:async(from,to)=>files.set(to,Buffer.from(files.get(from))),unlink:async p=>files.delete(p)};
const DraftStore={open:async(dir,env,thread)=>{const key=JSON.stringify([dir,env,thread]);return{load:async()=>metadata.get(key)??'',save:async text=>metadata.set(key,text)};}};
globalThis.__attachmentMocks={fs,DraftStore,prepareImage:async(fd,uri,name)=>{await fs.copyFile(fd,uri);return name;},util:{generateRandomUUID:()=>String(++next).padStart(36,'0')}};
const source=readFileSync(new URL('../app/entry/src/main/ets/connection/AttachmentDraftStore.ets',import.meta.url),'utf8').replace(/^import .*;$/gm,'');
let runtimeId=0;
const freshStore=async()=> (await import('data:text/javascript;base64,'+Buffer.from('const {fs,DraftStore,util,prepareImage}=globalThis.__attachmentMocks;const {attachmentMime,supportedImageFile,fileUploadLimit,MAX_FILE_BYTES}=globalThis.__fileAttachmentFunctions;\n'+stripTypeScriptTypes(source)+`\n// runtime ${++runtimeId}`).toString('base64'))).AttachmentDraftStore;
const AttachmentDraftStore=await freshStore();
test('copies selected bytes privately, reloads per task and removes only owned copies',async()=>{
 const store=await AttachmentDraftStore.open('/private','env','thread');const row=await store.add('gallery-uri');
 assert.notEqual(row.uri,'gallery-uri');assert.ok(files.has('gallery-uri'));
 const restored=await AttachmentDraftStore.open('/private','env','thread');assert.equal(restored.images.length,1);
 assert.equal((await AttachmentDraftStore.open('/private','other','thread')).images.length,0);
 await restored.remove(row.uri);assert.equal((await AttachmentDraftStore.open('/private','env','thread')).images.length,0);
 assert.ok(files.has('gallery-uri'));assert.equal(files.has(row.uri),false);
});
test('uploaded reference survives reopening and clearing leaves gallery untouched',async()=>{
 const store=await AttachmentDraftStore.open('/private','env','second');const row=await store.add('gallery-uri');
 await store.setUploaded(row.uri,{type:'image',id:'pending-id',name:'image.jpg',mimeType:'image/jpeg',sizeBytes:11});
 const restored=await (await freshStore()).open('/private','env','second');assert.equal(restored.images[0].uploaded.id,'pending-id');
 await restored.clear();assert.equal(restored.images.length,0);assert.ok(files.has('gallery-uri'));
});
test('refuses a persisted path outside owned image storage without deleting it',async()=>{
 metadata.set(JSON.stringify(['/private','env','images:bad']),JSON.stringify([{uri:'gallery-uri'}]));
 await assert.rejects(AttachmentDraftStore.open('/private','env','bad'),/路径无效/);
 assert.ok(files.has('gallery-uri'));
});
test('failed private copy leaves no orphan or draft reference',async()=>{
 const store=await AttachmentDraftStore.open('/private','env','copy-failure');
 const before=[...files.keys()];const copy=fs.copyFile;
 fs.copyFile=async(from,to)=>{files.set(to,Buffer.from('partial'));throw new Error('disk full');};
 try { await assert.rejects(store.add('gallery-uri'),/disk full/); } finally {fs.copyFile=copy;}
 assert.deepEqual([...files.keys()],before);assert.deepEqual(store.images,[]);
});
test('original image name survives private copying, upload metadata updates and reopening',async()=>{
 const store=await AttachmentDraftStore.open('/private','env','named');
 const row=await store.add('gallery-uri','验证图片 01.png');assert.equal(row.name,'验证图片 01.png');
 await store.setUploaded(row.uri,{type:'image',id:'named-upload',name:row.name,mimeType:'image/png',sizeBytes:11});
 const restored=await AttachmentDraftStore.open('/private','env','named');
 assert.equal(restored.images[0].name,'验证图片 01.png');assert.equal(restored.images[0].uploaded.name,'验证图片 01.png');
});
test('an oversized converted output is removed without publishing a draft',async()=>{
 const store=await AttachmentDraftStore.open('/private','env','converted-too-large');const before=[...files.keys()];const copy=fs.copyFile;
 fs.copyFile=async(from,to)=>files.set(to,Buffer.alloc(10*1024*1024+1));
 try{await assert.rejects(store.add('gallery-uri','photo.heic'),/转换后.*10 MB/);assert.deepEqual(store.images,[]);assert.deepEqual([...files.keys()],before);}
 finally{fs.copyFile=copy;}
});

test('eight-image limit survives reopening and removing one frees exactly one slot',async()=>{
 const store=await AttachmentDraftStore.open('/private','env','eight-boundary');
 for(let i=0;i<8;i++)await store.add('gallery-uri',`image-${i}.png`);
 const restored=await AttachmentDraftStore.open('/private','env','eight-boundary');
 assert.deepEqual(restored.images.map(image=>image.name),Array.from({length:8},(_,i)=>`image-${i}.png`));
 const before=[...files.keys()];
 await assert.rejects(restored.add('gallery-uri','ninth.png'),/最多 8 张/);
 assert.deepEqual([...files.keys()],before);
 const retained=restored.images.slice(1).map(image=>image.uri);
 await restored.remove(restored.images[0].uri);
 await restored.add('gallery-uri','replacement.png');
 const final=await AttachmentDraftStore.open('/private','env','eight-boundary');
 assert.equal(final.images.length,8);assert.deepEqual(final.images.slice(0,7).map(image=>image.uri),retained);
 assert.equal(final.images[7].name,'replacement.png');
 await final.clear();assert.ok(files.has('gallery-uri'));
});
test('concurrent upload completions and removal retain every other image without resurrecting the removed one',async()=>{
 const store=await AttachmentDraftStore.open('/private','env','concurrent');
 const a=await store.add('gallery-uri','a.png'),b=await store.add('gallery-uri','b.png');
 const uploaded=id=>({type:'image',id,name:id+'.png',mimeType:'image/png',sizeBytes:11});
 await Promise.all([store.setUploaded(a.uri,uploaded('a')),store.setUploaded(b.uri,uploaded('b')),store.remove(a.uri)]);
 const restored=await AttachmentDraftStore.open('/private','env','concurrent');
 assert.deepEqual(restored.images.map(i=>[i.name,i.uploaded.id]),[['b.png','b']]);
 await restored.setUploaded(a.uri,uploaded('late-a'));assert.equal(restored.images.length,1);
});

test('document drafts preserve bytes, type and name across reopening without image conversion',async()=>{
 const original=Buffer.from('%PDF-1.7\n文档正文\0');files.set('document-uri',original);
 const store=await AttachmentDraftStore.open('/private','env','document');
 const row=await store.addFile('document-uri','资料.pdf',1024);
 assert.match(row.uri,/\.file$/);assert.equal(row.type,'file');assert.equal(row.mimeType,'application/pdf');
 assert.deepEqual(files.get(row.uri),original);
 await store.setUploaded(row.uri,{type:'file',id:'pdf-upload',name:'资料.pdf',mimeType:'application/pdf',sizeBytes:original.length});
 const restored=await AttachmentDraftStore.open('/private','env','document');
 assert.equal(restored.images[0].uploaded.type,'file');assert.equal(restored.images[0].sizeBytes,original.length);
 await restored.setUploaded(row.uri,undefined);
 const expired=await AttachmentDraftStore.open('/private','env','document');
 assert.equal(expired.images[0].uploaded,undefined);assert.equal(expired.images[0].name,'资料.pdf');
 assert.deepEqual(files.get(row.uri),original);
 await expired.clear();assert.deepEqual(files.get('document-uri'),original);
});

test('document copy enforces server limits and never keeps an incomplete private copy',async()=>{
 files.set('file-uri',Buffer.from('document'));
 const store=await AttachmentDraftStore.open('/private','env','document-failure');
 const before=[...files.keys()];
 await assert.rejects(store.addFile('file-uri','readme.txt',2),/不能超过/);
 const copy=fs.copyFile;fs.copyFile=async(from,to)=>files.set(to,Buffer.from('part'));
 try {await assert.rejects(store.addFile('file-uri','readme.txt',1024),/复制未完成/);}
 finally {fs.copyFile=copy;}
 assert.deepEqual(store.images,[]);assert.deepEqual([...files.keys()],before);
});
test('documents can be copied and restored locally before the server upload limit is available',async()=>{
 const bytes=Buffer.from('离线附件草稿');files.set('offline-document',bytes);
 const store=await AttachmentDraftStore.open('/private','env','offline-document');
 const row=await store.addFile('offline-document','说明.txt',0);
 const restored=await AttachmentDraftStore.open('/private','env','offline-document');
 assert.equal(restored.images[0].name,'说明.txt');assert.equal(restored.images[0].type,'file');
 assert.equal(restored.images[0].uploaded,undefined);assert.deepEqual(files.get(row.uri),bytes);
 await restored.remove(row.uri);assert.deepEqual(files.get('offline-document'),bytes);
});

test('replacing an image works at the limit and publishes the new copy before discarding the old file',async()=>{
 const store=await AttachmentDraftStore.open('/private','env','replace-eight');
 for(let i=0;i<8;i++)await store.add('gallery-uri',i+'.png');
 const old=store.images[3].uri,others=store.images.filter(i=>i.uri!==old);
 const replacement=await store.add('gallery-uri','edited.png',old);
 assert.equal(store.images.length,8);assert.equal(store.images[3].uri,replacement.uri);assert.equal(files.has(old),false);
 assert.deepEqual(store.images.filter(i=>i.uri!==replacement.uri),others);
 const restored=await AttachmentDraftStore.open('/private','env','replace-eight');assert.equal(restored.images[3].name,'edited.png');
});
test('failed replacement keeps the original private file and every attachment reference',async()=>{
 const store=await AttachmentDraftStore.open('/private','env','replace-failure');const original=await store.add('gallery-uri','original.png');
 const save=store.metadata.save;store.metadata.save=async()=>{throw Error('disk full');};const before=[...files.keys()];
 try {await assert.rejects(store.add('gallery-uri','edited.png',original.uri),/disk full/);}
 finally{store.metadata.save=save;}
 assert.deepEqual([...files.keys()],before);assert.deepEqual(store.images,[original]);
});

test('a late upload from another open page cannot revive a removed image or erase its replacement',async()=>{
 const open=()=>AttachmentDraftStore.open('/private','env','two-pages');const [parent,preview]=await Promise.all([open(),open()]);
 const a=await parent.add('gallery-uri','a.png');const reopened=await open();await reopened.remove(a.uri);
 const b=await preview.add('gallery-uri','b.png');await parent.setUploaded(a.uri,{id:'late'});
 assert.deepEqual(JSON.parse(metadata.get(JSON.stringify(['/private','env','images:two-pages']))).map(i=>i.uri),[b.uri]);
 assert.deepEqual(parent.images.map(i=>i.uri),[b.uri]);assert.equal(files.has(a.uri),false);
});
test('clear removes the actual files committed by an already queued addition',async()=>{
 const store=await AttachmentDraftStore.open('/private','env','clear-overlap');const entered=Promise.withResolvers(),finish=Promise.withResolvers(),save=store.metadata.save;
 store.metadata.save=async text=>{if(text){entered.resolve();await finish.promise}return save(text)};
 const adding=store.add('gallery-uri','added.png');await entered.promise;const clearing=store.clear();finish.resolve();
 const image=await adding;await clearing;assert.equal(files.has(image.uri),false);assert.deepEqual(store.images,[]);assert.ok(files.has('gallery-uri'));
});
