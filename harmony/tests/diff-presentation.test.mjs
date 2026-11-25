import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';

const load = async path => {
 const source=readFileSync(new URL(path,import.meta.url),'utf8').replace(/^import .*;\n/gm,'');
 return import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
};
const {parseDiffRows}=await load('../app/entry/src/main/ets/model/DiffRows.ets');
const {diffDisplayRows,diffAnchorIndex,diffLineText}=await load('../app/entry/src/main/ets/model/DiffPresentation.ets');
const {DiffDataSource}=await load('../app/entry/src/main/ets/pages/DiffDataSource.ets');
const source='diff --git a/中.ts b/中.ts\n--- a/中.ts\n+++ b/中.ts\n@@ -4,4 +4,5 @@\n context\n-old1\n-old2\n+new1\n+new2\n+extra\n last\n'
 +'diff --git a/image.bin b/image.bin\nBinary files a/image.bin and b/image.bin differ\n';

test('native unified list retains the full diff and folding only hides the selected file body',()=>{
 const rows=parseDiffRows(source), fileIds=rows.filter(r=>r.kind==='file').map(r=>r.id);
 const display=diffDisplayRows(rows,[],false);
 assert.deepEqual(display.map(r=>r.source),rows);
 const folded=diffDisplayRows(rows,[fileIds[0]],false);
 assert.deepEqual(folded.filter(r=>r.fileId===fileIds[0]).map(r=>r.kind),['file']);
 assert.equal(folded.at(-1).source.text,'二进制文件发生变化');
 assert.deepEqual(diffDisplayRows(rows,fileIds,false).map(r=>r.source),rows.filter(r=>r.kind==='file'));
 assert.equal(rows[0].additions,3);assert.equal(rows[0].deletions,2);
 assert.equal(new Set(display.map(r=>r.id)).size,display.length);
});

test('split view pairs replacement blocks without losing unmatched lines or crossing hunks',()=>{
 const rows=parseDiffRows(source), split=diffDisplayRows(rows,[],true).filter(r=>r.kind==='line');
 assert.deepEqual(split.map(r=>[r.left?.content,r.right?.content]),[
  ['context','context'],['old1','new1'],['old2','new2'],[undefined,'extra'],['last','last']
 ]);
 assert.equal(split[1].left.oldLineNumber,5);assert.equal(split[1].right.newLineNumber,5);
 assert.equal(split[3].right.newLineNumber,7);
 const separated=parseDiffRows('diff --git a/x b/x\n@@ -1 +0,0 @@\n-old\n@@ -4,0 +4 @@\n+new\n');
 assert.deepEqual(diffDisplayRows(separated,[],true).filter(r=>r.kind==='line').map(r=>[r.left?.content,r.right?.content]),[
  ['old',undefined],[undefined,'new']
 ]);
});

test('switching view modes retains the visible line and collapsing retains its file as the anchor',()=>{
 const rows=parseDiffRows(source), anchor=rows.find(r=>r.content==='new2');
 const split=diffDisplayRows(rows,[],true);
 assert.equal(split[diffAnchorIndex(split,anchor.id,anchor.fileId)].right.id,anchor.id);
 const folded=diffDisplayRows(rows,[anchor.fileId],false);
 assert.equal(folded[diffAnchorIndex(folded,anchor.id,anchor.fileId)].source.id,anchor.fileId);
 assert.equal(diffAnchorIndex([],anchor.id,anchor.fileId),0);
});

test('whitespace display never modifies the source used by code comments',()=>{
 const raw='  中文\tvalue  ';
 assert.equal(diffLineText(raw,false),raw);
 assert.equal(diffLineText(raw,true),'··中文→   value··');
 assert.equal(diffLineText(undefined,true),'');
 const rows=parseDiffRows(source);
 diffDisplayRows(rows,[],true);
 assert.equal(rows.find(r=>r.content==='old1').content,'old1');
});

test('native lazy list refresh invalidates recycled rows even when parser IDs are unchanged',()=>{
 const data=new DiffDataSource();let reloads=0;
 const listener={onDataReloaded(){reloads++}};
 data.registerDataChangeListener(listener);data.registerDataChangeListener(listener);
 const initial=diffDisplayRows(parseDiffRows(source),[],false);
 data.update(initial);const key=data.key(data.getData(3));
 const refreshed=diffDisplayRows(parseDiffRows(source.replace('old1','updated')),[],false);
 data.update(refreshed);
 assert.equal(data.totalCount(),refreshed.length);assert.equal(data.getData(3).source.content,'updated');
 assert.notEqual(data.key(data.getData(3)),key);assert.equal(reloads,2);
 data.unregisterDataChangeListener(listener);data.update([]);assert.equal(reloads,2);assert.equal(data.totalCount(),0);
});
