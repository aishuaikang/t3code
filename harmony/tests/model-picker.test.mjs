import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
const source=readFileSync(new URL('../app/entry/src/main/ets/pages/ComposerSettings.ets',import.meta.url),'utf8');
const methods=source.slice(source.indexOf('  private providers('),source.indexOf('  private requestModelPicker(')).replaceAll('private ','');
const {Picker}=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(`
export class Picker {models=[];selection=null;activeProviderId='';query='';reasoningOpen=false;picker='';sheetOpen=false; ${methods} }
`)).toString('base64'));
const catalog=[
 {instanceId:'codex',model:'gpt',label:'Codex · GPT',providerLabel:'Codex'},
 {instanceId:'claude',model:'fable',label:'Claude · Fable',providerLabel:'Claude'},
 {instanceId:'claude',model:'opus',label:'Claude · Opus',providerLabel:'Claude'},
 {instanceId:'claude-work',model:'fable',label:'Work Claude · Fable',providerLabel:'Work Claude'}
];
test('provider tabs initially follow the selected model and browsing does not change that pick',()=>{
 const page=new Picker();page.models=catalog;page.selection={instanceId:'claude',model:'fable',options:[{id:'effort',value:'max'}]};
 page.open('model');assert.equal(page.activeProvider(),'claude');assert.equal(page.providers().length,3);
 assert.deepEqual(page.matches(page.activeProvider()).map(m=>m.model),['fable','opus']);
 page.browseProvider('codex');assert.equal(page.activeProvider(),'codex');assert.deepEqual(page.matches(page.activeProvider()).map(m=>m.model),['gpt']);
 assert.equal(page.selection.instanceId,'claude');assert.equal(page.selection.options[0].value,'max');
 page.open('model');assert.equal(page.activeProvider(),'claude');
});
test('search stays within its provider tab and a removed tab falls back to a valid provider',()=>{
 const page=new Picker();page.models=catalog;page.selection={instanceId:'claude',model:'fable'};page.open('model');
 page.query='opus';assert.deepEqual(page.matches(page.activeProvider()).map(m=>m.model),['opus']);
 page.browseProvider('claude-work');assert.equal(page.query,'');assert.equal(page.matches(page.activeProvider()).length,1);
 page.models=catalog.filter(m=>m.instanceId!=='claude-work');assert.equal(page.activeProvider(),'claude');
 page.browseProvider('missing');assert.equal(page.activeProvider(),'claude');
 page.models=[];assert.equal(page.activeProvider(),'');assert.deepEqual(page.matches(page.activeProvider()),[]);
});
