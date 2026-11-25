import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const read = path => readFileSync(new URL('../app/entry/src/main/ets/' + path, import.meta.url), 'utf8');
const load = source => import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
const m = await load(read('model/MessageQuote.ets').replace(/^import .*;$/gm, '') + '\n' + read('model/MessageForwarding.ets').replace(/^import .*;$/gm, ''));
const image = {id:'image',type:'image',name:'照片.png',mimeType:'image/png',sizeBytes:120};
const row = (id, text, extra={}) => ({id,text,kind:'message',role:'user',streaming:false,createdAt:'time',...extra});
const target = {id:'target',runtimeMode:'approval-required',interactionMode:'plan',messages:[],session:{status:'running',activeTurnId:'active'}};

test('single and batch forwards preserve timeline order, quoted commands and every attachment without changing source messages', () => {
  const rows=[row('first','/clear 原文\n下一行',{attachments:[image]}),row('tool','ignored',{kind:'tool'}),row('last','答复',{role:'assistant',attachments:[image]})];
  const original=structuredClone(rows), content=m.forwardContent(rows,['last','first'],'来源任务');
  assert.equal(content.count,2); assert.ok(content.text.indexOf('/clear')<content.text.indexOf('答复'));
  assert.match(content.text,/^转发自「来源任务」\n\n用户：\n> \/clear 原文\n> 下一行/);
  assert.deepEqual(content.attachments,[image]); assert.deepEqual(rows,original);
  content.attachments[0].name='changed'; assert.equal(rows[0].attachments[0].name,'照片.png');
  assert.equal(m.forwardContent(rows,['first','first'],'来源').count,1);
});

test('forwarding a quoted reply keeps its author, quoted words and reply without exposing internal metadata', () => {
  const quoted = m.quotedMessageText('请继续分析', { environmentId: 'env', threadId: 'source', messageId: 'ai', role: 'assistant', text: '原回复\n第二行' });
  const content = m.forwardContent([row('quote', quoted), row('reply', '下一条', { role: 'assistant' })], ['reply', 'quote'], '来源会话');
  assert.match(content.text, /> > AI\n> > 原回复\n> > 第二行/);
  assert.ok(content.text.indexOf('请继续分析') < content.text.indexOf('下一条'));
  assert.ok(!content.text.includes('t3-message-quote'));assert.equal(content.count, 2);
});
test('image-only messages can be forwarded, while incomplete, removed or non-message selections cannot silently lose content', () => {
  const rows=[row('image','',{attachments:[image]}),row('stream','partial',{streaming:true}),row('tool','tool',{kind:'tool'}),row('empty','')];
  assert.equal(m.canForwardMessage(rows[0]),true);
  assert.match(m.forwardContent(rows,['image'],'source').text,/照片.png/);
  for(const ids of [[],['stream'],['tool'],['missing'],['image','missing'],['empty']]) assert.throws(()=>m.forwardContent(rows,ids,'source'));
  assert.throws(()=>m.forwardContent([row('many','text',{attachments:Array.from({length:9},(_,i)=>({...image,id:String(i)}))})],['many'],'source'),/8 个附件/);
});
test('recipient search supports Chinese titles, projects and branches and excludes the source and archives', () => {
  const threads=[{id:'source',title:'当前',projectId:'p'}, {id:'one',title:'登录优化',projectId:'p',branch:'分支一',updatedAt:'2026-11-16'},
    {id:'two',title:'Other',projectId:'q',updatedAt:'2026-11-15'}, {id:'archive',title:'归档',projectId:'p',archivedAt:'yes'}];
  const projects=[{id:'p',title:'中文项目'}], original=structuredClone(threads);
  assert.deepEqual(m.forwardTargets(threads,projects,'source','').map(t=>t.id),['one','two']);
  for(const query of ['登录','中文项目','分支一']) assert.deepEqual(m.forwardTargets(threads,projects,'source',query).map(t=>t.id),['one']);
  assert.deepEqual(threads,original);
});
test('a forward creates one turn using recipient permissions and queues without interpreting source slash commands', () => {
  const content=m.forwardContent([row('one','/side question',{attachments:[image]})],['one'],'source');
  const command=m.forwardCommand(target,content,'command','message','time');
  assert.equal(command.threadId,'target'); assert.equal(command.message.text,content.text);assert.deepEqual(command.message.attachments,[image]);
  assert.equal(command.runtimeMode,'approval-required');assert.equal(command.interactionMode,'plan');
  assert.deepEqual(command.dispatchMode,{type:'queue_after_active'});assert.equal(command.sideThreadId,undefined);assert.equal(command.freshContext,undefined);
});

const pageSource=read('pages/Thread.ets');
const selectionMethods=pageSource.slice(pageSource.indexOf('  private selectMessage('),pageSource.indexOf('  private async prepareForward(')).replaceAll('private ','');
globalThis.__forwardModel=m;
const {Page}=await load(`const {canForwardMessage,forwardContent}=globalThis.__forwardModel;
export class Page {
 selectingMessages=false;selectedMessageIds=[];entries=[];draft='保留我的草稿';imageUris=['photo'];
 forwardBusy=false;forwardOpen=false;forwardContent=null;cachedTitle='来源会话';operationError='';
 cache={shell:()=>({threads:[{id:'target'}],projects:[{id:'project'}]})};
 cancelPaths(){}follow={pause:()=>{this.paused=true}};showingHistory=false;
 ${selectionMethods}
}`);

test('batch selection toggles complete messages and cancel or back preserves the existing draft and attachments', () => {
  const page=new Page(), first=row('first','自己的消息'), last=row('last','AI回复',{role:'assistant'});
  page.beginMessageSelection(first);assert.equal(page.selectingMessages,true);assert.deepEqual(page.selectedMessageIds,['first']);
  page.selectMessage(last);page.selectMessage(row('tool','输出',{kind:'tool'}));assert.deepEqual(page.selectedMessageIds,['first','last']);
  page.selectMessage(first);assert.deepEqual(page.selectedMessageIds,['last']);
  assert.equal(page.onBackPress(),true);assert.equal(page.selectingMessages,false);assert.deepEqual(page.selectedMessageIds,[]);
  assert.equal(page.onBackPress(),false);assert.equal(page.draft,'保留我的草稿');assert.deepEqual(page.imageUris,['photo']);
});

test('batch forwarding opens a recipient chooser with both selected roles in timeline order', () => {
  const page=new Page();page.entries=[row('first','问题',{attachments:[image]}),row('last','答案',{role:'assistant'})];
  page.beginMessageSelection(page.entries[1]);page.selectMessage(page.entries[0]);page.openForward(page.selectedMessageIds);
  assert.equal(page.forwardOpen,true);assert.equal(page.forwardContent.count,2);
  assert.ok(page.forwardContent.text.indexOf('问题')<page.forwardContent.text.indexOf('答案'));
  assert.deepEqual(page.forwardContent.attachments,[image]);assert.deepEqual(page.forwardThreads,[{id:'target'}]);
  assert.equal(page.draft,'保留我的草稿');assert.deepEqual(page.imageUris,['photo']);
});

let sequence=0;
async function fixture(initial='') {
  const store={text:initial,writes:[],fail:false,async load(){return this.text},async save(text){if(this.fail)throw Error('disk full');this.text=text;this.writes.push(text)}};
  globalThis.__forwardStore=store;
  const source=read('connection/ForwardJournal.ets').replace("import { DraftStore } from './DraftStore';",'const DraftStore={open:async()=>globalThis.__forwardStore};').replace(/^import .*Models.*;$/gm,'');
  const {ForwardJournal}=await load(source+`\n// fixture ${++sequence}`);
  return {journal:await ForwardJournal.open('/files','env','source'),store,ForwardJournal};
}
const command=()=>m.forwardCommand(target,m.forwardContent([row('source-message','content')],['source-message'],'source'),'stable-command','stable-message','time');
test('a lost receipt persists one forward and retry after reopening uses its original target, content and IDs',async()=>{
  const {journal,store,ForwardJournal}=await fixture();const sent=[];
  await assert.rejects(journal.submit(async()=>command(),async c=>{sent.push(c);throw Error('lost receipt')}));
  assert.ok(store.text);assert.equal(journal.pending.commandId,'stable-command');
  const restored=await ForwardJournal.open('/files','env','source');
  await restored.submit(async()=>{throw Error('must not prepare again')},async c=>sent.push(c));
  assert.deepEqual(sent[1],sent[0]);assert.equal(store.text,'');assert.equal(restored.pending,null);
});
test('persistence failure sends nothing and receipt cleanup failure retains the same idempotent command',async()=>{
  const {journal,store}=await fixture();let calls=0;store.fail=true;
  await assert.rejects(journal.submit(async()=>command(),async()=>{calls++}));assert.equal(calls,0);assert.equal(journal.pending,null);
  store.fail=false;
  await assert.rejects(journal.submit(async()=>command(),async()=>{calls++;store.fail=true}));
  assert.equal(calls,1);assert.equal(journal.pending.message.messageId,'stable-message');assert.ok(store.text);
});
test('a concurrent confirmation cannot dispatch another message and invalid recovery data is never overwritten',async()=>{
  const {journal,store}=await fixture();let release,entered;const started=new Promise(r=>entered=r);const held=new Promise(r=>release=r);let calls=0;
  const sending=journal.submit(async()=>command(),async()=>{calls++;entered();await held});await started;
  await assert.rejects(journal.submit(async()=>command(),async()=>{calls++}),/正在转发/);release();await sending;assert.equal(calls,1);
  for(const patch of [{threadId:'source'},{type:'thread.delete'},{dispatchMode:{type:'steer_active'}}]){
    const raw=JSON.stringify({...command(),...patch});
    await assert.rejects(fixture(raw));
  }
  assert.equal(store.text,'');
});

test('both the forward picker and the fetched target reject only provider-owned subagents',()=>{
 const native={...target,id:'native',creationSource:'provider',lineage:{relationshipToParent:'subagent'}},owned={...native,id:'owned',creationSource:'mcp'},normal={...native,id:'normal',lineage:{relationshipToParent:'fork'}};
 assert.deepEqual(m.forwardTargets([native,owned,normal],[],'source','').map(t=>t.id),['owned','normal']);
 const content={count:1,text:'forward',attachments:[]};assert.throws(()=>m.forwardCommand(native,content,'c','m','now'),/只读/);
 assert.equal(m.forwardCommand(owned,content,'c','m','now').threadId,'owned');
});
