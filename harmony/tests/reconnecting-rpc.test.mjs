import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const source=readFileSync(new URL('../app/entry/src/main/ets/connection/ReconnectingRpc.ets',import.meta.url),'utf8').replace("import { RpcClient } from './Rpc';",'');
const {ReconnectingRpc}=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
const drain=async()=>{for(let i=0;i<12;i++) await Promise.resolve();};
test('retries failed subscriptions, backs off, and cancellation rejects late connections',async(t)=>{
 t.mock.timers.enable({apis:['setTimeout']});
 let opens=0,resolveLate;const peers=[],states=[];
 const open=async()=>{opens++;if(opens===4)return new Promise(r=>resolveLate=r);const p={closed:false,close(){this.closed=true;}};peers.push(p);return p;};
 const session=new ReconnectingRpc(open,async()=>{throw new Error('offline');},s=>states.push(s));
 session.start();await drain();assert.equal(opens,1);assert.equal(peers[0].closed,true);
 t.mock.timers.tick(249);await drain();assert.equal(opens,1);
 t.mock.timers.tick(1);await drain();assert.equal(opens,2);
 t.mock.timers.tick(499);await drain();assert.equal(opens,2);
 t.mock.timers.tick(1);await drain();assert.equal(opens,3);
 t.mock.timers.tick(1000);await drain();assert.equal(opens,4);
 session.stop();const late={closed:false,close(){this.closed=true;}};resolveLate(late);await drain();assert.equal(late.closed,true);
 t.mock.timers.tick(60000);await drain();assert.equal(opens,4);assert.ok(states.includes('reconnecting'));
});
test('healthy snapshots reset backoff and stop closes the active stream',async(t)=>{
 t.mock.timers.enable({apis:['setTimeout']});
 let fail,opens=0;const peers=[];
 const session=new ReconnectingRpc(async()=>{opens++;const p={closed:false,close(){this.closed=true;}};peers.push(p);return p;},()=>new Promise((_,reject)=>fail=reject),()=>{});
 session.start();await drain();session.healthy();fail(new Error('lost'));await drain();
 t.mock.timers.tick(250);await drain();assert.equal(opens,2);
 session.healthy();fail(new Error('lost'));await drain();t.mock.timers.tick(250);await drain();assert.equal(opens,3);
 session.stop();assert.equal(peers[2].closed,true);
});

test('restarts a socket that responds to heartbeats but never finishes synchronization',async(t)=>{
 t.mock.timers.enable({apis:['setTimeout']});
 let opens=0,peer;
 const session=new ReconnectingRpc(async()=>{opens++;return peer={close(){this.reject?.(new Error('closed'));}};},
  rpc=>new Promise((_,reject)=>rpc.reject=reject),()=>{});
 session.start();await drain();
 t.mock.timers.tick(30000);await drain();
 t.mock.timers.tick(250);await drain();assert.equal(opens,2);
 session.healthy();t.mock.timers.tick(60000);await drain();assert.equal(opens,2);
 session.stop();
});

test('synchronization progress extends the deadline and stop cancels it',async(t)=>{
 t.mock.timers.enable({apis:['setTimeout']});
 let opens=0,closes=0;
 const session=new ReconnectingRpc(async()=>{opens++;return {close(){closes++;this.reject?.(new Error('closed'));}};},
  rpc=>new Promise((_,reject)=>rpc.reject=reject),()=>{});
 session.start();await drain();
 t.mock.timers.tick(20000);session.progress();t.mock.timers.tick(20000);await drain();
 assert.equal(closes,0);session.stop();assert.equal(closes,1);
 t.mock.timers.tick(60000);await drain();assert.equal(opens,1);
});

test('a synchronization timeout asks for recovery while an isolated disconnect and stop do not',async(t)=>{
 t.mock.timers.enable({apis:['setTimeout']});let peer,recoveries=0;
 const session=new ReconnectingRpc(async()=>peer={closed:false,close(){this.closed=true;this.reject?.(new Error('closed'));}},
  rpc=>new Promise((_,reject)=>rpc.reject=reject),()=>{},()=>{assert.equal(peer.closed,true);recoveries++;});
 session.start();await drain();t.mock.timers.tick(30000);await drain();assert.equal(recoveries,1);
 t.mock.timers.tick(250);await drain();peer.close();await drain();assert.equal(recoveries,1);
 t.mock.timers.tick(500);await drain();session.stop();t.mock.timers.tick(60000);await drain();assert.equal(recoveries,1);
});

test('three consecutive incomplete subscriptions request recovery even when each fails before the timeout',async t=>{
 t.mock.timers.enable({apis:['setTimeout']});let peer,rejectSubscription,recoveries=0,opens=0;
 const session=new ReconnectingRpc(async()=>{opens++;return peer={closed:false,close(){this.closed=true;}};},
  ()=>new Promise((_,reject)=>rejectSubscription=reject),()=>{},()=>{assert.equal(peer.closed,true);recoveries++;});
 t.after(()=>session.stop());session.start();await drain();
 for(let attempt=0;attempt<3;attempt++){
  rejectSubscription(new Error('subscription failed'));await drain();
  assert.equal(recoveries,attempt===2?1:0);
  t.mock.timers.tick(250*2**attempt);await drain();
 }
 assert.equal(opens,4);assert.equal(recoveries,1);
});

test('successful synchronization clears earlier failure counts',async t=>{
 t.mock.timers.enable({apis:['setTimeout']});let rejectSubscription,recoveries=0;
 const session=new ReconnectingRpc(async()=>({close(){}}),()=>new Promise((_,reject)=>rejectSubscription=reject),()=>{},()=>recoveries++);
 t.after(()=>session.stop());session.start();await drain();
 for(const delay of [250,500]){rejectSubscription(new Error('lost'));await drain();t.mock.timers.tick(delay);await drain();}
 session.healthy();
 for(const delay of [250,500,1000]){rejectSubscription(new Error('lost'));await drain();t.mock.timers.tick(delay);await drain();}
 assert.equal(recoveries,0);
 rejectSubscription(new Error('lost'));await drain();assert.equal(recoveries,1);
});

test('failed connection opens do not invalidate a resumable conversation',async t=>{
 t.mock.timers.enable({apis:['setTimeout']});let recoveries=0,opens=0;
 const session=new ReconnectingRpc(async()=>{opens++;throw new Error('network unavailable');},async()=>{},()=>{},()=>recoveries++);
 t.after(()=>session.stop());session.start();await drain();
 for(const delay of [250,500,1000,2000]){t.mock.timers.tick(delay);await drain();}
 assert.equal(opens,5);assert.equal(recoveries,0);
});

test('a stalled subscription cannot block recovery even when closing its socket does not settle it',async t=>{
 t.mock.timers.enable({apis:['setTimeout']});let opens=0,finishOld,recoveries=0;
 const peers=[];
 const session=new ReconnectingRpc(async()=>{opens++;const peer={closed:false,close(){this.closed=true;}};peers.push(peer);return peer;},
  ()=>new Promise(resolve=>{if(opens===1)finishOld=resolve;}),()=>{},()=>recoveries++);
 t.after(()=>session.stop());session.start();await drain();
 t.mock.timers.tick(30000);await drain();t.mock.timers.tick(250);await drain();
 assert.equal(opens,2);assert.equal(recoveries,1);assert.equal(peers[0].closed,true);
 session.healthy();finishOld();await drain();
 t.mock.timers.tick(60000);await drain();assert.equal(opens,2);assert.equal(peers[1].closed,false);
});

test('a stalled connection open has a deadline and its late result cannot replace the new session',async t=>{
 t.mock.timers.enable({apis:['setTimeout']});let opens=0,finishOld,recoveries=0;const subscribed=[];
 const current={closed:false,close(){this.closed=true;}};
 const session=new ReconnectingRpc(()=>{opens++;return opens===1?new Promise(resolve=>finishOld=resolve):Promise.resolve(current);},
  rpc=>{subscribed.push(rpc);return new Promise(()=>{});},()=>{},()=>recoveries++);
 t.after(()=>session.stop());session.start();await drain();
 t.mock.timers.tick(30000);await drain();t.mock.timers.tick(250);await drain();
 assert.equal(opens,2);assert.deepEqual(subscribed,[current]);assert.equal(recoveries,0);
 const late={closed:false,close(){this.closed=true;}};finishOld(late);await drain();
 assert.equal(late.closed,true);assert.equal(current.closed,false);assert.deepEqual(subscribed,[current]);
});

test('resume coalesces pending opens and reuses a healthy session across foreground changes',async t=>{
 t.mock.timers.enable({apis:['setTimeout']});let opens=0,finish;const states=[],foregrounds=[];
 const peer={closed:false,close(){this.closed=true;},setForeground(value){foregrounds.push(value);},probe(){return !this.closed;}};
 const session=new ReconnectingRpc(()=>{opens++;return new Promise(resolve=>finish=resolve);},()=>new Promise(()=>{}),state=>states.push(state));
 t.after(()=>{session.stop();ReconnectingRpc.setForeground(true);});
 session.resume();session.resume();assert.equal(opens,1);finish(peer);await drain();session.healthy();
 ReconnectingRpc.setForeground(false);t.mock.timers.tick(120000);await drain();
 assert.equal(peer.closed,false);assert.equal(opens,1);
 ReconnectingRpc.setForeground(true);session.resume();await drain();
 assert.equal(peer.closed,false);assert.equal(opens,1);assert.deepEqual(states,['connecting']);
 assert.deepEqual(foregrounds,[false,true]);
 session.stop();ReconnectingRpc.setForeground(false);ReconnectingRpc.setForeground(true);await drain();assert.equal(opens,1);
});

test('background pauses retries and foreground immediately wakes a pending backoff',async t=>{
 t.mock.timers.enable({apis:['setTimeout']});let opens=0,online=false;
 const peer={close(){},setForeground(){},probe(){return true;}};
 const session=new ReconnectingRpc(async()=>{opens++;if(!online)throw new Error('offline');return peer;},()=>new Promise(()=>{}),()=>{});
 t.after(()=>{session.stop();ReconnectingRpc.setForeground(true);});
 session.start();await drain();t.mock.timers.tick(250);await drain();assert.equal(opens,2);
 ReconnectingRpc.setForeground(false);t.mock.timers.tick(120000);await drain();assert.equal(opens,2);
 online=true;ReconnectingRpc.setForeground(true);await drain();assert.equal(opens,3);
});

test('background does not consume the synchronization deadline or force a snapshot recovery',async t=>{
 t.mock.timers.enable({apis:['setTimeout']});let opens=0,recoveries=0;
 const peer={closed:false,close(){this.closed=true;},setForeground(){},probe(){return !this.closed;}};
 const session=new ReconnectingRpc(async()=>{opens++;return peer;},()=>new Promise(()=>{}),()=>{},()=>recoveries++);
 t.after(()=>{session.stop();ReconnectingRpc.setForeground(true);});
 session.start();await drain();t.mock.timers.tick(20000);ReconnectingRpc.setForeground(false);
 t.mock.timers.tick(120000);await drain();assert.equal(peer.closed,false);assert.equal(recoveries,0);
 ReconnectingRpc.setForeground(true);t.mock.timers.tick(29999);await drain();assert.equal(opens,1);assert.equal(recoveries,0);
 session.healthy();t.mock.timers.tick(60000);await drain();assert.equal(peer.closed,false);
});

test('foreground replaces an unfinished dial and discards the late socket',async t=>{
 let resolveOld,opens=0;const received=[];
 const current={close(){},probe(){return true},setForeground(){}};
 const session=new ReconnectingRpc(()=>++opens===1?new Promise(r=>resolveOld=r):Promise.resolve(current),
  peer=>{received.push(peer);return new Promise(()=>{})},()=>{});
 t.after(()=>{session.stop();ReconnectingRpc.setForeground(true)});session.start();
 ReconnectingRpc.setForeground(false);ReconnectingRpc.setForeground(true);await drain();assert.deepEqual(received,[current]);
 let closed=false;resolveOld({close(){closed=true}});await drain();assert.equal(closed,true);assert.equal(opens,2);
});
