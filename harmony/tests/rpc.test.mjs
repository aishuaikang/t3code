import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

// Only the platform transport is replaced. Requests, dispatch and lifecycle
// execute the same ArkTS source shipped in the HAP.
class Socket {
  handlers = new Map();
  sent = [];
  reply = null;
  on(event, callback) { this.handlers.set(event, callback); }
  off(event) { this.handlers.delete(event); }
  connect(_url, callback) { this.connectCallback=callback; callback(null); if (!globalThis.__stallSocket) this.handlers.get('open')?.(); }
  send(text) {
    const frame = JSON.parse(text);
    this.sent.push(frame);
    this.reply?.(frame);
    return Promise.resolve(true);
  }
  receive(frame) { this.handlers.get('message')?.(null, JSON.stringify(frame)); }
  receiveBytes(frame) { this.handlers.get('message')?.(null, new TextEncoder().encode(JSON.stringify(frame)).buffer); }
  close() { this.closed=true; this.handlers.get('close')?.(); return Promise.resolve(true); }
}
let socket;
globalThis.__harmonySocket = { createWebSocket() { socket = new Socket(); return socket; } };
const source = readFileSync(new URL('../app/entry/src/main/ets/connection/Rpc.ets', import.meta.url), 'utf8')
  .replace("import webSocket from '@ohos.net.webSocket';", 'const webSocket = globalThis.__harmonySocket;')
  .replace("import util from '@ohos.util';", "const util = { TextDecoder: { create: encoding => ({ decodeToString: value => new TextDecoder(encoding).decode(value) }) } };");
const { RpcClient } = await import('data:text/javascript;base64,' +
  Buffer.from(stripTypeScriptTypes(source)).toString('base64'));

async function withClient(run) {
  const client = new RpcClient();
  await client.connect('ws://test.invalid/ws');
  try { await run(client, socket); } finally { client.close(); }
}
async function settled(promise) {
  let timer;
  try {
    return await Promise.race([promise, new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error('request did not settle')), 300);
    })]);
  } finally { clearTimeout(timer); }
}

test('uses Effect header tuples and resolves a void response', () => withClient(async (client, peer) => {
  const result = client.call('terminal.write', { terminalId: 'term', data: 'x' });
  assert.deepEqual(peer.sent[0].headers, []);
  peer.receive({ _tag: 'Exit', requestId: peer.sent[0].id, exit: { _tag: 'Success' } });
  assert.equal(await settled(result), undefined);
}));

test('registers the request before a transport can return a response', () => withClient(async (client, peer) => {
  peer.reply = frame => {
    if (frame._tag === 'Request') peer.receive({ _tag: 'Exit', requestId: frame.id,
      exit: { _tag: 'Success', value: { ok: true } } });
  };
  assert.deepEqual(await settled(client.call('server.probe', {})), { ok: true });
}));

test('creates tasks with mobile provenance while preserving saved draft command identities', () => withClient(async (client, peer) => {
  peer.reply = frame => {
    if(frame._tag==='Request') peer.receive({_tag:'Exit',requestId:frame.id,exit:{_tag:'Success'}});
  };
  const saved = {type:'thread.create',commandId:'saved-command',threadId:'saved-thread',projectId:'p',
    title:'Draft',modelSelection:{instanceId:'codex',model:'gpt'},runtimeMode:'auto',interactionMode:'default',
    branch:null,worktreePath:null,createdAt:'2026-11-14T00:00:00.000Z'};
  const before = structuredClone(saved);
  await client.call('orchestration.dispatchCommand',saved);
  await client.call('orchestration.dispatchCommand',saved);
  assert.equal(peer.sent[0].payload.createdBy,'user');
  assert.equal(peer.sent[0].payload.creationSource,'mobile');
  assert.equal(peer.sent[0].payload.commandId,saved.commandId);
  assert.equal(peer.sent[0].payload.threadId,saved.threadId);
  assert.deepEqual(peer.sent[0].payload,peer.sent[1].payload);
  assert.deepEqual(saved,before);
}));

test('dispatches journaled first messages with the current wire schema without changing local records', () => withClient(async (client, peer) => {
  peer.reply = frame => {
    if(frame._tag==='Request') peer.receive({_tag:'Exit',requestId:frame.id,exit:{_tag:'Success'}});
  };
  const saved = {type:'thread.turn.start',commandId:'retry-command',threadId:'t',
    message:{messageId:'same-message',role:'user',text:'Hello',attachments:[{type:'file',id:'a'}]},
    runtimeMode:'auto',interactionMode:'default',createdAt:'now'};
  const before = structuredClone(saved);
  await client.call('orchestration.dispatchCommand',saved);
  assert.deepEqual(peer.sent[0].payload,{type:'message.dispatch',createdBy:'user',creationSource:'mobile',
    commandId:'retry-command',threadId:'t',messageId:'same-message',text:'Hello',attachments:[{type:'file',id:'a'}],
    dispatchMode:{type:'start_immediately'}});
  assert.deepEqual(saved,before);
}));

test('an interrupt keeps the run selected at tap time even if another run has started before dispatch', () => withClient(async (client, peer) => {
  const models = readFileSync(new URL('../app/entry/src/main/ets/model/Models.ets', import.meta.url), 'utf8');
  const { interruptTurnCommand } = await import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(models)).toString('base64'));
  const thread = { id: 't', session: { status: 'running', activeTurnId: 'r1' } };
  const command = interruptTurnCommand(thread, 'stop', true);
  thread.session.activeTurnId = 'r2';
  peer.reply = f => peer.receive({ _tag: 'Exit', requestId: f.id, exit: { _tag: 'Success' } });
  await client.call('orchestration.dispatchCommand', command);
  assert.deepEqual(peer.sent[0].payload, { type: 'run.interrupt', commandId: 'stop', threadId: 't', runId: 'r1', holdQueue: true });
}));

test('acknowledges each processed stream chunk so the server can continue', () => withClient(async (client, peer) => {
  const values = [];
  const done = client.callStream('orchestration.subscribeThread', {}, chunk => values.push(...chunk));
  const id = peer.sent[0].id;
  peer.receive({ _tag: 'Chunk', requestId: id, values: [{ sequence: 1 }] });
  assert.deepEqual(values, [{ sequence: 1 }]);
  assert.deepEqual(peer.sent[1], { _tag: 'Ack', requestId: id });
  peer.receive({ _tag: 'Exit', requestId: id, exit: { _tag: 'Success' } });
  await settled(done);
}));

test('processes UTF-8 binary stream frames and acknowledges them before the next chunk', () => withClient(async (client, peer) => {
  const values = [];
  const done = client.callStream('orchestration.subscribeThread', {}, chunk => values.push(...chunk));
  done.catch(() => {});
  const id = peer.sent[0].id;
  peer.receiveBytes({ _tag: 'Chunk', requestId: id, values: [{ text: '你好', sequence: 1 }] });
  assert.deepEqual(values, [{ text: '你好', sequence: 1 }]);
  assert.deepEqual(peer.sent[1], { _tag: 'Ack', requestId: id });
  peer.receiveBytes({ _tag: 'Exit', requestId: id, exit: { _tag: 'Success' } });
  await done;
}));

test('fresh sessions and side questions preserve journal identity on the current message wire format', () => withClient(async (client, peer) => {
  peer.reply = frame => { if (frame._tag === 'Request') peer.receive({ _tag: 'Exit', requestId: frame.id, exit: { _tag: 'Success' } }); };
  const saved = { type: 'thread.turn.start', commandId: 'cmd', threadId: 'source', freshContext: true,
    composerText: '/clear Hello', message: { messageId: 'm', text: 'Hello', attachments: [] } };
  await client.call('orchestration.dispatchCommand', saved);
  assert.equal(peer.sent[0].payload.freshContext, true); assert.equal(peer.sent[0].payload.composerText, undefined);
  await client.call('orchestration.dispatchCommand', { ...saved, freshContext: undefined, sideThreadId: 'side' });
  assert.equal(peer.sent[1].payload.threadId, 'side'); assert.equal(peer.sent[1].payload.messageId, 'm');
  assert.equal(saved.threadId, 'source');
  await client.call('orchestration.dispatchCommand', { ...saved, dispatchMode: { type: 'queue_after_active' } });
  assert.equal(peer.sent[2].payload.dispatchMode.type, 'queue_after_active');
  const pick={instanceId:'claude',model:'fable',options:[{id:'effort',value:'max'},{id:'ultracode',value:true},{id:'fastMode',value:false}]};
  const queued={...saved,freshContext:undefined,modelSelection:pick,dispatchMode:{type:'queue_after_active'}};
  await client.call('orchestration.dispatchCommand',queued);
  assert.deepEqual(peer.sent[3].payload.modelSelection,pick);assert.equal(peer.sent[3].payload.dispatchMode.type,'queue_after_active');
  await client.call('orchestration.dispatchCommand',queued);assert.deepEqual(peer.sent[4].payload,peer.sent[3].payload);
}));

test('current timeline request cards answer through the runtime-request command', () => withClient(async (client, peer) => {
  peer.reply = frame => { if (frame._tag === 'Request') peer.receive({ _tag: 'Exit', requestId: frame.id, exit: { _tag: 'Success' } }); };
  const command = { type: 'thread.user-input.respond', commandId: 'answer', threadId: 't', requestId: 'request', answers: { q: 'yes' } };
  await client.call('orchestration.dispatchCommand', command);
  assert.equal(peer.sent[0].payload.type, 'runtime-request.respond'); assert.equal(command.type, 'thread.user-input.respond');
  assert.deepEqual(peer.sent[0].payload.answers, { q: 'yes' });
}));

test('rejects in-flight work when the socket closes', () => withClient(async (client, peer) => {
  const result = client.call('server.probe', {});
  peer.close();
  await assert.rejects(settled(result), /closed|disconnect/i);
}));

test('rejects calls made without an open connection', async () => {
  const client = new RpcClient();
  await assert.rejects(settled(client.call('server.probe', {})), /connected|closed/i);
});

test('tolerates delayed pongs while valid stream traffic keeps the connection alive', async (t) => {
  t.mock.timers.enable({ apis: ['setInterval', 'Date'], now: 1000 });
  await withClient(async (client, peer) => {
    const values = [];
    const done = client.callStream('orchestration.subscribeThread', {}, chunk => values.push(...chunk));
    done.catch(() => {});
    const id = peer.sent[0].id;
    t.mock.timers.tick(15000);
    peer.receive({ _tag: 'Pong' });
    for (let i = 0; i < 8; i++) {
      t.mock.timers.tick(5000);
      peer.receive({ _tag: 'Chunk', requestId: id, values: [{ sequence: i }] });
    }
    assert.equal(values.length, 8);
    peer.receive({ _tag: 'Exit', requestId: id, exit: { _tag: 'Success' } });
    await done;
  });
});

test('closes a silent connection after the heartbeat deadline', async (t) => {
  t.mock.timers.enable({ apis: ['setInterval', 'Date'], now: 1000 });
  await withClient(async (client) => {
    const done = client.callStream('orchestration.subscribeThread', {}, () => {});
    const closed = assert.rejects(done, /closed/i);
    t.mock.timers.tick(30000);
    await closed;
  });
});

test('background time does not expire a healthy socket and foreground probes reuse its stream', async t => {
  t.mock.timers.enable({apis:['setInterval','setTimeout','Date'],now:1000});
  await withClient(async(client,peer)=>{
    const chunks=[];
    const done=assert.rejects(client.callStream('orchestration.subscribeThread',{},values=>chunks.push(...values)),/closed/i);
    const id=peer.sent[0].id;
    client.setForeground(false);t.mock.timers.tick(120000);
    assert.notEqual(peer.closed,true);assert.equal(peer.sent.length,1);
    client.setForeground(true);assert.equal(peer.sent.at(-1)._tag,'Ping');
    peer.receive({_tag:'Pong'});t.mock.timers.tick(10000);
    peer.receive({_tag:'Chunk',requestId:id,values:[{sequence:2}]});
    assert.notEqual(peer.closed,true);assert.deepEqual(chunks,[{sequence:2}]);
    peer.close();await done;
  });
});

test('a silent resumed socket is closed within the probe deadline and duplicate probes do not prolong it', async t => {
  t.mock.timers.enable({apis:['setInterval','setTimeout','Date'],now:1000});
  await withClient(async(client,peer)=>{
    client.setForeground(false);t.mock.timers.tick(60000);client.setForeground(true);
    const closed=assert.rejects(client.callStream('orchestration.subscribeThread',{},()=>{}),/closed/i);
    t.mock.timers.tick(9000);assert.notEqual(peer.closed,true);client.probe();
    t.mock.timers.tick(1000);await closed;assert.equal(peer.closed,true);
  });
});

test('connection timeout and explicit cancellation settle stalled handshakes', async (t) => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  globalThis.__stallSocket = true;
  const client = new RpcClient();
  try {
    const opening = client.connect('ws://test.invalid/ws');
    const timedOut = assert.rejects(opening, /closed|timeout/i);
    t.mock.timers.tick(10000);
    await timedOut;
    const second = client.connect('ws://test.invalid/ws');
    client.close();
    await assert.rejects(second, /closed/i);
  } finally { globalThis.__stallSocket = false; client.close(); }
});

test('late events from an old socket cannot close or feed the replacement connection', () => withClient(async (client, old) => {
  const callbacks=new Map(old.handlers);
  await client.connect('ws://test.invalid/replacement');const current=socket;
  const result=client.call('server.probe',{});const received=assert.doesNotReject(result);
  callbacks.get('error')();callbacks.get('close')();callbacks.get('open')();
  callbacks.get('message')(null,'invalid old frame');old.connectCallback(new Error('late failure'));
  current.receive({_tag:'Exit',requestId:current.sent[0].id,exit:{_tag:'Success',value:{ok:true}}});
  await received;assert.deepEqual(await result,{ok:true});
}));

test('a late send failure belongs only to the socket that sent the request', () => withClient(async (client, old) => {
  let finishSend;old.send=()=>new Promise(resolve=>finishSend=resolve);
  const oldResult=assert.rejects(client.call('server.probe',{}),/closed/i);
  await client.connect('ws://test.invalid/replacement');await oldResult;const current=socket;
  const result=client.call('server.probe',{});const received=assert.doesNotReject(result);
  finishSend(false);for(let i=0;i<6;i++)await Promise.resolve();
  current.receive({_tag:'Exit',requestId:current.sent[0].id,exit:{_tag:'Success',value:{ok:true}}});
  await received;assert.deepEqual(await result,{ok:true});
}));

test('preserves a definitive command rejection separately from unknown delivery failures', () => withClient(async (client, peer) => {
  for (const [tag, name, definitive] of [
    ['OrchestrationDispatchCommandError', 'OrchestrationCommandInvariantError', true],
    ['OrchestrationDispatchCommandError', 'OrchestrationCommandPreviouslyRejectedError', true],
    ['EnvironmentAuthorizationError', '', true],
    ['OrchestrationDispatchCommandError', 'DatabaseError', false],
    ['AssetAttachmentNotFoundError', '', false],
  ]) {
    const result = client.call('orchestration.dispatchCommand', {});
    const id = peer.sent.at(-1).id;
    peer.receive({_tag:'Exit',requestId:id,exit:{_tag:'Failure',cause:[{_tag:'Fail',error:{_tag:tag,message:'Rejected fixture',cause:{name}}}]}});
    await assert.rejects(result, error => error.remoteTag === tag && error.message.includes(tag) && error.definitivelyRejected === definitive);
  }
  const pending = client.call('orchestration.dispatchCommand', {});
  peer.close();
  await assert.rejects(pending, error => error.definitivelyRejected !== true);
}));

test('restores attachments explicitly rejected before command dispatch', () => withClient(async (client, peer) => {
  for (const [message, definitive] of [
    ["Attachment 'image.jpg' cannot be sent: attachment not found.", true],
    ["Attachment 'image.jpg' cannot be sent: attachment not found (removed or expired).", true],
    ["Attachment 'image.jpg' cannot be sent: stored size does not match.", true],
    ["Attachment 'image.jpg' cannot be sent: attachment type does not match the upload.", true],
    ['Failed to dispatch orchestration command', false],
  ]) {
    const result = client.call('orchestration.dispatchCommand', {});
    peer.receive({_tag:'Exit',requestId:peer.sent.at(-1).id,exit:{_tag:'Failure',cause:[{_tag:'Fail',error:{_tag:'OrchestrationDispatchCommandError',message,cause:{name:'SystemError'}}}]}});
    await assert.rejects(result, error => error.definitivelyRejected === definitive);
  }
}));


test('allows correcting workspace paths rejected by pre-dispatch normalization', () => withClient(async (client, peer) => {
  for (const [message, definitive] of [
    ['Workspace root is not a directory: /fixture/file.txt', true],
    ['Workspace root does not exist: /fixture/missing', true],
    ['Failed to create workspace root: /fixture/denied', true],
    ["Failed to stat workspace root '/fixture/path' during 'validate-existing'.", true],
    ["Failed to stat workspace root '/fixture/path' during 'verify-created'.", true],
    ["Failed to stat workspace root '/fixture/path' during 'validate-created'.", false],
    ['Failed to dispatch orchestration command', false],
    ["Failed to stat workspace root '/fixture/path' during 'commit'.", false],
  ]) {
    const result = client.call('orchestration.dispatchCommand', { type: 'project.create' });
    peer.receive({_tag:'Exit',requestId:peer.sent.at(-1).id,exit:{_tag:'Failure',cause:[{_tag:'Fail',error:{_tag:'OrchestrationDispatchCommandError',message}}]}});
    await assert.rejects(result, error => error.definitivelyRejected === definitive);
  }
}));

test('V2 dispatch distinguishes explicit server rejections from an uncertain projection or database failure', () => withClient(async (client, peer) => {
  const tag='OrchestrationV2DispatchCommandError';
  for(const [cause,message,expected] of [
    [{name:'OrchestratorCommandRejectedError'},'Request rejected',true], [{_tag:'OrchestratorCommandPreviouslyRejectedError'},'Rejected previously',true],
    [{name:'OrchestratorSubagentThreadReadOnlyError'},'Read-only thread',true], [{name:'OrchestratorProviderSelectionBusyError'},'Busy',true],
    [{name:'SystemError'},"Attachment 'photo' cannot be sent: attachment not found.",true],
    [{name:'OrchestratorDispatchError'},'Unknown delivery status',false], [{name:'SqlError'},'Write failed',false],
  ]) {const pending=client.call('orchestration.dispatchCommand',{});peer.receive({_tag:'Exit',requestId:peer.sent.at(-1).id,exit:{_tag:'Failure',cause:[{_tag:'Fail',error:{_tag:tag,message,cause}}]}});await assert.rejects(pending,e=>e.definitivelyRejected===expected);}
}));

test('thread pages share a socket; closing one interrupts only its streams and cannot close the task list', () => withClient(async (home, peer) => {
  const chat = home.openScope(), other = home.openScope(), events = [];
  const rootStream = home.callStream('shell', {}, values => events.push(...values));
  const threadStream = chat.callStream('thread', {}, () => chat.close());
  const query = other.call('detail', {});
  const [shell, thread, detail] = peer.sent.map(frame => frame.id);
  assert.equal(new Set([shell, thread, detail]).size, 3);
  peer.receive({_tag:'Chunk', requestId:thread, values:['close this page']});
  await assert.rejects(threadStream, /closed/);
  assert.deepEqual(peer.sent.filter(frame => frame._tag === 'Interrupt'), [{_tag:'Interrupt', requestId:thread}]);
  assert.ok(!peer.closed);
  peer.receive({_tag:'Chunk', requestId:shell, values:['still live']});
  peer.receive({_tag:'Exit', requestId:detail, exit:{_tag:'Success', value:{id:'other'}}});
  assert.deepEqual(await query, {id:'other'}); assert.deepEqual(events, ['still live']);
  await assert.rejects(chat.call('stale', {}), /connected|closed/);
  const pending = other.call('still-pending', {});
  peer.close(); await assert.rejects(pending, /closed/); await assert.rejects(rootStream, /closed/);
  assert.equal(home.openScope(), null); assert.equal(other.probe(), false);
}));


test('a transport failure while leaving a shared thread settles every pending subscription', () => withClient(async (home, peer) => {
  const page = home.openScope();
  const shell = home.callStream('shell', {}, () => {}), detail = page.callStream('thread', {}, () => {});
  peer.send = () => {throw new Error('socket closed during send');};
  page.close();
  await assert.rejects(detail, /closed/); await assert.rejects(shell, /closed/); assert.equal(home.isOpen(), false);
}));

test('a rejected checkout shows the available reason without leaking the wire error or inferring a conflict', () => withClient(async (client, peer) => {
  const base = { _tag: 'GitCommandError', operation: 'GitVcsDriver.switchRef.checkout', cwd: '/fixture', exitCode: 1, stderrLength: 172 };
  for (const [failure, expected] of [
    [{ ...base, detail: 'git checkout failed' }, /检查.*本地改动/],
    [{ ...base, detail: 'another worktree already uses feature' }, /another worktree already uses feature/],
    [{ _tag: 'EnvironmentAuthorizationError', message: 'permission denied' }, /permission denied/],
  ]) {
    const pending = client.call('vcs.switchRef', { cwd: '/fixture', refName: 'feature' });
    peer.receive({ _tag: 'Exit', requestId: peer.sent.at(-1).id, exit: { _tag: 'Failure', cause: [{ _tag: 'Fail', error: failure }] } });
    await assert.rejects(pending, error => { assert.match(error.message, expected); assert.doesNotMatch(error.message, /_tag|stderrLength|\/fixture|RPC vcs/); return true; });
  }
}));

test('unlocking after a long sleep resumes missed records on a fresh socket even if the old peer still answers pings', async t => {
  t.mock.timers.enable({ apis: ['setInterval', 'setTimeout', 'Date'], now: 1000 });
  const reconnect = readFileSync(new URL('../app/entry/src/main/ets/connection/ReconnectingRpc.ets', import.meta.url), 'utf8').replace(/^import .*;$/gm, '');
  const { ReconnectingRpc } = await import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(reconnect)).toString('base64'));
  const drain = async () => { for (let i = 0; i < 12; i++) await Promise.resolve(); };
  const peers = [], messages = [];
  const session = new ReconnectingRpc(async () => {
    const client = new RpcClient(); await client.connect('ws://test.invalid/ws'); peers.push(socket); return client;
  }, client => client.callStream('orchestration.subscribeThread', { afterSequence: messages.length }, chunk => {
    messages.push(...chunk); session.healthy();
  }), () => {});
  t.after(() => { session.stop(); ReconnectingRpc.setForeground(true); });
  session.start(); await drain();
  const old = peers[0], id = old.sent[0].id;
  old.receive({ _tag: 'Chunk', requestId: id, values: ['on screen before lock'] });
  old.reply = frame => { if (frame._tag === 'Ping') old.receive({ _tag: 'Pong' }); };
  ReconnectingRpc.setForeground(false); t.mock.timers.tick(10 * 60 * 1000);
  assert.equal(peers.length, 1); assert.notEqual(old.closed, true);
  ReconnectingRpc.setForeground(true); await drain();
  assert.equal(peers.length, 2, 'a Pong on the old socket cannot confirm that its subscription survived sleep');
  assert.equal(old.closed, true);
  const request = peers[1].sent.find(frame => frame._tag === 'Request');
  assert.equal(request.payload.afterSequence, 1);
  old.receive({ _tag: 'Chunk', requestId: id, values: ['stale'] });
  peers[1].receive({ _tag: 'Chunk', requestId: request.id, values: ['arrived while locked'] });
  assert.deepEqual(messages, ['on screen before lock', 'arrived while locked']);
});
