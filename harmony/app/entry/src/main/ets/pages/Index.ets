import { menuIcon, menuModalMode, menuHapticFeedbackMode } from './MenuIcon';
import { ChatPageHeader, ChatGlass, immersiveMaterial } from './ChatGlass';
import { ProjectPicker } from './ProjectPicker';
import { EnvironmentPanel, EnvironmentPanelActions } from './EnvironmentPanel';
import { EnvironmentPicker } from './EnvironmentPicker';
import { NewTask } from './NewTask';
import { TaskWorkTime } from './TaskWorkTime';
import { ThreadReads } from '../connection/ThreadReads';
import { ThreadReadTarget, threadReadRevision } from '../model/ThreadReadState';
import { LatestTurn } from '../model/Models';
import { ConnectionProgressBadge, StatusIndicator } from './StatusIndicator';
import { ClientCache } from '../connection/ClientCache';
import { ComposerOutbox } from '../connection/ComposerOutbox';
import { TaskNotifications } from '../connection/TaskNotifications';
import { connectionProgressLabel, statusLabel, statusColor } from '../model/StatusVisuals';
import { ProjectIcon } from './ProjectIcon';
import { ProviderIcon } from './ProviderIcon';
import { fastModeEnabled } from '../model/ModelOptions';
import { relativeTaskTime, taskSection, taskLatestTurn, taskWorkTurn } from '../model/TaskPresentation';
import { sortTaskThreads, inThreadOrderGroup, planThreadReorder } from '../model/ThreadOrdering';
import { AppIcon } from './AppIcon';
import { AppearanceStore } from '../connection/AppearanceStore';
import { ProjectGroup, groupProjects } from '../model/ProjectGrouping';
import { Typography, resolveTypography, scaledFontSize } from '../model/Typography';
import { ThemeRuntime } from '../connection/ThemeRuntime';
import router from '@ohos.router';
import util from '@ohos.util';
import { connectEnvironment, connectDirectEnvironment, restoreDirectEnvironment, restoreSshEnvironment, EnvironmentSession, PreparedConnection } from '../connection/Environment';
import { SavedEnvironment, loadEnvironments, readBearer, readSshCredentials, forgetEnvironment, setPrimarySshRoute } from '../connection/EnvironmentStore';
import { SshTarget } from '../connection/SshTunnel';
import { ThreadShell, ProjectShell, ShellSnapshot, ShellState, ShellItem, ServerConfig, WS, taskStatus, visibleThreads, searchArchivedThreads, shownUnderParent } from '../model/Models';
import { EmptyPayload, RpcClient, RpcRemoteError } from '../connection/Rpc';
import { ReconnectingRpc } from '../connection/ReconnectingRpc';

interface ThreadRow {
  id: string;
  title: string;
  state: string;
  projectTitle: string;
  branch: string;
  faviconPath: string;
  cwd: string;
  archived: boolean;
  settled: boolean;
  updated: string;
  provider: string;
  fast: boolean;
  pinned: boolean;
  section: number;
  workTurn: LatestTurn | null;
  unread: boolean;
  readRevision: string;
}
const TASK_FILTER_ICONS: Record<string, string> = {
  'active': 'chat', 'all': 'queue', 'settled': 'check', 'archived': 'archive', 'running': 'play',
  'waiting': 'clock', 'queued': 'queue', 'failed': 'warning', 'interrupted': 'stop', 'idle': 'chat'
};
interface TaskFilterOption { value: string; }
interface ShellSubscription { afterSequence?: number; requestCompletionMarker?: boolean; }

interface TaskActionCommand {
  type: string;
  commandId: string;
  threadId: string;
  title?: string;
  reason?: string;
  orderKey?: string;
}

@Entry({ useSharedStorage: true })
@Component
struct Index {
  private font(size: number): number { return scaledFontSize(size, this.sizes.baseFontSize); }
  @StorageLink('textSizes') sizes: Typography = resolveTypography(16, null, null);
  @StorageLink('themeKey') themeKey: string = 't3-code-light';
  @StorageLink('fontError') fontError: string = '';
  @StorageLink('windowError') windowError: string = '';
  @StorageLink('themeError') themeError: string = '';
  @StorageLink('threadReadVersion') @Watch('refreshThreads') readVersion: number = 0;
  @StorageLink('threadReadError') readError: string = '';
  private color(role: string): string { return ThemeRuntime.color(this.themeKey, role); }
  @LocalStorageLink('environment.direct') direct: boolean = true;
  @LocalStorageLink('environment.environmentUrl') environmentUrl: string = '';
  @LocalStorageLink('environment.pairingToken') pairingToken: string = '';
  private shell: ShellState = new ShellState();
  @LocalStorageLink('environment.hostname') hostname: string = '';
  @LocalStorageLink('environment.port') port: string = '22';
  @LocalStorageLink('environment.username') username: string = '';
  @LocalStorageLink('environment.password') password: string = '';
  @LocalStorageLink('environment.hostFingerprint') hostFingerprint: string = '';
  @LocalStorageLink('environment.packageSpec') packageSpec: string = 't3@nightly';
  @LocalStorageLink('environment.existingSshServer') existingSshServer: boolean = true;
  @LocalStorageLink('environment.serverPort') serverPort: string = '3773';
  @LocalStorageLink('environment.serverHost') serverHost: string = '';
  @LocalStorageLink('environment.status') status: string = '';
  @LocalStorageLink('environment.connecting') connecting: boolean = false;
  @LocalStorageLink('environment.forgetting') forgetting: boolean = false;
  private connectionAttempt: number = 0;
  @LocalStorageLink('environment.connected') connected: PreparedConnection | null = null;
  @State threads: ThreadRow[] = [];
  @State collapsedTaskSections: number[] = [];
  @State pressedTaskId: string = '';
  @State hoveredTaskId: string = '';
  @State menuTaskId: string = '';
  @State markingAllRead: boolean = false;
  @State projects: ProjectShell[] = [];
  @State projectId: string = '';
  @State composerOpen: boolean = false;
  @State composerCloseRequest: number = 0;
  @State projectsOpen: boolean = false;
  @State projectGroups: ProjectGroup[] = [];
  @State groupingError: string = '';
  @State groupingMode: string = 'repository';
  @State machinesOpen: boolean = false;
  @State query: string = '';
  @State searchOpen: boolean = false;
  private taskScroller: Scroller = new Scroller();
  private threadSearch: SearchController = new SearchController();
  @State filtersOpen: boolean = false;
  @State filterIndex: number = 1;
  private taskFilters: string[] = ['active', 'all', 'settled', 'archived', 'running', 'waiting', 'queued', 'failed', 'interrupted', 'idle'];
  private filterLabels: string[] = ['进行中', '全部任务', '已完成', '已归档', '执行中', '等待处理', '排队中', '异常', '已中断', '未开始'];
  @State filterOptions: TaskFilterOption[] = [{ value: '进行中' }, { value: '全部任务' }, { value: '已完成' }, { value: '已归档' }];
  @State renamingId: string = '';
  @State renameTitle: string = '';
  @State renameOpen: boolean = false;
  @State renameError: string = '';
  private renameOriginalTitle: string = '';
  private renameEnvironmentId: string = '';
  @State pinSupported: boolean = false;
  @State pinReorderSupported: boolean = false;
  @State activeReorderSupported: boolean = false;
  @State orderOpen: boolean = false;
  @State orderRows: ThreadRow[] = [];
  @State orderPinned: boolean = false;
  @State orderError: string = '';
  private orderOriginalIds: string[] = [];
  private orderMovedIds: string[] = [];
  private orderConnection: PreparedConnection | null = null;
  @State actionBusy: boolean = false;
  @State loadingArchive: boolean = false;
  @State archiveOrder: string = 'newest';
  @State archiveError: boolean = false;
  private archivedSnapshot: ShellSnapshot = { snapshotSequence: 0, projects: [], threads: [] };
  @LocalStorageLink('environment.saved') saved: SavedEnvironment[] = [];
  @State live: boolean = false;
  @State cached: boolean = false;
  @State cachedLabel: string = '';
  @LocalStorageLink('environment.connectionState') connectionState: string = 'offline';
  private parentCaches: Map<string, ClientCache | null> = new Map();
  private cacheEnvironmentId: string = '';
  private cache: ClientCache | null = null;
  private subscription: ReconnectingRpc | null = null;
  private pageGeneration: number = 0;
  private retrySaved: SavedEnvironment | null = null;
  private restoreTimer: number = -1;
  private restoreDelay: number = 1000;
  @StorageLink('appForeground') @Watch('restoreVisibilityChanged') foreground: boolean = true;
  private homeNavigationId: string = '';
  @State managingEnvironments: boolean = false;
  @LocalStorageLink('environment.environmentFormOpen') environmentFormOpen: boolean = false;
  @LocalStorageLink('environment.restoringConnectionId') restoringConnectionId: string = '';
  @StorageLink('notificationRoute') @Watch('openNotification') notificationRoute: string = '';
  private openingNotification: boolean = false;
  private async openNotification(): Promise<void> {
    const generation = this.pageGeneration;
    if (!this.isHome(generation) || this.environmentFormOpen || !this.notificationRoute || this.openingNotification) return;
    this.openingNotification = true;
    const request = this.notificationRoute;
    try {
      const route = JSON.parse(request) as Record<string, string>;
      if (this.connected?.descriptor.environmentId !== route.environmentId) {
        if (this.connecting || this.forgetting) return;
        const attempt = this.connectionAttempt;
        const routes = await loadEnvironments(getContext(this));
        const saved = routes.find((entry: SavedEnvironment) => entry.environmentId === route.environmentId);
        if (!this.isConnectionAttempt(attempt) || this.environmentFormOpen || this.notificationRoute !== request) return;
        if (saved === undefined) { this.managingEnvironments = true; this.status = '此会话所在环境尚未连接，请先添加环境'; return; }
        this.saved = routes;
        await this.restore(this.preferredRoute(saved, routes));
      }
      if (!this.isHome(generation) || this.environmentFormOpen || this.notificationRoute !== request || this.connected?.descriptor.environmentId !== route.environmentId) return;
      await router.pushUrl({ url: 'pages/Thread', params: route });
      if (this.notificationRoute === request) this.notificationRoute = '';
    } catch (_) { if (this.notificationRoute === request && this.isHome(generation)) this.status = '暂时无法打开此会话，请恢复连接后重试'; }
    finally {
      this.openingNotification = false;
      if (this.notificationRoute && this.notificationRoute !== request && this.isHome(generation)) await this.openNotification();
    }
  }

  aboutToAppear(): void {
    this.pageGeneration = ++EnvironmentSession.homeGeneration;
    const actions: EnvironmentPanelActions = {
      reload: () => { this.reloadSaved(); }, back: () => { this.environmentBack(); },
      add: (routed: boolean) => { this.openEnvironmentForm(routed ? this.managingEnvironments : true); },
      tasks: (routed: boolean) => { this.managingEnvironments = false; if (routed) router.back({ url: 'pages/Index' }); },
      toggle: (saved: SavedEnvironment, enabled: boolean, routed: boolean) => { this.setEnvironmentEnabled(saved, enabled, routed ? this.managingEnvironments : true); },
      reconnect: (saved: SavedEnvironment, routed: boolean) => { this.reconnectEnvironment(saved, routed ? this.managingEnvironments : true); },
      prefer: (saved: SavedEnvironment) => { this.preferRoute(saved); }, forget: (saved: SavedEnvironment) => { this.forget(saved); },
      connect: () => { this.connect(); }
    };
    this.getUIContext().getSharedLocalStorage()?.setOrCreate<EnvironmentPanelActions>('environment.actions', actions);
    if (this.connected === null && !this.connecting) this.restoreLast();
  }

  private openComposerAfterSwitch: boolean = false;

  private async selectComposerMachine(id: string, openComposer: boolean): Promise<void> {
    if (!this.isHome(this.pageGeneration) || this.forgetting) return;
    const attempt = this.beginConnectionAttempt();
    this.connecting = true;
    try {
      const routes = await loadEnvironments(getContext(this));
      if (!this.isConnectionAttempt(attempt)) return;
      this.saved = routes;
      const saved = routes.find((entry: SavedEnvironment) => (entry.connectionId ?? entry.environmentId) === id);
      if (saved === undefined) { this.status = '机器连接已移除，请重新连接'; return; }
      await this.restore(saved, false, false, openComposer);
    } catch (error) { if (this.isConnectionAttempt(attempt)) this.status = error instanceof Error ? error.message : String(error); }
    finally { if (this.isConnectionAttempt(attempt)) this.connecting = false; }
  }

  onPageShow(): void {
    this.pressedTaskId = ''; this.hoveredTaskId = ''; this.menuTaskId = '';
    this.loadGrouping();
    const params = (router.getParams() ?? {}) as Record<string, string>;
    if (params.homeRequest && params.homeRequest !== this.homeNavigationId) {
      this.homeNavigationId = params.homeRequest;
      if (params.view === 'connections') {
        this.managingEnvironments = true;
        this.environmentFormOpen = false;
        this.reloadSaved();
        if (params.selectConnection) this.selectComposerMachine(params.selectConnection, params.openComposer === 'true');
      }
      if (params.view === 'archive' && this.connected?.descriptor.environmentId === params.environmentId) {
        this.managingEnvironments = false;
        this.projectId = '';
        this.searchOpen = false;
        this.query = '';
        this.renamingId = '';
        this.archiveOrder = 'newest';
        this.selectFilter(3);
      }
    }
    if (this.connected !== null && this.connectionState !== 'failed') this.subscription?.resume();
    this.openNotification();
  }

  private async loadGrouping(): Promise<void> {
    const generation = this.pageGeneration;
    try {
      const grouping = await (await AppearanceStore.open(getContext(this))).projectGroupingMode();
      if (!this.isHome(generation)) return;
      this.groupingMode = grouping;
      this.groupingError = '';
      this.refreshThreads();
    } catch (_) { if (this.isHome(generation)) this.groupingError = '项目分组读取失败，请在设置中重试'; }
  }

  private async restoreLast(): Promise<void> {
    const attempt = this.beginConnectionAttempt();
    this.connecting = true;
    try {
      const saved = await loadEnvironments(getContext(this));
      if (!this.isConnectionAttempt(attempt)) return;
      this.saved = saved; this.connecting = false;
      if (saved.length > 0 && !this.environmentFormOpen) await this.restore(this.preferredRoute(saved[0], saved), this.managingEnvironments);
    } catch (error) { if (this.isConnectionAttempt(attempt)) this.status = error instanceof Error ? error.message : '无法读取已保存连接'; }
    finally { if (this.isConnectionAttempt(attempt)) this.connecting = false; }
  }

  private cancelRestoreTimer(): void {
    if (this.restoreTimer !== -1) clearTimeout(this.restoreTimer);
    this.restoreTimer = -1;
  }

  private isHome(generation: number): boolean {
    return generation !== 0 && generation === this.pageGeneration && generation === EnvironmentSession.homeGeneration;
  }

  private beginConnectionAttempt(): number {
    this.cancelRestoreTimer();
    this.retrySaved = null; this.restoringConnectionId = ''; this.connecting = false;
    this.openComposerAfterSwitch = false;
    return ++this.connectionAttempt;
  }

  private isConnectionAttempt(attempt: number): boolean {
    return this.isHome(this.pageGeneration) && attempt === this.connectionAttempt;
  }

  private preferredRoute(saved: SavedEnvironment, routes: SavedEnvironment[]): SavedEnvironment {
    if (!saved.ssh) return saved;
    return routes.find(route => route.environmentId === saved.environmentId && route.sshRole === 'primary') ?? saved;
  }

  private alternateRoutes(saved: SavedEnvironment): SavedEnvironment[] {
    if (!saved.ssh) return [];
    return this.saved.filter(route => route.ssh !== undefined && route.environmentId === saved.environmentId && route.connectionId !== saved.connectionId)
      .sort((a: SavedEnvironment, b: SavedEnvironment) => Number(b.sshRole === 'primary') - Number(a.sshRole === 'primary'));
  }

  private routeIdentityError(reason: string): boolean {
    return /认证|凭据|指纹|配对|ID 不匹配|authentication|fingerprint|permission denied|HTTP 40[13]/i.test(reason);
  }

  private retryableRouteError(reason: string): boolean {
    return /网络|超时|RPC connection|socket|connect failed|ssh handshake failed|timed? ?out|unreachable|HTTP 5\d\d/i.test(reason) &&
      !this.routeIdentityError(reason);
  }

  private restoreVisibilityChanged(): void {
    this.cancelRestoreTimer();
    if (this.isHome(this.pageGeneration) && !this.environmentFormOpen && this.foreground && this.retrySaved !== null && !this.forgetting && !this.connecting && this.connected === null) {
      this.restore(this.retrySaved, this.managingEnvironments, true);
    }
  }

  private scheduleRestore(saved: SavedEnvironment): void {
    if (!this.isHome(this.pageGeneration)) return;
    this.retrySaved = saved;
    this.cancelRestoreTimer();
    if (!this.foreground || this.environmentFormOpen) return;
    this.restoreTimer = setTimeout(() => { this.restoreVisibilityChanged(); }, this.restoreDelay);
    this.restoreDelay = Math.min(15000, this.restoreDelay * 2);
  }

  aboutToDisappear(): void {
    this.pageGeneration = 0; this.beginConnectionAttempt();
    this.disconnect().catch(() => {});
  }

  private async reloadSaved(): Promise<void> {
    const generation = this.pageGeneration;
    try { const saved = await loadEnvironments(getContext(this)); if (this.isHome(generation)) { this.saved = saved; this.refreshThreads(); } }
    catch (error) { if (this.isHome(generation)) this.status = error instanceof Error ? error.message : '无法读取已保存连接'; }
  }

  private async remember(connection: PreparedConnection): Promise<void> {
    const generation = this.pageGeneration;
    if (!this.isHome(generation) || this.connected !== connection) return;
    try {
      await connection.save();
      if (this.isHome(generation) && this.connected === connection) await this.reloadSaved();
    } catch (_) { if (this.isHome(generation) && this.connected === connection) this.status = '已连接，但无法保存凭据；下次可能需要重新配对'; }
  }

  private async restore(saved: SavedEnvironment, stayInEnvironments: boolean = false, retry: boolean = false, openComposer: boolean = false): Promise<void> {
    const id = saved.connectionId ?? saved.environmentId;
    if (!this.isHome(this.pageGeneration) || this.forgetting || this.environmentFormOpen ||
      (this.connecting && (retry || this.restoringConnectionId === id))) return;
    const attempt = this.beginConnectionAttempt();
    if (!retry) this.restoreDelay = 1000;
    this.managingEnvironments = stayInEnvironments;
    if (this.connected?.matchesSaved(saved)) { if (openComposer) this.newTask(); return; }
    this.connecting = true; this.retrySaved = saved; this.restoringConnectionId = id;
    const progress = retry ? 'reconnecting' : 'connecting';
    if (this.connected === null) this.connectionState = progress;
    try {
      if (this.connected !== null) await this.disconnect();
      if (!this.isConnectionAttempt(attempt)) return;
      this.connectionState = progress;
      if (!retry || this.cache === null) await this.loadCachedEnvironment(saved);
      const routes = [saved, ...this.alternateRoutes(saved)];
      for (let index = 0; index < routes.length; index++) {
        if (!this.isConnectionAttempt(attempt)) return;
        const route = routes[index];
        this.restoringConnectionId = route.connectionId ?? route.environmentId;
        const onStatus = (message: string): void => {
          if (this.isConnectionAttempt(attempt)) this.status = index > 0 && route.ssh ? `尝试 ${route.ssh.hostname}:${route.ssh.port} · ${message}` : message;
        };
        let connection: PreparedConnection;
        try {
          if (route.ssh) {
            const credentials = await readSshCredentials(route.connectionId ?? '');
            if (!this.isConnectionAttempt(attempt)) return;
            connection = await restoreSshEnvironment(route, credentials, onStatus);
          } else {
            const bearer = await readBearer(route.environmentId);
            if (!this.isConnectionAttempt(attempt)) return;
            connection = await restoreDirectEnvironment(route, bearer, onStatus);
          }
        } catch (error) {
          const reason = error instanceof Error ? error.message : String(error);
          if (index + 1 === routes.length || !this.foreground || !this.retryableRouteError(reason)) throw new Error(reason);
          continue;
        }
        await this.installConnection(connection, attempt, openComposer);
        return;
      }
    } catch (error) {
      if (!this.isConnectionAttempt(attempt)) return;
      this.retrySaved = null;
      const reason = error instanceof Error ? error.message : String(error);
      this.connectionState = 'failed'; this.status = `恢复失败：${reason}`;
      if (this.connected === null && this.retryableRouteError(reason)) this.scheduleRestore(saved);
    }
    finally { if (this.isConnectionAttempt(attempt)) { this.connecting = false; this.restoringConnectionId = ''; } }
  }

  private async installConnection(connection: PreparedConnection, attempt: number, openComposer: boolean = false): Promise<void> {
    if (!this.isConnectionAttempt(attempt)) { await connection.close(); return; }
    if (this.cacheEnvironmentId && this.cacheEnvironmentId !== connection.descriptor.environmentId) {
      this.shell = new ShellState(); this.cache = null; this.cached = false;
      this.threads = []; this.projects = []; this.projectId = '';
    }
    this.retrySaved = null;
    this.openComposerAfterSwitch = openComposer;
    this.connected = connection;
    const installed = this.connected;
    EnvironmentSession.current = installed;
    this.pairingToken = ''; this.password = '';
    if (this.environmentFormOpen) { this.environmentFormOpen = false; this.managingEnvironments = false; }
    this.status = `已连接：${connection.descriptor.label ?? connection.descriptor.environmentId}`;
    await Promise.all([this.remember(installed), this.loadThreads()]);
  }

  private async loadCachedEnvironment(saved: SavedEnvironment): Promise<void> {
    const generation = this.pageGeneration;
    const attempt = this.connectionAttempt;
    this.cached = false;
    this.cache = null;
    this.shell = new ShellState();
    this.threads = []; this.projects = [];
    this.cachedLabel = saved.label;
    this.cacheEnvironmentId = saved.environmentId;
    try {
      const cache = await ClientCache.open(getContext(this).filesDir, saved.environmentId);
      if (!this.isHome(generation) || attempt !== this.connectionAttempt || this.cacheEnvironmentId !== saved.environmentId) return;
      this.cache = cache;
      const snapshot = cache.shell();
      if (snapshot !== null) {
        this.shell.apply({ kind: 'snapshot', snapshot: snapshot });
        this.projects = this.shell.projects;
        this.cached = true;
        this.refreshThreads();
      }
    } catch (_) {}
  }

  private forget(saved: SavedEnvironment): void {
    if (this.connecting || this.forgetting) return;
    AlertDialog.show({ title: '忘记连接', message: `从此手机移除 ${saved.label}（${saved.ssh !== undefined ? saved.ssh.hostname + ':' + saved.ssh.port.toString() : saved.httpBaseUrl}）的访问凭据。再次连接需要重新配对。`,
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '忘记', action: async () => {
        if (this.connecting || this.forgetting) return;
        const generation = this.pageGeneration, id = saved.connectionId ?? saved.environmentId;
        const retrying = (this.retrySaved?.connectionId ?? this.retrySaved?.environmentId) === id;
        if (retrying) this.cancelRestoreTimer();
        this.forgetting = true;
        try {
          await forgetEnvironment(saved, getContext(this));
          if (!this.isHome(generation)) return;
          this.saved = this.saved.filter(route => (route.connectionId ?? route.environmentId) !== id);
          const remaining = this.saved.find(route => route.environmentId === saved.environmentId);
          const next = remaining ? this.preferredRoute(remaining, this.saved) : null;
          const activeRoute = this.connected?.matchesSaved(saved) === true;
          if (retrying || activeRoute) this.retrySaved = next;
          if (activeRoute || (this.connected === null && this.cacheEnvironmentId === saved.environmentId && !next)) {
            await this.disconnect();
            if (activeRoute && next && this.isHome(generation)) await this.loadCachedEnvironment(next);
          }
          await this.reloadSaved();
        } catch (_) { if (this.isHome(generation)) this.status = '无法删除已保存连接，请重试'; }
        finally { this.forgetting = false; if (this.retrySaved !== null && this.restoreTimer === -1) this.restoreVisibilityChanged(); }
      } }
    });
  }

  private async preferRoute(saved: SavedEnvironment): Promise<void> {
    try { await setPrimarySshRoute(getContext(this), saved); await this.reloadSaved(); }
    catch (_) { this.status = '无法保存主用线路，请重试'; this.getUIContext().getPromptAction().showToast({ message: this.status }); }
  }

  private makeTarget(): SshTarget {
    const target: SshTarget = {
      hostname: this.hostname,
      port: Number(this.port),
      username: this.username,
      password: this.password,
      hostFingerprint: this.hostFingerprint.trim()
    };
    if (this.existingSshServer) {
      target.serverHost = this.serverHost.trim() || undefined;
      target.serverPort = Number(this.serverPort);
      target.pairingToken = this.pairingToken;
    }
    return target;
  }

  private async connect(): Promise<void> {
    if (!this.isHome(this.pageGeneration) || this.connecting || this.forgetting) return;
    const attempt = this.beginConnectionAttempt();
    const direct = this.direct;
    const url = this.environmentUrl;
    const token = this.pairingToken;
    const target = direct ? null : this.makeTarget();
    const packageSpec = this.packageSpec;
    this.connecting = true;
    this.status = '准备…';
    try {
      const onStatus = (message: string): void => { if (this.isConnectionAttempt(attempt)) this.status = message; };
      if (this.connected !== null) await this.disconnect();
      if (!this.isConnectionAttempt(attempt)) return;
      this.connectionState = 'connecting';
      const connection = target === null
        ? await connectDirectEnvironment(url, token, onStatus)
        : await connectEnvironment(target, packageSpec, onStatus);
      await this.installConnection(connection, attempt);
    } catch (error) {
      if (!this.isConnectionAttempt(attempt)) return;
      this.connectionState = 'failed';
      this.status = `连接失败：${error instanceof Error ? error.message : String(error)}`;
    } finally {
      if (this.isConnectionAttempt(attempt)) this.connecting = false;
    }
  }

  private async loadThreads(): Promise<void> {
    const connection = this.connected, owner = this.pageGeneration;
    if (connection === null || !this.isHome(owner)) return;
    try {
      const cache = await ClientCache.open(getContext(this).filesDir, connection.descriptor.environmentId);
      if (!this.isHome(owner) || this.connected !== connection) return;
      this.cache = cache; this.cacheEnvironmentId = connection.descriptor.environmentId;
    } catch (_) {}
    if (!this.isHome(owner) || this.connected !== connection) return;
    this.subscription?.stop();
    let initial: RpcClient | null = connection.rpc;
    let requestGeneration: number = 0;
    let resumeShell: boolean = false;
    this.subscription = new ReconnectingRpc(async (): Promise<RpcClient> => {
      if (initial !== null) {
        const rpc = initial;
        initial = null;
        return rpc;
      }
      const reopening = requestGeneration;
      try { return await connection.openRpc(); }
      catch (error) {
        const reason = error instanceof Error ? error.message : String(error);
        if (this.isHome(owner) && this.connected === connection && reopening === requestGeneration && this.foreground &&
          !this.environmentFormOpen && !this.connecting && !this.forgetting) {
          if (this.routeIdentityError(reason)) {
            this.subscription?.stop();
            this.connectionState = 'failed'; this.status = `重连失败：${reason}`;
          } else if (this.retryableRouteError(reason)) {
            const active = this.saved.find(route => connection.matchesSaved(route));
            const alternate = active && this.alternateRoutes(active)[0];
            if (alternate) this.restore(alternate, this.managingEnvironments);
          }
        }
        throw new Error(reason);
      }
    }, async (rpc: RpcClient): Promise<void> => {
      if (!this.isHome(owner) || this.connected !== connection) return;
      const generation = requestGeneration;
      connection.rpc = rpc;
      this.connectionState = 'syncing';
      const configLoad = rpc.call<ServerConfig>(WS.serverGetConfig, new EmptyPayload()).catch((error: Error): ServerConfig | null => {
        if (!(error instanceof RpcRemoteError)) throw error;
        return null;
      });
      connection.pendingConfig = configLoad;
      AppStorage.setOrCreate('rpcEnvironmentId', connection.descriptor.environmentId);
      // Leave time for the live subscription when the optional HTTP refresh stalls.
      const snapshotLoad = resumeShell ? Promise.resolve<ShellSnapshot | null>(null)
        : connection.loadSnapshot<ShellSnapshot>('/api/orchestration/shell', 5000);
      const results = await Promise.all([configLoad, snapshotLoad]);
      if (!this.isHome(owner) || this.connected !== connection || connection.rpc !== rpc || generation !== requestGeneration) return;
      const config = results[0] as ServerConfig | null;
      connection.liveConfig = config;
      connection.pendingConfig = null;
      const snapshot = results[1] as ShellSnapshot | null;
      this.pinSupported = config?.environment?.capabilities?.threadPinning === true;
      this.pinReorderSupported = config?.environment?.capabilities?.threadPinReorder === true;
      this.activeReorderSupported = config?.environment?.capabilities?.threadActiveReorder === true;
      if (config !== null) this.cache?.setCatalog(config);
      const authoritative = snapshot !== null && Number.isSafeInteger(snapshot.snapshotSequence) && snapshot.snapshotSequence >= 0 &&
        Array.isArray(snapshot.threads) && Array.isArray(snapshot.projects);
      let replacedHistory = authoritative && snapshot!.snapshotSequence < (this.shell.cursor() ?? -1);
      if (authoritative) {
        this.shell.requireSnapshot();
        this.shell.apply({ kind: 'snapshot', snapshot: snapshot! });
      }
      const subscription: ShellSubscription = {};
      if (config?.shellResumeCompletionMarker === true) subscription.requestCompletionMarker = true;
      const cursor = this.shell.cursor();
      if ((authoritative || resumeShell) && cursor !== null) subscription.afterSequence = cursor;
      let baseline = (authoritative || resumeShell) && cursor !== null;
      let synchronized = baseline && config?.shellResumeCompletionMarker !== true;
      let firstData = true;
      const applyItems = (values: object[]): void => {
        if (!this.isHome(owner) || this.connected !== connection || connection.rpc !== rpc || generation !== requestGeneration) return;
        const restored = !this.live;
        const before = this.shell.cursor();
        for (const value of values) {
          const item = value as ShellItem;
          if (item.kind === 'snapshot-required') { resumeShell = false; rpc.close(); return; }
          const full = item.kind === 'snapshot' && item.resolvedRepositoryIdentityRoots === undefined;
          if (full && (!Number.isSafeInteger(item.snapshot?.snapshotSequence) || (item.snapshot?.snapshotSequence ?? -1) < 0 ||
            !Array.isArray(item.snapshot?.threads) || !Array.isArray(item.snapshot?.projects))) continue;
          if (full) {
            if (firstData) {
              if (item.snapshot!.snapshotSequence < (this.shell.cursor() ?? -1)) replacedHistory = true;
              this.shell.requireSnapshot();
            }
            baseline = true;
          }
          if (!baseline) continue;
          this.shell.apply(item);
          if (item.resolvedRepositoryIdentityRoots !== undefined) continue;
          firstData = false;
          if (item.kind === 'synchronized' || full) synchronized = true;
        }
        if (baseline && this.shell.cursor() !== before) this.subscription?.progress();
        this.live = synchronized;
        if (this.live) { resumeShell = true; this.subscription?.healthy(); }
        if ((restored || replacedHistory) && this.live) {
          AppStorage.setOrCreate('onlineEnvironmentId', connection.descriptor.environmentId);
          ComposerOutbox.connected(getContext(this).filesDir, connection.descriptor.environmentId, rpc, this.shell, replacedHistory);
          replacedHistory = false;
        }
        this.cached = !synchronized && this.shell.threads.length > 0;
        this.connectionState = synchronized ? 'connected' : 'syncing';
        this.status = synchronized ? `已连接：${connection.descriptor.label ?? connection.descriptor.environmentId}` : '正在同步新增任务…';
        this.projects = this.shell.projects;
        if (baseline) this.cache?.setShell(this.shell.snapshot());
        if (this.live) TaskNotifications.observe(connection.descriptor.environmentId, this.shell.snapshot());
        if (this.live) this.openNotification();
        if (this.live && this.openComposerAfterSwitch && this.projects.length > 0) { this.openComposerAfterSwitch = false; this.projectId = ''; this.newTask(); }
        this.refreshThreads();
        if (restored && this.live && this.filterIndex === 3) this.loadArchive();
      };
      applyItems([]);
      return rpc.callStream(WS.threadsList, subscription, applyItems);
    }, (state: string) => {
      requestGeneration++;
      if (!this.isHome(owner) || this.connected !== connection) return;
      connection.liveConfig = null;
      connection.pendingConfig = null;
      AppStorage.setOrCreate('rpcEnvironmentId', '');
      AppStorage.setOrCreate('onlineEnvironmentId', '');
      ComposerOutbox.disconnected(connection.rpc);
      this.live = false;
      this.cached = this.shell.threads.length > 0 || this.projects.length > 0;
      this.connectionState = state;
      this.status = state === 'connecting' ? '正在连接环境…' : '连接中断，正在自动重连…';
    }, () => { resumeShell = false; });
    this.subscription.start();
  }

  @Builder
  private projectSheet() {
    ProjectPicker({ projects: this.filterIndex === 3 ? this.archivedSnapshot.projects : this.projects,
      selectedId: this.projectId, environmentId: this.connected?.descriptor.environmentId ?? this.cacheEnvironmentId,
      groupingMode: this.groupingMode, allowAll: true, canAdd: this.live,
      onSelect: (id: string) => { this.projectId = id; this.projectsOpen = false; this.refreshThreads(); },
      onAdd: () => { this.projectsOpen = false; router.pushUrl({ url: 'pages/AddProject' }); }
    })
  }

  @Builder
  private machineSheet() {
    EnvironmentPicker({ environments: this.saved,
      selectedId: this.restoringConnectionId || (this.saved.find((saved: SavedEnvironment) => this.connected?.matchesSaved(saved))?.connectionId ?? this.connected?.descriptor.environmentId ?? ''),
      connectionState: this.connectionState, disabled: this.forgetting, canManage: true,
      onSelect: (saved: SavedEnvironment) => { this.machinesOpen = false; this.restore(saved); },
      onManage: () => { this.machinesOpen = false; router.pushUrl({ url: 'pages/Environments' }); }
    }).padding({ left: 16, right: 16, top: 8, bottom: 24 })
  }

  private refreshThreads(): void {
    const projects = this.filterIndex === 3 ? this.archivedSnapshot.projects : this.projects;
    const models = this.cache?.models() ?? [];
    this.projectGroups = groupProjects(projects, this.connected?.descriptor.environmentId ?? '', this.groupingMode);
    const group = this.projectGroups.find((entry: ProjectGroup) => entry.projectIds.includes(this.projectId));
    const filters = this.taskFilters;
    let localParents: Set<string> | null = null;
    const parentListed = (environmentId: string, threadId: string): boolean => {
      if (environmentId !== (this.connected?.descriptor.environmentId ?? this.cacheEnvironmentId)) return this.remoteParentListed(environmentId, threadId);
      if (!localParents) localParents = new Set(this.shell.threads.filter(thread => !thread.archivedAt).map(thread => thread.id));
      return localParents.has(threadId);
    };
    const source = this.filterIndex === 3
      ? searchArchivedThreads(this.archivedSnapshot, this.query, this.connected?.descriptor.label ?? '', parentListed)
      : this.shell.threads;
    const visible = visibleThreads(source, '', filters[this.filterIndex], this.filterIndex === 3 ? '' : this.query, this.archiveOrder, parentListed)
      .filter((thread: ThreadShell) => !this.projectId || (group !== undefined && group.projectIds.includes(thread.projectId)));
    this.threads = (this.filterIndex === 3 ? visible : sortTaskThreads(visible)).map((thread: ThreadShell): ThreadRow => ({
        id: thread.id, title: thread.title ?? '未命名任务',
        state: taskStatus(thread), branch: thread.branch ?? '',
        faviconPath: projects.find((project: ProjectShell) => project.id === thread.projectId)?.faviconPath ?? '',
        projectTitle: projects.find((project: ProjectShell) => project.id === thread.projectId)?.title ?? '',
        cwd: projects.find((project: ProjectShell) => project.id === thread.projectId)?.workspaceRoot ?? '',
        archived: Boolean(thread.archivedAt), settled: taskStatus(thread) === 'completed',
        updated: relativeTaskTime(this.filterIndex === 3 ? thread.archivedAt ?? thread.updatedAt : thread.updatedAt, Date.now()),
        provider: models.find((model) => model.instanceId === thread.modelSelection?.instanceId)?.driver ?? thread.modelSelection?.instanceId ?? '',
        fast: fastModeEnabled(thread.modelSelection ?? null, models.find((model) => model.instanceId === thread.modelSelection?.instanceId &&
          model.model === thread.modelSelection?.model)?.optionDescriptors ?? []),
        pinned: !!thread.pinnedAt,
        section: taskSection(taskStatus(thread), !!thread.pinnedAt),
        workTurn: taskWorkTurn(thread),
        unread: ThreadReads.unread(this.connected?.descriptor.environmentId ?? this.cacheEnvironmentId, thread.id, threadReadRevision(taskLatestTurn(thread))),
        readRevision: threadReadRevision(taskLatestTurn(thread))
      }));
    if (this.filterIndex === 1 || this.filterIndex === 0) this.threads.sort((left: ThreadRow, right: ThreadRow) => left.section - right.section);
    const counts: Map<string, number> = new Map();
    const query = this.query.trim().toLocaleLowerCase();
    let total = 0;
    for (const thread of this.shell.threads) {
      if (shownUnderParent(thread, parentListed) || thread.archivedAt || (this.projectId && !group?.projectIds.includes(thread.projectId)) ||
        (query && !(thread.title ?? '').toLocaleLowerCase().includes(query))) continue;
      const category = taskStatus(thread);
      counts.set(category, (counts.get(category) ?? 0) + 1);
      total++;
    }
    this.filterOptions = filters.map((filter: string, index: number): TaskFilterOption => ({
      value: this.filterLabels[index] + (index === 3 ? '' : ` (${filter === 'all' ? total : filter === 'active' ? total - (counts.get('completed') ?? 0) : counts.get(filter === 'settled' ? 'completed' : filter) ?? 0})`)
    }));
  }

  private remoteParentListed(environmentId: string, threadId: string): boolean {
    if (!this.saved.some(entry => entry.environmentId === environmentId)) return false;
    if (!this.parentCaches.has(environmentId)) {
      const generation = this.pageGeneration;
      this.parentCaches.set(environmentId, null);
      ClientCache.open(getContext(this).filesDir, environmentId).then((cache: ClientCache) => {
        this.parentCaches.set(environmentId, cache);
        if (this.isHome(generation)) this.refreshThreads();
      }).catch(() => { this.parentCaches.delete(environmentId); });
    }
    return this.parentCaches.get(environmentId)?.listsThread(threadId) === true;
  }

  private selectFilter(index: number): void {
    const archiveChanged = (this.filterIndex === 3) !== (index === 3);
    this.filterIndex = index; this.filtersOpen = false; this.refreshThreads();
    if (archiveChanged && this.threads.length > 0) this.taskScroller.scrollToIndex(0, false, ScrollAlign.START);
    if (index === 3) this.loadArchive();
  }
  @Builder
  private filterSheet() {
    List({ space: 4 }) {
      ForEach(this.filterOptions, (option: TaskFilterOption, index: number) => {
        ListItem() {
          Row({ space: 12 }) {
            AppIcon({ name: TASK_FILTER_ICONS[this.taskFilters[index]] ?? 'filter', iconSize: 18,
              tint: statusColor(index === 2 ? 'completed' : this.taskFilters[index], this.color('screen')) })
            Text(option.value).fontSize(this.font(15)).fontColor(this.color('foreground')).layoutWeight(1)
            if (this.filterIndex === index) { AppIcon({ name: 'check', iconSize: 20, tint: this.color('primary') }) }
          }.width('100%').padding(14).borderRadius(12)
            .backgroundColor(this.filterIndex === index ? this.color('card') : Color.Transparent)
            .onClick(() => { this.selectFilter(index); }).accessibilityText(`筛选 ${option.value}`)
        }
      }, (option: TaskFilterOption) => option.value)
    }.padding({ left: 16, right: 16, bottom: 20 }).height('100%').width('100%')
  }

  private selectArchiveOrder(order: string): void {
    if (this.archiveOrder === order) return;
    this.archiveOrder = order;
    this.refreshThreads();
    if (this.threads.length) this.taskScroller.scrollToIndex(0, false, ScrollAlign.START);
  }
  @Builder
  private archiveToolbar() {
    Row({ space: 6 }) {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 6 }) {
          AppIcon({ name: 'archive', iconSize: 17, tint: this.color('primary') })
          Text('已归档').fontSize(this.font(15)).fontWeight(FontWeight.Medium).fontColor(this.color('foreground')).maxLines(1)
          if (this.threads.length > 0) { Text(`${this.threads.length}`).fontSize(this.font(12)).fontColor(this.color('foreground-muted')).maxLines(1) }
          AppIcon({ name: 'close', iconSize: 11, tint: this.color('foreground-muted') })
        }.width('100%')
      }.id('archive-exit').height(40).layoutWeight(1).padding(0).borderRadius(10).backgroundColor(Color.Transparent)
        .accessibilityText('清除归档筛选').onClick(() => { this.selectFilter(1); })
      Button({ type: ButtonType.Normal }) {
        Row({ space: 4 }) {
          Text(this.archiveOrder === 'oldest' ? '最早优先' : '最新优先').fontSize(this.font(13)).fontColor(this.color('foreground-secondary')).maxLines(1)
          AppIcon({ name: 'down', iconSize: 11, tint: this.color('foreground-muted') })
        }
      }.id('archive-sort').height(40).padding({ left: 8, right: 8 }).borderRadius(12).backgroundColor(Color.Transparent)
        .accessibilityText(`归档排序：${this.archiveOrder === 'oldest' ? '最早优先' : '最新优先'}`)
        .bindMenu([
          { value: '最新归档优先', symbolIcon: menuIcon($r('sys.symbol.text_and_arrow_down')), action: () => { this.selectArchiveOrder('newest'); } },
          { value: '最早归档优先', symbolIcon: menuIcon($r('sys.symbol.text_and_arrow_up')), action: () => { this.selectArchiveOrder('oldest'); } }
        ], { modalMode: menuModalMode() })
      Button({ type: ButtonType.Circle }) {
        AppIcon({ name: 'refresh', iconSize: 17, tint: this.color('foreground-secondary') })
      }.id('archive-refresh').width(40).height(40).padding(0).backgroundColor(this.color('subtle'))
        .enabled(this.live && !this.loadingArchive).accessibilityText(this.loadingArchive ? '正在刷新归档' : '刷新归档').onClick(() => { this.loadArchive(); })
    }.width('100%').padding({ left: 18, right: 14, top: 8, bottom: 6 })
  }

  private async loadArchive(): Promise<void> {
    const connection = this.connected;
    if (connection === null || !this.live || this.loadingArchive) return;
    this.loadingArchive = true; this.archiveError = false;
    try {
      const snapshot = await connection.rpc.call<ShellSnapshot>('orchestration.getArchivedShellSnapshot', new EmptyPayload());
      if (this.connected !== connection) return;
      this.archivedSnapshot = snapshot;
      this.refreshThreads();
    } catch (_) { if (this.connected === connection) this.archiveError = true; }
    finally { if (this.connected === connection) this.loadingArchive = false; }
  }

  private newTask(): void {
    this.composerOpen = true;
  }

  @Builder
  private newTaskSheet() {
    NewTask({ environmentId: this.connected?.descriptor.environmentId ?? this.cacheEnvironmentId, projects: this.projects, groupingMode: this.groupingMode, initialProjectId: this.projectId, closeRequest: this.composerCloseRequest, connectionState: this.connectionState,
      onClose: () => { this.composerOpen = false; },
      onCreated: (params: Record<string, string>) => {
        this.composerOpen = false;
        router.pushUrl({ url: 'pages/Thread', params: params });
      },
      onMachine: (saved: SavedEnvironment) => {
        this.composerOpen = false;
        this.restore(saved, false, false, true);
      }
    })
  }

  private startRename(thread: ThreadRow): void {
    if (!this.live || this.actionBusy || this.connected === null) return;
    this.renamingId = thread.id;
    this.renameTitle = thread.title;
    this.renameOriginalTitle = thread.title;
    this.renameEnvironmentId = this.connected.descriptor.environmentId;
    this.renameError = '';
    this.renameOpen = true;
  }

  private async saveRename(): Promise<void> {
    if (!this.renameOpen || !this.renamingId || !this.live || this.actionBusy ||
      this.connected?.descriptor.environmentId !== this.renameEnvironmentId) return;
    const title = this.renameTitle.trim();
    if (!title) return;
    if (title === this.renameOriginalTitle.trim()) { this.renameOpen = false; this.renamingId = ''; return; }
    const id = this.renamingId;
    this.renameError = '';
    const saved = await this.taskAction('thread.metadata.update', id, title);
    if (this.renamingId !== id || !this.renameOpen) return;
    if (saved) { this.renameOpen = false; this.renamingId = ''; }
    else this.renameError = `重命名未成功：${this.status || '请检查连接后重试'}`;
  }

  private async taskAction(type: string, threadId: string, title: string = ''): Promise<boolean> {
    const connection = this.connected;
    if (connection === null || !this.live || this.actionBusy) return false;
    const command: TaskActionCommand = {
      type: type, commandId: util.generateRandomUUID(true), threadId: threadId
    };
    if (type === 'thread.metadata.update') {
      if (!title.trim()) return false;
      command.title = title.trim();
    }
    if (type === 'thread.unsettle') command.reason = 'user';
    this.actionBusy = true;
    try {
      await connection.rpc.call(WS.threadStartTurn, command);
      if (this.connected !== connection) return false;
      if (this.filterIndex === 3) await this.loadArchive();
      return this.connected === connection;
    } catch (error) {
      if (this.connected === connection) this.status = error instanceof Error ? error.message : String(error);
      return false;
    }
    finally { this.actionBusy = false; }
  }

  private canOrder(thread: ThreadRow): boolean {
    return this.connected !== null && this.live && !this.actionBusy && !thread.archived &&
      (thread.pinned ? this.pinReorderSupported : !thread.settled && this.activeReorderSupported);
  }

  private startOrder(thread: ThreadRow): void {
    if (!this.canOrder(thread)) return;
    const rows = new Map<string, ThreadRow>();
    for (const row of this.threads) rows.set(row.id, row);
    this.orderRows = sortTaskThreads(this.shell.threads)
      .filter((entry: ThreadShell) => rows.has(entry.id) && inThreadOrderGroup(entry, thread.pinned))
      .map((entry: ThreadShell) => rows.get(entry.id)!);
    this.orderOriginalIds = this.orderRows.map((row: ThreadRow) => row.id);
    this.orderMovedIds = [];
    this.orderPinned = thread.pinned;
    this.orderConnection = this.connected;
    this.orderError = '';
    this.orderOpen = true;
  }

  private orderDirty(): boolean {
    return this.orderRows.some((row: ThreadRow, index: number) => row.id !== this.orderOriginalIds[index]);
  }

  private moveOrder(from: number, to: number): void {
    if (!this.orderOpen || this.actionBusy || from === to || from < 0 || to < 0 || from >= this.orderRows.length || to >= this.orderRows.length) return;
    const rows = this.orderRows.slice();
    const moved = rows.splice(from, 1)[0];
    rows.splice(to, 0, moved);
    this.orderRows = rows;
    if (!this.orderMovedIds.includes(moved.id)) this.orderMovedIds.push(moved.id);
    this.orderError = '';
  }

  private async saveOrder(): Promise<void> {
    const connection = this.orderConnection;
    if (!this.orderOpen || this.actionBusy || !this.live || connection === null || this.connected !== connection ||
      !(this.orderPinned ? this.pinReorderSupported : this.activeReorderSupported)) return;
    if (!this.orderDirty()) { this.orderOpen = false; return; }
    const ids = this.orderRows.map((row: ThreadRow) => row.id);
    const currentIds = new Set(this.shell.threads.filter((thread: ThreadShell) => inThreadOrderGroup(thread, this.orderPinned)).map((thread: ThreadShell) => thread.id));
    if (ids.some((id: string) => !currentIds.has(id))) {
      this.orderError = '会话状态已变化，请关闭后重新打开排序';
      return;
    }
    const assignments = planThreadReorder(this.shell.threads, ids, this.orderMovedIds, this.orderPinned);
    const rpc = connection.rpc;
    this.actionBusy = true;
    this.orderError = '';
    try {
      for (const assignment of assignments) {
        if (this.connected !== connection || connection.rpc !== rpc || !this.live) throw new Error('连接已变化，请恢复连接后重试');
        const command: TaskActionCommand = { type: this.orderPinned ? 'thread.pin.reorder' : 'thread.active.reorder',
          commandId: util.generateRandomUUID(true), threadId: assignment.id, orderKey: assignment.orderKey };
        await rpc.call(WS.threadStartTurn, command);
      }
      if (this.connected !== connection || connection.rpc !== rpc || !this.live) throw new Error('连接已变化，请恢复连接后重试');
      this.orderOpen = false;
    } catch (error) {
      if (this.connected === connection) this.orderError = `顺序未全部保存，请重试：${error instanceof Error ? error.message : String(error)}`;
    } finally { this.actionBusy = false; }
  }

  private deleteTask(thread: ThreadRow): void {
    AlertDialog.show({ title: '删除任务？', message: `将删除“${thread.title}”，此操作不可恢复。`,
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '删除', action: () => { this.taskAction('thread.delete', thread.id); } }
    });
  }

  private async disconnect(): Promise<void> {
    this.orderOpen = false; this.orderRows = []; this.orderConnection = null;
    this.pinSupported = false; this.pinReorderSupported = false; this.activeReorderSupported = false;
    this.cache?.flush();
    this.cache = null; this.cacheEnvironmentId = ''; this.cached = false; this.loadingArchive = false; this.connectionState = 'offline';
    this.subscription?.stop();
    this.subscription = null;
    this.live = false;
    const connection = this.connected;
    if (connection !== null) {
      ComposerOutbox.disconnected(connection.rpc);
      if (EnvironmentSession.current === connection) {
        EnvironmentSession.current = null;
        AppStorage.setOrCreate('rpcEnvironmentId', '');
        AppStorage.setOrCreate('onlineEnvironmentId', '');
      }
    }
    this.shell = new ShellState();
    this.connected = null;
    this.threads = [];
    this.projects = [];
    this.projectId = '';
    this.archivedSnapshot = { snapshotSequence: 0, projects: [], threads: [] }; this.archiveError = false;
    this.filterIndex = 1;
    this.status = '已断开';
    if (connection !== null) await connection.close();
  }

  private openThread(thread: ThreadRow): void {
    if (!thread.archived) { this.routeThread(thread); return; }
    if (!this.live || this.actionBusy) return;
    AlertDialog.show({ title: '恢复并打开任务？', message: `“${thread.title}”已归档。恢复后可查看消息和文件，并继续任务。`,
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '恢复并打开', action: async () => {
        if (await this.taskAction('thread.unarchive', thread.id)) this.routeThread(thread);
      } }
    });
  }

  private routeThread(thread: ThreadRow): void {
    const connection = this.connected;
    const params: Record<string, string> = {
      'environmentId': connection !== null ? connection.descriptor.environmentId : this.cacheEnvironmentId,
      'threadId': thread.id,
      'socketUrl': connection !== null ? connection.socketUrl : '',
      'httpBaseUrl': connection !== null ? connection.httpBaseUrl : '',
      'cwd': thread.cwd, 'title': thread.title, 'projectTitle': thread.projectTitle === 'No project' ? '独立任务' : thread.projectTitle
    };
    const options: router.RouterOptions = {
      url: 'pages/Thread',
      params: params
    };
    router.pushUrl(options);
  }

  private openEnvironmentForm(stayInEnvironments: boolean = true): void {
    if (this.forgetting) return;
    const resume = this.retrySaved;
    this.beginConnectionAttempt();
    this.retrySaved = resume;
    this.managingEnvironments = stayInEnvironments; this.environmentFormOpen = true; this.status = '';
    if (this.connected === null) this.connectionState = 'offline';
  }

  private environmentBack(): void {
    if (this.environmentFormOpen) {
      if (this.connecting) this.beginConnectionAttempt();
      this.environmentFormOpen = false;
      if (this.connected === null && this.retrySaved === null && this.saved.length === 0) this.restoreLast();
      else this.restoreVisibilityChanged();
    } else if (this.connected !== null || this.cached) this.managingEnvironments = false;
    else router.pushUrl({ url: 'pages/Settings' });
  }

  onBackPress(): boolean {
    if (this.environmentFormOpen || (this.managingEnvironments && (this.connected !== null || this.cached))) {
      this.environmentBack();
      return true;
    }
    if (this.searchOpen) { this.closeThreadSearch(); return true; }
    return false;
  }

  private async setEnvironmentEnabled(saved: SavedEnvironment, enabled: boolean, stayInEnvironments: boolean = true): Promise<void> {
    if (this.forgetting) return;
    if (enabled) await this.restore(saved, stayInEnvironments);
    else if (this.connected?.matchesSaved(saved)) { this.beginConnectionAttempt(); await this.disconnect(); }
  }

  private reconnectEnvironment(saved: SavedEnvironment, stayInEnvironments: boolean = true): void {
    if (this.forgetting) return;
    if (this.connected?.matchesSaved(saved)) { this.beginConnectionAttempt(); this.subscription?.start(); }
    else this.restore(saved, stayInEnvironments);
  }

  @Builder
  private orderSheet() {
    Column({ space: 12 }) {
      Text('长按拖动调整当前筛选内的会话顺序').fontSize(this.font(13)).fontColor(this.color('foreground-muted')).width('100%')
      List({ space: 6 }) {
        ForEach(this.orderRows, (thread: ThreadRow) => {
          ListItem() {
            Row({ space: 12 }) {
              ProjectIcon({ cwd: thread.cwd, faviconPath: thread.faviconPath, iconSize: 24, label: thread.projectTitle, chatFallback: true })
              Column({ space: 4 }) {
                Text(thread.title).fontSize(this.font(16)).fontColor(this.color('foreground')).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                Text(thread.projectTitle).fontSize(this.font(12)).fontColor(this.color('foreground-muted')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              AppIcon({ name: 'grip', iconSize: 22, tint: this.color('foreground-muted') })
            }.width('100%').padding(16).borderRadius(14).backgroundColor(this.color('card'))
              .accessibilityText(`${thread.title}，长按拖动排序`)
          }
        }, (thread: ThreadRow) => thread.id)
          .onMove((from: number, to: number) => { this.moveOrder(from, to); })
      }.width('100%').layoutWeight(1).enabled(!this.actionBusy)
      if (!this.live) { Text('连接恢复后可保存').fontSize(this.font(13)).fontColor(this.color('foreground-muted')).width('100%') }
      if (this.orderError) { Text(this.orderError).fontSize(this.font(13)).fontColor(this.color('danger-foreground')).width('100%') }
      Row({ space: 12 }) {
        Button('取消').height(44).layoutWeight(1).fontColor(this.color('foreground')).backgroundColor(this.color('subtle'))
          .enabled(!this.actionBusy).onClick(() => { this.orderOpen = false; })
        Button(this.actionBusy ? '保存中…' : '保存').height(44).layoutWeight(1)
          .fontColor(this.color('primary-foreground')).backgroundColor(this.color('primary'))
          .enabled(this.live && !this.actionBusy && this.orderDirty()).onClick(() => { this.saveOrder(); })
      }.width('100%')
    }.width('100%').height('100%').padding({ left: 20, right: 20, top: 8, bottom: 24 })
  }

  @Builder
  private renameSheet() {
    Column({ space: 16 }) {
      TextInput({ text: this.renameTitle, placeholder: '输入会话名称' }).fontSize(this.font(16)).height(48)
        .fontColor(this.color('foreground')).backgroundColor(this.color('input')).borderRadius(12)
        .defaultFocus(true).enterKeyType(EnterKeyType.Done).enabled(!this.actionBusy)
        .onChange((value: string) => { this.renameTitle = value; this.renameError = ''; })
        .onSubmit(() => { this.saveRename(); })
      if (this.renameError) { Text(this.renameError).fontSize(this.font(13)).fontColor(this.color('danger-foreground')).width('100%') }
      Row({ space: 12 }) {
        Button('取消').height(44).layoutWeight(1).fontColor(this.color('foreground')).backgroundColor(this.color('subtle'))
          .enabled(!this.actionBusy).onClick(() => { this.renameOpen = false; this.renamingId = ''; })
        Button(this.actionBusy ? '保存中…' : '保存').height(44).layoutWeight(1)
          .fontColor(this.color('primary-foreground')).backgroundColor(this.color('primary'))
          .enabled(this.live && !this.actionBusy && this.renameTitle.trim().length > 0)
          .onClick(() => { this.saveRename(); })
      }.width('100%')
    }.width('100%').padding({ left: 20, right: 20, top: 8, bottom: 24 })
  }

  @Builder
  private taskMenu(thread: ThreadRow) {
    Menu() {
      MenuItem({ content: thread.pinned ? '取消置顶' : '置顶会话', symbolStartIcon: menuIcon(thread.pinned ? $r('sys.symbol.pin_slash') : $r('sys.symbol.pin')) }).enabled(this.live && !this.actionBusy && this.pinSupported)
        .onClick(() => { this.taskAction(thread.pinned ? 'thread.unpin' : 'thread.pin', thread.id); })
      if (thread.pinned ? this.pinReorderSupported : !thread.settled && this.activeReorderSupported) {
        MenuItem({ content: '调整顺序', symbolStartIcon: menuIcon($r('sys.symbol.sort')) }).enabled(this.canOrder(thread))
          .onClick(() => { this.startOrder(thread); })
      }
      MenuItem({ content: thread.unread ? '标记为已读' : '标记为未读', symbolStartIcon: menuIcon(thread.unread ? $r('sys.symbol.envelope_open') : $r('sys.symbol.envelope_badge_dot')) })
        .onClick(() => { ThreadReads.mark(this.connected?.descriptor.environmentId ?? this.cacheEnvironmentId, thread.id, thread.readRevision, !thread.unread).catch(() => {}); })
      MenuItem({ content: '重命名', symbolStartIcon: menuIcon($r('sys.symbol.square_and_pencil')) }).enabled(this.live && !this.actionBusy)
        .onClick(() => { this.startRename(thread); })
      MenuItem({ content: thread.settled ? '恢复进行中' : '标记完成', symbolStartIcon: menuIcon(thread.settled ? $r('sys.symbol.play') : $r('sys.symbol.checkmark_circle')) }).enabled(this.live && !this.actionBusy)
        .onClick(() => { this.taskAction(thread.settled ? 'thread.unsettle' : 'thread.settle', thread.id); })
      MenuItem({ content: thread.archived ? '恢复归档' : '归档', symbolStartIcon: menuIcon(thread.archived ? $r('sys.symbol.folder_badge_arrow_left') : $r('sys.symbol.archivebox')) }).enabled(this.live && !this.actionBusy)
        .onClick(() => { this.taskAction(thread.archived ? 'thread.unarchive' : 'thread.archive', thread.id); })
      MenuItem({ content: '删除', symbolStartIcon: menuIcon($r('sys.symbol.trash'), this.color('danger-foreground')) }).contentFontColor(this.color('danger-foreground')).enabled(this.live && !this.actionBusy)
        .onClick(() => { this.deleteTask(thread); })
    }
  }

  private async markAllRead(): Promise<void> {
    if (this.markingAllRead) return;
    const environmentId = this.connected?.descriptor.environmentId ?? this.cacheEnvironmentId;
    if (!environmentId) return;
    const targets: Map<string, ThreadReadTarget> = new Map();
    for (const thread of this.archivedSnapshot.threads.concat(this.archivedSnapshot.archivedThreads ?? [], this.shell.threads)) {
      targets.set(thread.id, { threadId: thread.id, revision: threadReadRevision(taskLatestTurn(thread)) });
    }
    this.markingAllRead = true;
    try { await ThreadReads.markAll(environmentId, Array.from(targets.values())); }
    catch (_) {}
    finally { this.markingAllRead = false; }
  }
  @Builder
  private floatingNavigation() {
    Row({ space: 12 }) {
      Column() {
      ChatGlass({ capsule: true, radius: 32 }) {
      Row({ space: 4 }) {
        Button({ type: ButtonType.Normal }) { AppIcon({ name: 'chat', iconSize: 24, tint: this.color('foreground') }) }
          .height(48).layoutWeight(1).padding(0).borderRadius(24).backgroundColor(this.color('subtle-strong')).accessibilityText('全部任务')
          .onClick(() => { this.projectId = ''; this.selectFilter(1); })
        Button({ type: ButtonType.Normal }) { AppIcon({ name: 'folder', iconSize: 24, tint: this.projectId ? this.color('primary') : this.color('glass-label') }) }
          .height(48).layoutWeight(1).padding(0).borderRadius(24).backgroundColor(Color.Transparent).accessibilityText('项目')
          .onClick(() => { this.projectsOpen = true; })
          .bindSheet($$this.projectsOpen, this.projectSheet(), { systemMaterial: immersiveMaterial('popup'), height: SheetSize.LARGE, title: { title: '项目' }, dragBar: true, showClose: true })
        Button({ type: ButtonType.Normal }) { AppIcon({ name: 'settings', iconSize: 24, tint: this.color('glass-label') }) }
          .height(48).layoutWeight(1).padding(0).borderRadius(24).backgroundColor(Color.Transparent).accessibilityText('设置')
          .onClick(() => { router.pushUrl({ url: 'pages/Settings' }); })
      }.padding(6).width('100%')
      }
      }.layoutWeight(1)
      Button({ type: ButtonType.Circle }) {
        ChatGlass({ capsule: true, radius: 30 }) {
          Stack() { AppIcon({ name: 'plus', iconSize: 32, tint: this.color('chat-link') }) }
            .width(60).height(60).linearGradient({ angle: 145, colors: [
              [this.themeKey.endsWith('-dark') ? '#52000000' : '#25' + this.color('glass-glow').slice(1), 0],
              [this.themeKey.endsWith('-dark') ? '#78000000' : '#66' + this.color('glass-depth').slice(1), 1]
            ] }).hitTestBehavior(HitTestMode.None)
        }
      }.height(60).width(60).padding(0).backgroundColor(Color.Transparent).clip(true).accessibilityText('新任务')
        .enabled(this.projects.length > 0 && !!(this.connected?.descriptor.environmentId || this.cacheEnvironmentId)).onClick(() => { this.newTask(); })
    }.margin({ left: 16, right: 16, bottom: 12 }).hitTestBehavior(HitTestMode.Default)
  }

  private closeThreadSearch(): void {
    this.threadSearch.stopEditing();
    this.searchOpen = false;
    if (this.query.length > 0) { this.query = ''; this.refreshThreads(); }
  }

  @Builder
  private threadFilterButton() {
    Button({ type: ButtonType.Circle }) { AppIcon({ name: 'filter', iconSize: 21, tint: this.filterIndex === 1 ? this.color('glass-label') : this.color('primary') }) }.width(36).height(36).padding(0)
      .id('thread-filter').backgroundColor(Color.Transparent).accessibilityText('筛选任务')
      .onClick(() => { if (this.searchOpen) this.threadSearch.stopEditing(); this.filtersOpen = true; })
      .bindSheet($$this.filtersOpen, this.filterSheet(), { systemMaterial: immersiveMaterial('popup'), height: SheetSize.LARGE, title: { title: '筛选任务' }, dragBar: true, showClose: true })
  }

  private showingTaskList(): boolean {
    return !this.managingEnvironments && (this.connected !== null || this.cached || this.restoringConnectionId !== '');
  }

  private listProgressLabel(): string {
    return connectionProgressLabel(this.connectionState, this.filterIndex === 3 && this.loadingArchive);
  }

  @Builder
  private threadSearchBar() {
    Row({ space: 4 }) {
      Search({ value: this.query, placeholder: '搜索会话', controller: this.threadSearch })
        .id('thread-search-input').layoutWeight(1).height(44).margin(0).backgroundColor(Color.Transparent)
        .searchIcon({ size: 19, color: this.color('glass-label') })
        .cancelButton({ style: CancelButtonStyle.INPUT, icon: { size: 16, color: this.color('glass-label') } })
        .textFont({ size: this.font(16) }).placeholderFont({ size: this.font(16) })
        .fontColor(this.color('foreground')).placeholderColor(this.color('glass-label'))
        .onAppear(() => { this.getUIContext().getFocusController().requestFocus('thread-search-input'); })
        .onChange((value: string) => { this.query = value; this.refreshThreads(); })
      this.threadFilterButton()
      Button('取消', { type: ButtonType.Normal }).id('thread-search-cancel').height(44)
        .padding({ left: 10, right: 10 }).fontSize(this.font(15)).fontWeight(FontWeight.Medium)
        .backgroundColor(Color.Transparent).fontColor(this.color('foreground')).accessibilityText('取消搜索')
        .onClick(() => { this.closeThreadSearch(); })
    }.width('100%').padding({ left: 4, right: 6 })
  }

  @Builder
  private navigationActions() {
    Row({ space: 8 }) {
        if (this.showingTaskList()) {
          Button({ type: ButtonType.Circle }) { AppIcon({ name: 'check-all', iconSize: 21, tint: this.color('glass-label') }) }.width(36).height(36).padding(0)
            .backgroundColor(Color.Transparent).accessibilityText('全部标为已读').enabled(!this.markingAllRead)
            .onClick(() => { this.markAllRead(); })
          Button({ type: ButtonType.Circle }) { AppIcon({ name: 'search', iconSize: 21, tint: this.color('glass-label') }) }.width(36).height(36).padding(0)
            .id('thread-search-open').backgroundColor(Color.Transparent).accessibilityText('搜索会话').onClick(() => { this.searchOpen = true; })
          this.threadFilterButton()
        }
    }
  }

  build() {
    Navigation() {
    Stack({ alignContent: Alignment.Bottom }) {
    Column() {}.width('100%').height('100%')
      .backgroundColor(this.color(this.showingTaskList() ? 'card' : 'screen'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM]).hitTestBehavior(HitTestMode.None)
    Column({ space: 8 }) {
      if (this.groupingError) { Text(this.groupingError).fontColor(this.color('danger-foreground')) }
      if (this.fontError) { Text(this.fontError).fontColor(this.color('danger-foreground')) }
      if (this.windowError) { Text(this.windowError).fontColor(this.color('danger-foreground')) }
      if (this.themeError) { Text(this.themeError).fontColor(this.color('danger-foreground')) }
      if (this.readError) { Text(this.readError).fontColor(this.color('danger-foreground')) }
      if (this.showingTaskList()) {
        ChatPageHeader() {
          if (this.searchOpen) { this.threadSearchBar() }
          else {
            Row({ space: 8 }) {
              Button({ type: ButtonType.Normal }) {
                Row({ space: 6 }) {
                  if (this.listProgressLabel()) {
                    ConnectionProgressBadge({ label: this.listProgressLabel() }).id('list-connection-progress')
                  } else {
                    Text(this.connected?.descriptor.label || this.cachedLabel || '当前环境').fontSize(this.font(16)).fontWeight(FontWeight.Medium)
                      .fontColor(this.color('foreground')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: 190 }).flexShrink(1)
                    if (this.connectionState === 'failed' || this.connectionState === 'offline') {
                      Text(this.connectionState === 'failed' ? '连接失败' : '离线').fontSize(this.font(11)).fontColor(this.color('foreground-secondary'))
                    }
                    AppIcon({ name: 'down', iconSize: 11, tint: this.color('glass-label') })
                  }
                }.width('100%').justifyContent(FlexAlign.Start)
              }.layoutWeight(1).height(44).padding({ left: 8, right: 0 })
                .borderRadius({ topLeft: 22, bottomLeft: 22, topRight: 12, bottomRight: 12 }).clip(true).backgroundColor(Color.Transparent)
                .id('list-environment-switcher').onClick(() => { this.reloadSaved(); this.machinesOpen = true; })
                .accessibilityText(`切换环境，${this.listProgressLabel() || statusLabel(this.connectionState)}`)
                .bindSheet($$this.machinesOpen, this.machineSheet(), { systemMaterial: immersiveMaterial('popup'), height: SheetSize.LARGE, title: { title: '选择环境' }, dragBar: true, showClose: true })
              this.navigationActions()
            }.width('100%').padding({ left: 4, right: 8 })
          }
        }
      }

      if (!this.showingTaskList()) {
        EnvironmentPanel({ canReturnHome: this.connected !== null || this.cached })
      } else {
        if (this.projectId || (this.filterIndex !== 1 && this.filterIndex !== 3)) {
          Row({ space: 8 }) {
            if (this.projectId) {
              Button({ type: ButtonType.Normal }) {
                Row({ space: 6 }) {
                  AppIcon({ name: 'folder', iconSize: 14, tint: this.color('foreground-secondary') })
                  Text(this.projectGroups.find((group: ProjectGroup) => group.projectIds.includes(this.projectId))?.label ?? '项目')
                    .fontSize(this.font(12)).fontColor(this.color('foreground-secondary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }.height(32).layoutWeight(1).padding({ left: 10, right: 10 }).borderRadius(16).backgroundColor(this.color('card'))
                .onClick(() => { this.projectsOpen = true; }).accessibilityText('选择项目')
            }
            if (this.filterIndex !== 1 && this.filterIndex !== 3) {
              Button(this.filterOptions[this.filterIndex]?.value ?? '全部任务', { type: ButtonType.Normal }).height(32).fontSize(this.font(12))
                .fontColor(this.color('foreground-muted')).backgroundColor(this.color('card')).borderRadius(16).padding({ left: 12, right: 12 })
                .onClick(() => { this.filtersOpen = true; }).accessibilityText('选择任务状态')
            }
            Button({ type: ButtonType.Circle }) { AppIcon({ name: 'close', iconSize: 14, tint: this.color('foreground-muted') }) }
              .width(32).height(32).padding(0).backgroundColor(Color.Transparent).accessibilityText('清除筛选')
              .onClick(() => { this.projectId = ''; this.selectFilter(this.filterIndex === 3 ? 3 : 1); })
          }.width('100%').padding({ left: 16, right: 16 })
        }
        Column() {
          if (this.filterIndex === 3) {
            this.archiveToolbar()
            if (!connectionProgressLabel(this.connectionState) && (this.archiveError || !this.live)) {
                Text(this.live ? '归档列表刷新失败，点刷新重试' : '连接环境后可刷新归档').fontSize(this.font(13))
                  .fontColor(this.color('foreground-muted')).width('100%').padding({ left: 18, right: 18, top: 8, bottom: 8 })
            }
          }
          List({ space: 2, scroller: this.taskScroller }) {
          if (this.query.trim().length > 0 && this.threads.length > 0 && this.filterIndex !== 3) {
            ListItem() {
              Text(`搜索结果 · ${this.threads.length}`).fontSize(this.font(13)).fontWeight(FontWeight.Medium)
                .fontColor(this.color('foreground-secondary')).width('100%').padding({ left: 20, right: 20, top: 16, bottom: 8 })
            }
          } else if (this.threads.length === 0 && !connectionProgressLabel(this.connectionState) && !this.loadingArchive && (this.filterIndex !== 3 || (this.live && !this.archiveError))) {
            ListItem() {
              Column({ space: 8 }) {
                if (this.query.trim().length > 0) {
                  AppIcon({ name: 'search', iconSize: 28, tint: this.color('foreground-muted') })
                  Text('没有找到会话').fontSize(this.font(16)).fontWeight(FontWeight.Medium).fontColor(this.color('foreground'))
                  Text('试试其他关键词').fontSize(this.font(13)).fontColor(this.color('foreground-muted'))
                } else if (this.filterIndex === 3) {
                  AppIcon({ name: 'archive', iconSize: 28, tint: this.color('foreground-muted') })
                  Text('暂无已归档会话').fontSize(this.font(15)).fontColor(this.color('foreground-secondary'))
                } else { Text('此视图暂无任务').fontColor(this.color('foreground-muted')) }
              }.width('100%').padding({ top: 40, bottom: 24 })
            }
          }
          ForEach(this.threads, (thread: ThreadRow, index: number) => {
            if (!this.query.trim() && (this.filterIndex === 1 || this.filterIndex === 0) && (index === 0 || this.threads[index - 1].section !== thread.section)) {
              ListItem() {
                Button({ type: ButtonType.Normal }) {
                  Row({ space: 8 }) {
                    if (thread.pinned) { AppIcon({ name: 'pin', iconSize: 13, tint: this.color('foreground-secondary') }) }
                    Text(thread.pinned ? '已置顶' : thread.section === 0 ? '进行中' : thread.section === 2 ? '已完成' : '最近任务')
                      .fontSize(this.font(12)).fontWeight(FontWeight.Medium).fontColor(this.color('foreground-secondary'))
                    Text(`${this.threads.filter((row: ThreadRow) => row.section === thread.section).length}`)
                      .fontSize(this.font(11)).fontColor(this.color('foreground-muted')).padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .borderRadius(8).backgroundColor(this.color('subtle'))
                    Blank()
                    AppIcon({ name: 'down', iconSize: 13, tint: this.color('foreground-muted') })
                      .rotate({ angle: this.collapsedTaskSections.includes(thread.section) ? -90 : 0 })
                  }.width('100%')
                }.width('100%').height(40).padding({ left: 20, right: 20 }).margin({ top: 8 })
                  .backgroundColor(Color.Transparent).borderRadius(12)
                  .accessibilityText(`${thread.pinned ? '已置顶' : thread.section === 0 ? '进行中' : thread.section === 2 ? '已完成' : '最近任务'}，点击${this.collapsedTaskSections.includes(thread.section) ? '展开' : '收起'}`)
                  .onClick(() => {
                    this.collapsedTaskSections = this.collapsedTaskSections.includes(thread.section)
                      ? this.collapsedTaskSections.filter((section: number) => section !== thread.section)
                      : this.collapsedTaskSections.concat(thread.section);
                  })
              }
            }
            if (this.query.trim().length > 0 || (this.filterIndex !== 1 && this.filterIndex !== 0) || !this.collapsedTaskSections.includes(thread.section)) {
            ListItem() {
              Row({ space: 12 }) {
                ProjectIcon({ cwd: thread.cwd, faviconPath: thread.faviconPath, iconSize: 26, label: thread.projectTitle, chatFallback: true })
                Column({ space: 6 }) {
                  Text(thread.title).fontColor(this.color(thread.settled && !thread.unread ? 'foreground-secondary' : 'foreground')).fontSize(this.font(16)).fontWeight(thread.unread ? FontWeight.Bold : FontWeight.Medium).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                  Row({ space: 5 }) {
                    Text(thread.projectTitle === 'No project' ? this.connected?.descriptor.label ?? this.cachedLabel : thread.projectTitle).fontSize(this.font(11)).fontColor(this.color('foreground-muted')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: 110 })
                    if (thread.branch) {
                      AppIcon({ name: 'branch', iconSize: 12, tint: this.color('foreground-muted') })
                      Text(thread.branch).fontSize(this.font(12)).fontColor(this.color('foreground-muted')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                    }
                    if (this.filterIndex === 3) {
                      if (!thread.branch) { Blank() }
                      if (thread.pinned) { AppIcon({ name: 'pin', iconSize: 12, tint: this.color('foreground-muted') }).accessibilityText('已置顶') }
                      if (thread.fast) { AppIcon({ name: 'bolt', iconSize: 12, tint: this.color('foreground-muted') }).accessibilityText('Fast 已开启') }
                      ProviderIcon({ driver: thread.provider, label: thread.provider, iconSize: 12 })
                      Text(thread.updated).fontSize(this.font(11)).fontColor(this.color('foreground-muted')).maxLines(1)
                    }
                  }.width('100%')
                  if (thread.workTurn !== null) { TaskWorkTime({ turn: thread.workTurn }) }
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                if (this.filterIndex !== 3) {
                Column({ space: 7 }) {
                  Text(thread.updated).fontSize(this.font(11)).fontColor(this.color('foreground-muted'))
                  StatusIndicator({ label: statusLabel(thread.state), tint: statusColor(thread.state, this.color('screen')) })
                  Row({ space: 5 }) {
                    if (thread.pinned) { AppIcon({ name: 'pin', iconSize: 12, tint: this.color('foreground-secondary') }).accessibilityText('已置顶') }
                    if (thread.fast) { AppIcon({ name: 'bolt', iconSize: 12, tint: this.color('foreground-secondary') }).accessibilityText('Fast 已开启') }
                    ProviderIcon({ driver: thread.provider, label: thread.provider, iconSize: 13 })
                  }
                }.alignItems(HorizontalAlign.End)
                }
              }.width('100%').padding({ left: 16, right: 16, top: this.filterIndex === 3 ? 12 : 16, bottom: this.filterIndex === 3 ? 12 : 16 }).borderRadius(12)
                .backgroundColor((this.menuTaskId || this.pressedTaskId) === thread.id ? this.color('subtle-strong') :
                  !this.menuTaskId && !this.pressedTaskId && this.hoveredTaskId === thread.id ? this.color('subtle') : Color.Transparent)
                .scale({ x: this.pressedTaskId === thread.id ? 0.985 : 1, y: this.pressedTaskId === thread.id ? 0.985 : 1 })
                .animation({ duration: 120, curve: Curve.EaseOut })
                .onTouch((event: TouchEvent) => {
                  if (event.type === TouchType.Down) { this.pressedTaskId = thread.id; this.hoveredTaskId = ''; }
                  if ((event.type === TouchType.Up || event.type === TouchType.Cancel) && this.pressedTaskId === thread.id) this.pressedTaskId = '';
                })
                .onHover((hovered: boolean) => { if (hovered) this.hoveredTaskId = thread.id; else if (this.hoveredTaskId === thread.id) this.hoveredTaskId = ''; })
                .onClick(() => { this.openThread(thread); })
                .bindContextMenu(this.taskMenu(thread), ResponseType.LongPress, {
                  modalMode: menuModalMode(), hapticFeedbackMode: menuHapticFeedbackMode(),
                  onAppear: () => { this.menuTaskId = thread.id; this.pressedTaskId = ''; },
                  onDisappear: () => { this.menuTaskId = ''; this.pressedTaskId = ''; }
                })
                .accessibilityText(`${thread.title}${thread.pinned ? '，已置顶' : ''}，${thread.unread ? '未读' : '已读'}，${statusLabel(thread.state)}${thread.fast ? '，Fast 已开启' : ''}，长按显示任务操作`)
            }
            }
          }, (thread: ThreadRow) => JSON.stringify(thread))
        }
        .layoutWeight(1)
        .scrollBarWidth(2)
        .divider(this.filterIndex === 3 ? { strokeWidth: 0.5, color: this.color('border'), startMargin: 54, endMargin: 16 } : undefined)
        .width('100%').contentEndOffset(this.searchOpen ? 16 : 96)
        }.layoutWeight(1).width('100%').borderRadius({ topLeft: 28, topRight: 28 }).backgroundColor(this.color('card')).clip(true)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        .bindSheet($$this.renameOpen, this.renameSheet(), { systemMaterial: immersiveMaterial('popup'), height: SheetSize.FIT_CONTENT, title: { title: '重命名会话' },
          keyboardAvoidMode: SheetKeyboardAvoidMode.TRANSLATE_AND_RESIZE, dragBar: true, showClose: true,
        })

      }

    }
    .padding({ left: !this.showingTaskList() ? 16 : 0, right: !this.showingTaskList() ? 16 : 0, top: 0, bottom: 0 })
    .width('100%')
    .height('100%')
    .backgroundColor(this.color('screen'))
    .bindSheet($$this.orderOpen, this.orderSheet(), { systemMaterial: immersiveMaterial('popup'), height: '85%', title: { title: this.orderPinned ? '置顶会话排序' : '进行中会话排序' },
      dragBar: true, showClose: !this.actionBusy,
      onWillDismiss: (action: DismissSheetAction) => { if (!this.actionBusy) action.dismiss(); } })
    if (this.showingTaskList() && !this.searchOpen) { this.floatingNavigation() }
    }.width('100%').height('100%')
    }
    .hideTitleBar(true).hideBackButton(true).mode(NavigationMode.Stack)
    .width('100%').height('100%').backgroundColor(this.color('screen'))
    .bindSheet($$this.composerOpen, this.newTaskSheet(), {
      systemMaterial: immersiveMaterial('sheet', '#BF' + this.color('card').slice(1)), backgroundColor: this.color('card'),
      height: '85%', keyboardAvoidMode: SheetKeyboardAvoidMode.TRANSLATE_AND_RESIZE, dragBar: true, showClose: false,
      onWillDismiss: () => { this.composerCloseRequest++; }
    })
  }
}
