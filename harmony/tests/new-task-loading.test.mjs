import {test} from 'node:test';import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';import {stripTypeScriptTypes} from 'node:module';
const source=readFileSync(new URL('../app/entry/src/main/ets/pages/NewTask.ets',import.meta.url),'utf8');
const models=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(readFileSync(new URL('../app/entry/src/main/ets/model/Models.ets',import.meta.url),'utf8'))).toString('base64'));
const commands=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(readFileSync(new URL('../app/entry/src/main/ets/model/ComposerCommands.ets',import.meta.url),'utf8'))).toString('base64'));
const files=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(readFileSync(new URL('../app/entry/src/main/ets/model/FileAttachments.ets',import.meta.url),'utf8'))).toString('base64'));
globalThis.__taskLoading={availableModels:models.availableModels,preferredModelIndex:models.preferredModelIndex,buildCommandCatalog:commands.commandCatalog,fileUploadLimit:files.fileUploadLimit};
const body=`const {availableModels,preferredModelIndex,buildCommandCatalog,fileUploadLimit}=globalThis.__taskLoading;const getContext=()=>({filesDir:'/private'});const WS={serverGetConfig:'server.getConfig'};const EmptyPayload=class{};
export const EnvironmentSession={current:{descriptor:{environmentId:'a'},rpc:{call:()=>new Promise(()=>{})}}};
const NewTaskDraftStore={open:async()=>({load:async()=>({projectId:'p',title:'Saved',text:'Original draft',modelSelection:{instanceId:'provider',model:'m'},runtimeMode:'auto',interactionMode:'default',createdThreadId:'',turnCommand:null,createCommand:{commandId:'original-create-id',threadId:'original-thread-id'}})})};
const ClientCache={open:async()=>({models:()=>[{instanceId:'provider',model:'m',label:'Model'}],commands:()=>[],setCatalog(){}})};
export class Fixture{
 environmentId='a';
 ${source.slice(source.indexOf('  private currentConnection('),source.indexOf('  aboutToAppear(')).replaceAll('private ','')}
connectionState='connected';active=true;draftReady=false;busy=false;error='';projects=[{id:'p',workspaceRoot:'/p'}];projectIndex=0;modelIndex=-1;models=[];explicitSelection=null;queueSave(){} updatePathSearch(){} uploadAttachments(){}
${source.slice(source.indexOf('  private chooseProject('),source.indexOf('  private updatePathSearch(')).replaceAll('private ','')}
${source.slice(source.indexOf('  private resumeAttachmentUploads('),source.indexOf('  private async pickAttachments(')).replaceAll('private ','')}
${source.slice(source.indexOf('  private async restoreDraft('),source.indexOf('  private queueSave(')).replaceAll('private ','')}
}`;
const {Fixture,EnvironmentSession}=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(body)).toString('base64'));
test('new-task drafts and models restore before the network catalog, which cannot overwrite editing or retry IDs',async()=>{
 let finish;EnvironmentSession.current.rpc.call=()=>new Promise(resolve=>finish=resolve);
 const page=new Fixture();const restoring=page.restoreDraft();for(let i=0;i<24;i++)await Promise.resolve();
 try{assert.equal(page.draftReady,true);assert.equal(page.draft,'Original draft');assert.equal(page.models[0].model,'m');
  page.draft='Edited while syncing';finish({providers:[]});await restoring;for(let i=0;i<8;i++)await Promise.resolve();
  assert.equal(page.draft,'Edited while syncing');assert.equal(page.pendingCreate.commandId,'original-create-id');
  assert.equal(page.models.length,0);assert.equal(page.modelIndex,-1);
 }finally{finish?.({providers:[]})}
});

test('cached environment drafts can open cold, stay editable and reconnect only to their own server',async()=>{
 const previous=EnvironmentSession.current;try{
  EnvironmentSession.current=null;const p=new Fixture();p.environmentId='a';await p.restoreDraft();
  assert.equal(p.draftReady,true);assert.equal(p.draft,'Original draft');assert.equal(p.models[0].model,'m');p.draft='Typed offline';
  let calls=0;EnvironmentSession.current={descriptor:{environmentId:'b'},rpc:{call:async()=>{calls++;return {providers:[]}}}};
  p.connectionState='connected';p.resumeAttachmentUploads();await new Promise(setImmediate);assert.equal(calls,0);assert.equal(p.draft,'Typed offline');
  EnvironmentSession.current={descriptor:{environmentId:'a'},rpc:{call:async()=>{calls++;return {providers:[]}}}};p.resumeAttachmentUploads();await new Promise(setImmediate);
  assert.equal(calls,1);assert.equal(p.draft,'Typed offline');assert.equal(p.pendingCreate.commandId,'original-create-id');
 }finally{EnvironmentSession.current=previous;}
});

const fullCatalog = {providers:[{instanceId:'p',enabled:true,installed:true,models:[{slug:'A',name:'A'},{slug:'B',name:'B'}]}]};
for(const cached of [[],[{instanceId:'p',model:'A'}]]) test(`a new task recovers both the project model and its options with ${cached.length} cached models`,async()=>{
 const p=new Fixture();p.models=cached;p.projects=[{id:'project',defaultModelSelection:{instanceId:'p',model:'B',options:[{id:'effort',value:'high'}]}}];
 p.chooseProject(0);assert.equal(p.modelIndex,-1);const rpc=EnvironmentSession.current.rpc;rpc.call=async()=>fullCatalog;
 await p.refreshCatalog(EnvironmentSession.current);assert.equal(p.models[p.modelIndex].model,'B');assert.deepEqual(p.selectedOptions,[{id:'effort',value:'high'}]);
});
test('a user choice made while the catalog is in flight wins, and changing projects returns to its defaults',async()=>{
 const p=new Fixture();p.projects=[{id:'p0',defaultModelSelection:{instanceId:'p',model:'B',options:[{id:'effort',value:'high'}]}}];p.models=[{instanceId:'p',model:'A'}];p.chooseProject(0);
 const pending=Promise.withResolvers();EnvironmentSession.current.rpc.call=()=>pending.promise;const updating=p.refreshCatalog(EnvironmentSession.current);
 p.selectModel({instanceId:'p',model:'A',options:[{id:'effort',value:'low'}]});pending.resolve(fullCatalog);await updating;
 assert.equal(p.models[p.modelIndex].model,'A');assert.equal(p.selectedOptions[0].value,'low');p.chooseProject(0);assert.equal(p.models[p.modelIndex].model,'B');assert.equal(p.selectedOptions[0].value,'high');
});

test('a project arriving after the model catalog restores its default without overwriting an explicit choice',async()=>{
 const p=new Fixture();p.projects=[];EnvironmentSession.current.rpc.call=async()=>fullCatalog;await p.refreshCatalog(EnvironmentSession.current);p.draftReady=true;
 p.projects=[{id:'later',defaultModelSelection:{instanceId:'p',model:'B',options:[{id:'effort',value:'high'}]}}];p.reconcileProject();assert.equal(p.models[p.modelIndex].model,'B');assert.equal(p.selectedOptions[0].value,'high');
 p.selectModel({instanceId:'p',model:'A'});p.reconcileProject();assert.equal(p.models[p.modelIndex].model,'A');assert.deepEqual(p.selectedOptions,[]);
});
