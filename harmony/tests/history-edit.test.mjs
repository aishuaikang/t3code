import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const read = (name) => readFileSync(new URL(`../app/entry/src/main/ets/${name}.ets`, import.meta.url), 'utf8');
const withoutImports = (name) => read(name).replace(/^import .*;$/gm, '');
const thread = read('pages/Thread');
const methods = (from, to) => thread.slice(thread.indexOf(from), thread.indexOf(to)).replaceAll('private ', '');
const source = `
${withoutImports('model/MessageActions')}
${withoutImports('model/MessageQuote')}
const EnvironmentSession = { current: { httpBaseUrl:'http://fixture', descriptor:{ environmentId:'env' } } };
const WS = { threadStartTurn: 'orchestration.dispatchCommand' };
const DialogButtonStyle = { HIGHLIGHT: 1 }, DialogButtonDirection = { VERTICAL: 2 };
const util = { generateRandomUUID: () => 'request' };
const getContext = (page) => ({ cacheDir: page });
class RpcRemoteError extends Error {}
class TranscriptFrame { constructor(action) { this.action = action; } }
class FileDownload {
  async fetch(_rpc, _baseUrl, resource, page) {
    this.page = page; this.path = resource.attachmentId; page.downloaded.push(resource);
    if (this.path === page.missing) throw new Error('附件已不存在');
  }
  localFile() { return this.path; }
  async dispose() { this.page.disposed.push(this.path); }
}
export class Fixture {
  params = { threadId:'thread', environmentId:'env' };
  active=true; readVisible=true; loaded=true; draftReady=true; imagesReady=true; journalReady=true;
  rollbackProviders=['codex']; observeRewind=null; stopRewindObservation=null;
  draft='Existing draft'; draftQuote=null; draftTimer=-1; imageUpload=null;
  saved=[]; downloaded=[]; disposed=[]; calls=[]; focused=0; jumps=0; missing='';
  message={ id:'message', role:'user', sourceThreadId:'thread', turnId:'run2', inputIntent:'turn_start', text:'Try again',
    attachments:[{type:'image',id:'old-image',name:'photo.png',mimeType:'image/png'}, {type:'file',id:'old-file',name:'report.pdf',mimeType:'application/pdf'}] };
  state={ messages:[this.message], thread:{ id:'thread', activeProviderThreadId:'provider',
    providerThreads:[{id:'provider',providerInstanceId:'codex',lastRunOrdinal:2}],
    turns:[{turnId:'run2',ordinal:2,state:'completed'},{turnId:'run1',ordinal:1,state:'completed'}],
    rewindCheckpoints:[{id:'checkpoint',scopeId:'scope',appRunOrdinal:1,ordinalWithinScope:1,status:'missing'}] } };
  imageStore={ images:[{uri:'existing-attachment'}],
    add:async (uri,name) => this.stage(uri,name,'image'),
    addFile:async (uri,name,_limit,keepType) => this.stage(uri,name,keepType?'file':'untyped'),
    remove:async (uri) => { this.imageStore.images=this.imageStore.images.filter((item)=>item.uri!==uri); } };
  draftStore={ save:async (text)=>{ this.saved.push(text); } };
  rpc={ call:async (method,command)=>{ this.calls.push({method,command}); this.didDispatch?.(); } };
  composerController={ requestFocus:()=>{ this.focused++; } };
  stage(uri,name,type) { const image={uri,name,type}; this.imageStore.images.push(image); return image; }
  color(role){return role;}
  getUIContext(){return {postFrameCallback:(frame)=>frame.action(),showAlertDialog:(dialog)=>{this.dialog=dialog;}};}
  jumpToLatest(){this.jumps++;}
  uploadDraftImages(){}
  cancelPaths(){}
  run(){ return this.rewindMessage(this.message, this.targetForHistoryEdit(this.message), false); }
  ${methods('  private targetForHistoryEdit(', '  private waitForRewind(')}
  ${methods('  private waitForRewind(', '  private openSubagent(')}
  ${methods('  private async rewindMessage(', '  private async forkMessage(')}
}`;
const { Fixture } = await import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(source)).toString('base64'));

const dispatchOf = (page) => new Promise((resolve) => { page.didDispatch = resolve; });

test('the confirmation keeps file restore visible and only enables it for an available worktree snapshot', () => {
  const page = new Fixture();
  const open = () => page.confirmHistoryEdit({ id: page.message.id });
  const button = (value) => page.dialog.buttons.find(entry => entry.value === value);
  open();
  assert.equal(button('同时还原文件').enabled, false);
  button('取消').action();
  button('同时还原文件').action();
  assert.deepEqual(page.calls, []);
  assert.deepEqual(page.saved, []);
  assert.deepEqual(page.downloaded, []);

  page.state.thread.rewindCheckpoints[0].status = 'ready';
  open();
  assert.equal(button('同时还原文件').enabled, false);
  page.state.thread.worktreePath = '/isolated-worktree';
  open();
  assert.equal(button('同时还原文件').enabled, true);
});

test('the prompt and both attachment kinds reach durable draft storage before dispatch, with focus after rollback', async () => {
  const page = new Fixture();
  const dispatched = dispatchOf(page);
  const editing = page.run();
  await dispatched;
  assert.deepEqual(page.calls, [{method:'orchestration.dispatchCommand',command:{type:'checkpoint.rollback',commandId:'request',threadId:'thread',
    scopeId:'scope',checkpointId:'checkpoint',restoreFiles:false}}]);
  assert.equal(page.saved.at(-1), 'Existing draft\n\nTry again');
  assert.deepEqual(page.imageStore.images.map((image) => image.type), [undefined, 'image', 'file']);
  assert.deepEqual(page.disposed, ['old-image', 'old-file']);
  page.state.thread.providerThreads[0].lastRunOrdinal = 1;
  page.observeRewind();
  assert.equal(page.focused, 0);
  page.state.thread.turns[0].state = 'rolled_back';
  page.observeRewind();
  await editing;
  assert.equal(page.focused, 1);
  assert.deepEqual(page.imageUris, ['existing-attachment', 'old-image', 'old-file']);
});

test('a missing attachment aborts before rollback and removes only files staged for the edit', async () => {
  const page = new Fixture(); page.missing = 'old-file';
  await page.run();
  assert.deepEqual(page.calls, []);
  assert.deepEqual(page.disposed, ['old-image', 'old-file']);
  assert.deepEqual(page.imageUris, ['existing-attachment']);
  assert.equal(page.draft, 'Existing draft');
  assert.match(page.operationError, /附件已不存在/);
});

test('a historical edit target remains available during a run but cannot start a rollback or stage a draft', async () => {
  const page = new Fixture();
  const target = page.targetForHistoryEdit(page.message);
  page.state.thread.turns.unshift({ turnId: 'run3', ordinal: 3, state: 'running' });
  page.state.thread.session = { status: 'running', activeTurnId: 'run3' };
  assert.deepEqual(page.targetForHistoryEdit(page.message), target);
  await page.rewindMessage(page.message, target, false);
  assert.deepEqual(page.calls, []);
  assert.deepEqual(page.downloaded, []);
  assert.deepEqual(page.saved, []);
});

test('a new run or a replaced checkpoint during draft persistence prevents rollback and keeps the previous draft', async () => {
  for (const update of [
    (thread) => thread.turns.unshift({ turnId: 'run3', ordinal: 3, state: 'completed' }),
    (thread) => {
      thread.turns.unshift({ turnId: 'run3', ordinal: 3, state: 'running' });
      thread.session = { status: 'running', activeTurnId: 'run3' };
    },
    (thread) => { thread.rewindCheckpoints[0] = { ...thread.rewindCheckpoints[0], id: 'replacement' }; }
  ]) {
    const page = new Fixture();
    page.draftStore.save = async (text) => {
      page.saved.push(text);
      if (text.includes('Try again')) update(page.state.thread);
    };
    page.didDispatch = () => { page.state.thread.rollbackFailure = { requestId: 'request', message: 'Unexpected rollback' }; };
    await page.run();
    assert.deepEqual(page.calls, []);
    assert.deepEqual(page.saved, ['Existing draft\n\nTry again', 'Existing draft']);
    assert.deepEqual(page.imageUris, ['existing-attachment']);
    assert.match(page.operationError, /会话已变化/);
  }
});

test('an explicit rollback failure restores the previous draft while an uncertain result keeps recovery files', async () => {
  for (const rejected of [true, false]) {
    const page = new Fixture(), dispatched = dispatchOf(page);
    const editing = page.run();
    await dispatched;
    if (rejected) {
      page.state.thread.rollbackFailure = { requestId: 'request', message: '已拒绝回退' };
      page.observeRewind();
    } else page.stopRewindObservation();
    await editing;
    assert.equal(page.draft, rejected ? 'Existing draft' : 'Existing draft\n\nTry again');
    assert.equal(page.saved.at(-1), page.draft);
    assert.equal(page.imageUris.length, rejected ? 1 : 3);
    assert.equal(page.focused, 0);
  }
});
