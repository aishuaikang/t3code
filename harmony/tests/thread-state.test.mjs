import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
const path = new URL('../app/entry/src/main/ets/model/Models.ets', import.meta.url);
const model = await import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(readFileSync(path, 'utf8'))).toString('base64'));

test('shell subscription replaces snapshots and applies upserts/removals', () => {
  const state = new model.ShellState();
  state.apply({ kind: 'snapshot', snapshot: { snapshotSequence: 3, projects: [], threads: [{id:'t',title:'old'}] } });
  state.apply({ kind: 'thread-upserted', sequence: 4, thread: {id:'t',title:'new'} });
  state.apply({ kind: 'thread-upserted', sequence: 2, thread: {id:'t',title:'stale'} });
  assert.equal(state.threads[0].title, 'new');
  state.apply({ kind: 'thread-removed', sequence: 5, threadId:'t' });
  assert.deepEqual(state.threads, []);
});

test('repository enrichment preserves tasks and project metadata without advancing the live cursor', () => {
  const state = new model.ShellState();
  state.apply({kind:'snapshot',snapshot:{snapshotSequence:3,threads:[{id:'t',title:'Task'}],projects:[
    {id:'p',title:'Current name',workspaceRoot:'/p'}, {id:'q',title:'Other',workspaceRoot:'/q'}]}});
  state.apply({kind:'snapshot',resolvedRepositoryIdentityRoots:['/p'],snapshot:{snapshotSequence:8,
    threads:[],archivedThreads:[],projects:[{id:'p',title:'Old name',workspaceRoot:'/p',repositoryIdentity:{canonicalKey:'repo'}}]}});
  assert.deepEqual(state.threads.map(t=>t.id),['t']);
  assert.deepEqual(state.projects.map(p=>p.id),['p','q']);
  assert.equal(state.projects[0].title,'Current name');
  assert.equal(state.projects[0].repositoryIdentity.canonicalKey,'repo');
  state.apply({kind:'thread.updated',location:'active',sequence:4,thread:{id:'t',title:'Live task'}});
  assert.equal(state.threads[0].title,'Live task');
  state.apply({kind:'snapshot',snapshot:{snapshotSequence:2,threads:[],projects:[]}});
  assert.equal(state.threads[0].title,'Live task');
});

test('current shell events update active tasks and projects without mixing in archive events', () => {
  const state = new model.ShellState();
  state.apply({kind:'snapshot',snapshot:{snapshotSequence:1,threads:[{id:'t',title:'Task'}],projects:[]}});
  state.apply({kind:'thread.updated',location:'archive',sequence:3,thread:{id:'archived'}});
  state.apply({kind:'thread.updated',location:'active',sequence:2,thread:{id:'t',title:'Updated'}});
  assert.deepEqual(state.threads.map(t=>t.title),['Updated']);
  state.apply({kind:'project.updated',sequence:4,project:{id:'p',title:'Project'}});
  assert.equal(state.projects[0].title,'Project');
  state.apply({kind:'project.removed',sequence:5,projectId:'p'});
  state.apply({kind:'thread.removed',location:'active',sequence:6,threadId:'t'});
  assert.deepEqual(state.projects,[]);assert.deepEqual(state.threads,[]);
});

test('current thread projection and message events load history and replace streamed message bodies', () => {
  const state = new model.ThreadState();
  const thread = {id:'t',projectId:'p',title:'History',runtimeMode:'auto',interactionMode:'default'};
  const message = {id:'m',threadId:'t',runId:'r',role:'assistant',text:'Hello',streaming:true,createdAt:'01',updatedAt:'02',attachments:[]};
  const run = {id:'r',threadId:'t',ordinal:1,status:'running',requestedAt:'01',startedAt:'02',completedAt:null};
  state.apply({kind:'snapshot',snapshotSequence:5,projection:{thread,messages:[message],runs:[run]}});
  assert.equal(state.thread.title,'History');assert.equal(state.messages[0].text,'Hello');
  assert.equal(state.messages[0].turnId,'r');assert.equal(state.thread.session.activeTurnId,'r');
  const update = {kind:'event',sequence:6,event:{type:'message.updated',threadId:'t',payload:{...message,text:'Hello world',streaming:false,updatedAt:'03'}}};
  state.apply(update);state.apply(update);
  assert.equal(state.messages[0].text,'Hello world');assert.equal(state.messages.length,1);
  assert.equal(state.messages[0].streaming,false);
  state.apply({kind:'event',sequence:7,event:{type:'run.updated',threadId:'t',payload:{...run,status:'completed',completedAt:'04'}}});
  assert.equal(state.thread.session.status,'ready');assert.equal(state.thread.latestTurn.state,'completed');
  state.apply({kind:'event',sequence:8,event:{type:'thread.metadata-updated',threadId:'t',payload:{...thread,title:'Renamed'}}});
  assert.equal(state.thread.title,'Renamed');assert.equal(state.messages.length,1);
  state.apply({kind:'event',sequence:9,event:{type:'message.updated',threadId:'other',payload:{...message,text:'Wrong task'}}});
  state.apply({kind:'snapshot',snapshotSequence:4,projection:{thread,messages:[],runs:[]}});
  assert.equal(state.messages[0].text,'Hello world');
});
test('persisted history resumes only missing events without losing earlier runs or moving existing records',()=>{
 const state=new model.ThreadState();
 state.restoreCached({id:'t',syncSequence:10,transcriptVersion:6,messages:[{id:'a',role:'assistant',text:'Old reply',turnId:'old',timelinePosition:10},
  {id:'thought',role:'reasoning',text:'Thinking',turnId:'active',timelinePosition:11}],
  activities:[{id:'cmd',kind:'tool.updated',summary:'first',turnId:'active',createdAt:'now',timelinePosition:12}],
  turns:[{turnId:'old',state:'completed',ordinal:1},{turnId:'active',state:'running',ordinal:2}],session:{status:'running',activeTurnId:'active'}});
 assert.equal(state.cursor(),10);
 state.apply({kind:'event',sequence:11,event:{threadId:'t',type:'turn-item.updated',payload:{id:'thought',type:'reasoning',runId:'active',text:'Updated thought',status:'completed',updatedAt:'later'}}});
 state.apply({kind:'event',sequence:12,event:{threadId:'t',type:'run.updated',payload:{id:'active',ordinal:2,status:'completed',requestedAt:'now',completedAt:'later'}}});
 assert.equal(state.thread.turns.length,2);assert.equal(state.messages.find(m=>m.id==='a').text,'Old reply');
 assert.equal(state.messages.find(m=>m.id==='thought').timelinePosition,11);assert.equal(state.cursor(),12);
 state.apply({kind:'event',sequence:13,event:{threadId:'t',type:'turn-item.updated',payload:{id:'new',type:'command_execution',runId:'active',status:'running',input:'next',updatedAt:'later'}}});
 assert.equal(state.activities.find(a=>a.id==='new').timelinePosition,13);
 state.apply({kind:'snapshot',snapshotSequence:20,projection:{thread:{id:'t',title:'Snapshot fallback'},messages:[],runs:[]}});
 assert.equal(state.cursor(),20);assert.equal(state.messages.length,0);
 const legacy=new model.ThreadState();legacy.restoreCached({id:'t',messages:[]});assert.equal(legacy.cursor(),null);
});

test('requiring a fresh snapshot preserves visible history but resets ordering and invalidates older history loads', () => {
 const state=new model.ThreadState();
 state.restoreCached({id:'t',title:'Cached',messages:[{id:'m',text:'Cached'}],syncSequence:10,transcriptVersion:2,
   historyCursor:'older',hasMoreHistory:true});
 state.applyShell({kind:'thread.updated',sequence:11,thread:{id:'t',title:'Old session metadata'}},'t');
 const epoch=state.historyVersion();
 state.requireSnapshot();
 assert.equal(state.cursor(),null);assert.equal(state.messages[0].text,'Cached');
 assert.equal(state.mergeHistory({snapshotSequence:9,items:[],nextCursor:null,hasMoreHistory:false},'older',epoch),false);
 state.apply({kind:'snapshot',snapshotSequence:4,projection:{thread:{id:'t',title:'Fresh session'},
   messages:[{id:'new',text:'Current'}],runs:[]}});
 assert.equal(state.cursor(),4);assert.equal(state.thread.title,'Fresh session');assert.equal(state.messages[0].text,'Current');
 state.apply({kind:'snapshot',snapshotSequence:3,projection:{thread:{id:'t',title:'Delayed'},messages:[],runs:[]}});
 assert.equal(state.thread.title,'Fresh session');
});

test('current shell metadata reaches an open task after an enrichment patch', () => {
  const state = new model.ThreadState();
  state.apply({kind:'snapshot',snapshotSequence:1,projection:{thread:{id:'t',title:'Task'},messages:[],runs:[]}});
  state.applyShell({kind:'snapshot',resolvedRepositoryIdentityRoots:['/p'],snapshot:{snapshotSequence:9,threads:[],projects:[]}},'t');
  state.applyShell({kind:'thread.updated',location:'active',sequence:2,thread:{id:'t',title:'Updated',runtimeMode:'auto',interactionMode:'plan'}},'t');
  assert.equal(state.thread.title,'Updated');assert.equal(state.thread.interactionMode,'plan');
});

test('metadata arriving on separate subscriptions respects event order', () => {
  const state = new model.ThreadState();
  const thread = {id:'t',title:'Initial',runtimeMode:'full-access',interactionMode:'default'};
  state.apply({kind:'snapshot',snapshotSequence:1,projection:{thread,messages:[],runs:[]}});
  state.applyShell({kind:'thread.updated',location:'active',sequence:3,thread:{...thread,title:'Shell',runtimeMode:'auto'}},'t');
  state.apply({kind:'event',sequence:2,event:{type:'thread.metadata-updated',threadId:'t',payload:{...thread,title:'Older detail'}}});
  assert.equal(state.thread.title,'Shell');assert.equal(state.thread.runtimeMode,'auto');
  state.apply({kind:'event',sequence:4,event:{type:'thread.runtime-mode-updated',threadId:'t',payload:{...thread,title:'New detail',runtimeMode:'approval-required'}}});
  state.applyShell({kind:'thread.updated',location:'active',sequence:3,thread:{...thread,title:'Older shell'}},'t');
  assert.equal(state.thread.title,'New detail');assert.equal(state.thread.runtimeMode,'approval-required');
});

test('thread snapshot and streaming deltas are deduplicated by sequence', () => {
  const state = new model.ThreadState();
  state.apply({kind:'snapshot',snapshot:{snapshotSequence:2,thread:{id:'t',messages:[{id:'m',role:'assistant',text:'hello',streaming:true}]}}});
  const event = {kind:'event',event:{sequence:3,type:'thread.message-sent',payload:{threadId:'t',messageId:'m',role:'assistant',text:' world',streaming:true}}};
  state.apply(event); state.apply(event);
  assert.equal(state.messages[0].text, 'hello world');
  state.apply({kind:'event',event:{sequence:4,type:'thread.message-sent',payload:{threadId:'t',messageId:'m',role:'assistant',text:'',streaming:false}}});
  assert.equal(state.messages[0].text, 'hello world');
  assert.equal(state.messages[0].streaming, false);
});

test('turn submission uses existing thread modes and server command shape', () => {
  const thread = {id:'t',runtimeMode:'approval-required',interactionMode:'plan'};
  const cmd = model.startTurnCommand(thread, 'hello', 'cmd-id', 'message-id', '2026-09-07T00:00:00.000Z');
  assert.equal(cmd.type, 'thread.turn.start');
  assert.equal(cmd.threadId, 't');
  assert.deepEqual(cmd.message, {messageId:'message-id',role:'user',text:'hello',attachments:[]});
  assert.equal(cmd.runtimeMode, 'approval-required');
  assert.equal(cmd.interactionMode, 'plan');
});

test('tracks ready checkpoints for the full-thread diff request',()=>{
 const state=new model.ThreadState();
 state.apply({kind:'snapshot',snapshot:{snapshotSequence:1,thread:{id:'t',messages:[],checkpoints:[{checkpointTurnCount:2,status:'ready'}]}}});
 assert.equal(state.checkpointCount,2);
 state.apply({kind:'event',event:{sequence:2,type:'thread.turn-diff-completed',payload:{threadId:'t',checkpointTurnCount:3,status:'ready'}}});
 assert.equal(state.checkpointCount,3);
});

test('home filters projects, archived and settled tasks without losing active runs', () => {
 const threads=[
  {id:'running',projectId:'p',title:'Build UI',updatedAt:'2026-09-07T02:00:00Z',session:{status:'running'},settledAt:'old'},
  {id:'settled',projectId:'p',title:'Done',updatedAt:'2026-09-07T01:00:00Z',settledAt:'old'},
  {id:'archived',projectId:'p',title:'Archived',updatedAt:'2026-09-07T03:00:00Z',archivedAt:'old'},
  {id:'other',projectId:'q',title:'Other project',updatedAt:'2026-09-07T04:00:00Z'},
 ];
 assert.deepEqual(model.visibleThreads(threads,'p','active','').map(t=>t.id),['running']);
 assert.deepEqual(model.visibleThreads(threads,'p','settled','').map(t=>t.id),['settled']);
 assert.deepEqual(model.visibleThreads(threads,'p','archived','').map(t=>t.id),['archived']);
 assert.deepEqual(model.visibleThreads(threads,'','all','BUILD').map(t=>t.id),['running']);
 assert.deepEqual(model.visibleThreads(threads,'','all','').map(t=>t.id),['other','running','settled']);
});

test('new task choices route by enabled provider instance and prefer project defaults', () => {
 const providers=[
  {instanceId:'disabled',enabled:false,installed:true,models:[{slug:'no',name:'No'}]},
  {instanceId:'missing',enabled:true,installed:false,models:[{slug:'no',name:'No'}]},
  {instanceId:'secondary',enabled:true,installed:true,availability:'available',displayName:'Secondary',models:[{slug:'a',name:'A'}]},
  {instanceId:'primary',enabled:true,installed:true,models:[{slug:'a',name:'A'},{slug:'b',name:'B'}]},
 ];
 const choices=model.availableModels(providers);
 assert.equal(choices.length,3);
 const preferred=model.preferredModelIndex(choices,{instanceId:'primary',model:'b'});
 assert.equal(choices[preferred].instanceId,'primary');
 assert.equal(choices[preferred].model,'b');
 assert.equal(model.preferredModelIndex(choices,{instanceId:'gone',model:'b'}),0);
 assert.equal(model.preferredModelIndex([],null),-1);
});

test('stop targets a known run and only falls back to a supported whole-thread stop', () => {
 const state=new model.ThreadState();
 state.apply({kind:'snapshot',snapshot:{snapshotSequence:1,thread:{id:'t',messages:[],session:{status:'ready',activeTurnId:null}}}});
 assert.equal(model.interruptTurnCommand(state.thread,'cmd',true),null);
 state.apply({kind:'event',event:{sequence:2,type:'thread.session-set',payload:{threadId:'t',session:{status:'starting',activeTurnId:null}}}});
 assert.equal(model.interruptTurnCommand(state.thread,'cmd',false),null);
 assert.deepEqual(model.interruptTurnCommand(state.thread,'cmd',true),{type:'thread.stop',commandId:'cmd',threadId:'t'});
 state.apply({kind:'event',event:{sequence:3,type:'thread.session-set',payload:{threadId:'t',session:{status:'running',activeTurnId:'run-one'}}}});
 for(const supported of [false,true]) assert.deepEqual(model.interruptTurnCommand(state.thread,'cmd',supported),
   {type:'run.interrupt',commandId:'cmd',threadId:'t',runId:'run-one',holdQueue:true});
 state.apply({kind:'event',event:{sequence:4,type:'thread.session-set',payload:{threadId:'t',session:{status:'ready',activeTurnId:null}}}});
 assert.equal(model.interruptTurnCommand(state.thread,'cmd',true),null);
});

test('tool updates merge into one chronological row and preserve command and latest output', () => {
 const state=new model.ThreadState();
 const started={id:'a',kind:'tool.updated',summary:'Ran command',turnId:'turn',createdAt:'02',payload:{toolCallId:'call',status:'inProgress',detail:'echo hello',data:{command:'echo hello'}}};
 state.apply({kind:'snapshot',snapshot:{snapshotSequence:1,thread:{id:'t',messages:[{id:'m',role:'user',text:'test',createdAt:'01'}],activities:[started],session:{status:'running'}}}});
 const activity={id:'b',kind:'tool.completed',summary:'Tool',turnId:'turn',createdAt:'03',payload:{toolCallId:'call',status:'completed',detail:'hello\nexit 0'}};
 const event={kind:'event',event:{sequence:2,type:'thread.activity-appended',payload:{threadId:'t',activity}}};
 state.apply(event);state.apply(event);
 const rows=model.threadTimeline(state.messages,state.activities,'turn');
 assert.equal(rows.length,2);
 assert.equal(rows[0].kind,'message');
 assert.equal(rows[1].text,'echo hello');
 assert.equal(rows[1].detail,'hello\nexit 0');
 assert.equal(rows[1].status,'completed');
 assert.equal(rows[1].createdAt,'02');
 assert.equal(state.activities.length,2);
});

test('unfinished historical tools do not claim they are still running or succeeded',()=>{
 const activities=[{id:'a',kind:'tool.updated',summary:'Tool',turnId:'old',createdAt:'01',payload:{toolCallId:'call',status:'inProgress',detail:'partial'}}];
 const row=model.threadTimeline([],activities,null)[0];
 assert.equal(row.status,'未收到完成状态');
 const other={...activities[0],id:'b',turnId:'new',createdAt:'02'};
 const rows=model.threadTimeline([],activities.concat(other),'new');
 assert.equal(rows.length,2);
 assert.equal(rows[0].status,'未收到完成状态');
 assert.equal(rows[1].status,'inProgress');
});

test('pending requests honor lifecycle, provider options and stale response failures',()=>{
 const a=(id,kind,requestId,payload={})=>({id,kind,createdAt:id,payload:{requestId,...payload}});
 const list=[a('1','approval.requested','r',{detail:'read a file',options:[{decision:'accept',label:'Read once'}]}),a('2','approval.resolved','r'),a('3','approval.requested','s',{options:[{decision:'decline',label:'No'}]}),a('4','user-input.requested','u',{questions:[{id:'q',header:'Color',question:'Which?',options:[{label:'Blue',description:'Blue color'}]}]})];
 const pending=model.pendingRequests(list);
 assert.deepEqual(pending.map(r=>r.requestId),['s','u']);
 assert.deepEqual(pending[0].options,[{decision:'decline',label:'No'}]);
 assert.equal(pending[1].questions[0].id,'q');
 assert.equal(model.pendingRequests(list.concat(a('5','provider.user-input.respond.failed','u',{detail:'Unknown pending user-input request'}))).length,1);
 assert.equal(model.pendingRequests([a('1','user-input.requested','bad',{questions:[]})]).length,0);
});

test('question answers require all questions, keep multi-select arrays and prefer typed answers',()=>{
 const qs=[{id:'one',multiSelect:false},{id:'many',multiSelect:true}];
 assert.equal(model.questionAnswers(qs,[]),null);
 const drafts=[{questionId:'one',selected:['A'],custom:''},{questionId:'many',selected:['B','C'],custom:''}];
 assert.deepEqual(model.questionAnswers(qs,drafts),{one:'A',many:['B','C']});
 drafts[0].custom='  custom answer  ';
 assert.deepEqual(model.questionAnswers(qs,drafts),{one:'custom answer',many:['B','C']});
});

test('malformed question data is ignored while valid free-text questions remain answerable',()=>{
 const payload={requestId:'r',questions:[null,{id:'bad',header:'Bad',question:'Bad',options:'invalid'},{id:'good',header:'Good',question:'Answer',options:[]}]};
 const requests=model.pendingRequests([{id:'a',kind:'user-input.requested',createdAt:'01',payload}]);
 assert.deepEqual(requests[0].questions.map(q=>q.id),['good']);
});

test('message attachments survive live updates and reach the timeline',()=>{
 const attachment={type:'image',id:'a',name:'image.jpg',mimeType:'image/jpeg',sizeBytes:123};
 const state=new model.ThreadState();
 state.apply({kind:'snapshot',snapshot:{snapshotSequence:1,thread:{id:'t',messages:[]}}});
 state.apply({kind:'event',event:{sequence:2,type:'thread.message-sent',payload:{threadId:'t',messageId:'m',role:'user',text:'image',attachments:[attachment],streaming:false}}});
 state.apply({kind:'event',event:{sequence:3,type:'thread.message-sent',payload:{threadId:'t',messageId:'m',text:'',streaming:false}}});
 assert.deepEqual(state.messages[0].attachments,[attachment]);
 assert.deepEqual(model.threadTimeline(state.messages,[],null)[0].attachments,[attachment]);
});

test('archive view orders by actual archive time in either direction and keeps active view ordering',()=>{
 const threads=[
  {id:'a',title:'one',archivedAt:'2026-09-08T01:00:00Z',updatedAt:'2026-09-08T05:00:00Z'},
  {id:'b',title:'two',archivedAt:'2026-09-08T02:00:00Z',updatedAt:'2026-09-08T03:00:00Z'},
  {id:'active',title:'three',updatedAt:'2026-09-08T06:00:00Z'}
 ];
 assert.deepEqual(model.visibleThreads(threads,'','archived','').map(t=>t.id),['b','a']);
 assert.deepEqual(model.visibleThreads(threads,'','archived','','oldest').map(t=>t.id),['a','b']);
 assert.deepEqual(model.visibleThreads(threads,'','archived','TWO','oldest').map(t=>t.id),['b']);
 assert.deepEqual(model.visibleThreads(threads,'','active','','oldest').map(t=>t.id),['active']);
});

test('archive timestamps compare instants and ties remain stable by title then id',()=>{
 const threads=[
  {id:'b',title:'same',archivedAt:'2026-09-08T10:00:00+08:00'},
  {id:'a',title:'same',archivedAt:'2026-09-08T02:00:00Z'},
  {id:'c',title:'before',archivedAt:'2026-09-08T02:00:00Z'},
  {id:'invalid',title:'old',archivedAt:'invalid'}
 ];
 assert.deepEqual(model.visibleThreads(threads,'','archived','').map(t=>t.id),['c','a','b','invalid']);
 assert.deepEqual(model.visibleThreads(threads,'','archived','','oldest').map(t=>t.id),['invalid','c','a','b']);
});

test('archive search finds project name, workspace path, environment and branch without leaking unrelated tasks',()=>{
 const snapshot={snapshotSequence:1,projects:[{id:'p',title:'Core App',workspaceRoot:'/work/alpha'},{id:'q',title:'Other',workspaceRoot:'/work/beta'}],threads:[
  {id:'a',projectId:'p',title:'Fix login',branch:'fix/auth',archivedAt:'2026-09-08'},
  {id:'b',projectId:'p',title:'Refactor',branch:null,archivedAt:'2026-09-08'},
  {id:'c',projectId:'q',title:'Other task',archivedAt:'2026-09-08'},
  {id:'live',projectId:'p',title:'Active',archivedAt:null},
  {id:'orphan',projectId:'missing',title:'orphan',archivedAt:'2026-09-08'}
 ]};
 const ids=query=>model.searchArchivedThreads(snapshot,query,'Studio Work').map(t=>t.id);
 assert.deepEqual(ids(' CORE '),['a','b']);assert.deepEqual(ids('/WORK/ALPHA'),['a','b']);
 assert.deepEqual(ids('studio'),['a','b','c']);assert.deepEqual(ids('AUTH'),['a']);
 assert.deepEqual(ids('refactor'),['b']);assert.deepEqual(ids('not found'),[]);
 assert.deepEqual(ids(''),['a','b','c']);
});

test('remote runtime and interaction changes govern the next turn without reconnecting',()=>{
 const state=new model.ThreadState();
 state.apply({kind:'snapshot',snapshot:{snapshotSequence:1,thread:{id:'t',runtimeMode:'full-access',interactionMode:'default',messages:[]}}});
 state.apply({kind:'event',event:{sequence:2,type:'thread.runtime-mode-set',payload:{threadId:'t',runtimeMode:'approval-required'}}});
 state.apply({kind:'event',event:{sequence:3,type:'thread.interaction-mode-set',payload:{threadId:'t',interactionMode:'plan'}}});
 const command=model.startTurnCommand(state.thread,'Do not use tools','c','m','2026-09-08T00:00:00.000Z');
 assert.equal(command.runtimeMode,'approval-required');assert.equal(command.interactionMode,'plan');
 state.apply({kind:'event',event:{sequence:2,type:'thread.runtime-mode-set',payload:{threadId:'t',runtimeMode:'full-access'}}});
 state.apply({kind:'event',event:{sequence:4,type:'thread.runtime-mode-set',payload:{threadId:'other',runtimeMode:'full-access'}}});
 assert.equal(state.thread.runtimeMode,'approval-required');
 state.apply({kind:'event',event:{sequence:5,type:'thread.runtime-mode-set',payload:{threadId:'t',runtimeMode:'full-access'}}});
 state.apply({kind:'event',event:{sequence:6,type:'thread.interaction-mode-set',payload:{threadId:'t',interactionMode:'default'}}});
 assert.equal(state.thread.runtimeMode,'full-access');assert.equal(state.thread.interactionMode,'default');
});


test('model changes from another client update the current model without losing options',()=>{
 const state=new model.ThreadState();state.apply({kind:'snapshot',snapshot:{snapshotSequence:1,thread:{id:'t',messages:[],modelSelection:{instanceId:'old',model:'old'}}}});
 const selection={instanceId:'new',model:'next',options:{reasoning:'high'}};
 state.apply({kind:'event',event:{sequence:2,type:'thread.meta-updated',payload:{threadId:'t',modelSelection:selection}}});
 assert.deepEqual(state.thread.modelSelection,selection);
 state.apply({kind:'event',event:{sequence:3,type:'thread.meta-updated',payload:{threadId:'t',title:'renamed'}}});assert.deepEqual(state.thread.modelSelection,selection);
});

test('shell metadata updates task modes when the detail feed does not emit mode events',()=>{
 const state=new model.ThreadState();assert.equal(typeof state.applyShell,'function');
 state.apply({kind:'snapshot',snapshot:{snapshotSequence:2,thread:{id:'t',runtimeMode:'full-access',interactionMode:'default',messages:[]}}});
 state.applyShell({kind:'thread-upserted',sequence:3,thread:{id:'t',runtimeMode:'auto',interactionMode:'plan',modelSelection:{instanceId:'omp',model:'new'}}},'t');
 assert.equal(state.thread.runtimeMode,'auto');assert.equal(state.thread.interactionMode,'plan');assert.equal(state.thread.modelSelection.model,'new');
 state.applyShell({kind:'thread-upserted',sequence:1,thread:{id:'t',runtimeMode:'full-access',interactionMode:'default'}},'t');
 state.applyShell({kind:'thread-upserted',sequence:4,thread:{id:'other',runtimeMode:'full-access',interactionMode:'default'}},'t');
 assert.equal(state.thread.runtimeMode,'auto');assert.equal(state.thread.interactionMode,'plan');
 const cmd=model.startTurnCommand(state.thread,'hello','c','m','now');assert.equal(cmd.runtimeMode,'auto');assert.equal(cmd.interactionMode,'plan');
});
test('newer shell snapshot survives late older detail snapshot and newer detail wins older shell',()=>{
 const state=new model.ThreadState();assert.equal(typeof state.applyShell,'function');
 state.applyShell({kind:'snapshot',snapshot:{snapshotSequence:10,threads:[{id:'t',runtimeMode:'approval-required',interactionMode:'plan'}]}},'t');
 state.apply({kind:'snapshot',snapshot:{snapshotSequence:9,thread:{id:'t',runtimeMode:'full-access',interactionMode:'default',messages:[]}}});
 assert.equal(state.thread.runtimeMode,'approval-required');assert.equal(state.thread.interactionMode,'plan');
 state.apply({kind:'snapshot',snapshot:{snapshotSequence:12,thread:{id:'t',runtimeMode:'auto-accept-edits',interactionMode:'default',messages:[]}}});
 assert.equal(state.thread.runtimeMode,'auto-accept-edits');assert.equal(state.thread.interactionMode,'default');
 state.applyShell({kind:'thread-upserted',sequence:11,thread:{id:'t',runtimeMode:'full-access',interactionMode:'plan'}},'t');
 assert.equal(state.thread.runtimeMode,'auto-accept-edits');
 state.applyShell({kind:'thread-upserted',sequence:13,thread:{id:'t',runtimeMode:'full-access',interactionMode:'default'}},'t');
 assert.equal(state.thread.runtimeMode,'full-access');
});
test('composer workspace and title follow authoritative shell changes, including returning to the project directory',()=>{
 const state=new model.ThreadState();
 state.apply({kind:'snapshot',snapshot:{snapshotSequence:1,thread:{id:'t',title:'old',branch:'main',worktreePath:null,messages:[]}}});
 state.applyShell({kind:'thread-upserted',sequence:2,thread:{id:'t',title:'new',branch:'feature',worktreePath:'/worktrees/feature'}},'t');
 assert.equal(state.thread.branch,'feature');assert.equal(state.thread.worktreePath,'/worktrees/feature');assert.equal(state.thread.title,'new');
 state.applyShell({kind:'thread-upserted',sequence:3,thread:{id:'t',title:'new',branch:'main',worktreePath:null}},'t');
 assert.equal(state.thread.worktreePath,null);assert.equal(state.thread.branch,'main');
});

test('main task filters hide subagent rows while retaining independent forks and cached child metadata',()=>{
 const parent={id:'parent',projectId:'p',title:'Build UI',updatedAt:'2026-11-23T00:00:00Z'};
 const child={...parent,id:'child',lineage:{parentThreadId:'parent',relationshipToParent:'subagent'},status:'running',pinnedAt:'now'};
 const fork={...parent,id:'fork',lineage:{parentThreadId:'parent',relationshipToParent:'fork'}};
 const archived={...child,id:'archived-child',archivedAt:'now'};
 const state=new model.ShellState();
 state.apply({kind:'snapshot',snapshot:{snapshotSequence:1,projects:[{id:'p',title:'Project',workspaceRoot:'/p'}],threads:[parent,child,fork,archived]}});
 assert.equal(state.threads.length,4);
 assert.deepEqual(model.visibleThreads(state.threads,'','all','').map(t=>t.id),['parent','fork']);
 assert.deepEqual(model.visibleThreads(state.threads,'p','active','Build').map(t=>t.id),['parent','fork']);
 assert.deepEqual(model.visibleThreads(state.threads,'','running',''),[]);
 assert.deepEqual(model.visibleThreads(state.threads,'','archived',''),[]);
 assert.deepEqual(model.searchArchivedThreads({projects:[{id:'p',title:'Project',workspaceRoot:'/p'}],threads:[archived]},'','Local'),[]);
});

test('a non-resumable cache stays readable without suppressing a replacement snapshot with a lower sequence',()=>{
 const state=new model.ThreadState();
 state.restoreCached({id:'t',messages:[{id:'old',text:'Cached'}],transcriptVersion:3,syncSequence:90});
 assert.equal(state.cursor(),null);assert.equal(state.messages[0].text,'Cached');
 state.apply({kind:'snapshot',snapshotSequence:4,projection:{thread:{id:'t',title:'Restored server'},messages:[],runs:[]}});
 assert.equal(state.cursor(),4);assert.equal(state.thread.title,'Restored server');
});
