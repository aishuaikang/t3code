import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
const { terminalExcerpt } = await import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(readFileSync(
 new URL('../app/entry/src/main/ets/model/TerminalOutput.ets',import.meta.url),'utf8'))).toString('base64'));
test('terminal excerpts preserve selected visible lines, Unicode and spacing with explicit line numbers',()=>{
 const lines=['hidden above selection','  编译通过 ✅','', '$ done'];
 const excerpt=terminalExcerpt(lines,1,3,'term-1');
 assert.match(excerpt,/可见行 2–4/);assert.ok(excerpt.includes('  编译通过 ✅\n\n$ done'));assert.ok(!excerpt.includes('hidden above selection'));
});
test('empty, invalid and oversized selections cannot be attached',()=>{
 for(const [start,end] of [[-1,0],[0,2],[1,0],[0.5,1]])assert.equal(terminalExcerpt(['a','b'],start,end,'term'),null);
 assert.equal(terminalExcerpt(['','  '],0,1,'term'),null);
 assert.ok(terminalExcerpt(['x'.repeat(64000)],0,0,'term'));
 assert.equal(terminalExcerpt(['x'.repeat(64001)],0,0,'term'),null);
});
test('output containing Markdown fences stays inside one intact code block',()=>{
 const excerpt=terminalExcerpt(['```','````','still output'],0,2,'term');
 assert.ok(excerpt.includes('\n`````text\n```\n````\nstill output\n`````'));
});
const pageSource=readFileSync(new URL('../app/entry/src/main/ets/pages/Terminal.ets',import.meta.url),'utf8');
const attach=pageSource.slice(pageSource.indexOf('  private async attachOutput('),pageSource.indexOf('  @Builder\n  outputSheet(')).replaceAll('private ','');
const {Page,EnvironmentSession}=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(`
const getContext=()=>({filesDir:'/private'});const DraftStore={open:async()=>globalThis.__outputDraftStore};
export const EnvironmentSession={current:{descriptor:{environmentId:'env'}}};
const router={back:()=>globalThis.__outputBacks++};
export class Page {active=true;attachingOutput=false;outputOpen=true;environmentId='env';threadId='thread';outputError='';outputText(){return 'Selected output'}${attach}}
`)).toString('base64'));
test('attaching output appends to the latest saved draft and does not send a message',async()=>{
 let draft='User text  ';globalThis.__outputBacks=0;globalThis.__outputDraftStore={load:async()=>draft,save:async value=>draft=value};
 const page=new Page();await page.attachOutput();assert.equal(draft,'User text  \n\nSelected output');assert.equal(globalThis.__outputBacks,1);
});
test('failed output attachment leaves the draft and selection available for retry',async()=>{
 const page=new Page();globalThis.__outputDraftStore={load:async()=> 'User text',save:async()=>{throw Error('disk full')}};
 await page.attachOutput();assert.equal(page.outputOpen,true);assert.match(page.outputError,/保存/);assert.equal(page.attachingOutput,false);
});
test('switching environments while the draft loads cannot attach output to the new environment',async()=>{
 let finish,writes=0;const page=new Page();globalThis.__outputDraftStore={load:()=>new Promise(resolve=>finish=resolve),save:async()=>writes++};
 const pending=page.attachOutput();await Promise.resolve();await Promise.resolve();
 EnvironmentSession.current={descriptor:{environmentId:'other'}};finish('Draft');await pending;
 assert.equal(writes,0);EnvironmentSession.current={descriptor:{environmentId:'env'}};
});
