import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const read=path=>readFileSync(new URL('../app/entry/src/main/ets/model/'+path,import.meta.url),'utf8');
const load=source=>import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
const models=await load(read('Models.ets'));globalThis.__notificationModels=models;
const {TaskNotificationTracker,taskNotificationId}=await load('const {taskStatus}=globalThis.__notificationModels;'+read('TaskNotifications.ets').replace(/^import .*;$/gm,''));
const task=(id,status,run='run')=>({id,title:id,projectId:'project',activityRunStatus:status,latestTurn:{turnId:run}});
const projects=[{id:'project',title:'项目',workspaceRoot:'/project'}];
test('initial history is silent and every task gets its own waiting, completed and failure notification while run starts stay silent',()=>{
 const tracker=new TaskNotificationTracker();
 assert.deepEqual(tracker.update('env',[task('one','idle'),task('two','idle')],projects,true),[]);
 assert.deepEqual(tracker.update('env',[task('one','running'),task('two','running')],projects),[]);
 const notices=tracker.update('env',[task('one','waiting'),task('two','failed')],projects);
 assert.deepEqual(notices.map(n=>n.state),['waiting','failed']);assert.equal(notices[0].projectTitle,'项目');assert.equal(notices[0].cwd,'/project');
 assert.equal(tracker.update('env',[task('one','idle')],projects)[0].state,'completed');
});
test('replayed shell updates never repeat a notification and only a new run completion notifies',()=>{
 const tracker=new TaskNotificationTracker();tracker.update('env',[task('task','idle')],projects,true);
 assert.equal(tracker.update('env',[task('task','running')],projects).length,0);
 assert.equal(tracker.update('env',[task('task','running')],projects).length,0);
 assert.equal(tracker.update('env',[task('task','completed')],projects).length,1);
 assert.equal(tracker.update('env',[task('task','completed')],projects).length,0);
 assert.equal(tracker.update('env',[task('task','running','next-run')],projects).length,0);
 assert.equal(tracker.update('env',[task('task','completed','next-run')],projects).length,1);
 assert.equal(tracker.update('env',[{...task('task','idle'),archivedAt:'2026-11-15T00:00:00Z'}],projects).length,0);
});
for(const state of ['completed','failed','interrupted','waiting']) test(`reconnecting after a new run reaches ${state} notifies once with current shell fields`,()=>{
 const tracker=new TaskNotificationTracker();
 const shell=run=>({id:'task',title:'任务',projectId:'project',status:state,activeRunId:null,latestRunId:run});
 assert.deepEqual(tracker.update('env',[shell('previous-run')],projects,true),[]);
 assert.deepEqual(tracker.update('env',[shell('previous-run')],projects),[]);
 const notices=tracker.update('env',[shell('next-run')],projects);
 assert.equal(notices.length,1);assert.equal(notices[0].state,state);assert.equal(notices[0].threadId,'task');
 assert.deepEqual(tracker.update('env',[shell('next-run')],projects),[]);
 assert.deepEqual(tracker.update('env',[{...shell('next-run'),title:'重命名任务'}],projects),[]);
});
test('current shell run starts stay silent and active run identity survives delayed latest-run metadata',()=>{
 const tracker=new TaskNotificationTracker();
 const shell={id:'task',title:'任务',projectId:'project',status:'completed',activeRunId:null,latestRunId:'previous-run'};
 tracker.update('env',[shell],projects,true);
 assert.deepEqual(tracker.update('env',[{...shell,status:'running',activeRunId:'next-run'}],projects),[]);
 assert.equal(tracker.update('env',[{...shell,status:'waiting',activeRunId:'next-run'}],projects)[0].state,'waiting');
 assert.deepEqual(tracker.update('env',[{...shell,status:'waiting',activeRunId:'next-run',latestRunId:'next-run'}],projects),[]);
 assert.equal(tracker.update('env',[{...shell,latestRunId:'next-run'}],projects)[0].state,'completed');
 assert.deepEqual(tracker.update('env',[{...shell,latestRunId:'next-run'}],projects),[]);
});
test('system notification identity is stable per environment and task without grouping different tasks together',()=>{
 assert.equal(taskNotificationId('env','one'),taskNotificationId('env','one'));
 assert.notEqual(taskNotificationId('env','one'),taskNotificationId('env','two'));
 assert.notEqual(taskNotificationId('env','one'),taskNotificationId('other','one'));
 assert.ok(taskNotificationId('env','one')>=0);
});
test('a new active run stays silent even while metadata catches up and later transitions notify per environment',()=>{
 const tracker=new TaskNotificationTracker();const old=task('task','running','previous-run');
 tracker.update('env',[{...old,activeRunId:'previous-run'}],projects,true);
 assert.equal(tracker.update('env',[{...old,activeRunId:'new-run'}],projects).length,0);
 assert.equal(tracker.update('env',[{...old,activeRunId:'new-run'}],projects).length,0);
 tracker.update('other',[task('task','idle')],projects,true);
 assert.equal(tracker.update('other',[task('task','running')],projects).length,0);
 assert.equal(tracker.update('other',[task('task','waiting')],projects).length,1);
 assert.equal(tracker.update('env',[task('task','failed','new-run')],projects).length,1);
});
