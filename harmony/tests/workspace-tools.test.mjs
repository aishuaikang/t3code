import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
const source=readFileSync(new URL('../app/entry/src/main/ets/model/WorkspaceActions.ets',import.meta.url),'utf8').replace(/^import .*;\n/gm,'');
const {resolveProjectScripts,projectScriptsPatch,upsertProjectScript,workspaceGitRequest,workspaceGitDisabled}=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
const script=(id,extra={})=>({id,name:id,command:'echo '+id,icon:'play',runOnWorktreeCreate:false,...extra});
test('project script resolution matches PC precedence, including explicit empty overrides',()=>{
 const project={id:'p',scripts:[script('project')]}, settings={defaultProjectScripts:[script('default')],projectScriptOverrides:{},projectSettingsOverrides:{}};
 assert.equal(resolveProjectScripts(settings,project)[0].id,'project');
 settings.projectScriptOverrides.p=null;assert.equal(resolveProjectScripts(settings,project)[0].id,'default');
 settings.projectSettingsFolded=true;settings.projectScriptOverrides.p=[script('legacy')];assert.equal(resolveProjectScripts(settings,project)[0].id,'default');
 settings.projectSettingsOverrides.p={defaultProjectScripts:[]};assert.deepEqual(resolveProjectScripts(settings,project),[]);
 settings.projectSettingsOverrides.p.defaultProjectScripts=[script('modern')];assert.equal(resolveProjectScripts(settings,project)[0].id,'modern');
});
test('script writes preserve unrelated project settings and target only the selected project',()=>{
 const settings={projectSettingsOverrides:{p:{theme:'dark',customValue:5},other:{theme:'light'}}}, next=[script('new')];
 assert.deepEqual(projectScriptsPatch(settings,'p',next,true),{patch:{projectSettingsOverrides:{p:{theme:'dark',customValue:5,defaultProjectScripts:next}}}});
 assert.deepEqual(projectScriptsPatch(settings,'p',next,false),{patch:{projectScriptOverrides:{p:next}}});
 assert.equal(settings.projectSettingsOverrides.p.defaultProjectScripts,undefined);
});
test('editing script text preserves preview and settle behavior; claiming setup releases the previous setup script',()=>{
 const original=script('a',{previewUrl:'http://localhost:3000',runOnSettle:true,stopOnSettle:true,async:false});
 const changed={...original,name:'Updated',command:'pnpm dev',runOnWorktreeCreate:true};
 const result=upsertProjectScript([script('setup',{runOnWorktreeCreate:true}),original],changed);
 assert.equal(result[0].runOnWorktreeCreate,false);assert.equal(result[1].previewUrl,original.previewUrl);
 assert.equal(result[1].stopOnSettle,true);assert.equal(result[1].async,false);assert.equal(original.runOnWorktreeCreate,false);
});
test('git actions use the server workflow contract and omit an empty commit message',()=>{
 assert.deepEqual(workspaceGitRequest('commit_push_pr','action','/repo','t','p','   ',true),{actionId:'action',cwd:'/repo',action:'commit_push_pr',threadId:'t',projectId:'p',featureBranch:true});
 assert.equal(workspaceGitRequest('commit','id','/repo','t','p','Fix bug',false).commitMessage,'Fix bug');
});
test('git publishing availability follows repository status and never permits publishing an unchanged default branch',()=>{
 const status={isRepo:true,hasPrimaryRemote:true,isDefaultRef:false,hasWorkingTreeChanges:true};
 assert.equal(workspaceGitDisabled(status,'commit',false),'');
 assert.equal(workspaceGitDisabled({...status,hasWorkingTreeChanges:false},'commit',false),'没有可提交的改动');
 assert.equal(workspaceGitDisabled({...status,hasPrimaryRemote:false},'create_pr',false),'当前仓库没有远程地址');
 assert.equal(workspaceGitDisabled({...status,isDefaultRef:true},'commit_push_pr',false),'请先切换分支，或选择在新分支上发布');
 assert.equal(workspaceGitDisabled({...status,isDefaultRef:true},'commit_push_pr',true),'');
});
