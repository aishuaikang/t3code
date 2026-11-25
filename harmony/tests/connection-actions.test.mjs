import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const source=readFileSync(process.env.T3_INDEX_SOURCE??new URL('../app/entry/src/main/ets/pages/Index.ets',import.meta.url),'utf8');
const method=(name,next)=>source.slice(source.indexOf('  private '+name),source.indexOf('  private '+next)).replace('private ','');
let hooks;
globalThis.__connectionActions={get:()=>hooks};
const body=`
const h=()=>globalThis.__connectionActions.get();const getContext=()=>({});
export const EnvironmentSession={current:null,homeGeneration:1};class ShellState{}
const AppStorage={setOrCreate(){}};const ComposerOutbox={disconnected(){}};
const connectDirectEnvironment=async(url,token)=>{h().requests.push({method:'direct',url,token});return {descriptor:{environmentId:'new'},matchesSaved:()=>false};};
const connectEnvironment=async(target,packageSpec)=>{h().requests.push({method:'ssh',target,packageSpec});return {descriptor:{environmentId:'new'},matchesSaved:()=>false};};
const readBearer=async()=> 'saved-bearer';const readSshCredentials=async()=>({bearer:'saved-bearer',password:'saved-password'});
const restoreDirectEnvironment=async()=>{h().requests.push({method:'restore'});if(h().restoring)await h().restoring;if(h().restoreError)throw Error(h().restoreError);return {descriptor:{environmentId:'new'},matchesSaved:()=>false,close:async()=>h().closed++};};
const restoreSshEnvironment=async(saved,credentials,status)=>{if(h().sshRestore)return h().sshRestore(saved,status);return restoreDirectEnvironment();};
const loadEnvironments=async()=>await h().saved??[];const forgetEnvironment=async()=>{await h().deletion;};
const AlertDialog={show(dialog){h().dialogs.push(dialog);}};
class Fixture {
 ${source.slice(source.indexOf('  private cancelRestoreTimer()'),source.indexOf('  private async reloadSaved()')).replaceAll('private ','')}
 pageGeneration=1;connectionAttempt=0;forgetting=false;saved=[];environmentFormOpen=false;foreground=true;retrySaved=null;restoreDelay=1000;restoreTimer=-1;
 connecting=false;status='';connected={matchesSaved:()=>false,close:async()=>await h().closing};direct=true;environmentUrl='http://intended.example';pairingToken='fixture-only';packageSpec='original-package';hostname='original-host';managingEnvironments=true;
 makeTarget(){return {hostname:this.hostname,pairingToken:this.pairingToken};}
 ${method('async disconnect()', 'openThread(')}
 ${method('openEnvironmentForm(', 'environmentBack()')}
 ${method('environmentBack()', 'async setEnvironmentEnabled(')}
 ${method('async setEnvironmentEnabled(', 'reconnectEnvironment(')}
 ${method('reconnectEnvironment(', 'orderSheet()').replace('@Builder','')}
 ${method('showingTaskList()', 'listProgressLabel()')}
 async reloadSaved(){}
 async loadThreads(){} async remember(){}
 ${method('async restoreLast()','cancelRestoreTimer()')}
 ${method('async connect()','async loadThreads()')}
 ${method('async restore(saved:','forget(saved:')}
 ${method('forget(saved:','makeTarget()')}
}
export default Fixture;
`;
const {default:Fixture,EnvironmentSession}=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(body)).toString('base64'));
function setup(){let release;EnvironmentSession.current=null;EnvironmentSession.homeGeneration=1;hooks={closed:0,requests:[],dialogs:[],closing:new Promise(r=>release=r),deletion:Promise.resolve()};return release;}
test('direct connection uses the URL, token and mode captured at click time while old connection closes',async()=>{
 const release=setup(),page=new Fixture();const pending=page.connect();
 page.environmentUrl='http://changed.example';page.pairingToken='changed-token';page.direct=false;
 release();await pending;
 assert.deepEqual(hooks.requests,[{method:'direct',url:'http://intended.example',token:'fixture-only'}]);
});
test('SSH connection freezes target and package before waiting for previous transport cleanup',async()=>{
 const release=setup(),page=new Fixture();page.direct=false;const pending=page.connect();
 page.hostname='changed-host';page.pairingToken='changed-token';page.packageSpec='changed-package';page.direct=true;
 release();await pending;
 assert.deepEqual(hooks.requests,[{method:'ssh',target:{hostname:'original-host',pairingToken:'fixture-only'},packageSpec:'original-package'}]);
});
test('pending credential deletion excludes connect, restore and another forget operation',async()=>{
 const close=setup();close();let release;hooks.deletion=new Promise(r=>release=r);
 const page=new Fixture(),saved={label:'fixture',environmentId:'env',httpBaseUrl:'http://fixture'};
 page.forget(saved);const deletion=hooks.dialogs[0].secondaryButton.action();
 await Promise.resolve();await page.connect();await page.restore(saved);page.forget(saved);
 assert.equal(hooks.dialogs.length,1);assert.deepEqual(hooks.requests,[]);
 release();await deletion;assert.equal(page.connecting,false);
});


test('restoring a saved environment clears transient credentials from a previous pairing form',async()=>{
 const release=setup();release();const page=new Fixture();page.password='previous-password';
 await page.restore({environmentId:'env',httpBaseUrl:'http://saved',label:'saved'});
 assert.equal(page.pairingToken,'');assert.equal(page.password,'');
});

test('failed saved connection recovers when the network returns without restarting the app',async t=>{
 t.mock.timers.enable({apis:['setTimeout']});const release=setup();release();const p=new Fixture();p.connected=null;
 const saved={environmentId:'env',httpBaseUrl:'http://saved',label:'saved'};
 hooks.restoreError='网络请求失败，请检查环境地址和连接';await p.restore(saved);assert.equal(p.retrySaved,saved);
 p.foreground=false;p.restoreVisibilityChanged();t.mock.timers.tick(60000);assert.equal(hooks.requests.length,1);
 p.foreground=true;p.restoreVisibilityChanged();for(let i=0;i<15;i++)await Promise.resolve();assert.equal(hooks.requests.length,2);
 hooks.restoreError='';t.mock.timers.tick(2000);for(let i=0;i<15;i++)await Promise.resolve();assert.ok(p.connected);assert.equal(hooks.requests.length,3);
});
test('a rejected saved credential does not trigger an automatic retry',async t=>{
 t.mock.timers.enable({apis:['setTimeout']});const release=setup();release();const p=new Fixture();p.connected=null;
 hooks.restoreError='环境请求失败（HTTP 401）';await p.restore({environmentId:'env',httpBaseUrl:'http://saved'});
 t.mock.timers.tick(60000);assert.equal(p.retrySaved,null);assert.equal(hooks.requests.length,1);
});

const savedA={environmentId:'a',httpBaseUrl:'http://old.example',label:'A'};
const drain=async()=>{for(let i=0;i<24;i++)await Promise.resolve()};
test('an open pairing form keeps its address, mode and credentials across foreground retries',async t=>{
 t.mock.timers.enable({apis:['setTimeout']});setup()();const page=new Fixture();page.connected=null;
 hooks.restoreError='网络请求失败';await page.restore(savedA);
 page.environmentFormOpen=true;page.direct=false;page.environmentUrl='http://new.example';page.pairingToken='B';page.password='B-secret';
 hooks.restoreError='';page.foreground=false;page.restoreVisibilityChanged();page.foreground=true;page.restoreVisibilityChanged();t.mock.timers.tick(20000);await drain();
 assert.equal(hooks.requests.length,1);assert.equal(page.environmentUrl,'http://new.example');assert.equal(page.direct,false);assert.equal(page.pairingToken,'B');assert.equal(page.password,'B-secret');
 page.environmentFormOpen=false;page.restoreVisibilityChanged();await drain();assert.equal(hooks.requests.length,2);assert.ok(page.connected);
});
for(const outcome of ['success','failure'])test(`a disposed home ignores a late restore ${outcome} and releases its own resources`,async t=>{
 t.mock.timers.enable({apis:['setTimeout']});setup()();const page=new Fixture();page.connected=null;
 let release,stopped=0;hooks.restoring=new Promise(r=>release=r);page.subscription={stop(){stopped++}};
 const pending=page.restore(savedA);await drain();assert.equal(hooks.requests.length,1);page.aboutToDisappear();
 const newer={descriptor:{environmentId:'b'}};EnvironmentSession.current=newer;
 if(outcome==='failure')hooks.restoreError='网络请求失败';release();await pending;t.mock.timers.tick(60000);await drain();
 assert.equal(stopped,1);assert.equal(EnvironmentSession.current,newer);assert.equal(page.connected,null);assert.equal(page.retrySaved,null);assert.equal(hooks.requests.length,1);assert.equal(hooks.closed,outcome==='success'?1:0);
});

test('a late cold-start saved-environment list cannot start a restore on a destroyed home',async()=>{
 setup()();const p=new Fixture();p.connected=null;const saved=Promise.withResolvers();hooks.saved=saved.promise;
 const loading=p.restoreLast();p.aboutToDisappear();saved.resolve([savedA]);await loading;assert.deepEqual(hooks.requests,[]);assert.equal(p.retrySaved,null);
});
test('closing a former home never clears a replacement connection, including after slow transport cleanup',async()=>{
 setup()();const p=new Fixture(),closing=Promise.withResolvers(),old={close:()=>closing.promise};p.connected=old;EnvironmentSession.current=old;
 const pending=p.disconnect();const next={descriptor:{environmentId:'b'}};EnvironmentSession.current=next;closing.resolve();await pending;assert.equal(EnvironmentSession.current,next);
 p.connected=old;p.aboutToDisappear();await drain();assert.equal(EnvironmentSession.current,next);
});

const sshRoute = port => ({environmentId:'shared', connectionId:`ssh-${port}`, label:'Shared · SSH',
  ssh:{hostname:'gateway',username:'user',port,serverPort:3773}});
const routeA=sshRoute(22),routeB=sshRoute(2222);
function setupRoutes() {
  setup()();const page=new Fixture();page.connected=null;page.saved=[routeA,routeB];
  const calls=[],closed=[];
  hooks.sshRestore=(saved,status)=>{
    const gate=Promise.withResolvers();calls.push({saved,status,gate});
    return gate.promise.then(()=>({descriptor:{environmentId:saved.environmentId},matchesSaved:r=>r.connectionId===saved.connectionId,
      close:async()=>{closed.push(saved.connectionId);}}));
  };
  return {page,calls,closed};
}
for(const outcome of ['success','failure']) test(`opening Add while restoring keeps the editable form after a late ${outcome}`,async()=>{
  const {page,calls,closed}=setupRoutes();const first=page.restore(routeA);await drain();
  page.openEnvironmentForm();page.hostname='new-gateway';page.pairingToken='new-token';page.password='new-password';
  calls[0].status('old status');if(outcome==='success')calls[0].gate.resolve();else calls[0].gate.reject(Error('socket timeout'));
  await first;assert.equal(page.environmentFormOpen,true);assert.equal(page.managingEnvironments,true);assert.equal(page.connecting,false);
  assert.equal(page.hostname,'new-gateway');assert.equal(page.pairingToken,'new-token');assert.equal(page.password,'new-password');
  assert.equal(page.status,'');assert.equal(page.connected,null);assert.deepEqual(closed,outcome==='success'?[routeA.connectionId]:[]);
  page.environmentBack();await drain();assert.deepEqual(calls.map(c=>c.saved),[routeA,routeA]);calls[1].gate.resolve();await drain();
});
for(const oldFinishesFirst of [true,false]) test(`selecting another SSH route for the same environment wins (old finishes first: ${oldFinishesFirst})`,async()=>{
  const {page,calls,closed}=setupRoutes();const first=page.restore(routeA);await drain();
  const second=page.setEnvironmentEnabled(routeB,true);await drain();assert.deepEqual(calls.map(c=>c.saved),[routeA,routeB]);
  if(oldFinishesFirst){calls[0].gate.resolve();await first;assert.equal(page.connecting,true);assert.equal(page.restoringConnectionId,routeB.connectionId);}
  calls[1].gate.resolve();await second;
  if(!oldFinishesFirst){calls[0].status('obsolete');calls[0].gate.resolve();await first;}
  assert.equal(page.connected.matchesSaved(routeB),true);assert.equal(EnvironmentSession.current,page.connected);
  assert.deepEqual(closed,[routeA.connectionId]);assert.equal(page.retrySaved,null);assert.equal(page.managingEnvironments,true);
});
test('deleting one saved SSH route leaves its sibling eligible for automatic reconnect',async()=>{
  const {page}=setupRoutes();page.retrySaved=routeB;page.foreground=false;page.forget(routeA);
  await hooks.dialogs[0].secondaryButton.action();assert.equal(page.retrySaved,routeB);
});
test('late cold-start lookup cannot replace a route explicitly selected while reading the saved list',async()=>{
  const {page,calls}=setupRoutes();const list=Promise.withResolvers();hooks.saved=list.promise;const initial=page.restoreLast();
  const selected=page.setEnvironmentEnabled(routeB,true);await drain();list.resolve([routeA]);await initial;
  assert.deepEqual(calls.map(c=>c.saved),[routeB]);assert.equal(page.connecting,true);calls[0].gate.resolve();await selected;
  assert.equal(page.connected.matchesSaved(routeB),true);
});

test('cold start prefers primary over a more recently used backup; a network failure uses only a sibling of that environment',async()=>{
 const {page,calls}=setupRoutes();const main={...routeA,sshRole:'primary'},backup={...routeB,sshRole:'backup'};
 hooks.saved=[backup,{...sshRoute(42),environmentId:'another',sshRole:'primary'},main];
 const start=page.restoreLast();await drain();assert.deepEqual(calls.map(c=>c.saved),[main]);
 calls[0].gate.reject(Error('tcp connect failed'));await drain();assert.deepEqual(calls.map(c=>c.saved),[main,backup]);
 calls[1].gate.resolve();await start;assert.ok(page.connected.matchesSaved(backup));
});
for(const reason of ['fingerprint mismatch','authentication failed','环境 ID 不匹配','环境请求失败（HTTP 401）'])test(`an identity or authentication error stops SSH failover: ${reason}`,async()=>{
 const {page,calls}=setupRoutes();const start=page.restore(routeA);await drain();calls[0].gate.reject(Error(reason));await start;
 assert.deepEqual(calls.map(c=>c.saved),[routeA]);assert.equal(page.retrySaved,null);assert.ok(page.status.includes(reason));
});
test('a failed sweep tries each SSH route once before backing off and a later manual selection cancels background retry',async t=>{
 t.mock.timers.enable({apis:['setTimeout']});const {page,calls}=setupRoutes();const start=page.restore(routeA);await drain();calls[0].gate.reject(Error('socket timeout'));await drain();
 assert.equal(calls[1]?.saved,routeB);calls[1].gate.reject(Error('tcp connect failed'));await start;assert.equal(page.retrySaved,routeA);
 const manual=page.restore(routeB);await drain();calls[2].gate.resolve();await manual;t.mock.timers.tick(60000);await drain();
 assert.equal(calls.length,3);assert.ok(page.connected.matchesSaved(routeB));
});

test('opening environment management while a restore is in flight keeps the list open when the route connects',async()=>{
 const {page,calls}=setupRoutes();page.managingEnvironments=false;const opening=page.restore(routeA);await drain();
 page.managingEnvironments=true;calls[0].gate.resolve();await opening;assert.equal(page.managingEnvironments,true);
});

for (const [label, remaining, visible] of [
  ['last route', [], false], ['another environment', [savedA], false], ['SSH backup', [routeB], true],
  ['direct route to the same environment', [{environmentId:routeA.environmentId,httpBaseUrl:'http://same'}], true]
]) test(`forgetting an offline route updates the cached task list: ${label}`, async () => {
  setup()();const page=new Fixture();page.connected=null;page.cached=true;page.cacheEnvironmentId=routeA.environmentId;
  page.managingEnvironments=false;page.restoringConnectionId='';page.saved=[routeA,...remaining];page.threads=[{id:'cached-task'}];
  page.forget(routeA);await hooks.dialogs[0].secondaryButton.action();
  assert.deepEqual(page.saved,remaining);assert.equal(page.showingTaskList(),visible);assert.equal(page.cacheEnvironmentId,visible?routeA.environmentId:'');
  assert.deepEqual(page.threads,visible?[{id:'cached-task'}]:[]);
});

test('forgetting the active SSH route reconnects only its remaining sibling when foregrounded',async()=>{
 const {page,calls}=setupRoutes();const active={matchesSaved:r=>r.connectionId===routeA.connectionId,close:async()=>{}};
 page.connected=active;EnvironmentSession.current=active;page.foreground=false;
 page.forget(routeA);await hooks.dialogs[0].secondaryButton.action();
 assert.equal(page.connected,null);assert.equal(page.retrySaved,routeB);assert.equal(calls.length,0);
 page.foreground=true;page.restoreVisibilityChanged();await drain();assert.deepEqual(calls.map(c=>c.saved),[routeB]);
 calls[0].gate.resolve();await drain();assert.ok(page.connected.matchesSaved(routeB));
});
test('a failed credential deletion leaves the current route available',async()=>{
 setup()();const page=new Fixture(),active={matchesSaved:()=>true,close:async()=>{throw Error('should stay connected')}};
 page.connected=active;page.saved=[routeA];hooks.deletion=Promise.reject(Error('locked'));
 page.forget(routeA);await hooks.dialogs[0].secondaryButton.action();
 assert.equal(page.connected,active);assert.deepEqual(page.saved,[routeA]);assert.match(page.status,/无法删除/);
});
