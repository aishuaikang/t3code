import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const source=readFileSync(new URL('../app/entry/src/main/ets/model/Models.ets',import.meta.url),'utf8');
const m=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
const messages=[{id:'u',role:'user',text:'fix',turnId:'r',createdAt:'2026-11-16T00:00:00Z'},
  {id:'step',role:'assistant',text:'working',turnId:'r',createdAt:'2026-11-16T00:00:01Z'},
  {id:'a',role:'assistant',text:'done',turnId:'r',createdAt:'2026-11-16T00:00:03Z'}];
const turn={turnId:'r',state:'completed',ordinal:7,assistantMessageId:'a',completedAt:'2026-11-16T00:00:04Z'};
const activity=(payload)=>({id:'checkpoint',kind:'timeline.updated',turnId:'r',createdAt:'2026-11-16T00:00:05Z',
  payload:{itemType:'checkpoint',title:'改动摘要 · 2 个文件',...payload}});
const rows=payload=>m.transcriptRows(messages,[activity(payload)],null,turn,[],[turn]);
test('completed replies keep their actual file summary visible outside the collapsed process',()=>{
 const files=[{path:'src/你好.ts',additions:4,deletions:2},{path:'AGENTS.md',additions:5,deletions:5}];
 const result=rows({changedFiles:files});
 assert.deepEqual(result.map(r=>r.kind),['message','turn','message','changes']);
 assert.deepEqual(result.at(-1).changedFiles,files);assert.equal(result.at(-1).checkpointTurnCount,7);
 assert.equal(result.at(-1).turnId,'r');
});
test('older cached checkpoint details recover file counts without parsing ordinary activity text',()=>{
 const result=rows({detail:'src/my file.ts  +4 −2\nAGENTS.md  +5 −5'});
 assert.deepEqual(result.at(-1).changedFiles,[{path:'src/my file.ts',additions:4,deletions:2},{path:'AGENTS.md',additions:5,deletions:5}]);
 assert.equal(rows({detail:''}).some(r=>r.kind==='changes'),false);
 const other=activity({itemType:'dynamic_tool',detail:'file.ts  +1 −0'});
 assert.equal(m.transcriptRows(messages,[other],null,turn,[],[turn]).some(r=>r.kind==='changes'),false);
});
test('changing only file totals invalidates its rendered row while retaining unrelated history',()=>{
 const previous=rows({changedFiles:[{path:'file.ts',additions:1,deletions:0}]});
 const next=rows({changedFiles:[{path:'file.ts',additions:2,deletions:0}]});
 const reconciled=m.reconcileTranscriptRows(previous,next);
 assert.equal(reconciled[0],previous[0]);assert.notEqual(reconciled.at(-1),previous.at(-1));
 assert.equal(reconciled.at(-1).changedFiles[0].additions,2);
});
