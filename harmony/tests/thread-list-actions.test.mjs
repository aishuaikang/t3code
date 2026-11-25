import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const read = file => readFileSync(new URL('../app/entry/src/main/ets/' + file, import.meta.url), 'utf8');
const load = source => import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
const models = await load(read('model/Models.ets'));
globalThis.__threadListModels = models;
const presentation = await load('const {taskStatus}=globalThis.__threadListModels;\n' + read('model/TaskPresentation.ets').replace(/^import .*;$/gm, ''));
const groups = await load(read('model/ProjectGrouping.ets').replace(/^import .*;$/gm, ''));
globalThis.__threadListPresentation = { ...presentation, ...groups };
const ordering = await load('const {taskStatus}=globalThis.__threadListModels;const {sortPinnedThreads}=globalThis.__threadListPresentation;\n' +
  read('model/ThreadOrdering.ets').replace(/^import .*;$/gm, ''));
globalThis.__threadListOrdering = ordering;
const source = read('pages/Index.ets');
const methods = (start, end) => source.slice(source.indexOf(start), source.indexOf(end, source.indexOf(start))).replaceAll('private ', '');
const { Page } = await load(`
const {ShellState,WS,taskStatus,visibleThreads,searchArchivedThreads,shownUnderParent}=globalThis.__threadListModels;
const {relativeTaskTime,taskSection,taskLatestTurn,taskWorkTurn,sortPinnedThreads,groupProjects}=globalThis.__threadListPresentation;
const {sortTaskThreads,inThreadOrderGroup,planThreadReorder}=globalThis.__threadListOrdering;
const util={generateRandomUUID:()=> 'command-id'};
const ThreadReads={unread:()=>false};const threadReadRevision=()=>'';const fastModeEnabled=()=>false;
export class Page {
 saved=[];parentCaches=new Map();shell=new ShellState();projects=[{id:'p',title:'Project',workspaceRoot:'/project'}];projectId='';groupingMode='repository';query='';
 taskFilters=['active','all','settled','archived','running','waiting'];filterLabels=[];filterIndex=1;archiveOrder='newest';
 archivedSnapshot={threads:[],projects:[]};cacheEnvironmentId='env';cache=null;live=true;actionBusy=false;status='';
 calls=[];connected={descriptor:{environmentId:'env',label:'Machine'},rpc:{call:async(method,command)=>this.calls.push({method,command})}};
 renameOpen=false;renamingId='';renameTitle='';renameOriginalTitle='';renameEnvironmentId='';renameError='';
 async loadArchive(){}
 ${methods('  private refreshThreads():', '  private selectFilter(')}
 ${methods('  private startRename(', '  private deleteTask(')}
}
`);
const thread = (id, extra = {}) => ({ id, title: id, projectId: 'p', status: 'idle',
  createdAt: '2026-11-16T00:00:00Z', updatedAt: '2026-11-16T01:00:00Z', ...extra });

test('pins follow the server order and Android tie breaks without changing unpinned order or the input', () => {
  const input = [thread('ordinary'), thread('new-keyless', { pinnedAt: 'now', createdAt: '2026-11-16T02:00:00Z' }),
    thread('key-b', { pinnedAt: 'now', pinOrderKey: 'b' }), thread('key-a', { pinnedAt: 'now', pinOrderKey: 'a' }),
    thread('older-keyless', { pinnedAt: 'now' }), thread('another-ordinary')];
  const before = input.slice();
  assert.deepEqual(presentation.sortPinnedThreads(input).map(t => t.id),
    ['key-a', 'key-b', 'new-keyless', 'older-keyless', 'ordinary', 'another-ordinary']);
  assert.deepEqual(input, before);
  const tied = [thread('z', { pinnedAt: 'now', pinOrderKey: 'a' }), thread('a', { pinnedAt: 'now', pinOrderKey: 'a' })];
  assert.deepEqual(presentation.sortPinnedThreads(tied).map(t => t.id), ['a', 'z']);
});

test('live pin, rename and unpin events update one list and preserve status, project and search filters', async () => {
  const page = new Page();
  const pinned = thread('done', { status: 'completed', pinnedAt: 'now', pinOrderKey: 'a' });
  const running = thread('running', { status: 'running' });
  page.shell.apply({ kind: 'snapshot', snapshot: { snapshotSequence: 1, projects: page.projects,
    threads: [running, thread('idle'), thread('foreign', { projectId: 'other', pinnedAt: 'now' }), pinned] } });
  page.projectId = 'p';page.refreshThreads();
  assert.deepEqual(page.threads.map(t => [t.id, t.section]), [['done', -1], ['running', 0], ['idle', 1]]);
  assert.equal(page.threads.filter(t => t.id === 'done').length, 1);
  page.shell.apply({ kind: 'thread-upserted', sequence: 2, thread: { ...pinned, title: '改名后的会话' } });
  page.query = '改名';page.refreshThreads();
  assert.deepEqual(page.threads.map(t => t.title), ['改名后的会话']);
  page.query = '';page.shell.apply({ kind: 'thread-upserted', sequence: 3, thread: { ...pinned, pinnedAt: null, pinOrderKey: null } });
  page.refreshThreads();
  assert.deepEqual(page.threads.map(t => [t.id, t.section]), [['running', 0], ['idle', 1], ['done', 2]]);
  assert.equal(page.threads.at(-1).pinned, false);
  page.filterIndex = 4;page.refreshThreads();assert.deepEqual(page.threads.map(t => t.id), ['running']);
  await page.taskAction('thread.pin', 'running');await page.taskAction('thread.unpin', 'running');
  assert.deepEqual(page.calls.map(c => c.command), [
    { type: 'thread.pin', commandId: 'command-id', threadId: 'running' },
    { type: 'thread.unpin', commandId: 'command-id', threadId: 'running' }
  ]);
});

test('PC reorder events update the visible list in place while retaining status categories and filtered relative order', () => {
  const page = new Page();
  const input = [thread('running', { status: 'running', activeOrderKey: 't' }), thread('a', { activeOrderKey: 'g' }),
    thread('b', { activeOrderKey: 'n' }), thread('done', { status: 'completed' })];
  page.shell.apply({ kind: 'snapshot', snapshot: { snapshotSequence: 1, projects: page.projects, threads: input } });
  page.refreshThreads();assert.deepEqual(page.threads.map(thread => thread.id), ['running', 'a', 'b', 'done']);
  page.shell.apply({ kind: 'thread-upserted', sequence: 2, thread: { ...input[2], activeOrderKey: 'b' } });
  page.refreshThreads();assert.deepEqual(page.threads.map(thread => thread.id), ['running', 'b', 'a', 'done']);
  page.filterIndex = 0;page.projectId = 'p';page.refreshThreads();
  assert.deepEqual(page.threads.map(thread => thread.id), ['running', 'b', 'a']);
  page.shell.apply({ kind: 'thread-upserted', sequence: 3, thread: { ...input[2], activeOrderKey: 'v' } });
  page.refreshThreads();assert.deepEqual(page.threads.map(thread => thread.id), ['running', 'a', 'b']);
});

test('rename waits for the server receipt, trims Chinese titles and does not send duplicate saves', async () => {
  const page = new Page();page.startRename(thread('t', { title: 'Original' }));page.renameTitle = '  新会话名称  ';
  let release;page.connected.rpc.call = async (method, command) => {
    page.calls.push({ method, command });await new Promise(resolve => { release = resolve; });
  };
  const saving = page.saveRename();
  assert.equal(page.actionBusy, true);assert.equal(page.renameOpen, true);
  await page.saveRename();assert.equal(page.calls.length, 1);
  assert.equal(page.calls[0].method, models.WS.threadStartTurn);
  assert.deepEqual(page.calls[0].command, { type: 'thread.metadata.update', commandId: 'command-id', threadId: 't', title: '新会话名称' });
  release();await saving;
  assert.equal(page.renameOpen, false);assert.equal(page.actionBusy, false);
});

test('empty and unchanged names make no command, and offline or changed environments cannot rename', async () => {
  const page = new Page();page.startRename(thread('t'));page.renameTitle = ' \n ';
  await page.saveRename();assert.equal(page.renameOpen, true);assert.equal(page.calls.length, 0);
  page.renameTitle = ' t ';await page.saveRename();assert.equal(page.renameOpen, false);assert.equal(page.calls.length, 0);
  page.startRename(thread('t'));page.renameTitle = 'new';page.live = false;
  await page.saveRename();assert.equal(page.calls.length, 0);
  page.live = true;page.connected.descriptor.environmentId = 'other';
  await page.saveRename();assert.equal(page.calls.length, 0);
});

test('a rejected rename retains the title for correction or retry and never closes the editor as a success', async () => {
  const page = new Page();page.startRename(thread('t'));page.renameTitle = 'New title';
  page.connected.rpc.call = async () => { throw new Error('Connection lost'); };
  await page.saveRename();
  assert.equal(page.renameOpen, true);assert.equal(page.renameTitle, 'New title');
  assert.match(page.renameError, /Connection lost/);assert.equal(page.actionBusy, false);
  page.connected.rpc.call = async (method, command) => { page.calls.push({ method, command }); };
  await page.saveRename();assert.equal(page.renameOpen, false);assert.equal(page.calls[0].command.title, 'New title');
});

test('archive sorting and displayed ages follow the archive date, including pinned conversations', () => {
  const page = new Page();
  const hoursAgo = h => new Date(Date.now() - h * 3600000 - 1000).toISOString();
  page.filterIndex = 3;
  page.archivedSnapshot = { projects: page.projects, threads: [
    thread('earlier', { pinnedAt: hoursAgo(9), archivedAt: hoursAgo(8), updatedAt: hoursAgo(1) }),
    thread('later', { archivedAt: hoursAgo(2), updatedAt: hoursAgo(12) })
  ] };
  page.refreshThreads();
  assert.deepEqual(page.threads.map(row => [row.id, row.updated]), [['later', '2h'], ['earlier', '8h']]);
  page.archiveOrder = 'oldest'; page.refreshThreads();
  assert.deepEqual(page.threads.map(row => row.id), ['earlier', 'later']);
});

test('home, search, counts and archive list hide side chats and delegated tasks only while their scoped parent is listed',()=>{
 const p=new Page(),remote=new Set(['parent']);p.saved=[{environmentId:'linked'}];p.parentCaches.set('linked',{listsThread:id=>remote.has(id)});
 const fork=thread('fork',{lineage:{relationshipToParent:'fork',parentThreadId:'parent'}}),side=thread('side',{lineage:{...fork.lineage,sideChat:true}}),native=thread('native',{lineage:{relationshipToParent:'subagent'}});
 const child=thread('delegated',{delegatedFrom:{environmentId:'linked',threadId:'parent'}}),sameId=thread('parent');p.shell.threads=[sameId,fork,side,native,child];p.refreshThreads();
 assert.deepEqual(p.threads.map(t=>t.id).sort(),['fork','parent']);assert.match(p.filterOptions[1].value,/\(2\)/);
 p.query='side';p.refreshThreads();assert.deepEqual(p.threads,[]);p.query='';remote.clear();p.refreshThreads();assert.ok(p.threads.some(t=>t.id==='delegated'));
 p.filterIndex=3;p.archivedSnapshot={projects:p.projects,threads:[child,side,fork].map(t=>({...t,archivedAt:'2026-11-12'}))};remote.add('parent');p.refreshThreads();assert.deepEqual(p.threads.map(t=>t.id),['fork']);
 p.saved=[];p.refreshThreads();assert.deepEqual(p.threads.map(t=>t.id).sort(),['delegated','fork']);
});
