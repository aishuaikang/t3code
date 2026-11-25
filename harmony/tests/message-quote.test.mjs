import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
const read = path => readFileSync(new URL('../app/entry/src/main/ets/' + path, import.meta.url), 'utf8');
const load = source => import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
const quoteModel = read('model/MessageQuote.ets').replace(/^import .*;$/gm, '');
const q = await load(quoteModel);
const quote = (extra = {}) => ({ environmentId: 'env', threadId: 'thread', messageId: 'original', role: 'assistant', text: '原回复', ...extra });
const message = (extra = {}) => ({ id: 'original', kind: 'message', role: 'assistant', text: '原回复', attachments: [], ...extra });

test('both roles can be quoted, while thinking, tool output, empty and unfinished messages cannot', () => {
  for (const role of ['user', 'assistant']) assert.equal(q.canQuoteMessage(message({ role })), true);
  for (const extra of [{ kind: 'thinking' }, { kind: 'tool' }, { role: 'system' }, { text: ' ' }, { streaming: true }]) {
    assert.equal(q.canQuoteMessage(message(extra)), false);assert.equal(q.createMessageQuote(message(extra), 'env', 'thread'), null);
  }
  const onlyImage = message({ text: '', attachments: [{ type: 'image', name: '照片.png' }] });
  assert.equal(q.createMessageQuote(onlyImage, 'env', 'thread').text, '[图片] 照片.png');
});

test('quoting preserves exact Chinese, emoji, code, empty lines and reply text with readable cross-client blockquotes', () => {
  for (const role of ['user', 'assistant']) {
    const source = quote({ role, text: '第一行 🧑‍💻\n\n```ts\n  x = "</quote>";\n```\n> 原引用\n' });
    const body = '\n我的回复\n> 回复内的引用\n';
    const raw = q.quotedMessageText(body, source);
    assert.deepEqual(q.parseQuotedMessage(raw), { text: body, quote: source });
    assert.ok(raw.includes('> 第一行 🧑‍💻\n> \n> ```ts'));
    assert.equal(q.quotedMessageText('普通消息', null), '普通消息');
  }
});

test('quote identifiers cannot break the hidden metadata and inherited messages retain their source thread', () => {
  const original = quote({ environmentId: 'env / ()', threadId: 'thread-->\n中文', messageId: 'id--><tag>"' });
  const raw = q.quotedMessageText('', original);
  assert.deepEqual(q.parseQuotedMessage(raw), { text: '', quote: original });
  assert.ok(!raw.substring(0, raw.indexOf('\n')).includes('id-->'));
  assert.equal(q.createMessageQuote(message({ sourceThreadId: 'parent' }), 'env', 'child').threadId, 'parent');
});

test('quoting a quoted reply takes that reply body once, without recursively repeating older quotes', () => {
  const original = message({ role: 'user', text: q.quotedMessageText('我新的问题', quote()) });
  const quoted = q.createMessageQuote(original, 'env', 'thread');
  assert.equal(quoted.text, '我新的问题');assert.equal(quoted.role, 'user');assert.equal(quoted.messageId, 'original');
});

test('ordinary Markdown, malformed metadata and incomplete quote blocks are left intact', () => {
  const valid = q.quotedMessageText('回复', quote());
  for (const raw of ['> 我\n> 普通引用\n\n回复', '<!-- ordinary comment -->\ntext', valid.replace('v1 ', 'v2 '),
    valid.replace(/%7B.*%7D/, '%ZZ'), valid.replace('> AI', '> 我'), valid.substring(0, valid.lastIndexOf('\n\n')),
    valid.replace('> 原回复', '原回复')]) {
    assert.deepEqual(q.parseQuotedMessage(raw), { text: raw, quote: null });
  }
  assert.equal(q.quoteMessageCopyText(valid), '> AI\n> 原回复\n\n回复');
});

const image = (extra = {}) => ({ type: 'image', id: 'upload-id', name: '截图.png', mimeType: 'image/png', sizeBytes: 2048, ...extra });

test('new quotes retain image descriptors through sending and cold-start draft restoration without changing reply attachments', () => {
  const attachments = [image(), { type: 'file', id: 'file', name: '报告.pdf', mimeType: 'application/pdf', sizeBytes: 1024 }];
  const quoted = q.createMessageQuote(message({ text: '看这张截图', attachments }), 'env', 'thread');
  assert.deepEqual(quoted.images, [image()]);
  assert.deepEqual(q.parseQuotedMessage(q.quotedMessageText('回复', quoted)), { text: '回复', quote: quoted });
  assert.deepEqual(q.messageQuoteImages(quoted, [], 'env', 'thread'), [image()]);
  assert.deepEqual(attachments, [image(), { type: 'file', id: 'file', name: '报告.pdf', mimeType: 'application/pdf', sizeBytes: 1024 }]);
});

test('older quotes recover images only from their exact original message and environment, including inherited threads', () => {
  const original = message({ attachments: [image()] });
  assert.deepEqual(q.messageQuoteImages(quote(), [original], 'env', 'thread'), [image()]);
  assert.deepEqual(q.messageQuoteImages(quote(), [original], 'other-env', 'thread'), []);
  assert.deepEqual(q.messageQuoteImages(quote({ threadId: 'other-thread' }), [original], 'env', 'thread'), []);
  assert.deepEqual(q.messageQuoteImages(quote({ messageId: 'other-message' }), [original], 'env', 'thread'), []);
  assert.deepEqual(q.messageQuoteImages(quote({ threadId: 'parent' }), [message({ sourceThreadId: 'parent', attachments: [image()] })], 'env', 'child'), [image()]);
  assert.deepEqual(q.messageQuoteImages(quote({ images: [image()] }), [], 'other-env', 'thread'), []);
});

test('quote previews show readable image and file labels even when the original image is not available yet', () => {
  const original = quote({ text: '看这里\n![截图.png](t3-context://v1/image/image_reference)\n[报告.pdf](t3-context://v1/attachment/file_reference)' });
  assert.equal(q.messageQuotePreview(original), '看这里 [图片] 截图.png [附件] 报告.pdf');
  assert.deepEqual(q.messageQuoteImages(original, [], 'env', 'thread'), []);
  assert.equal(q.messageQuotePreview(quote({ text: '普通文字\n继续回复' })), '普通文字 继续回复');
  assert.equal(q.parseQuotedMessage(q.quotedMessageText('回复', original)).quote.text, original.text);
});

test('invalid optional image descriptors do not break an otherwise readable historical quote', () => {
  for (const images of [null, 'bad-data', [null, image({ id: '' }), image({ sizeBytes: -1 })]]) {
    const metadata = encodeURIComponent(JSON.stringify({ environmentId: 'env', threadId: 'thread', messageId: 'original', role: 'assistant', images }));
    const raw = q.quotedMessageText('回复', quote()).replace(/^<!--.*-->/, `<!-- t3-message-quote:v1 ${metadata} -->`);
    assert.deepEqual(q.parseQuotedMessage(raw), { text: '回复', quote: quote() });
  }
});

const source = read('pages/Thread.ets');
const methods = (start, end) => source.slice(source.indexOf(start), source.indexOf(end, source.indexOf(start))).replaceAll('private ', '');
const frame = source.slice(source.indexOf('class TranscriptFrame'), source.indexOf('@Entry'));
const { Page, navigation, notices } = await load(`
${quoteModel}
class FrameCallback{};const ScrollAlign={START:0};${frame}
const queuedDraftText=(message,text,attachments)=>JSON.stringify({text,attachments});
const getContext=()=>({filesDir:'/private'});
export const navigation=[],notices=[];
const router={pushUrl:value=>navigation.push(value)},promptAction={showToast:value=>notices.push(value.message)};
const WS={threadStartTurn:'threadStartTurn'};
const DraftStore={open:async()=>globalThis.__quoteDraftStore};
export class Page {
 active=true;readVisible=true;loaded=true;draftReady=true;sending=false;hasPendingSend=false;pickingImage=false;
 params={environmentId:'env',threadId:'thread'};draft='未发送的草稿';draftQuote=null;quoteFocusPending=false;draftTimer=-1;draftStatus='';
 editingQueue=null;queueAttachments=[];imageUris=['attachment'];imageProgress=[];
 imageStore={clear:async()=>{this.imagesCleared=true}};
 draftStore={text:'',save:async text=>{if(this.failSave)throw Error('disk full');this.draftStore.text=text}};
 journal={pending:null,clear:async()=>{this.journal.pending=null}};
 state={};rpc={call:async(method,command)=>this.dispatched.push(command)};dispatched=[];
 focused=0;composerController={requestFocus:()=>this.focused++};cancelPaths(){}updatePathSearch(){}reconcilePending(){}
 quoteTargetId='';quoteTargetThreadId='';highlightedMessageId='';quoteNavigationVersion=0;quoteHighlightTimer=-1;
 entries=[];hasMoreHistory=false;historyLoading=false;historyError='';pendingHistory=null;showingHistory=false;frames=[];scrolls=[];historyLoads=0;
 follow={pause:()=>{this.paused=true}};cancelFollowScroll(){}scroller={scrollToIndex:index=>this.scrolls.push(index)};
 getUIContext(){return {postFrameCallback:callback=>this.frames.push(callback)}}
 async loadOlderHistory(){this.historyLoads++;this.historyLoading=true;}
 ${methods('  private async loadDraft(', '  private async subscribeFeed(')}
 ${methods('  private async quoteMessage(', '  private selectMessage(')}
 ${methods('  private async finishPending(', '  private reconcilePending(')}
}
`);

test('selecting, replacing and cancelling a quote preserves text and attachments and persists each draft', async () => {
  const page = new Page();await page.quoteMessage(message());
  assert.equal(page.draft, '未发送的草稿');assert.deepEqual(page.imageUris, ['attachment']);assert.equal(page.focused, 0);
  assert.deepEqual(q.parseQuotedMessage(page.draftStore.text), { text: page.draft, quote: quote() });
  page.focusQuotedMessage();assert.equal(page.focused, 0);page.frames.shift().onFrame(0);assert.equal(page.focused, 1);
  await page.quoteMessage(message({ id: 'own', role: 'user', text: '自己的原消息' }));
  assert.equal(page.draftQuote.role, 'user');assert.equal(page.draftQuote.messageId, 'own');
  await page.removeQuote();assert.equal(page.draftQuote, null);assert.equal(page.draftStore.text, '未发送的草稿');
  assert.deepEqual(page.imageUris, ['attachment']);
});

test('quote focus waits for the message menu to close and the quote to lay out, and is cancelled when hidden or removed', async () => {
  const page = new Page();await page.quoteMessage(message());
  assert.equal(page.focused, 0);assert.equal(page.frames.length, 0);
  page.focusQuotedMessage();page.focusQuotedMessage();assert.equal(page.frames.length, 1);
  page.frames.shift().onFrame(0);assert.equal(page.focused, 1);
  for (const state of ['hidden', 'removed', 'replaced']) {
    await page.quoteMessage(message());page.focusQuotedMessage();
    if (state === 'hidden') page.readVisible = false;
    else if (state === 'removed') await page.removeQuote();
    else page.draftQuote = quote({messageId:'another'});
    page.frames.shift().onFrame(0);assert.equal(page.focused, 1);
    page.readVisible = true;
  }
});

test('cold-start draft restoration retains the quote and keeps only the reply body in the editor', async () => {
  const page = new Page();globalThis.__quoteDraftStore = { load: async () => q.quotedMessageText('继续提问', quote()) };
  await page.loadDraft();assert.equal(page.draft, '继续提问');assert.deepEqual(page.draftQuote, quote());assert.equal(page.draftReady, true);
  globalThis.__quoteDraftStore = { load: async () => '原来的普通草稿' };
  await page.loadDraft();assert.equal(page.draft, '原来的普通草稿');assert.equal(page.draftQuote, null);
});

test('persistence failure retains the editable quote, while pending and active sends prevent quote replacement or removal', async () => {
  const page = new Page();page.failSave = true;await page.quoteMessage(message());
  assert.deepEqual(page.draftQuote, quote());assert.match(page.draftStatus, /保存失败/);
  for (const state of ['sending', 'hasPendingSend']) {
    page[state] = true;await page.quoteMessage(message({ id: 'other' }));await page.removeQuote();
    assert.equal(page.draftQuote.messageId, 'original');page[state] = false;
  }
});

test('acknowledgement clears only its exact quoted draft and a later draft or quote is preserved', async () => {
  const page = new Page();page.draftQuote = quote();
  page.journal.pending = { message: { text: q.quotedMessageText(page.draft, page.draftQuote) } };
  await page.finishPending();assert.equal(page.draft, '');assert.equal(page.draftQuote, null);assert.equal(page.draftStore.text, '');
  page.draft = '新草稿';page.draftQuote = quote({ messageId: 'new' });
  page.journal.pending = { message: { text: q.quotedMessageText('旧草稿', quote()) } };
  await page.finishPending();assert.equal(page.draft, '新草稿');assert.equal(page.draftQuote.messageId, 'new');
});

test('locating a loaded source pauses following, handles the history header index and highlights the exact original message', async t => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const page = new Page();page.entries = [message({ id: 'earlier' }), message()];page.hasMoreHistory = true;
  await page.locateQuote(quote());assert.equal(page.paused, true);assert.equal(page.showingHistory, true);
  page.frames.splice(0).forEach(frame => frame.onFrame(1));assert.deepEqual(page.scrolls, [2]);
  assert.equal(page.highlightedMessageId, 'original');t.mock.timers.tick(1600);assert.equal(page.highlightedMessageId, '');
});

test('quote navigation resolves the source position after older history has been prepended before the frame', async t => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const page = new Page();page.entries = [message()];
  await page.locateQuote(quote());page.entries.unshift(message({ id: 'older' }));page.hasMoreHistory = true;
  page.frames.splice(0).forEach(frame => frame.onFrame(1));
  assert.deepEqual(page.scrolls, [2]);assert.equal(page.highlightedMessageId, 'original');
  t.mock.timers.tick(1600);
});

test('a side conversation uses the reply body as its title while retaining the quote in the dispatched message', async () => {
  navigation.length = 0;
  const page = new Page(), command = { commandId: 'send', threadId: 'thread', sideThreadId: 'side', sideForkCommandId: 'fork',
    message: { text: q.quotedMessageText('旁支问题', quote()) } };
  await page.dispatchPending(command);
  assert.equal(page.dispatched[0].title, '旁支问题');assert.equal(page.dispatched[1], command);
  page.journal.pending = command;await page.finishPending();
  assert.equal(navigation[0].params.title, '旁支问题');assert.equal(navigation[0].params.threadId, 'side');
});

test('missing source navigation loads older history and user cancellation prevents a delayed jump', async () => {
  const page = new Page();page.hasMoreHistory = true;await page.locateQuote(quote());
  assert.equal(page.historyLoads, 1);assert.equal(page.quoteTargetId, 'original');
  page.navigateToQuote();assert.equal(page.historyLoads, 1);
  page.cancelQuoteNavigation();page.entries = [message()];page.historyLoading = false;page.navigateToQuote();
  assert.equal(page.frames.length, 0);assert.equal(page.quoteTargetId, '');
  await page.locateQuote(quote());page.cancelQuoteNavigation();page.frames.splice(0).forEach(frame => frame.onFrame(1));
  assert.deepEqual(page.scrolls, []);
});

test('a newly selected quote cancels an older scheduled jump while its missing source is loading', async () => {
  const page = new Page();page.entries = [message()];page.hasMoreHistory = true;
  await page.locateQuote(quote());await page.locateQuote(quote({ messageId: 'another' }));
  page.frames.splice(0).forEach(frame => frame.onFrame(1));
  assert.deepEqual(page.scrolls, []);assert.equal(page.quoteTargetId, 'another');assert.equal(page.historyLoads, 1);
});

test('foreign environments never resolve an equal local message ID and another thread opens the proper source', async () => {
  const page = new Page();page.entries = [message()];navigation.length = 0;notices.length = 0;
  await page.locateQuote(quote({ environmentId: 'other' }));assert.equal(page.frames.length, 0);assert.equal(navigation.length, 0);
  assert.match(notices[0], /所在的环境/);
  await page.locateQuote(quote({ threadId: 'another' }));assert.equal(navigation[0].params.threadId, 'another');
  assert.equal(navigation[0].params.quoteMessageId, 'original');assert.equal(page.draftStore.text, page.draft);
});
