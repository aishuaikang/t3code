import {test} from 'node:test';import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';import {stripTypeScriptTypes} from 'node:module';
const model=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(readFileSync(new URL('../app/entry/src/main/ets/model/Models.ets',import.meta.url),'utf8'))).toString('base64'));
const commands=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(readFileSync(new URL('../app/entry/src/main/ets/model/ComposerCommands.ets',import.meta.url),'utf8'))).toString('base64'));
const disk=new Map();const reads=[];const written=[];let writes=0,revision=0;
globalThis.__clientCacheDeps={availableModels:model.availableModels,commandCatalog:commands.commandCatalog,DraftStore:{async open(dir,env,id){const key=JSON.stringify([dir,env,id]);return {load:async()=>{reads.push(key);return disk.get(key)??''},save:async text=>{writes++;written.push(key);disk.set(key,text)}}}}};
async function runtime(){let source=readFileSync(new URL('../app/entry/src/main/ets/connection/ClientCache.ets',import.meta.url),'utf8').replace(/^import .*;\n/gm,'');source='const {DraftStore,availableModels,commandCatalog}=globalThis.__clientCacheDeps;\n'+source;return import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(source)+`\n// runtime ${++revision}`).toString('base64'))}
test('cached reads survive restarts, stay isolated by environment and contain no credentials',async()=>{
 const {ClientCache}=await runtime();const a=await ClientCache.open('/files','a');
 a.setShell({snapshotSequence:8,threads:[{id:'t',title:'History'}],projects:[]});
 a.setThread({id:'t',title:'History',projectId:'p',runtimeMode:'auto',interactionMode:'default',messages:[]},[{id:'m',text:'Cached reply'}],[],0);
 a.setCatalog({environment:{environmentId:'a'},providers:[{instanceId:'p',enabled:true,installed:true,models:[{slug:'m',name:'Model'}],slashCommands:[{name:'review'}],secretToken:'NEVER_PERSIST'}],access_token:'NEVER_PERSIST'});
 await a.flush();
 assert.ok(![...disk.values()].join('').includes('NEVER_PERSIST'));
 const fresh=await runtime();const restored=await fresh.ClientCache.open('/files','a');
 assert.equal(restored.shell().threads[0].title,'History');assert.equal((await restored.thread('t')).messages[0].text,'Cached reply');
 assert.equal(restored.models()[0].model,'m');assert.equal(restored.commands()[0].commands[0].name,'review');
 assert.equal(await (await fresh.ClientCache.open('/files','b')).thread('t'),null);
 const copy=await restored.thread('t');copy.messages[0].text='changed';assert.equal((await restored.thread('t')).messages[0].text,'Cached reply');
});
test('server pins and renamed titles survive a cold shell-cache read and unpinning replaces the persisted pin',async()=>{
 const {ClientCache}=await runtime();const cache=await ClientCache.open('/pins','one');const shell=new model.ShellState();
 shell.apply({kind:'snapshot',snapshot:{snapshotSequence:1,projects:[],threads:[{id:'t',title:'Original',pinnedAt:null}]}});
 shell.apply({kind:'thread-upserted',sequence:2,thread:{id:'t',title:'新会话名称',pinnedAt:'2026-11-16T00:00:00Z',pinOrderKey:'a'}});
 cache.setShell(shell.snapshot());await cache.flush();
 const fresh=await runtime();const cold=await fresh.ClientCache.open('/pins','one');
 assert.equal(cold.shell().threads[0].title,'新会话名称');assert.equal(cold.shell().threads[0].pinOrderKey,'a');
 assert.ok(cold.shell().threads[0].pinnedAt);assert.equal((await fresh.ClientCache.open('/pins','two')).shell(),null);
 shell.apply({kind:'thread-upserted',sequence:3,thread:{id:'t',title:'新会话名称',pinnedAt:null,pinOrderKey:null}});
 cold.setShell(shell.snapshot());await cold.flush();
 const final=await runtime();assert.equal((await final.ClientCache.open('/pins','one')).shell().threads[0].pinnedAt,null);
});

test('PC active ordering keys and restore timestamps survive incremental shell updates and a cold cache read',async()=>{
 const {ClientCache}=await runtime();const cache=await ClientCache.open('/thread-order','one');const shell=new model.ShellState();
 shell.apply({kind:'snapshot',snapshot:{snapshotSequence:1,projects:[],threads:[{id:'t',title:'Task',activeOrderKey:'n'}]}});
 shell.apply({kind:'thread-upserted',sequence:2,thread:{id:'t',title:'Task',activeOrderKey:'g',unsettledAt:'2026-11-16T01:00:00Z'}});
 cache.setShell(shell.snapshot());await cache.flush();
 const fresh=await runtime();const saved=(await fresh.ClientCache.open('/thread-order','one')).shell();
 assert.equal(saved.snapshotSequence,2);assert.equal(saved.threads[0].activeOrderKey,'g');
 assert.equal(saved.threads[0].unsettledAt,'2026-11-16T01:00:00Z');
 shell.apply({kind:'thread-upserted',sequence:3,thread:{id:'t',title:'Task',activeOrderKey:null}});
 cache.setShell(shell.snapshot());await cache.flush();
 const final=await runtime();assert.equal((await final.ClientCache.open('/thread-order','one')).shell().threads[0].activeOrderKey,null);
});

test('streaming cache writes are coalesced while complete loaded history and recent task limits survive',async t=>{
 t.mock.timers.enable({apis:['setTimeout']});const {ClientCache}=await runtime();const a=await ClientCache.open('/bounded','a');const before=writes;
 for(let i=0;i<12;i++)a.setThread({id:String(i),title:'Task',messages:[]},Array.from({length:300},(_,n)=>({id:String(n),text:'message'})),[],0);
 assert.equal(writes,before);await a.flush();assert.equal(writes,before+13);
 assert.equal(await a.thread('0'),null);assert.equal((await a.thread('11')).messages.length,300);
 assert.equal((await a.thread('11')).messages[0].id,'0');
});
test('a cache restart retains the exact event cursor together with messages and execution state',async()=>{
 const {ClientCache}=await runtime();const cache=await ClientCache.open('/resume','a');
 cache.setThread({id:'t',title:'Task',turns:[{turnId:'r',state:'running',ordinal:1}],messages:[]},
  [{id:'m',role:'assistant',text:'Before disconnect',turnId:'r',timelinePosition:17}],[],0,121);
 await cache.flush();const fresh=await runtime();const thread=await (await fresh.ClientCache.open('/resume','a')).thread('t');
 assert.equal(thread.syncSequence,121);assert.equal(thread.messages[0].timelinePosition,17);assert.equal(thread.turns[0].ordinal,1);
});
test('corrupt or foreign cache cannot replace the selected environment',async()=>{
 disk.set(JSON.stringify(['/corrupt','a','read-cache-v1']),'{broken');
 const {ClientCache}=await runtime();const cache=await ClientCache.open('/corrupt','a');assert.equal(cache.shell(),null);
 disk.set(JSON.stringify(['/foreign','a','read-cache-v1']),JSON.stringify({version:1,environmentId:'b',shell:{threads:[{id:'foreign'}]}}));
 assert.equal((await ClientCache.open('/foreign','a')).shell(),null);
});

test('opening the environment reads no histories, and changing one task never rewrites another history',async()=>{
 const {ClientCache}=await runtime();const cache=await ClientCache.open('/shards','a');
 for(const id of ['one','two'])cache.setThread({id,title:id,messages:[]},[{id:'m',text:id}],[],0,1);
 await cache.flush();const fresh=await runtime();const before=reads.length;
 const restored=await fresh.ClientCache.open('/shards','a');
 assert.equal(reads.length,before+1);
 assert.equal((await restored.thread('one')).messages[0].text,'one');
 assert.equal(reads.length,before+2);
 const start=written.length;
 restored.setThread({id:'one',title:'one',messages:[]},[{id:'m',text:'updated'}],[],0,2);
 await restored.flush();
 assert.deepEqual(written.slice(start).map(key=>JSON.parse(key)[2]).sort(),['read-cache-v1','read-thread-v2:one']);
});
test('streaming stays in memory between checkpoints while preserving an older disk snapshot',async t=>{
 t.mock.timers.enable({apis:['setTimeout']});const {ClientCache}=await runtime();const cache=await ClientCache.open('/active','a');
 cache.setThread({id:'t',title:'Task',messages:[]},[{id:'m',text:'settled'}],[],0,7);await cache.flush();
 const start=writes;
 for(let n=0;n<30;n++)cache.setThread({id:'t',title:'Task',messages:[]},[{id:'m',text:'live-'+n,streaming:true}],[],0,8+n,false);
 t.mock.timers.tick(2000);await Promise.resolve();assert.equal(writes,start);
 assert.equal((await cache.thread('t')).messages[0].text,'live-29');
 cache.setShell({snapshotSequence:40,threads:[],projects:[]});await cache.flush(false);
 const cold=await runtime();assert.equal((await (await cold.ClientCache.open('/active','a')).thread('t')).syncSequence,7);
 await cache.flush();
 const final=await runtime();const resumed=await (await final.ClientCache.open('/active','a')).thread('t');
 assert.equal(resumed.syncSequence,37);assert.equal(resumed.messages[0].text,'live-29');
});
test('legacy combined cache migrates with its cursor and full history intact',async()=>{
 disk.set(JSON.stringify(['/legacy','a','read-cache-v1']),JSON.stringify({version:1,environmentId:'a',shell:null,models:[],commands:[],
   threads:[{id:'t',title:'Legacy',messages:[{id:'m',text:'Existing cache'}],syncSequence:51}]}));
 const {ClientCache}=await runtime();const cache=await ClientCache.open('/legacy','a');
 assert.equal((await cache.thread('t')).syncSequence,51);await cache.flush();
 const manifest=JSON.parse(disk.get(JSON.stringify(['/legacy','a','read-cache-v1'])));
 assert.equal(manifest.version,2);assert.equal(manifest.threads,undefined);
 const fresh=await runtime();assert.equal((await (await fresh.ClientCache.open('/legacy','a')).thread('t')).messages[0].text,'Existing cache');
});

test('current question history and its resume version survive metadata updates and a disk restart',async()=>{
 const state=new model.ThreadState();
 state.apply({kind:'snapshot',snapshotSequence:41,projection:{thread:{id:'t',title:'Task'},messages:[],runs:[],visibleTurnItems:[
  {position:0,item:{id:'q',threadId:'t',runId:null,type:'user_input_request',status:'completed',startedAt:'01',updatedAt:'02',requestId:'request',
    questions:[{id:'one',header:'Ready',question:'Ready?',options:[]}],
    questionAnswer:{requestId:'request',questionTextById:{one:'Ready?'},answers:{one:'Yes'},attachmentsByQuestionId:{}}}}
 ]}});
 state.apply({kind:'event',sequence:42,event:{threadId:'t',type:'thread.metadata-updated',payload:{id:'t',title:'Updated'}}});
 const {ClientCache}=await runtime();const cache=await ClientCache.open('/question-history','a');
 cache.setThread(state.thread,state.messages,state.activities,0,state.cursor());await cache.flush();
 const fresh=await runtime();const saved=await (await fresh.ClientCache.open('/question-history','a')).thread('t');
 const restored=new model.ThreadState();restored.restoreCached(saved);
 assert.equal(restored.cursor(),42);
 const rows=model.threadTimeline(restored.messages,restored.activities,null);
 assert.equal(rows[0].kind,'question');assert.equal(rows[0].detail,'Ready?\nYes');
});

test('an active conversation survives a cold restart without leaving the page or receiving a lifecycle flush',async t=>{
 t.mock.timers.enable({apis:['setTimeout']});
 const {ClientCache}=await runtime();const cache=await ClientCache.open('/active-cold-start','a');const start=writes;
 for(let n=0;n<8;n++){
  cache.setThread({id:'t',title:'Running',transcriptVersion:2,canonicalTimeline:true,historyCursor:'earlier',hasMoreHistory:true,messages:[],
    turns:[{turnId:'r',state:'running',ordinal:1}]},
    [{id:'m',role:'assistant',text:'live-'+n,streaming:true,visibleInTimeline:true,itemOrdinal:1}],[],0,n+1,false);
  t.mock.timers.tick(1000);
  for(let i=0;i<24;i++)await Promise.resolve();
 }
 assert.equal(writes,start+2); // One thread checkpoint and its manifest during uninterrupted streaming.
 const cold=await runtime();const restored=await (await cold.ClientCache.open('/active-cold-start','a')).thread('t');
 assert.ok(restored,'The first entry after restarting must have cached history.');
 assert.equal(restored.messages[0].text,'live-4');assert.equal(restored.syncSequence,5);
 assert.equal(restored.transcriptVersion,2);assert.equal(restored.canonicalTimeline,true);
 assert.equal(restored.historyCursor,'earlier');assert.equal(restored.hasMoreHistory,true);
 assert.equal((await cache.thread('t')).messages[0].text,'live-7');
 await cache.flush();
});

test('multiple open views cannot replace newer cached replies, even across a lower authoritative server snapshot',async()=>{
 const {ClientCache}=await runtime(),cache=await ClientCache.open('/two-pages','a'),t={id:'t',messages:[]};
 const save=(text,seq,epoch)=>cache.setThread(t,[{id:'m',text}],[],0,seq,true,epoch);
 save('new',80,0);save('delayed',75,0);assert.equal((await cache.thread('t')).messages[0].text,'new');
 const epoch=cache.threadSnapshotEpoch('t',0,80,4);save('after restore',4,epoch);save('old connection',81,0);
 assert.equal((await cache.thread('t')).messages[0].text,'after restore');
 for(const seq of [4,81]) {const stale=cache.threadSnapshotEpoch('t',0,80,seq);assert.equal(stale,null);}
 const joined=cache.threadSnapshotEpoch('t',cache.threadEpoch('t'),null,4);save('current lower timeline',5,joined);save('old',82,0);
 await cache.flush();const fresh=await runtime();const persisted=await (await fresh.ClientCache.open('/two-pages','a')).thread('t');
 assert.equal(persisted.syncSequence,5);assert.equal(persisted.messages[0].text,'current lower timeline');
});

test('the parent lookup tracks cached, removed and archived parents without loading thread histories',async()=>{
 const {ClientCache}=await runtime(),c=await ClientCache.open('/parents','e');c.setShell({snapshotSequence:1,threads:[{id:'p'}],projects:[]});await c.flush();
 const cold=await (await runtime()).ClientCache.open('/parents','e');assert.equal(cold.listsThread('p'),true);
 cold.setShell({snapshotSequence:2,threads:[{id:'p',archivedAt:'now'}],projects:[]});assert.equal(cold.listsThread('p'),false);
 cold.setShell({snapshotSequence:3,threads:[{id:'q'}],projects:[]});assert.equal(cold.listsThread('q'),true);assert.equal(cold.listsThread('p'),false);await cold.flush();
});

test('hidden side chats can be reopened from their own parent, including from the offline shell',async()=>{
 const {ClientCache}=await runtime();const c=await ClientCache.open('/side','env');c.setShell({snapshotSequence:1,projects:[],threads:[
  {id:'side',lineage:{parentThreadId:'p',sideChat:true}}, {id:'fork',lineage:{parentThreadId:'p',relationshipToParent:'fork'}},
  {id:'other',lineage:{parentThreadId:'q',sideChat:true}},{id:'archived',archivedAt:'now',lineage:{parentThreadId:'p',sideChat:true}}]});await c.flush();
 const restarted=await (await runtime()).ClientCache.open('/side','env');assert.deepEqual(restarted.sideChats('p').map(t=>t.id),['side']);
});
