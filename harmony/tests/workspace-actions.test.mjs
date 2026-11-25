import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
const load=source=>import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
const {pullRequestLink,validBranchName}=await load(readFileSync(new URL('../app/entry/src/main/ets/model/WorkspaceActions.ets',import.meta.url),'utf8').replace(/^import .*;\n/gm,''));
test('resolved pull request links retain their host, port, repository and number',()=>{
 assert.deepEqual(pullRequestLink('https://github.com/Team/Repo/pull/123/files'),{host:'github.com',repository:'team/repo',number:123,url:'https://github.com/Team/Repo/pull/123',source:'manual'});
 for(const url of ['https://gitlab.com/team/nested/repo/-/merge_requests/7','http://forge.example:3000/team/repo/pulls/7','https://bitbucket.org/team/repo/pull-requests/7']){
  const link=pullRequestLink(url);assert.equal(link.number,7);assert.ok(link.url.startsWith(url));
 }
 for(const url of ['https://github.com/team/repo/pull/0','https://github.com/team/repo/pull/9007199254740992','https://user@github.com/team/repo/pull/1','javascript:bad','https://host/team/../pull/1'])assert.equal(pullRequestLink(url),null);
});
test('branch entry follows Git ref name rules without rejecting Unicode or nested branch names',()=>{
 for(const name of ['feature/cache','fix-123','修复/滚动','t3/harmony-1'])assert.equal(validBranchName(name),true,name);
 for(const name of ['', '-bad', '@', 'a..b','a@{b','a b','a:b','a?b','a[b','a\\b','a/','a//b','.hidden','a/.b','a.lock','a/b.lock','bad.'])assert.equal(validBranchName(name),false,name);
});
const {ThreadState}=await load(readFileSync(new URL('../app/entry/src/main/ets/model/Models.ets',import.meta.url),'utf8'));
test('pull request link, update and unlink markers stay in sync with the event cursor',()=>{
 const state=new ThreadState();state.restoreCached({id:'t',title:'Task',messages:[],syncSequence:1,transcriptVersion:6});
 const link=pullRequestLink('https://github.com/team/repo/pull/1');
 for(const [sequence,source] of [[2,'manual'],[3,'stack-dismissed']]){
  state.apply({kind:'event',sequence,event:{threadId:'t',type:'thread.pull-request-link-updated',payload:{...link,source}}});
  assert.equal(state.thread.pullRequests.length,1);assert.equal(state.thread.pullRequests[0].source,source);assert.equal(state.cursor(),sequence);
 }
});
globalThis.__workspaceActions={pullRequestLink,validBranchName};
const workspace=readFileSync(new URL('../app/entry/src/main/ets/pages/WorkspaceContext.ets',import.meta.url),'utf8');
const method=workspace.slice(workspace.indexOf('  private async submitAction('),workspace.indexOf('  private async unlink(')).replaceAll('private ','');
const {ActionPage,EnvironmentSession}=await load(`
const {pullRequestLink,validBranchName}=globalThis.__workspaceActions;const util={generateRandomUUID:()=> 'command-id'};const WS={threadStartTurn:'dispatch'};
export const EnvironmentSession={current:{rpc:{call:(...args)=>globalThis.__workspaceCall(...args)}}};
export class ActionPage {cwd='/repo';threadId='t';disabled=false;branchDisabled=false;actionBusy=false;actionView='branch';actionInput='feature/ui';selectedBranch='main';currentBranch='main';sheetOpen=true;error='';
 getRpc(){return EnvironmentSession.current.rpc}loadRefs(){}onBranch(ref){this.selected=ref}${method}}
`);
test('branch creation preserves the checkout until the parent task accepts its new ref',async()=>{
 const calls=[];globalThis.__workspaceCall=async(tag,input)=>{calls.push({tag,...input});return tag==='vcs.listRefs'?{isRepo:true,refs:[]}:{refName:input.refName}};
 const page=new ActionPage();await page.submitAction();
 assert.equal(calls[1].tag,'vcs.createRef');assert.equal(calls[1].switchRef,false);assert.equal(page.selected.name,'feature/ui');
 const other=new ActionPage();other.branchDisabled=true;await other.submitAction();assert.equal(calls.length,2);
});
test('retrying a lost worktree receipt reuses its existing directory',async()=>{
 let created=false,creates=0;globalThis.__workspaceCall=async(tag,input)=>{
  if(tag==='vcs.listRefs')return {isRepo:true,refs:created?[{name:'feature/ui',worktreePath:'/worktree',current:false}]:[]};
  if(tag==='vcs.createWorktree'){created=true;creates++;throw Error('lost response')}
 };
 const page=new ActionPage();page.actionView='worktree';await page.submitAction();assert.match(page.error,/lost/);
 await page.submitAction();assert.equal(creates,1);assert.equal(page.selected.worktreePath,'/worktree');
});
test('PR numbers resolve against the current repository before emitting a link command',async()=>{
 const calls=[];globalThis.__workspaceCall=async(tag,input)=>{calls.push({tag,...input});return {pullRequest:{url:'https://github.com/team/repo/pull/42'}}};
 const page=new ActionPage();page.actionView='link';page.actionInput='#42';await page.submitAction();
 assert.deepEqual(calls[0],{tag:'git.resolvePullRequest',cwd:'/repo',reference:'#42'});
 assert.equal(calls[1].type,'thread.pull-request.link');assert.equal(calls[1].number,42);assert.equal(calls[1].threadId,'t');
});
