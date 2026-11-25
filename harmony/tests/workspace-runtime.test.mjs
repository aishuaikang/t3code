import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
const read=path=>readFileSync(new URL(path,import.meta.url),'utf8');
const load=source=>import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
const actions=await load(read('../app/entry/src/main/ets/model/WorkspaceActions.ets').replace(/^import .*;\n/gm,''));
globalThis.__workspaceRuntimeActions=actions;
function method(source,start,end){return source.slice(source.indexOf(start),source.indexOf(end)).replaceAll('private ','')}
const scripts=read('../app/entry/src/main/ets/pages/ProjectScripts.ets');
const git=read('../app/entry/src/main/ets/pages/WorkspaceGit.ets');
const {ScriptPage,GitPage,EnvironmentSession}=await load(`
const {resolveProjectScripts,projectScriptsPatch,upsertProjectScript,workspaceGitRequest,workspaceGitDisabled}=globalThis.__workspaceRuntimeActions;
const util={generateRandomUUID:()=> 'unique-id'};class EmptyPayload{};
export const EnvironmentSession={current:null};
export class ScriptPage {
 active=true;busy=false;disabled=false;project={id:'p',title:'Project',workspaceRoot:'/repo',scripts:[]};threadId='t';worktreePath='/worktree';rpc=null;
 editId='';deleteId='';name='Dev';command='pnpm dev';icon='play';setup=false;scripts=[];editing=true;terminalId='';error='';
 getRpc(){return this.rpc}onTerminal(id){this.opened=id}
 ${method(scripts,'  private async save(', '  build()')}
}
export class GitPage {
 active=true;busy=false;disabled=false;branchDisabled=false;threadId='t';projectId='p';cwd='/worktree';worktreePath='/worktree';rpc=null;revision=0;
 status={isRepo:true,hasPrimaryRemote:true,isDefaultRef:false,hasWorkingTreeChanges:true};action='commit_push_pr';message='';featureBranch=true;expanded=true;error='';refreshes=0;
 getRpc(){return this.rpc}disabledReason(){return this.branchDisabled?'running':workspaceGitDisabled(this.status,this.action,this.featureBranch)}refresh(){this.refreshes++}
 ${method(git,'  private async run(', '  private openAction(')}
}
`);
const script=(id,extra={})=>({id,name:id,command:'echo '+id,icon:'play',runOnWorktreeCreate:false,...extra});
function setup(Page){const page=new Page(),calls=[];EnvironmentSession.current={descriptor:{environmentId:'env'}};return {page,calls}}
test('script save merges with the latest PC settings and keeps another script added while the sheet was open',async()=>{
 const {page,calls}=setup(ScriptPage);
 page.editId='dev';
 page.rpc={call:async(tag,input)=>{
  calls.push({tag,input});
  if(tag==='server.getSettings')return {projectSettingsOverrides:{p:{theme:'dark',defaultProjectScripts:[script('dev',{previewUrl:'http://localhost:3000'}),script('added-on-pc')]}}};
  if(tag==='server.getConfig')return {environment:{capabilities:{projectSettingsOverrides:true}}};
  return {};
 }};
 await page.save();assert.equal(page.error,'');
 const entry=calls.find(c=>c.tag==='server.updateSettings').input.patch.projectSettingsOverrides.p;
 assert.equal(entry.theme,'dark');assert.deepEqual(entry.defaultProjectScripts.map(s=>s.id),['dev','added-on-pc']);
 assert.equal(entry.defaultProjectScripts[0].previewUrl,'http://localhost:3000');assert.equal(page.editing,false);
});
test('script deletion removes only the selected id from the latest shared list',async()=>{
 const {page,calls}=setup(ScriptPage);page.deleteId='delete';
 page.rpc={call:async(tag,input)=>{
  calls.push({tag,input});
  if(tag==='server.getSettings')return {projectScriptOverrides:{p:[script('delete'),script('keep')]}};
  if(tag==='server.getConfig')return {environment:{capabilities:{}}};return {};
 }};
 await page.save(true);assert.deepEqual(calls.at(-1).input.patch.projectScriptOverrides.p.map(s=>s.id),['keep']);
});
test('script execution opens its own terminal with the worktree environment and writes exactly once',async()=>{
 const {page,calls}=setup(ScriptPage);page.rpc={call:async(tag,input)=>{calls.push({tag,input});return {}}};
 await page.run(script('dev',{command:'pnpm dev'}));
 assert.equal(calls[0].tag,'terminal.open');assert.equal(calls[0].input.cwd,'/repo');assert.equal(calls[0].input.worktreePath,'/worktree');
 assert.deepEqual(calls[0].input.env,{T3CODE_PROJECT_ROOT:'/repo',T3CODE_WORKTREE_PATH:'/worktree'});
 assert.deepEqual(calls[1],{tag:'terminal.write',input:{threadId:'t',terminalId:'script-unique-id',data:' pnpm dev\r'}});
 assert.equal(calls.length,2);assert.equal(page.opened,'script-unique-id');
});
test('leaving the script page during terminal creation never dispatches its command',async()=>{
 const {page,calls}=setup(ScriptPage);let resolve;
 page.rpc={call:(tag,input)=>{calls.push({tag,input});return new Promise(yes=>{resolve=yes})}};
 const pending=page.run(script('dev'));page.active=false;resolve({});await pending;
 assert.equal(calls.length,1);assert.equal(page.opened,undefined);
});
test('an unconfirmed terminal write remains inspectable and is not replayed automatically',async()=>{
 const {page,calls}=setup(ScriptPage);page.rpc={call:async(tag,input)=>{calls.push({tag,input});if(tag==='terminal.write')throw Error('connection closed');return {}}};
 await page.run(script('dev'));assert.match(page.error,/先查看终端/);assert.equal(page.terminalId,'script-unique-id');assert.equal(calls.length,2);
});
test('Git workflow persists a newly created branch to the same thread without sending chat messages',async()=>{
 const {page,calls}=setup(GitPage);page.rpc={call:async(tag,input)=>{calls.push({tag,input});return {branch:{status:'created',name:'feature/new'},pr:{url:'https://github.com/team/repo/pull/5'}}}};
 await page.run();assert.equal(page.error,'');assert.equal(calls[0].tag,'git.runStackedAction');assert.equal(calls[0].input.featureBranch,true);
 assert.deepEqual(calls[1],{tag:'orchestration.dispatchCommand',input:{type:'thread.metadata.update',commandId:'unique-id',threadId:'t',branch:'feature/new',worktreePath:'/worktree'}});
 assert.equal(page.resultUrl,'https://github.com/team/repo/pull/5');assert.equal(page.refreshes,1);
});
test('a Git result from another environment never updates this thread metadata',async()=>{
 const {page,calls}=setup(GitPage);let resolve;
 page.rpc={call:(tag,input)=>{calls.push({tag,input});return new Promise(yes=>{resolve=yes})}};
 const pending=page.run();EnvironmentSession.current={descriptor:{environmentId:'other'}};
 resolve({branch:{status:'created',name:'wrong'},pr:{}});await pending;
 assert.equal(calls.length,1);assert.equal(page.refreshes,0);
});
test('running tasks and a protected default branch cannot dispatch Git workflows',async()=>{
 for(const change of [{branchDisabled:true},{status:{isRepo:true,hasPrimaryRemote:true,isDefaultRef:true},featureBranch:false}]){
  const {page,calls}=setup(GitPage);Object.assign(page,change);page.rpc={call:async(...args)=>calls.push(args)};
  await page.run();assert.equal(calls.length,0);
 }
});
