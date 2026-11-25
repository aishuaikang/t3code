import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
const read=p=>readFileSync(new URL('../app/entry/src/main/ets/'+p,import.meta.url),'utf8');
const src=read('pages/ComposerSettings.ets');
const methods=src.slice(src.indexOf('  private reasoning('),src.indexOf('  private providers(')).replaceAll('private ','');
const changeOption=src.slice(src.indexOf('  private changeOption('),src.indexOf('  @Builder',src.indexOf('  private changeOption('))).replace('private ','');
const { Settings }=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(`
${read('model/ModelOptions.ets').replace(/^import .*;$/gm,'')}
export class Settings { selection={instanceId:'codex',model:'model'};catalog=[];descriptors(){return this.catalog;} ${methods} ${changeOption} onOptions(next){this.selection=next;} }
`)).toString('base64'));
test('speed controls always mark the effective default and follow saved boolean values',()=>{
 const p=new Settings();p.catalog=[{id:'fastMode',type:'boolean'}];let [standard,fast]=p.speedChoices();
 assert.equal(p.speedSelected(standard),true);assert.equal(p.speedSelected(fast),false);assert.equal(p.fastEnabled(),false);
 p.selection.options=[{id:'fastMode',value:true}];assert.equal(p.speedSelected(fast),true);assert.equal(p.speedSelected(standard),false);assert.equal(p.fastEnabled(),true);
 p.selection.options=[{id:'fastMode',value:false}];assert.equal(p.speedSelected(standard),true);assert.equal(p.fastEnabled(),false);
});
test('service-tier speed controls display a single current choice with or without explicit defaults',()=>{
 const p=new Settings();p.catalog=[{id:'serviceTier',type:'select',options:[{id:'default',label:'Standard'},{id:'priority',label:'Fast'}]}];let [standard,fast]=p.speedChoices();
 assert.equal(p.speedSelected(standard),true);assert.equal(p.speedSelected(fast),false);assert.equal(p.fastEnabled(),false);
 p.selection.options=[{id:'serviceTier',value:'priority'}];assert.equal(p.speedSelected(fast),true);assert.equal(p.speedSelected(standard),false);assert.equal(p.fastEnabled(),true);
 p.selection.options=[];p.catalog[0].currentValue='priority';assert.equal(p.speedSelected(fast),true);assert.equal(p.fastEnabled(),true);
 p.selection.options=[{id:'serviceTier',value:'default'}];assert.equal(p.fastEnabled(),false);
});
test('the composer fast indicator restores the saved choice and hides for unsupported or unloaded models',()=>{
 const p=new Settings();p.catalog=[{id:'fastMode',type:'boolean',currentValue:true}];assert.equal(p.fastEnabled(),true);
 p.selection.options=[{id:'fastMode',value:false}];assert.equal(p.fastEnabled(),false);
 p.selection=JSON.parse(JSON.stringify({instanceId:'codex',model:'model',options:[{id:'fastMode',value:true}]}));assert.equal(p.fastEnabled(),true);
 p.catalog=[];assert.equal(p.fastEnabled(),false);
 p.catalog=[{id:'fastMode',type:'boolean'}];p.selection=null;assert.equal(p.fastEnabled(),false);
});

test('the model sheet exposes Ultracode separately and keeps unrelated model controls',()=>{
 const p=new Settings();
 const effort={id:'effort',label:'Reasoning',type:'select',options:[{id:'medium',label:'Medium',isDefault:true},{id:'max',label:'Max'}]};
 const workflow={id:'ultracode',label:'Ultracode',type:'boolean'};
 const context={id:'contextWindow',label:'Context Window',type:'select',options:[{id:'1m',label:'1M'}]};
 p.catalog=[effort,{id:'fastMode',type:'boolean'},workflow,context];
 assert.equal(p.ultracode(),workflow);
 assert.deepEqual(p.extraOptions(),[context]);
 assert.equal(p.workflowEnabled(),false);
 p.selection={instanceId:'claude',model:'claude-fable-5-2',options:[{id:'effort',value:'max'},{id:'ultracode',value:true}]};
 assert.equal(p.workflowEnabled(),true);assert.equal(p.fastEnabled(),false);
 p.catalog=[effort,context];assert.equal(p.workflowEnabled(),false);
 assert.deepEqual(p.extraOptions(),[context]);
});

test('the composer shortcut keeps effort and speed independent, including after resetting effort',()=>{
 const effort={id:'reasoningEffort',label:'Reasoning',type:'select',options:[{id:'medium',label:'Medium',isDefault:true},{id:'max',label:'Max'}]};
 for(const speed of [{id:'fastMode',type:'boolean'},{id:'serviceTier',type:'select',options:[{id:'default',label:'Standard'},{id:'priority',label:'Fast'}]}]){
  const p=new Settings();p.catalog=[effort,speed];p.changeOption(effort,'max');
  const [standard,fast]=p.speedChoices();assert.equal(fast.label,'Fast');
  const change=choice=>p.changeOption(p.fastMode(),p.speedValue(choice));
  change(fast);assert.equal(p.quickOptionsLabel(),'Max');assert.equal(p.fastEnabled(),true);
  assert.deepEqual(p.selection.options,[{id:'reasoningEffort',value:'max'},{id:speed.id,value:speed.type==='boolean'?true:'priority'}]);
  change(standard);assert.equal(p.quickOptionsLabel(),'Max');assert.equal(p.fastEnabled(),false);
  change(fast);p.changeOption(effort,'medium');assert.equal(p.quickOptionsLabel(),'Medium');assert.equal(p.fastEnabled(),true);
  p.changeOption(effort,null);assert.equal(p.fastEnabled(),true);assert.deepEqual(p.selection.options,[{id:speed.id,value:speed.type==='boolean'?true:'priority'}]);
 }
});
test('a speed-only model names the active speed in the shortcut; effort-only models offer no speeds',()=>{
 const p=new Settings();p.catalog=[{id:'fastMode',type:'boolean',currentValue:true}];assert.equal(p.quickOptionsLabel(),'Fast');
 p.changeOption(p.fastMode(),false);assert.equal(p.quickOptionsLabel(),'标准');
 p.catalog=[{id:'effort',type:'select',options:[{id:'low',label:'Low',isDefault:true},{id:'max',label:'Max'}]}];
 assert.equal(p.quickOptionsLabel(),'Low');assert.deepEqual(p.speedChoices(),[]);
});
