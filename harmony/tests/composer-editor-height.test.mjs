import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const source=readFileSync(new URL('../app/entry/src/main/ets/pages/ComposerEditor.ets',import.meta.url),'utf8');
const methods=source.slice(source.indexOf('  private measure():'),source.indexOf('  private selection(')).replaceAll('private ','');
const js=`
const composerRawText=spans=>spans.map(s=>s.raw).join('');
export class Editor {
 ready=true;cancelMeasure=null;editorHeight=28;spans=[];afterLayout=new Set();heights=[24];
 controller={getLayoutManager:()=>({getLineCount:()=>this.heights.length,getLineMetrics:n=>({height:this.heights[n]*2})})};
 getUIContext(){return {px2vp:n=>n/2,getUIObserver:()=>({on:(_,cb)=>this.afterLayout.add(cb),off:(_,cb)=>this.afterLayout.delete(cb)})}}lineHeight(){return 24}
 ${methods}
 flush(layout=()=>{}){layout();[...this.afterLayout].forEach(callback=>callback())}
}`;
const {Editor}=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(js)).toString('base64'));
test('skill and reference chips use measured native line heights instead of clipping them to plain text height',()=>{
 const editor=new Editor();editor.spans=[{raw:'$review',kind:'skill'}];editor.heights=[32];
 editor.measure();editor.flush();assert.equal(editor.editorHeight,36);
 editor.heights=[32,40];editor.measure();editor.flush();assert.equal(editor.editorHeight,76);
});
test('empty placeholder keeps its native centering while long drafts show at most four measured lines',()=>{
 const editor=new Editor();editor.heights=[19];editor.measure();editor.flush();assert.equal(editor.editorHeight,23);
 editor.spans=[{raw:'long draft',kind:'text'}];editor.heights=[30,30,30,30,30,30];editor.measure();editor.flush();
 assert.equal(editor.editorHeight,124);
});
test('disposed editor does not resize from a queued frame',()=>{
 const editor=new Editor();editor.measure();editor.ready=false;editor.flush();assert.equal(editor.editorHeight,28);
});

test('one paste expands to its freshly wrapped lines and clearing it shrinks without another keystroke',()=>{
 const editor=new Editor();editor.spans=[{raw:'pasted paragraph',kind:'text'}];
 editor.measure();editor.flush(()=>{editor.heights=[24,24,24,24,24]});assert.equal(editor.editorHeight,100);
 editor.spans=[];editor.measure();editor.flush(()=>{editor.heights=[19]});assert.equal(editor.editorHeight,23);
});
