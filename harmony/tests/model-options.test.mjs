import {test} from 'node:test';import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';import {stripTypeScriptTypes} from 'node:module';
const path=new URL('../app/entry/src/main/ets/model/ModelOptions.ets',import.meta.url);
const source=readFileSync(path,'utf8').replace(/^import .*;$/gm,'');
const m=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
const descriptor={id:'reasoning',type:'select',label:'Thinking',currentValue:'xhigh',options:[{id:'low',label:'Low'},{id:'xhigh',label:'Extra high',isDefault:true},{id:'ultrathink',label:'Ultra'},{id:'ultracode',label:'Code'}],promptInjectedValues:['ultrathink']};
const current={instanceId:'omp',model:'cursor/default',options:[{id:'fast',value:false},{id:'reasoning',value:'xhigh'}]};
test('select option replaces only its own canonical selection without mutating source',()=>{
 const changed=m.withModelOption(current,descriptor,'low');assert.deepEqual(changed,{...current,options:[{id:'fast',value:false},{id:'reasoning',value:'low'}]});assert.equal(current.options[1].value,'xhigh');
});
test('reset removes only explicit selection and resolves provider default',()=>{
 const changed=m.withModelOption(current,descriptor,null);assert.deepEqual(changed.options,[{id:'fast',value:false}]);assert.equal(m.modelOptionValue(changed,descriptor),'xhigh');
});
test('unsupported values and prompt-injected workflows cannot be selected',()=>{
 for(const v of ['missing','ultrathink','ultracode',true])assert.equal(m.withModelOption(current,descriptor,v),null);
 assert.deepEqual(m.modelOptionChoices(descriptor).map(c=>c.id),['low','xhigh']);
});
test('boolean false remains explicit and unknown stored selection remains visible',()=>{
 const toggle={id:'fast',type:'boolean',label:'Fast',currentValue:true};assert.equal(m.modelOptionValue(current,toggle),false);
 assert.equal(m.withModelOption(current,toggle,'false'),null);assert.equal(m.withModelOption(current,toggle,true).options.at(-1).value,true);
 assert.equal(m.modelOptionValue({...current,options:[{id:'reasoning',value:'external-value'}]},descriptor),'external-value');
});
test('reasoning control uses only real selectable provider levels',()=>{
 assert.equal(m.reasoningOption([descriptor]),descriptor);
 const serverReasoning={...descriptor,id:'budget',label:'Compute',role:'reasoning'};
 assert.equal(m.reasoningOption([serverReasoning]),serverReasoning);
 assert.equal(m.reasoningOption([{...descriptor,options:[{id:'low',label:'Low'},{id:'ultracode',label:'Code'}]}]),undefined);
 assert.equal(m.reasoningOption([{id:'temperature',type:'select',label:'Temperature',options:[{id:'low'},{id:'high'}]}]),undefined);
});
test('quick speed control supports only catalog-backed boolean fastMode and Standard/Fast service tiers',()=>{
 const fast={id:'fastMode',type:'boolean',label:'Fast',currentValue:false};
 assert.equal(m.fastModeOption([descriptor,fast]),fast);
 assert.equal(m.fastModeOption([{...fast,type:'select'}]),undefined);
 assert.equal(m.fastModeOption([{...fast,id:'unknown-speed'}]),undefined);
 const tiers={id:'serviceTier',type:'select',options:[{id:'default',label:'Standard',isDefault:true},{id:'priority',label:'Fast'}]};
 assert.equal(m.fastModeOption([tiers]),tiers);
 assert.equal(m.fastModeOption([{...tiers,options:[{id:'default',label:'Standard'}]}]),undefined);
});
test('fast indicators follow each thread selection, including explicit off and provider defaults',()=>{
 const fast={id:'fastMode',type:'boolean',currentValue:true};
 const tiers={id:'serviceTier',type:'select',options:[{id:'default',label:'Standard',isDefault:true},{id:'priority',label:'Fast'}]};
 const selection=options=>({instanceId:'codex',model:'model',options});
 assert.equal(m.fastModeEnabled(selection([{id:'fastMode',value:true}]),[fast]),true);
 assert.equal(m.fastModeEnabled(selection([{id:'fastMode',value:false}]),[fast]),false);
 assert.equal(m.fastModeEnabled(selection([]),[fast]),true);
 assert.equal(m.fastModeEnabled(selection([{id:'serviceTier',value:'priority'}]),[tiers]),true);
 assert.equal(m.fastModeEnabled(selection([{id:'serviceTier',value:'default'}]),[tiers]),false);
 assert.equal(m.fastModeEnabled(selection([{id:'fastMode',value:'true'}]),[fast]),false);
 assert.equal(m.fastModeEnabled(null,[fast]),false);
 assert.equal(m.fastModeEnabled(selection([{id:'fastMode',value:true}]),[]),false);
});

test('a recorded model transition uses matching provider names and falls back to historical model IDs',()=>{
 const from={instanceId:'codex',model:'a'},to={instanceId:'codex',model:'b'};
 const providers=[{instanceId:'codex',models:[{slug:'a',name:'Model A'},{slug:'b',name:'Full Model B',shortName:'Model B'}]}];
 assert.equal(m.modelSwitchLabel({from,to},providers),'Model A → Model B');
 assert.equal(m.modelSwitchLabel({from,to},[]),'a → b');
});

test('effort-only transitions show a change from the model default and omit unrelated options',()=>{
 const from={instanceId:'codex',model:'a'};
 const providers=[{instanceId:'codex',models:[{slug:'a',name:'Model A',capabilities:{optionDescriptors:[descriptor]}}]}];
 assert.equal(m.modelSwitchLabel({from,to:{...from,options:[{id:'reasoning',value:'low'}]}},providers),'Extra high → Low');
 assert.equal(m.modelSwitchLabel({from,to:{...from,options:[{id:'fastMode',value:true}]}},providers),'');
});

test('Ultracode is a catalog-backed independent boolean and follows saved values',()=>{
 const toggle={id:'ultracode',label:'Ultracode',type:'boolean',currentValue:true};
 const selection=options=>({instanceId:'claude',model:'claude-fable-5-2',options});
 assert.equal(m.ultracodeOption([descriptor,toggle]),toggle);
 assert.equal(m.ultracodeOption([{...toggle,type:'select'}]),undefined);
 assert.equal(m.ultracodeEnabled(selection([]),[toggle]),true);
 assert.equal(m.ultracodeEnabled(selection([{id:'ultracode',value:false}]),[toggle]),false);
 assert.equal(m.ultracodeEnabled(selection([{id:'ultracode',value:'true'}]),[toggle]),false);
 assert.equal(m.ultracodeEnabled(selection([{id:'ultracode',value:true}]),[]),false);
 assert.equal(m.ultracodeEnabled(null,[toggle]),false);
 const effort={id:'effort',label:'Reasoning',type:'select',options:[
  {id:'low',label:'Low'},{id:'medium',label:'Medium',isDefault:true},{id:'high',label:'High'},
  {id:'xhigh',label:'Extra High'},{id:'max',label:'Max'},{id:'ultrathink',label:'Ultrathink'}
 ],promptInjectedValues:['ultrathink']};
 assert.deepEqual(m.modelOptionChoices(effort).map(c=>c.id),['low','medium','high','xhigh','max']);
 const original=selection([{id:'effort',value:'max'},{id:'fastMode',value:true},{id:'ultracode',value:true}]);
 const changed=m.withModelOption(original,toggle,false);
 assert.equal(m.modelOptionValue(changed,effort),'max');
 assert.equal(m.fastModeEnabled(changed,[{id:'fastMode',type:'boolean'}]),true);
 assert.equal(m.ultracodeEnabled(changed,[toggle]),false);
 assert.equal(original.options.at(-1).value,true);
});

test('agent metadata shows the actual provider, catalog model and recorded effort, with honest offline fallback',()=>{
 const providers=[{instanceId:'codex-2',displayName:'Codex',models:[{slug:'demo',name:'Demo Model',shortName:'Demo',capabilities:{optionDescriptors:[descriptor]}}]}];
 const agent={providerInstanceId:'codex-2',driver:'codex',modelSelection:{instanceId:'codex-2',model:'demo',options:[{id:'reasoning',value:'xhigh'}]}};
 assert.equal(m.subagentModelLabel(agent,providers),'Codex · Demo · Extra high');
 assert.equal(m.subagentModelLabel({...agent,modelSelection:{instanceId:'codex-2',model:'demo'}},providers),'Codex · Demo');
 assert.equal(m.subagentModelLabel({...agent,providerInstanceId:'local'},[]),'local · demo · Xhigh');
 assert.equal(m.subagentModelLabel({},[]),'');
});
