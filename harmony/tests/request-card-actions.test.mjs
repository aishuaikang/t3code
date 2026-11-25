import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
const read = name => readFileSync(new URL('../app/entry/src/main/ets/' + name, import.meta.url), 'utf8');
const load = source => import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
const models = await load(read('model/Models.ets'));
globalThis.__requestModels = models;
const { RequestDrafts } = await load(read('model/RequestDrafts.ets').replace(/^import .*;$/gm, ''));
globalThis.__requestMocks = { RequestDrafts, selected: [], stores: new Map(), uploaded: [], deleted: [] };
const source = read('pages/RequestCard.ets');
const methods = source.slice(source.indexOf('  aboutToAppear('), source.indexOf('  @Builder')).replaceAll('private ', '');
const { Page, environment } = await load(`
const {questionAnswers}=globalThis.__requestModels;const mocks=globalThis.__requestMocks;const {RequestDrafts}=mocks;
const getContext=()=>({filesDir:'/private'});const AttachmentDraftStore={open:async(...args)=>mocks.open(...args)};
const uploadImage=(...args)=>mocks.upload(...args);const imageUploadExists=async()=>true;const deleteImageUpload=async(_rpc,id)=>mocks.deleted.push(id);
const picker={DocumentViewPicker:class{async select(){return mocks.selected}}};
const photoAccessHelper={PhotoViewPicker:class{async select(){return {photoUris:mocks.selected}}},PhotoViewMIMETypes:{IMAGE_TYPE:1}};
const fileUri={FileUri:class{constructor(uri){this.name=uri.split('/').at(-1)}}};
export const environment={descriptor:{environmentId:'env'},rpc:{},httpBaseUrl:'http://fixture'};const EnvironmentSession={current:environment};
export class Page {
 active=true;loadingAttachments=false;environmentId='env';threadId='thread';canAttach=false;maxFileBytes=1024;online=true;busy=false;picking=false;resolved=false;
 drafts=[];attachmentsReady=true;attachmentGroups=[];stores=new Map();progress=new Map();failures=new Map();upload=null;
 calls=[];onRespond=async(...args)=>{this.calls.push(args);return false};request={requestId:'request',kind:'input',questions:[]};
 ${methods}
}`);

const question = (id, extra = {}) => ({ id, header: 'Question', question: 'Choose', options: [{ label: 'Continue', value: 'native-continue', description: 'Continue' }], ...extra });
test('native option values, custom-answer restrictions and asynchronous dismissal survive request projection', () => {
  const q = question('q', { allowCustomAnswer: false, initialAnswer: 'initial' });
  const state = new models.ThreadState();
  state.apply({ kind: 'snapshot', snapshotSequence: 1, projection: { thread: { id: 'thread' }, messages: [], runs: [], turnItems: [{
    id: 'input', threadId: 'thread', runId: 'run', ordinal: 1, type: 'user_input_request', status: 'pending', requestId: 'request',
    responseMode: 'message', questions: [q], updatedAt: '2026-11-15T00:00:00Z'
  }] } });
  const request = models.pendingRequests(state.activities)[0];
  assert.equal(request.dismissible, true); assert.equal(request.questions[0].options[0].value, 'native-continue');
  assert.equal(request.questions[0].allowCustomAnswer, false); assert.equal(request.questions[0].initialAnswer, 'initial');
  assert.equal(models.questionAnswers([q], [{ questionId: 'q', selected: [], custom: 'disallowed' }]), null);
});

test('single and multiple choices retain their native values across card recreation', () => {
  const page = new Page(); page.request.questions = [question('one'), question('two', { multiSelect: true })];
  page.select(page.request.questions[0], 'native-continue'); page.select(page.request.questions[1], 'A'); page.select(page.request.questions[1], 'B');
  assert.deepEqual(page.answers(), { one: 'native-continue', two: ['A', 'B'] });
  page.select(page.request.questions[1], 'A'); assert.deepEqual(page.answers().two, ['B']);
  const restored = new Page(); restored.request = page.request; restored.aboutToAppear(); assert.deepEqual(restored.drafts, page.drafts);
  restored.aboutToDisappear();
});

test('question files upload on selection, stay isolated by question and survive a failed response', async () => {
  const mocks = globalThis.__requestMocks, page = new Page();
  page.canAttach = true; page.request.questions = [question('a'), question('b')];
  mocks.open = async (_dir, env, id) => {
    assert.equal(env, 'env'); const store = { images: [], cleared: false,
      async addFile(uri, name) { this.images.push({ uri, name, type: 'file', sizeBytes: 10 }); },
      async setUploaded(uri, uploaded) { this.images = this.images.map(row => row.uri === uri ? { ...row, uploaded } : row); },
      async clear() { this.cleared = true; this.images = []; }
    }; mocks.stores.set(id, store); return store;
  };
  mocks.upload = async (_rpc, _base, uri, name, progress, type) => {
    mocks.uploaded.push({ uri, type }); progress(50); return { type, id: uri, name, mimeType: 'application/pdf', sizeBytes: 10 };
  };
  await page.loadAttachments(); mocks.selected = ['private/answer.pdf']; await page.pick('a', true); await page.uploadAttachments();
  assert.equal(mocks.uploaded.length, 1); assert.equal(page.filesFor('a')[0].status, 'uploaded'); assert.deepEqual(page.filesFor('b'), []);
  assert.ok(mocks.stores.has('question:thread:request:a')); assert.ok(mocks.stores.has('question:thread:request:b'));
  page.save({ questionId: 'b', selected: [], custom: '第二个回答' });
  await page.submit(); assert.deepEqual(page.calls[0][1], { a: '', b: '第二个回答' });
  assert.equal(page.calls[0][2].a[0].id, 'private/answer.pdf'); assert.equal(page.resolved, false);
  assert.equal(mocks.stores.get('question:thread:request:a').cleared, false);
  page.onRespond = async () => true; await page.submit(); assert.equal(page.resolved, true);
  assert.equal(mocks.stores.get('question:thread:request:a').cleared, true);
});

test('dismissal is unavailable for blocking native questions and never sends an answer for async questions', async () => {
  const page = new Page(); page.request.questions = [question('q')];
  await page.submit('', true); assert.equal(page.calls.length, 0);
  page.request.dismissible = true; await page.submit('', true);
  assert.deepEqual(page.calls[0], ['', {}, {}, true]);
});

const thread = read('pages/Thread.ets');
const { Thread } = await load(`const util={generateRandomUUID:()=> 'response-command'};const {WS}=globalThis.__requestModels;
export class Thread {
 loaded=true;responding=false;params={threadId:'thread'};calls=[];rpc={call:async(method,payload)=>this.calls.push({method,payload})};
 ${thread.slice(thread.indexOf('  private async respond('), thread.indexOf('  private async loadJournal(')).replaceAll('private ', '')}
}`);
test('responses dispatch per-question attachments and dismissal uses its own command without empty answers', async () => {
  const page = new Thread(), request = { requestId: 'request', kind: 'input', dismissible: true };
  const file = { type: 'file', id: 'file', name: 'file.pdf', mimeType: 'application/pdf', sizeBytes: 10 };
  assert.equal(await page.respond(request, '', { q: '' }, { q: [file] }), true);
  assert.deepEqual(page.calls[0].payload.attachmentsByQuestionId, { q: [file] });
  assert.equal(await page.respond(request, '', {}, {}, true), true);
  assert.equal(page.calls[1].payload.type, 'thread.user-input.dismiss'); assert.equal(page.calls[1].payload.answers, undefined);
  page.rpc.call = async () => { throw new Error('offline'); };
  assert.equal(await page.respond(request, '', { q: 'answer' }), false); assert.match(page.responseError, /offline/);
});

test('approval cards describe current and legacy requests without replacing provider names, warnings or command text', () => {
  const detail = 'printf "%s\\n" "hello"\n'.repeat(30) + '# last line';
  const options = [{ label: 'Allow this tool', decision: 'acceptForSession', warning: 'Applies to this session' }, { label: 'Stop', decision: 'cancel' }];
  const project = payload => models.pendingRequests([{ id: 'a', kind: 'approval.requested', createdAt: '2026-11-25',
    payload: { requestId: 'r', detail, options, ...payload } }])[0];
  for (const [type, kind, title] of [['exec_command_approval', 'command', '运行命令'], ['file_read_approval', 'file-read', '读取文件'],
    ['apply_patch_approval', 'file-change', '修改文件'], ['mcp_elicitation_approval', 'mcp-elicitation', '工具请求'], ['permission_approval', 'permission', '请求权限']]) {
    const request = project({ requestType: type });
    assert.equal(request.approvalKind, kind); assert.equal(request.title, title); assert.equal(project({ requestKind: kind }).title, title);
  }
  const named = project({ requestKind: 'command', appName: 'Workspace tools' });
  assert.equal(named.title, 'Workspace tools'); assert.equal(named.approvalKind, 'command'); assert.equal(named.detail, detail); assert.deepEqual(named.options, options);
  assert.equal(project({}).title, '操作授权'); assert.equal(project({ requestKind: 'Custom operation' }).title, 'Custom operation');
});

test('approval decisions retain their exact scope; offline, duplicate and already submitted taps do not dispatch', async () => {
  for (const decision of ['accept', 'acceptForSession', 'acceptAlways', 'decline', 'cancel']) {
    const card = new Page(), thread = new Thread(); card.request = { kind: 'approval', requestId: 'approval', questions: [] };
    let finish; const gate = new Promise(resolve => { finish = resolve; });
    card.onRespond = async (...args) => { await gate; return thread.respond(card.request, ...args); };
    card.online = false; await card.submit(decision); assert.equal(card.picking, false);
    card.online = true; const send = card.submit(decision); await card.submit(decision);
    finish(); await send; await card.submit(decision); assert.equal(thread.calls.length, 1);
    const command = thread.calls[0].payload;
    assert.equal(command.type, 'thread.approval.respond'); assert.equal(command.decision, decision); assert.equal(command.requestId, 'approval');
    assert.equal(command.answers, undefined); assert.equal(card.resolved, true);
  }
});
