import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const read = path => readFileSync(new URL('../app/entry/src/main/ets/' + path, import.meta.url), 'utf8');
const load = source => import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
const models = await load(read('model/Models.ets'));
globalThis.__noticeModels = models;
const notices = await load('const {taskStatus}=globalThis.__noticeModels;\n' + read('model/TaskNotifications.ets').replace(/^import .*;$/gm, ''));

let allowed = false, requests = 0;
const persisted = new Map(), published = [], wants = [], storage = new Map();
const notificationManager = {
  ContentType: { NOTIFICATION_CONTENT_BASIC_TEXT: 0 }, SlotType: { SERVICE_INFORMATION: 4 },
  isNotificationEnabled: async () => allowed,
  requestEnableNotification: async () => { requests++; allowed = true; },
  publish: async value => { published.push(value); }
};
const wantAgent = {
  OperationType: { START_ABILITY: 1 }, WantAgentFlags: { UPDATE_PRESENT_FLAG: 2 },
  getWantAgent: async value => { wants.push(value); return { requestCode: value.requestCode }; }
};
const preferences = { getPreferences: async () => ({
  get: async (key, fallback) => persisted.get(key) ?? fallback,
  put: async (key, value) => persisted.set(key, value), flush: async () => {}
}) };
const AppStorage = { setOrCreate: (key, value) => storage.set(key, value) };
globalThis.__nativeNotices = { ...notices, notificationManager, wantAgent, preferences, AppStorage };
const { TaskNotifications } = await load('const {TaskNotificationTracker,taskNotificationId,notificationManager,wantAgent,preferences,AppStorage}=globalThis.__nativeNotices;\n' +
  read('connection/TaskNotifications.ets').replace(/^import .*;$/gm, ''));

const notice = { environmentId: 'machine', threadId: 'task', title: '任务', text: '回复已完成', state: 'completed', cwd: '/项目', projectTitle: '项目' };
test('system permission is requested once and disabling task notifications stops publishing', async () => {
  await TaskNotifications.initialize({});
  await TaskNotifications.requestOnce(); await TaskNotifications.requestOnce();
  assert.equal(requests, 1); assert.equal(persisted.get('asked'), true); assert.equal(await TaskNotifications.isEnabled(), true);
  await TaskNotifications.setEnabled(false); await TaskNotifications.publish(notice);
  assert.equal(published.length, 0); assert.equal(persisted.get('enabled'), false);
  await TaskNotifications.setEnabled(true);
});

test('each native notification carries the exact task and environment to its launch action', async () => {
  await TaskNotifications.publish(notice); await TaskNotifications.publish({ ...notice, threadId: 'another-task' });
  assert.notEqual(published[0].id, published[1].id);
  assert.equal(published[0].content.notificationContentType, notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT);
  assert.equal(published[0].content.normal.text, '回复已完成');
  assert.deepEqual(wants[0].wants[0], { bundleName: 'codes.t3.harmony', abilityName: 'EntryAbility', parameters: {
    notificationThreadId: 'task', notificationEnvironmentId: 'machine', notificationTitle: '任务', notificationCwd: '/项目', notificationProject: '项目'
  } });
});

const ability = read('entryability/EntryAbility.ets');
const { Ability } = await load(`const AppStorage=globalThis.__nativeNotices.AppStorage;const hilog={info(){}};let id=0;const util={generateRandomUUID:()=>String(++id)};
export class Ability {${ability.slice(ability.indexOf('  onCreate('), ability.indexOf('  onDestroy(')).replaceAll('private ', '')}}`);
test('cold and warm notification launches both preserve their route and allow repeated taps', () => {
  const page = new Ability(), want = wants[0].wants[0];
  page.onCreate(want, {}); const first = JSON.parse(storage.get('notificationRoute'));
  page.onNewWant(want, {}); const second = JSON.parse(storage.get('notificationRoute'));
  assert.equal(first.environmentId, 'machine'); assert.equal(first.threadId, 'task'); assert.equal(first.cwd, '/项目');
  assert.notEqual(first.request, second.request);
});

const index = read('pages/Index.ets');
globalThis.__noticeRoutes = { saved: [{ environmentId: 'machine' }], pushes: [] };
const { Home } = await load(`const state=globalThis.__noticeRoutes;const getContext=()=>({});const loadEnvironments=async()=>state.saved;const router={pushUrl:value=>state.pushes.push(value)};
export class Home {
 pageGeneration=1;connectionAttempt=0;isHome(id){return id===this.pageGeneration}
 ${index.slice(index.indexOf('  private isConnectionAttempt('),index.indexOf('  private alternateRoutes(')).replaceAll('private ', '')}
 connected=null;connecting=false;openingNotification=false;notificationRoute='';
 async restore(saved){this.connected={descriptor:{environmentId:saved.environmentId}}}
 ${index.slice(index.indexOf('  private async openNotification('), index.indexOf('  aboutToAppear(')).replaceAll('private ', '')}
}`);
test('tapping a notification restores its saved environment and opens the task once', async () => {
  const page = new Home(); page.notificationRoute = storage.get('notificationRoute'); await page.openNotification();
  assert.equal(page.connected.descriptor.environmentId, 'machine');
  assert.equal(globalThis.__noticeRoutes.pushes[0].params.threadId, 'task');
  assert.equal(page.notificationRoute, ''); await page.openNotification(); assert.equal(globalThis.__noticeRoutes.pushes.length, 1);
  page.notificationRoute = JSON.stringify({ environmentId: 'removed', threadId: 'task' }); await page.openNotification();
  assert.equal(page.managingEnvironments, true); assert.match(page.status, /此会话所在环境尚未连接/);
});

test('a second notification tap during reconnect opens only the latest task, even on another machine',async()=>{
 const p=new Home(),io=globalThis.__noticeRoutes;io.saved=[{environmentId:'one'},{environmentId:'two'}];io.pushes=[];
 const gate=Promise.withResolvers(),entered=Promise.withResolvers();p.restore=async saved=>{if(saved.environmentId==='one'){entered.resolve();await gate.promise;}p.connected={descriptor:saved};};
 const route=(env,id)=>JSON.stringify({request:id,environmentId:env,threadId:id});p.notificationRoute=route('one','first');const first=p.openNotification();await entered.promise;
 p.notificationRoute=route('two','second');await p.openNotification();gate.resolve();await first;
 assert.deepEqual(io.pushes.map(p=>p.params.threadId),['second']);assert.equal(p.connected.descriptor.environmentId,'two');assert.equal(p.notificationRoute,'');
});

const reconnect = await load(read('connection/ReconnectingRpc.ets').replace(/^import .*;$/gm, ''));
globalThis.__noticeShell = { ...models, ...reconnect, observed: [] };
const { ShellPage } = await load(`const {ShellState,WS,ReconnectingRpc,observed}=globalThis.__noticeShell;class EmptyPayload{}
const ClientCache={open:async()=>({setCatalog(){},setShell(){}})};const getContext=()=>({filesDir:'/private'});
const TaskNotifications={observe:(environment,snapshot)=>observed.push({environment,snapshot})};
const ComposerOutbox={connected(){},disconnected(){}};const AppStorage={setOrCreate(){}};
export class ShellPage {
 pageGeneration=1;isHome(id){return id===this.pageGeneration}
 shell=new ShellState();subscription=null;live=false;filterIndex=1;cache=null;projects=[];
 refreshThreads(){}openNotification(){}loadArchive(){}
 ${index.slice(index.indexOf('  private async loadThreads('), index.indexOf('  @Builder\n  private projectSheet(')).replaceAll('private ', '')}
}`);
test('initial shell replay finishes before notifications establish their baseline and legacy live snapshots connect immediately', async (t) => {
  const page = new ShellPage(); let feed;
  const legacy = new ShellPage();
  t.after(() => { page.subscription?.stop(); legacy.subscription?.stop(); });
  const drain = async () => { for(let i=0;i<20;i++) await Promise.resolve(); };
  page.connected = { descriptor: { environmentId: 'machine' }, loadSnapshot:async()=>({snapshotSequence:0,threads:[],projects:[]}), rpc: {
    close() {}, call: async () => ({ providers: [], shellResumeCompletionMarker:true }),
    callStream: (_method, _request, onValues) => { feed = onValues; return new Promise(()=>{}); }
  } };
  await page.loadThreads(); await drain(); assert.equal(typeof feed, 'function');
  feed([{ kind: 'thread-upserted', sequence: 1, thread: { id: 'one', activityRunStatus: 'running' } }]);
  feed([{ kind: 'thread-upserted', sequence: 2, thread: { id: 'two', activityRunStatus: 'failed' } }]);
  assert.equal(globalThis.__noticeShell.observed.length, 0);
  feed([{ kind: 'synchronized' }]); assert.equal(globalThis.__noticeShell.observed[0].snapshot.threads.length, 2);
  assert.equal(page.live, true);
  page.subscription.stop();
  legacy.connected = { ...page.connected, loadSnapshot:async()=>null, rpc:{...page.connected.rpc,call:async()=>({providers:[]})} }; await legacy.loadThreads(); await drain();
  feed([{ kind: 'snapshot', snapshot: { snapshotSequence: 3, threads: [], projects: [] } }]);
  assert.equal(legacy.live, true); assert.equal(legacy.connectionState, 'connected'); legacy.subscription.stop();
});
