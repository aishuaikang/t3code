import {test} from 'node:test';import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';import {stripTypeScriptTypes} from 'node:module';
const m=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(readFileSync(new URL('../app/entry/src/main/ets/model/Models.ets',import.meta.url),'utf8'))).toString('base64'));
test('status filters distinguish running, approval/input waits, queued, completed, failures and interruptions',()=>{
 const tasks=[{id:'run',status:'running'},{id:'wait',status:'running',pendingRuntimeRequest:{kind:'user_input'}},{id:'queue',status:'queued'},{id:'done',status:'completed'},{id:'bad',status:'failed'},{id:'stop',status:'interrupted'},{id:'idle',status:'idle'},{id:'archive',archivedAt:'now',status:'completed'}];
 for(const [filter,id] of [['running','run'],['waiting','wait'],['queued','queue'],['settled','done'],['failed','bad'],['interrupted','stop'],['idle','idle'],['archived','archive']])assert.deepEqual(m.visibleThreads(tasks,'',filter,'').map(t=>t.id),[id]);
 assert.equal(m.taskStatus({status:'completed',activityRunStatus:'running',settledAt:'old'}),'running');
 assert.equal(m.taskStatus({status:'completed',settledOverride:'active'}),'idle');
 assert.equal(m.taskStatus({session:{status:'starting'}}),'running');
});

test('status colors remain distinct and readable on both light and dark screens',async()=>{
 const v=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(readFileSync(new URL('../app/entry/src/main/ets/model/StatusVisuals.ets',import.meta.url),'utf8'))).toString('base64'));
 const luminance=hex=>{const rgb=[1,3,5].map(i=>parseInt(hex.slice(i,i+2),16)/255).map(c=>c<=0.04045?c/12.92:((c+0.055)/1.055)**2.4);return 0.2126*rgb[0]+0.7152*rgb[1]+0.0722*rgb[2]};
 for(const background of ['#FFFFFF','#0A0A0A']){
  const colors=['running','waiting','queued','completed','failed','interrupted','archived','idle'].map(status=>v.statusColor(status,background));
  assert.equal(new Set(colors).size,8);
  for(const color of colors){const a=luminance(color),b=luminance(background);assert.ok((Math.max(a,b)+0.05)/(Math.min(a,b)+0.05)>=4.5,`${color} on ${background}`)}
 }
});

test('connection progress distinguishes dialing, reconnecting and catching up without spinning after failure or disconnect',async()=>{
 const v=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(readFileSync(new URL('../app/entry/src/main/ets/model/StatusVisuals.ets',import.meta.url),'utf8'))).toString('base64'));
 assert.deepEqual(['connecting','reconnecting','syncing','connected','offline','failed'].map(state=>v.connectionProgressLabel(state)),
   ['正在连接','正在重新连接','正在同步','','','']);
 assert.deepEqual(['syncing','connected','failed','offline'].map(state=>v.connectionProgressLabel(state,true)),
   ['正在同步','正在同步归档','','']);
});
