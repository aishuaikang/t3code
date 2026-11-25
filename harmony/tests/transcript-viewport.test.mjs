import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const read=name=>readFileSync(new URL('../app/entry/src/main/ets/'+name,import.meta.url),'utf8');
const load=source=>import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
const {TranscriptFollow}=await load(read('model/TranscriptFollow.ets'));
globalThis.__viewportFollow=TranscriptFollow;
const source=read('pages/Thread.ets');
const frame=source.slice(source.indexOf('class TranscriptFrame'),source.indexOf('@Entry'));
const methods=source.slice(source.indexOf('  onDidBuild():'),source.indexOf('  private stopElapsedTimer(')).replaceAll('private ','');
const {Page}=await load(`const TranscriptFollow=globalThis.__viewportFollow;class FrameCallback{};${frame}
export class Page {
 active=true;entries=[];requests=[];follow=new TranscriptFollow();followQueued=false;followGeneration=0;showingHistory=false;
 frames=[];scrolls=[];scroller={scrollToIndex:(index,smooth,align)=>this.scrolls.push(index),scrollEdge:()=>{}};
 getUIContext(){return {postFrameCallback:callback=>this.frames.push(callback)}}needsThinking(){return false}
 cancelQuoteNavigation(){}
 ${methods}
}
const ScrollAlign={END:2};const Edge={Bottom:3};`);
function render(page){page.onDidBuild();page.frames.splice(0).forEach(frame=>frame.onFrame(1));}
test('a new message becomes visible on the next frame even when the UI has no idle time',()=>{
 const page=new Page();page.entries=[{id:'old'}];page.follow.update('old');render(page);
 page.entries.push({id:'sent'});page.follow.update('sent');render(page);
 assert.deepEqual(page.scrolls,[0,1]);
});
test('synchronized history stays at its final transcript row while the pending question occupies the composer',()=>{
 const page=new Page();page.entries=Array.from({length:400},(_,n)=>({id:String(n)}));page.requests=[{id:'question'}];
 page.follow.update('synchronized');render(page);assert.deepEqual(page.scrolls,[399]);
});
test('a recent history window follows the last message with its older-history control present',()=>{
 const page=new Page();page.hasMoreHistory=true;page.entries=[{id:'one'},{id:'latest'}];
 page.follow.update('recent-window');render(page);assert.deepEqual(page.scrolls,[2]);
});
test('streaming cannot move a reader who has scrolled up, and jump to latest resumes following',()=>{
 const page=new Page();page.entries=[{id:'one'},{id:'two'}];page.follow.pause();page.follow.update('token');render(page);
 assert.deepEqual(page.scrolls,[]);page.jumpToLatest();render(page);assert.deepEqual(page.scrolls,[1]);
});
