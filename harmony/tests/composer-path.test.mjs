import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const source=readFileSync(new URL('../app/entry/src/main/ets/model/ComposerPath.ets',import.meta.url),'utf8');
const model=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
const sharedSource=readFileSync(new URL('../../packages/shared/src/composerTrigger.ts',import.meta.url),'utf8');
const shared=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(sharedSource)).toString('base64'));
test('path completion follows shared cursor boundaries and ignores selected text and email addresses',()=>{
 for(const text of ['Inspect @src','你好 @分组','email@host','@','first\n@two','@src suffix','x @a\t@b']){
  for(let cursor=0;cursor<=text.length;cursor++){
   const expected=shared.detectComposerTrigger(text,cursor);
   const trigger=expected?.kind==='path'?{query:expected.query,start:expected.rangeStart,end:expected.rangeEnd}:null;
   if(trigger){while(trigger.end<text.length&&!/[\s@＠，。！？；、()（）]/.test(text[trigger.end]))trigger.end++;}
   assert.deepEqual(model.composerPathTrigger(text,cursor,cursor),trigger);
  }
 }
 assert.equal(model.composerPathTrigger('@file',0,5),null);
});
test('mentions can follow Chinese text and punctuation and replace only the active token around the caret',()=>{
 const text='请查看@会话 以及后面的文字';
 const trigger=model.composerPathTrigger(text,5,5);
 assert.deepEqual(trigger,{query:'会',start:3,end:6});
 assert.equal(model.insertComposerEntry(text,trigger,{kind:'thread',path:'id',threadId:'id',label:'目标任务'}).text,'请查看[目标任务](t3-thread://v1/id)  以及后面的文字');
 assert.deepEqual(model.composerPathTrigger('前文，＠文件',6,6),{query:'文件',start:3,end:6});
 assert.equal(model.composerPathTrigger('https://example.test/@abc',24,24),null);
});
test('inserted file links match iOS serialization and preserve text after the cursor',()=>{
 for(const path of ['src/main.ts','docs/a b[1](x)#?.md','目录/中文.md','src/a\\b.txt']){
  const text='Read @src then explain',trigger=model.composerPathTrigger(text,9,9);
  assert.deepEqual(model.insertComposerPath(text,trigger,path),shared.replaceTextRange(text,5,9,shared.serializeComposerFileLink(path)+' '));
 }
});

test('full-width mentions preserve Chinese queries and insertion keeps the surrounding text',()=>{
 const text='检查 ＠文档 末尾',trigger=model.composerPathTrigger(text,6,6);
 assert.deepEqual(trigger,{query:'文档',start:3,end:6});
 const inserted=model.insertComposerPath(text,trigger,'目录/文档.md');
 assert.equal(inserted.text,'检查 '+shared.serializeComposerFileLink('目录/文档.md')+'  末尾');
 assert.deepEqual(model.composerPathTrigger('＠',1,1),{query:'',start:0,end:1});
 assert.equal(model.composerPathTrigger('email＠host',10,10),null);
});

test('mention results include matching recent threads, exclude the current and archived thread, and preserve file results',()=>{
 const files=[{path:'docs/说明.md',kind:'file'},{path:'docs',kind:'directory'}];
 const threads=[
  {id:'old',title:'Windows 配置',updatedAt:'2026-11-14'},
  {id:'new',title:'Windows 安装',updatedAt:'2026-11-15'},
  {id:'self',title:'Windows 当前',updatedAt:'2026-11-16'},
  {id:'archived',title:'Windows 归档',updatedAt:'2026-11-16',archivedAt:'2026-11-16'},
  {id:'unrelated',title:'其他任务',updatedAt:'2026-11-16'}
 ];
 const rows=model.composerPathEntries(files,threads,'win','self');
 assert.deepEqual(rows.filter(r=>r.kind==='thread').map(r=>r.threadId),['new','old']);
 assert.deepEqual(rows.filter(r=>r.kind!=='thread'),files);
 assert.equal(model.composerEntryLabel(files[0]),'说明.md');
 assert.equal(model.composerEntryDescription(files[0]),'docs');
 const chinese=model.composerPathEntries([],threads,'安装','self');
 assert.equal(chinese[0].label,'Windows 安装');
 const trigger=model.composerPathTrigger('看看 @安装 后面',6,6);
 assert.deepEqual(model.insertComposerEntry('看看 @安装 后面',trigger,chinese[0]),{text:'看看 [Windows 安装](t3-thread://v1/new)  后面',cursor:36});
});

test('a missing file list still renders selectable cached thread mentions',()=>{
 const threads=[{id:'other',title:'旧任务',updatedAt:null}];
 const entries=model.composerPathEntries(undefined,threads,'');
 assert.deepEqual(entries.map(entry=>model.composerEntryLabel(entry)),['旧任务']);
 assert.equal(model.insertComposerEntry('@',{start:0,end:1,query:''},entries[0]).text,'[旧任务](t3-thread://v1/other) ');
});
