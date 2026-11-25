import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const load=path=>import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(readFileSync(new URL('../app/entry/src/main/ets/'+path,import.meta.url),'utf8').replace(/^import .*;$/gm,''))).toString('base64'));
const actions=await load('model/MessageActions.ets');
const row=(id,turnId,extra={})=>({id,turnId,role:'assistant',kind:'message',text:'Reply',createdAt:'first',updatedAt:'last',...extra});
test('assistant actions appear on the last completed reply of each turn and stay hidden while running',()=>{
 const rows=[row('comment','a'),row('final','a'),row('stream','b',{streaming:true}),row('user','a',{role:'user'}),row('empty','c',{text:''})];
 assert.deepEqual(actions.assistantActionIds(rows,'b'),['final']);
 rows[2].streaming=false;assert.deepEqual(actions.assistantActionIds(rows,null),['final','stream']);
});
test('forking from an older reply targets that run and never silently forks the newest context',()=>{
 const fork=actions.forkFromMessage('original',row('answer','old-run'),'command','new-thread','Task');
 assert.deepEqual(fork.sourcePoint,{type:'run',runId:'old-run'});assert.equal(fork.sourceThreadId,'original');assert.equal(fork.targetThreadId,'new-thread');
 assert.equal(fork.type,'thread.fork');assert.equal(fork.createdBy,'user');assert.equal(fork.creationSource,'mobile');
 assert.throws(()=>actions.forkFromMessage('original',row('stream','run',{streaming:true}),'c','t','Task'),/回复完成/);
 assert.throws(()=>actions.forkFromMessage('original',row('missing',null),'c','t','Task'),/回复完成/);
});
test('assistant time uses completion time while user time keeps the original send time',()=>{
 assert.equal(actions.messageTimeValue(row('assistant','run')),'last');
 assert.equal(actions.messageTimeValue(row('user','run',{role:'user'})),'first');
});

const historyMessage = { id: 'u4', role: 'user', sourceThreadId: 'thread', turnId: 'r4', inputIntent: 'turn_start', text: 'Try this', streaming: false };
const checkpoint = (id, ordinal, status = 'ready') => ({ id, scopeId: 'scope', appRunOrdinal: ordinal, ordinalWithinScope: ordinal ?? 0, status });
const history = () => ({ id: 'thread', worktreePath: '/worktree', activeProviderThreadId: 'provider-thread',
  providerThreads: [{ id: 'provider-thread', appThreadId: 'thread', ownerNodeId: null, providerInstanceId: 'codex', lastRunOrdinal: 5 }],
  turns: [{ turnId: 'r5', ordinal: 5, state: 'completed' }, { turnId: 'r4', ordinal: 4, state: 'completed', userMessageId: 'u4' },
    { turnId: 'r3', ordinal: 3, state: 'rolled_back' }, { turnId: 'r2', ordinal: 2, state: 'cancelled' },
    { turnId: 'r1', ordinal: 1, state: 'completed', userMessageId: 'u1' }],
  rewindCheckpoints: [checkpoint('start', null), checkpoint('after-r1', 1), checkpoint('after-r3', 3)] });

test('editing targets the previous retained run and rejects inherited, steered and unfinished messages', () => {
  const thread = history();
  const target = actions.historyEditTarget(thread, historyMessage);
  assert.equal(target.checkpoint.id, 'after-r1');
  assert.equal(target.witnessRunId, 'r5');
  assert.equal(target.canRestoreFiles, true);
  assert.equal(actions.historyEditTarget(thread, { ...historyMessage, id: 'u1', turnId: 'r1' }).turnCount, 0);
  assert.equal(actions.historyEditTarget(thread, { ...historyMessage, sourceThreadId: 'parent' }), null);
  assert.equal(actions.historyEditTarget(thread, { ...historyMessage, inputIntent: 'steer' }), null);
  thread.turns.unshift({ turnId: 'r6', ordinal: 6, state: 'running' });
  thread.session = { activeTurnId: 'r6' };
  assert.equal(actions.historyEditTarget(thread, historyMessage).checkpoint.id, 'after-r1');
  assert.equal(actions.historyEditTarget(thread, { ...historyMessage, id: 'u6', turnId: 'r6' }), null);
  assert.equal(actions.historyEditTarget({ ...thread, rewindCheckpoints: [checkpoint('after-r1', 1, 'missing')] }, historyMessage).canRestoreFiles, false);
});

test('a history page without predecessor run records cannot select an earlier checkpoint or the thread start', () => {
  const thread = history();
  thread.turns = thread.turns.filter(turn => turn.turnId !== 'r2');
  assert.equal(actions.historyEditTarget(thread, historyMessage), null);
  thread.turns = thread.turns.filter(turn => turn.ordinal >= 4);
  assert.equal(actions.historyEditTarget({ ...thread, hasMoreHistory: true }, historyMessage), null);
  assert.equal(actions.historyEditTarget({ ...thread, hasMoreHistory: false }, historyMessage), null);
});

test('a rollback is complete only when both the suffix and provider conversation have rewound', () => {
  const thread = history(), target = actions.historyEditTarget(thread, historyMessage);
  assert.equal(actions.historyEditCompleted(thread, target), false);
  thread.turns[0].state = 'rolled_back';
  assert.equal(actions.historyEditCompleted(thread, target), false);
  thread.providerThreads[0].lastRunOrdinal = 1;
  assert.equal(actions.historyEditCompleted(thread, target), true);
});
