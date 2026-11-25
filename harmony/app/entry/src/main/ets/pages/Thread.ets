import { menuIcon, menuModalMode, menuHapticFeedbackMode } from './MenuIcon';
import { ChatPageHeader, ChatGlass, immersiveMaterial } from './ChatGlass';
import { ComposerEditor, ComposerEditorController } from './ComposerEditor';
import { MessageQuoteCard } from './MessageQuoteCard';
import { MessageQuote, canQuoteMessage, createMessageQuote, quotedMessageText, parseQuotedMessage, quoteMessageCopyText, messageQuoteImages } from '../model/MessageQuote';
import { BrowserSessions, BrowserList, BrowserEvent, BrowserTab } from '../model/BrowserSessions';
import { ThreadReads } from '../connection/ThreadReads';
import { threadReadRevision } from '../model/ThreadReadState';
import { ComposerSkill, messageSkillSpans } from '../model/ComposerDocument';
import { AppIcon } from './AppIcon';
import { FloatingNotice } from './FloatingNotice';
import { WorkStatus } from './WorkStatus';
import { ConnectionProgressBadge, StatusIndicator } from './StatusIndicator';
import { CommandSuggestions } from './CommandSuggestions';
import { AttachmentGallery } from './AttachmentGallery';
import { ChatImage } from './ChatImage';
import { HtmlRenderReference, ProviderInfo, SubagentSummary, ViewedImage, turnSubagents, subagentPillLabel, subagentTitle, subagentDisplayTitle } from '../model/Models';
import { modelSwitchLabel } from '../model/ModelOptions';
import { InlineHtmlPreview } from './InlineHtmlPreview';
import { SubagentGroup } from './SubagentGroup';
import { MarkdownImageFile, markdownImageFileLink } from '../model/MarkdownLink';
import { viewedImageGallery } from '../model/ImageGallery';
import { parseImageComment, appendImageComment } from '../model/ImageEdits';
import { AttachmentText } from './AttachmentText';
import { QueuedMessages } from './QueuedMessages';
import { queuedDraftBase, queuedDraftText, restoreQueuedDraft } from '../model/QueuedDraft';
import { QueuedMessageCommand } from '../model/Models';
import { MessageForwarder } from './MessageForwarder';
import { ForwardContent, canForwardMessage, forwardContent, forwardCommand } from '../model/MessageForwarding';
import { ProjectShell, ThreadShell, ChangedFile } from '../model/Models';
import { DraftImages, DraftImageProgress } from './DraftImages';
import { ImageAssets } from '../connection/ImageAssets';
import { ImageEditRequests } from '../connection/ImageEditRequests';
import { TranscriptFollow } from '../model/TranscriptFollow';
import { TranscriptDataSource } from './TranscriptDataSource';
import { assistantActionIds, forkFromMessage, messageTimeValue, MessageForkCommand, HistoryEditIndex, HistoryEditTarget, historyEditTarget, historyEditCompleted, recalledHistoryText } from '../model/MessageActions';
import { reasoningTitle, reasoningBody } from '../model/Reasoning';
import { ClientCache } from '../connection/ClientCache';
import { ProviderCommandCatalog, SlashCommand, commandCatalog, commandsFor, commandQuery, insertCommand } from '../model/ComposerCommands';
import { connectionProgressLabel, statusColor } from '../model/StatusVisuals';
import { WorkspaceContext, WorkspaceRef } from './WorkspaceContext';
import { BranchChange, BranchChangeNotice, BranchNoticeInput, checkoutBranchMismatch } from '../model/BranchChange';
import { openThreadReference } from './ThreadReferenceNavigation';
import { SavedEnvironment, loadEnvironments } from '../connection/EnvironmentStore';
import { ComposerSettings } from './ComposerSettings';
import { ComposerActions } from './ComposerActions';
import { insertComposerTrigger } from '../model/ComposerCommands';
import { KeyboardAvoidMode, FrameCallback } from '@ohos.arkui.UIContext';
import { ComposerPathTrigger, ComposerPathEntry, composerPathTrigger, composerPathEntries, insertComposerEntry } from '../model/ComposerPath';
import { FileEntry } from '../model/FileEntries';
import { Typography, resolveTypography, scaledFontSize } from '../model/Typography';
import { ThemeRuntime } from '../connection/ThemeRuntime';
/**
 * 线程详情：消息流（feed 流式分块）+ composer。
 *
 * composer 的编辑面是平台原生文本组件，文档模型与受控协议跑在上游
 * Swift 代码里（T3ComposerEditor 模块经 SwiftBridge 驱动）。
 */
import router from '@ohos.router';
import pasteboard from '@ohos.pasteboard';
import promptAction from '@ohos.promptAction';
import photoAccessHelper from '@ohos.file.photoAccessHelper';
import fileUri from '@ohos.file.fileuri';
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import { fileUploadLimit } from '../model/FileAttachments';
import { uploadImage, imageUploadExists, deleteImageUpload, UploadedImage } from '../connection/ImageAttachment';
import util from '@ohos.util';
import { EnvironmentSession } from '../connection/Environment';
import { SwiftBridge } from '../bridge/NativeBridge';
import { EmptyPayload, RpcClient, RpcRemoteError } from '../connection/Rpc';
import { ModelChoice, ModelSelection, ServerConfig, ThreadDetail, ThreadSnapshotResponse, ThreadHistoryPage, CurrentTurnItem, StartTurnCommand, availableModels, WS, ChatAttachment, TimelineRow, ThreadState, ThreadItem, ShellItem, PendingRequest, pendingRequests, startTurnCommand, InterruptTurnCommand, interruptTurnCommand, transcriptRows, reconcileTranscriptRows, workDuration, QueuedMessage, queuedMessages, queuedMessageCommand } from '../model/Models';
import { RequestDrafts } from '../model/RequestDrafts';
import { RequestCard } from './RequestCard';
import { MarkdownText } from './MarkdownText';
import { ReconnectingRpc } from '../connection/ReconnectingRpc';
import { CommentSegment, parseCommentMessage } from '../model/ReviewComment';
import { AttachmentDraftStore, DraftImage } from '../connection/AttachmentDraftStore';
import { SendJournal } from '../connection/SendJournal';
import { DraftStore } from '../connection/DraftStore';
import { ComposerOutbox, ComposerSettingCommand, ModelDraft } from '../connection/ComposerOutbox';
import { FileDownload } from '../connection/FileDownload';
import { ChatMessage } from '../model/Models';

interface InlineHtmlAsset { relativeUrl: string; }
interface InlineHtmlResource { _tag: string; attachmentId: string; fileName: string; mimeType: string; disposition: string; }
interface InlineHtmlAssetRequest { resource: InlineHtmlResource; }
interface RollbackCommand { type: string; commandId: string; threadId: string; scopeId: string; checkpointId: string; restoreFiles: boolean; }

interface ComposerDraftSnapshot { text: string; quote: MessageQuote | null; store: DraftStore; images: AttachmentDraftStore; progress: DraftImageProgress[]; status: string; }
interface BrowserThreadRequest { threadId: string; }

interface ResponseCommand {
  type: string;
  commandId: string;
  threadId: string;
  requestId: string;
  createdAt: string;
  decision?: string;
  answers?: Record<string, string | string[]>;
  attachmentsByQuestionId?: Record<string, ChatAttachment[]>;
}

interface ThreadSubscription {
  threadId: string;
  afterSequence?: number;
  requestCompletionMarker?: boolean;
  reasoningMessages?: boolean;
  acceptBoundedSnapshot?: boolean;
  acceptCompactTurnItems?: boolean;
}
interface ShellSubscription { afterSequence?: number; requestCompletionMarker?: boolean; }

interface RouteParams {
  environmentId: string;
  threadId: string;
  socketUrl: string;
  httpBaseUrl: string;
}

interface SwitchRefRequest { cwd: string; refName: string; }
interface CheckoutBranchStatus { refName: string | null; isRepo?: boolean; }
interface PathSearchRequest { cwd: string; query: string; limit: number; }
interface RootEntriesRequest { cwd: string; }
interface PathSearchResult { entries?: FileEntry[]; truncated: boolean; }
interface TurnItemRequest { threadId: string; itemId: string; }
interface TurnItemResult { item: CurrentTurnItem | null; }
interface WorkspaceCatalogRequest { instanceId: string; cwd: string; }
interface ForkSource { type: string; }
interface SideChatCommand { type: string; commandId: string; sourceThreadId: string; targetThreadId: string;
  sourcePoint: ForkSource; sideChat: boolean; title: string; createdBy: string; creationSource: string; }
class TranscriptFrame extends FrameCallback {
  private ready: () => void;
  constructor(ready: () => void) { super(); this.ready = ready; }
  onFrame(_time: number): void { this.ready(); }
  onIdle(_time: number): void {}
}

@Entry
@Component
struct ThreadPage {
  private font(size: number): number { return scaledFontSize(size, this.sizes.baseFontSize); }
  private messageFiles(row: TimelineRow): ChatAttachment[] {
    return (row.attachments ?? []).filter((attachment: ChatAttachment) => attachment.type !== 'image');
  }
  private messageSkills(): ComposerSkill[] {
    return commandsFor(this.commandCatalog, this.composerThread?.modelSelection?.instanceId ?? '', this.state.thread?.worktreePath ?? this.cwd)
      .filter((command: SlashCommand) => command.kind === 'skill' && !!command.insertion)
      .map((command: SlashCommand): ComposerSkill => ({ insertion: command.insertion!, label: command.displayName ?? command.name.replace(/^skill:/, ''), icon: command.icon ?? 'skill' }));
  }
  private hasMessageSkill(text: string): boolean { return messageSkillSpans(text, this.messageSkills()).some((span) => span.kind === 'skill'); }
  @StorageLink('textSizes') sizes: Typography = resolveTypography(16, null, null);
  @StorageLink('themeKey') themeKey: string = 't3-code-light';
  private color(role: string): string { return ThemeRuntime.color(this.themeKey, role); }
  @State models: ModelChoice[] = [];
  @State timelineProviders: ProviderInfo[] = [];
  @State @Watch('updateBranchNotice') composerThread: ThreadDetail | null = null;
  @State settingsBusy: boolean = false;
  @State settingsPending: boolean = false;
  private outbox: ComposerOutbox | null = null;
  private unwatchSettings: (() => void) | null = null;
  @State modelDraftReady: boolean = false;
  @State pendingModelSelection: ModelSelection | null = null;
  private modelDraft: ModelDraft | null = null;
  @State settingsError: string = '';
  @State @Watch('updateBranchNotice') checkoutBranch: string = '';
  @State branchChange: BranchChange | null = null;
  @State restoringBranch: boolean = false;
  private branchNotice: BranchChangeNotice = new BranchChangeNotice();
  @State entries: TimelineRow[] = [];
  private transcriptSource: TranscriptDataSource = new TranscriptDataSource();
  @State assistantActions: string[] = [];
  @State copiedMessageId: string = '';
  @State historyEditIds: string[] = [];
  private historyEditIndex: HistoryEditIndex | null = null;
  private hiddenTranscriptChanged: boolean = false;
  @State rewindStatus: string = '';
  @State parentThreadId: string = '';
  @State parentTitle: string = '';
  @State nativeSubagent: boolean = false;
  private openedFromThreadId: string = '';
  private rollbackProviders: string[] = [];
  private observeRewind: (() => void) | null = null;
  private stopRewindObservation: (() => void) | null = null;
  @State pressedMessageKey: string = '';
  @State menuMessageKey: string = '';
  @State forkingMessageId: string = '';
  @State projectTitle: string = '';
  @State workspaceProject: ProjectShell | null = null;
  @State branchPickerRequest: number = 0;
  @State operationError: string = '';
  private copyTimer: number = -1;
  private forks: Map<string, MessageForkCommand> = new Map();
  @State selectingMessages: boolean = false;
  @State selectedMessageIds: string[] = [];
  @State forwardOpen: boolean = false;
  @State forwardBusy: boolean = false;
  @State forwardContent: ForwardContent = { text: '', attachments: [], count: 0 };
  @State forwardThreads: ThreadShell[] = [];
  @State forwardProjects: ProjectShell[] = [];
  @State expandedRows: string[] = [];
  @State detailLoading: string[] = [];
  @State detailError: string = '';
  @State elapsed: string = '';
  @State turnAgents: SubagentSummary[] = [];
  @State agentsOpen: boolean = false;
  @State browserTabs: BrowserTab[] = [];
  @State browserSupported: boolean = false;
  @State interrupted: boolean = false;
  @StorageLink('rpcEnvironmentId') @Watch('transportAvailable') rpcEnvironmentId: string = '';
  @StorageLink('appForeground') @Watch('foregroundChanged') foreground: boolean = true;
  private readVisible: boolean = false;
  @State queue: QueuedMessage[] = [];
  @State queueOpen: boolean = false;
  @State queueBusy: boolean = false;
  @State queueError: string = '';
  @State @Watch('updateBranchNotice') editingQueue: QueuedMessage | null = null;
  @State queueAttachments: ChatAttachment[] = [];
  private mainDraft: ComposerDraftSnapshot | null = null;
  private pendingQueueEdit: QueuedMessageCommand | null = null;
  private elapsedTimer: number = -1;
  @State requests: PendingRequest[] = [];
  @State responding: boolean = false;
  @State responseError: string = '';
  private scroller: Scroller = new Scroller();
  private follow: TranscriptFollow = new TranscriptFollow();
  private followQueued: boolean = false;
  private followGeneration: number = 0;
  private transcriptTimer: number = -1;
  private userScrolling: boolean = false;
  @State showingHistory: boolean = false;
  @State sending: boolean = false;
  @State sendError: string = '';
  @State stopping: InterruptTurnCommand | null = null;
  private threadStopSupported: boolean = false;
  @State running: boolean = false;
  @State loaded: boolean = false;
  @State cached: boolean = false;
  @State hasMoreHistory: boolean = false;
  @State historyLoading: boolean = false;
  @State refreshingHistory: boolean = false;
  @State historyError: string = '';
  private pendingHistory: ThreadHistoryPage | null = null;
  private pendingHistoryCursor: string = '';
  private pendingHistoryEpoch: number = 0;
  private firstVisibleIndex: number = 0;
  private historyAnchor: string = '';
  @State cachedTitle: string = '';
  @State connectionState: string = 'connecting';
  @State commandCatalog: ProviderCommandCatalog[] = [];
  @State modelPickerRequest: number = 0;
  private workspaceCatalogKey: string = '';
  private workspaceCatalogAt: number = 0;
  private catalogLoaded: boolean = false;
  @State fileLimitsPending: boolean = false;
  private cache: ClientCache | null = null;
  private cacheEpoch: number = 0;
  private cachedThreadLoad: Promise<void> | null = null;
  private threadNeedsSnapshot: boolean = false;
  private shellNeedsSnapshot: boolean = false;
  private state: ThreadState = new ThreadState();
  private cwd: string = '';
  private active: boolean = false;
  @State @Watch('updateBranchNotice') draft: string = '';
  @State @Watch('updateBranchNotice') draftQuote: MessageQuote | null = null;
  @State composerHeight: number = 0;
  private quoteFocusPending: boolean = false;
  @State quoteTargetId: string = '';
  @State highlightedMessageId: string = '';
  private quoteTargetThreadId: string = '';
  private quoteNavigationVersion: number = 0;
  private quoteHighlightTimer: number = -1;
  @State draftReady: boolean = false;
  @State draftStatus: string = '';
  private draftStore: DraftStore | null = null;
  private draftTimer: number = -1;
  private previousKeyboardAvoidMode: KeyboardAvoidMode | null = null;
  private composerController: ComposerEditorController = new ComposerEditorController();
  @State pathEntries: ComposerPathEntry[] = [];
  @State pathActive: boolean = false;
  @State pathLoading: boolean = false;
  @State pathStatus: string = '';
  @State pathStart: number = 0;
  @State pathEnd: number = 0;
  private pathTrigger: ComposerPathTrigger | null = null;
  private pathRevision: number = 0;
  private pathTimer: number = -1;
  private pathCwd: string = '';
  private pathRpc: RpcClient | null = null;
  @State composerInstance: string | null = null;
  @State @Watch('updateBranchNotice') imageUris: string[] = [];
  @State imageProgress: DraftImageProgress[] = [];
  private imageUpload: Promise<void> | null = null;
  private removingImages: Set<string> = new Set();
  private imageStore: AttachmentDraftStore | null = null;
  private receivedImageComments: Set<string> = new Set();
  private receivingImageComment: boolean = false;
  private attemptedImageRequest: string = '';
  @State imageRequestBusy: boolean = false;
  @State imagesReady: boolean = false;
  @State maxFileBytes: number = 0;
  @State canAttachQuestions: boolean = false;
  @State viewportHeight: number = 640;
  private journal: SendJournal | null = null;
  @State journalReady: boolean = false;
  @State hasPendingSend: boolean = false;
  @State pickingImage: boolean = false;
  @State threadStatus: string = '';
  private params: RouteParams = { environmentId: '', threadId: '', socketUrl: '', httpBaseUrl: '' };
  private rpc: RpcClient | null = null;
  private connection: ReconnectingRpc | null = null;

  aboutToAppear(): void {
    const pending = router.getParams() as Record<string, string>;
    this.params = {
      environmentId: pending['environmentId'] ?? '',
      threadId: pending['threadId'] ?? '',
      socketUrl: pending['socketUrl'] ?? '',
      httpBaseUrl: pending['httpBaseUrl'] ?? ''
    };
    this.active = true;
    this.cwd = pending['cwd'] ?? '';
    this.cachedTitle = pending['title'] ?? '';
    this.projectTitle = pending['projectTitle'] ?? '';
    this.parentThreadId = pending['parentThreadId'] ?? '';
    this.parentTitle = pending['parentTitle'] ?? '';
    this.openedFromThreadId = pending['openedFromThreadId'] ?? '';
    this.nativeSubagent = pending['nativeSubagent'] === 'true';
    this.quoteTargetId = pending['quoteMessageId'] ?? '';
    this.quoteTargetThreadId = this.params.threadId;
    this.cachedThreadLoad = this.loadCachedThread();
    this.connection = new ReconnectingRpc(async (): Promise<RpcClient> => {
      const environment = EnvironmentSession.current;
      const scope = environment?.descriptor.environmentId === this.params.environmentId ? environment.rpc.openScope() : null;
      if (!scope) throw new Error('等待环境连接');
      return scope;
    }, (rpc: RpcClient) => {
      this.rpc = rpc;
      this.connectionState = 'syncing';
      return this.subscribeFeed(rpc);
    }, (status: string) => {
      this.loaded = false;
      this.pendingHistory = null; this.historyLoading = false;
      this.cached = this.state.thread !== null;
      this.connectionState = status;
      this.rpc = null;
      this.checkoutBranch = '';
    }, () => {
      this.threadNeedsSnapshot = true;
      this.shellNeedsSnapshot = true;
    });

    // composer：Swift 侧实例（受控文档协议在原生层驱动）。
    try {
      const bridge = SwiftBridge.ensure();
      const instance: string | null = bridge.createView('T3ComposerEditor');
      this.composerInstance = instance;
    } catch (_) {
      this.composerInstance = null; // 无 .so 时退化纯 ArkTS 输入。
    }
  }

  onPageShow(): void {
    this.readVisible = true;
    if (this.hiddenTranscriptChanged) { this.hiddenTranscriptChanged = false; this.refreshTranscript(); }
    if (this.previousKeyboardAvoidMode === null) this.previousKeyboardAvoidMode = this.getUIContext().getKeyboardAvoidMode();
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    if (this.editingQueue !== null) {
      this.draftReady = true;
      this.receiveImageComment();
    } else {
      this.draftReady = false;
      Promise.all([this.loadDraft(), this.loadImages(), this.loadJournal(), this.loadModelDraft()]).then(() => { this.receiveImageComment(); });
    }
    this.connection?.resume();
    this.updateElapsed();
    if (this.quoteTargetId) this.navigateToQuote();
  }

  private transportAvailable(): void {
    if (this.active && this.rpcEnvironmentId === this.params.environmentId && this.connectionState === 'reconnecting') this.connection?.resume();
  }

  private restoreKeyboardAvoidMode(): void {
    if (this.previousKeyboardAvoidMode === null) return;
    this.getUIContext().setKeyboardAvoidMode(this.previousKeyboardAvoidMode);
    this.previousKeyboardAvoidMode = null;
  }

  onPageHide(): void {
    this.follow.touchEnd(); this.userScrolling = false;
    this.pressedMessageKey = ''; this.menuMessageKey = '';
    this.quoteFocusPending = false;
    this.cancelQuoteNavigation();
    this.readVisible = false;
    this.flushTranscriptRefresh();
    this.cancelFollowScroll();
    this.stopElapsedTimer();
    this.restoreKeyboardAvoidMode();
    this.cancelPaths();
    this.saveDraft();
    this.cache?.flush();
  }

  aboutToDisappear(): void {
    this.pressedMessageKey = ''; this.menuMessageKey = '';
    this.quoteFocusPending = false;
    this.cancelQuoteNavigation();
    if (this.quoteHighlightTimer !== -1) clearTimeout(this.quoteHighlightTimer);
    this.readVisible = false;
    if (this.copyTimer !== -1) clearTimeout(this.copyTimer);
    this.flushTranscriptRefresh();
    this.cancelFollowScroll();
    this.stopElapsedTimer();
    this.restoreKeyboardAvoidMode();
    this.cancelPaths();
    this.saveDraft();
    this.cache?.flush();
    this.active = false;
    this.unwatchSettings?.(); this.unwatchSettings = null;
    this.stopRewindObservation?.();
    this.connection?.stop();
    if (this.rpc !== null) {
      this.rpc.close();
    }
    if (this.composerInstance !== null) {
      SwiftBridge.ensure().destroyView(this.composerInstance);
    }
  }

  private async loadCachedThread(): Promise<void> {
    try {
      const cache = await ClientCache.open(getContext(this).filesDir, this.params.environmentId);
      if (!this.active) return;
      this.cache = cache; this.cacheEpoch = cache.threadEpoch(this.params.threadId);
      if (!this.catalogLoaded) { this.models = cache.models(); this.commandCatalog = cache.commands(); }
      const thread = await cache.thread(this.params.threadId);
      if (!this.active) return;
      const project = cache.shell()?.projects.find((project) => project.id === (thread?.projectId ?? this.state.thread?.projectId));
      this.projectTitle = project?.title ?? this.projectTitle;
      if (project !== undefined) this.workspaceProject = project;
      if (!this.cwd && project) this.cwd = project.workspaceRoot;
      if (this.state.thread === null && thread !== null) {
        this.state.restoreCached(thread);
        this.cached = true;
        this.refreshTranscript();
        this.syncComposerMetadata();
      } else if (this.loaded && this.state.thread !== null) {
        cache.setThread(this.state.thread, this.state.messages, this.state.activities, this.state.checkpointCount, this.state.cursor(), true, this.cacheEpoch);
      }
    } catch (_) {}
  }

  private selectCommand(command: SlashCommand): void {
    if (!this.draftReady || this.hasPendingSend || this.sending) return;
    const insertion = insertCommand(this.draft, this.pathStart, this.pathEnd, command);
    this.editDraft(insertion.text);
    if (command.kind === 'model' && !this.editingQueue) { this.modelPickerRequest++; return; }
    setTimeout(() => { if (this.active) this.composerController.caretPosition(insertion.cursor); }, 0);
  }
  private insertShortcut(trigger: string): void {
    if (!this.draftReady || this.hasPendingSend || this.sending) return;
    const insertion = insertComposerTrigger(this.draft, this.pathStart, this.pathEnd, trigger);
    this.editDraft(insertion.text);
    this.updatePathSearch(insertion.cursor, insertion.cursor);
    setTimeout(() => { if (this.active) this.composerController.caretPosition(insertion.cursor); }, 0);
  }

  private cancelPaths(): void {
    ++this.pathRevision;
    if (this.pathTimer !== -1) clearTimeout(this.pathTimer);
    this.pathTimer = -1;
    this.pathEntries = [];
    this.pathActive = false;
    this.pathLoading = false;
    this.pathStatus = '';
    this.pathTrigger = null;
    this.pathCwd = '';
    this.pathRpc = null;
  }

  private updatePathSearch(start: number, end: number): void {
    if (commandQuery(this.draft, start, end) !== null) this.refreshWorkspaceCommands();
    const trigger = composerPathTrigger(this.draft, start, end);
    const cwd = this.state.thread?.worktreePath ?? this.cwd;
    if (trigger !== null && this.pathTrigger !== null && trigger.start === this.pathTrigger.start &&
      trigger.end === this.pathTrigger.end && trigger.query === this.pathTrigger.query && this.pathCwd === cwd && this.pathRpc === this.rpc) return;
    this.cancelPaths();
    this.pathStart = start;
    this.pathEnd = end;
    if (!this.active || !this.draftReady || this.hasPendingSend || this.sending || trigger === null) return;
    this.pathActive = true;
    if (trigger.query.length > 256) { this.pathStatus = '文件查询不能超过 256 个字符'; return; }
    this.pathTrigger = trigger;
    this.pathCwd = cwd;
    this.pathRpc = this.rpc;
    this.pathEntries = composerPathEntries([], this.cache?.shell()?.threads ?? [], trigger.query, this.params.threadId);
    if (!this.loaded || this.rpc === null || !cwd) { this.pathStatus = '连接后可搜索项目文件'; return; }
    this.pathLoading = true;
    this.pathStatus = '正在搜索项目文件…';
    const revision = this.pathRevision;
    this.pathTimer = setTimeout(() => { this.pathTimer = -1; this.searchPaths(trigger, revision); }, 200);
  }

  private async searchPaths(trigger: ComposerPathTrigger, revision: number): Promise<void> {
    const rpc = this.rpc;
    if (rpc === null) { if (revision === this.pathRevision) { this.pathLoading = false; this.pathStatus = '连接已断开，请重新输入查询'; } return; }
    try {
      const cwd = this.state.thread?.worktreePath ?? this.cwd;
      const request: PathSearchRequest = { cwd: cwd, query: trigger.query.trim(), limit: 20 };
      const root: RootEntriesRequest = { cwd: cwd };
      const result = request.query ? await rpc.call<PathSearchResult>('projects.searchEntries', request) :
        await rpc.call<PathSearchResult>('projects.listEntries', root);
      if (!this.active || revision !== this.pathRevision) return;
      this.pathLoading = false;
      if (rpc !== this.rpc) { this.pathStatus = '连接已变化，请重新输入查询'; return; }
      this.pathEntries = composerPathEntries(result.entries, this.cache?.shell()?.threads ?? [], trigger.query, this.params.threadId);
      this.pathStatus = this.pathEntries.length === 0 ? '没有匹配的文件或会话' : result.truncated ? '仅显示前 20 项，请继续输入缩小范围' : '';
    } catch (_) {
      if (this.active && revision === this.pathRevision) { this.pathLoading = false; this.pathStatus = '文件搜索失败，请重新输入查询'; }
    }
  }

  private selectPath(entry: ComposerPathEntry): void {
    if (!this.pathEntries.some((candidate: FileEntry) => candidate.path === entry.path && candidate.kind === entry.kind)) return;
    const trigger = this.pathTrigger;
    const current = composerPathTrigger(this.draft, this.pathStart, this.pathEnd);
    if (!this.draftReady || this.hasPendingSend || this.sending || trigger === null || current === null ||
      trigger.start !== current.start || trigger.end !== current.end || trigger.query !== current.query) return;
    const insertion = insertComposerEntry(this.draft, trigger, entry);
    this.cancelPaths();
    this.editDraft(insertion.text);
    setTimeout(() => {
      if (this.active && this.draft === insertion.text) this.composerController.caretPosition(insertion.cursor);
    }, 0);
  }

  private async loadDraft(): Promise<void> {
    try {
      const store = await DraftStore.open(getContext(this).filesDir, this.params.environmentId, this.params.threadId);
      const text = await store.load();
      if (!this.active) return;
      this.draftStore = store;
      const restored = parseQuotedMessage(text);
      this.draft = restored.text;
      this.draftQuote = restored.quote;
    } catch (error) {
      this.draftStatus = '草稿读取失败，本次输入暂不保存';
    } finally {
      if (this.active) { this.draftReady = true; this.reconcilePending(); }
    }
  }

  private async loadModelDraft(): Promise<void> {
    if (this.modelDraftReady) return;
    const id = this.params.threadId, env = this.params.environmentId;
    try {
      const box = await ComposerOutbox.open(getContext(this).filesDir, env);
      const draft = await box.draft(id);
      if (!this.active || id !== this.params.threadId || env !== this.params.environmentId || this.modelDraftReady) return;
      this.outbox = box; this.modelDraft = draft; this.modelDraftReady = true;
      this.unwatchSettings = box.watch(id, () => this.settingsChanged());
      this.settingsChanged(); this.reconcilePending();
    } catch (error) {
      if (this.active && !this.modelDraftReady) this.settingsError = `模型选择读取失败，点此重试：${error instanceof Error ? error.message : String(error)}`;
    }
  }

  private settingsChanged(): void {
    if (this.outbox === null || !this.active) return;
    this.pendingModelSelection = this.modelDraft?.value ?? null;
    this.settingsPending = this.outbox.pending(this.params.threadId).length > 0;
    this.settingsError = this.outbox.error(this.params.threadId);
    this.syncComposerMetadata();
  }

  private editDraft(value: string): void {
    this.draft = value;
    this.updatePathSearch(value.length, value.length);
    if (this.draftStore === null) return;
    this.draftStatus = '正在保存草稿…';
    if (this.draftTimer !== -1) clearTimeout(this.draftTimer);
    this.draftTimer = setTimeout(() => { this.saveDraft(); }, 250);
  }

  private async saveDraft(): Promise<void> {
    if (this.draftTimer !== -1) clearTimeout(this.draftTimer);
    this.draftTimer = -1;
    const store = this.draftStore;
    if (store === null || !this.draftReady) return;
    const text = this.draft;
    const serialized = quotedMessageText(text, this.draftQuote);
    try {
      await store.save(this.editingQueue ? queuedDraftText(this.editingQueue, serialized, this.queueAttachments) : serialized);
      if (this.active && this.draft === text) this.draftStatus = text.length > 0 ? '草稿已保存' : '';
    } catch (error) {
      if (this.active) this.draftStatus = '草稿保存失败，请保留当前页面并重试';
    }
  }

  private async subscribeFeed(rpc: RpcClient): Promise<void> {
    await this.cachedThreadLoad;
    if (!this.active || this.rpc !== rpc) return;
    const id = this.params.threadId;
    let requestEpoch = this.cache?.threadEpoch(id) ?? this.cacheEpoch;
    const joining = requestEpoch !== this.cacheEpoch;
    const previousBaseline = joining ? this.cache?.threadSequence(id) ?? null : this.state.cursor() ?? this.state.thread?.syncSequence ?? null;
    const recoveringHistory = this.threadNeedsSnapshot || joining;
    if (recoveringHistory) {
      this.state.requireSnapshot();
      this.threadNeedsSnapshot = false;
    }
    const environment = EnvironmentSession.current;
    const shared = environment?.descriptor.environmentId === this.params.environmentId ? environment : null;
    const currentRequest = (): boolean => {
      if (!this.active || this.rpc !== rpc) return false;
      if (shared !== null && EnvironmentSession.current !== shared) { rpc.close(); return false; }
      if (!this.cache || requestEpoch === this.cache.threadEpoch(id)) return true;
      this.threadNeedsSnapshot = true;
      rpc.close();
      return false;
    };
    const acceptSnapshot = (baseline: number | null, sequence: number): boolean => {
      const epoch = this.cache ? this.cache.threadSnapshotEpoch(id, requestEpoch, baseline, sequence) : requestEpoch;
      if (epoch === null) return false;
      this.cacheEpoch = requestEpoch = epoch;
      return true;
    };
    this.workspaceCatalogKey = '';
    const knownConfig = shared?.liveConfig;
    this.threadStopSupported = false;
    const applyCapabilities = (config: ServerConfig): void => {
      this.threadStopSupported = config.environment?.capabilities?.threadStop === true;
      this.maxFileBytes = fileUploadLimit(config.environment?.capabilities?.fileAttachments?.maxUploadBytes);
      this.canAttachQuestions = config.environment?.capabilities?.questionAttachments === true && config.environment.capabilities.attachmentUploads === true;
    };
    // A resumable transcript can ask for replay while the shared catalog is in flight.
    // Only a snapshot or a completion marker from this feed confirms that replay.
    const earlyResume = !knownConfig && shared?.pendingConfig != null && !recoveringHistory && this.state.cursor() !== null;
    this.fileLimitsPending = earlyResume;
    if (knownConfig) applyCapabilities(knownConfig);
    else if (earlyResume) {
      this.catalogLoaded = false; this.maxFileBytes = 0; this.canAttachQuestions = false;
      this.rollbackProviders = []; this.browserSupported = false;
    }
    const loadConfig = async (): Promise<ServerConfig | null> => {
      try {
        const config = await (shared?.pendingConfig ?? rpc.call<ServerConfig>(WS.serverGetConfig, new EmptyPayload()));
        if (!currentRequest() || config === null) return null;
        this.catalogLoaded = true;
        this.models = availableModels(config.providers);
        this.timelineProviders = config.providers;
        this.rollbackProviders = config.providers.filter((provider) => provider.enabled && provider.supportsConversationRollback !== false)
          .map((provider) => provider.instanceId);
        applyCapabilities(config);
        this.browserSupported = config.environment?.capabilities?.serverBrowser === true;
        if (this.browserSupported) this.subscribeBrowser(rpc); else this.browserTabs = [];
        this.uploadDraftImages();
        this.cache?.setCatalog(config);
        if (!this.workspaceCatalogKey) this.commandCatalog = this.cache?.commands() ?? commandCatalog(config.providers);
        if (this.loaded) this.scheduleTranscriptRefresh();
        return config;
      } catch (error) { if (error instanceof RpcRemoteError) return null; throw new Error(error instanceof Error ? error.message : String(error)); }
    };
    const config = knownConfig ?? (earlyResume ? null : await loadConfig());
    if (!currentRequest()) return;
    this.subscribeCheckoutBranch(rpc);
    // The live feed can supply the bounded snapshot on its first reply. A forced
    // recovery still uses the independent HTTP snapshot to repair a stalled cursor.
    const bounded = earlyResume || config?.threadSnapshotPagination === true;
    const waitForMarker = earlyResume || config?.threadResumeCompletionMarker === true;
    const liveSnapshot = bounded && !recoveringHistory;
    if (!liveSnapshot && this.state.cursor() === null && environment?.descriptor.environmentId === this.params.environmentId) {
      const path = `/api/orchestration/threads/${encodeURIComponent(this.params.threadId)}` +
        (config?.reasoningMessages === true ? '?reasoningMessages=true' : '');
      // Both optional HTTP attempts must leave time for the live socket subscription.
      const snapshotDeadline = Date.now() + 5000;
      let snapshot = config?.threadSnapshotPagination === true ?
        await environment.loadSnapshot<ThreadSnapshotResponse>(`/api/orchestration/threads/${encodeURIComponent(this.params.threadId)}/bounded?compactTurnItems=1`, 5000) : null;
      const remaining = snapshotDeadline - Date.now();
      if (snapshot === null && remaining > 0) snapshot = await environment.loadSnapshot<ThreadSnapshotResponse>(path, remaining);
      if (!currentRequest()) return;
      if (snapshot !== null && Number.isSafeInteger(snapshot.snapshotSequence) && snapshot.snapshotSequence >= 0 &&
        (snapshot.hasMoreHistory !== true || typeof snapshot.historyCursor === 'string')) {
        if (snapshot.projection?.thread.id === this.params.threadId && Array.isArray(snapshot.projection.messages) && Array.isArray(snapshot.projection.runs)) {
          if (!acceptSnapshot(previousBaseline, snapshot.snapshotSequence)) return;
          this.state.apply({ kind: 'snapshot', snapshotSequence: snapshot.snapshotSequence, projection: snapshot.projection,
            historyCursor: snapshot.historyCursor, hasMoreHistory: snapshot.hasMoreHistory });
        } else if (snapshot.thread?.id === this.params.threadId && Array.isArray(snapshot.thread.messages)) {
          if (!acceptSnapshot(previousBaseline, snapshot.snapshotSequence)) return;
          this.state.apply({ kind: 'snapshot', snapshot: { snapshotSequence: snapshot.snapshotSequence, thread: snapshot.thread } });
        }
      }
      const httpSequence = this.state.cursor();
      if (httpSequence !== null) {
        this.cached = true;
        this.scheduleTranscriptRefresh();
        this.flushTranscriptRefresh();
        this.connection?.progress();
      }
    }
    const subscription: ThreadSubscription = { threadId: this.params.threadId };
    if (bounded) {
      subscription.acceptBoundedSnapshot = true;
      // ThreadState already reads visibleTurnItems and the remaining hidden request dependencies.
      subscription.acceptCompactTurnItems = true;
    }
    if (waitForMarker) subscription.requestCompletionMarker = true;
    if (earlyResume || config?.reasoningMessages === true) subscription.reasoningMessages = true;
    const cursor = this.state.cursor();
    if (cursor !== null) subscription.afterSequence = cursor;
    let synchronized = !waitForMarker && cursor !== null;
    this.loaded = synchronized && this.state.cursor() !== null && this.state.thread !== null;
    this.resumeImageRequest();
    if (this.loaded) {
      this.cached = false;
      this.connectionState = 'connected';
      this.connection?.healthy();
      this.scheduleTranscriptRefresh();
      this.flushTranscriptRefresh();
    }
    let firstDetail = true;
    const detail = rpc.callStream(WS.threadFeed, subscription, (values: object[]) => {
      if (!currentRequest()) return;
      const previousCursor = this.state.cursor();
      let completed = false;
      for (const value of values) {
        const item = value as ThreadItem;
        if (item.kind === 'snapshot') {
          const sequence = item.snapshotSequence ?? item.snapshot?.snapshotSequence;
          const valid = item.projection ? item.projection.thread?.id === this.params.threadId && Array.isArray(item.projection.messages) && Array.isArray(item.projection.runs) :
            item.snapshot?.thread?.id === this.params.threadId && Array.isArray(item.snapshot.thread.messages);
          if (!valid || sequence === undefined || !Number.isSafeInteger(sequence) || sequence < 0) continue;
          if (firstDetail) {
            if (!acceptSnapshot(cursor ?? previousBaseline, sequence)) return;
            if (sequence < (this.state.cursor() ?? -1)) this.state.requireSnapshot();
          }
        }
        this.state.apply(item);
        if (item.kind === 'snapshot' || this.state.cursor() !== previousCursor) firstDetail = false;
        // A full live snapshot is already authoritative; older peers may omit the marker.
        if (item.kind === 'synchronized' || item.kind === 'snapshot') { synchronized = true; completed = true; }
      }
      this.observeRewind?.();
      if (this.state.cursor() !== previousCursor) this.connection?.progress();
      this.loaded = synchronized && this.state.cursor() !== null && this.state.thread !== null;
      this.resumeImageRequest();
      if (this.loaded) {
        this.cached = false;
        this.connectionState = 'connected';
        this.connection?.healthy();
      }
      this.scheduleTranscriptRefresh();
      if (completed) this.flushTranscriptRefresh();
    });
    const shellRequest: ShellSubscription = {};
    if (config?.shellResumeCompletionMarker === true) shellRequest.requestCompletionMarker = true;
    const shellCursor = this.cache?.shellSequence();
    if (shellCursor !== undefined && !this.shellNeedsSnapshot) shellRequest.afterSequence = shellCursor;
    const shell = rpc.callStream(WS.threadsList, shellRequest, (values: object[]) => {
      if (!currentRequest()) return;
      let changed = false;
      for (const value of values) {
        const item = value as ShellItem;
        if (item.kind === 'snapshot-required') { this.shellNeedsSnapshot = true; rpc.close(); return; }
        if (item.kind === 'snapshot') this.shellNeedsSnapshot = false;
        const project = item.project?.id === this.state.thread?.projectId ? item.project : item.snapshot?.projects?.find((entry) => entry.id === this.state.thread?.projectId);
        if (project !== undefined) {
          this.projectTitle = project.title; this.workspaceProject = project;
          if (!this.cwd) { this.cwd = project.workspaceRoot; this.subscribeCheckoutBranch(rpc); }
        }
        if (this.state.applyShell(item, this.params.threadId)) changed = true;
      }
      if (changed) this.scheduleTranscriptRefresh();
    });
    const catalog = knownConfig || earlyResume ? loadConfig() : Promise.resolve<ServerConfig | null>(null);
    return Promise.all([detail, shell, catalog.then((fresh: ServerConfig | null) => {
      if (!earlyResume || !currentRequest()) return;
      this.fileLimitsPending = false;
      // Older peers may ignore requestCompletionMarker. Recover with a verified snapshot.
      if (fresh?.threadResumeCompletionMarker !== true && !this.loaded) { this.threadNeedsSnapshot = true; rpc.close(); }
    })]).then(() => {}, (error: Error) => {
      if (earlyResume && error instanceof RpcRemoteError && currentRequest() && !this.loaded) this.threadNeedsSnapshot = true;
      throw error;
    });
  }

  private async refreshWorkspaceCommands(): Promise<void> {
    const rpc = this.rpc;
    const instanceId = this.state.thread?.modelSelection?.instanceId ?? '';
    const cwd = this.state.thread?.worktreePath ?? this.cwd;
    if (!this.active || !this.loaded || rpc === null || !instanceId || !cwd) return;
    const key = JSON.stringify([instanceId, cwd]);
    if (this.workspaceCatalogKey === key && Date.now() - this.workspaceCatalogAt < 300000) return;
    this.workspaceCatalogKey = key; this.workspaceCatalogAt = Date.now();
    try {
      const request: WorkspaceCatalogRequest = { instanceId: instanceId, cwd: cwd };
      const config = await rpc.call<ServerConfig>('server.refreshProviders', request);
      if (!this.active || this.rpc !== rpc || this.workspaceCatalogKey !== key) return;
      this.commandCatalog = commandCatalog(config.providers);
      this.cache?.setCatalog(config);
    } catch (_) { if (this.workspaceCatalogKey === key) this.workspaceCatalogKey = ''; }
  }

  private syncComposerMetadata(): void {
    const thread = this.state.thread;
    if (thread === null) { this.composerThread = null; this.interrupted = false; return; }
    if (thread.lineage?.relationshipToParent === 'subagent') {
      this.parentThreadId = thread.lineage.parentThreadId ?? this.parentThreadId;
      if (thread.creationSource) this.nativeSubagent = thread.creationSource === 'provider';
      if (!this.parentTitle && this.parentThreadId) {
        this.parentTitle = this.cache?.shell()?.threads.find((entry: ThreadShell) => entry.id === this.parentThreadId)?.title ?? '';
      }
    }
    const turn = thread.latestTurn ?? thread.turns?.[thread.turns.length - 1];
    this.interrupted = ['interrupted', 'cancelled', 'stopped', 'rolled_back'].includes(turn?.state ?? thread.session?.status ?? '');
    // Copy only visible metadata; never clone the message history on a streaming token.
    const metadata: ThreadDetail = { id: thread.id, title: thread.title, projectId: thread.projectId,
      modelSelection: this.pendingModelSelection ?? thread.modelSelection, runtimeMode: thread.runtimeMode, interactionMode: thread.interactionMode,
      branch: thread.branch, worktreePath: thread.worktreePath, pullRequests: thread.pullRequests, messages: [] };
    const choices = (this.outbox?.receipts(this.params.threadId, this.state.composerMetadataSequence()) ?? [])
      .filter(command => !command.modelSelection || this.pendingModelSelection === null).concat(this.outbox?.pending(this.params.threadId) ?? []);
    for (const choice of choices) {
      if (choice.modelSelection) metadata.modelSelection = choice.modelSelection;
      if (choice.runtimeMode) metadata.runtimeMode = choice.runtimeMode;
      if (choice.interactionMode) metadata.interactionMode = choice.interactionMode;
    }
    if (JSON.stringify(metadata) !== JSON.stringify(this.composerThread)) this.composerThread = metadata;
  }

  private updateBranchNotice(): void {
    const input: BranchNoticeInput = { environmentId: this.params.environmentId, cwd: this.cwd,
      thread: this.state.thread, currentBranch: this.checkoutBranch,
      hasContent: !!this.draft.trim() || this.imageUris.length > 0 || this.draftQuote !== null };
    const next = this.editingQueue ? null : this.branchNotice.update(input);
    if (next?.key !== this.branchChange?.key) this.branchChange = next;
  }

  private subscribeCheckoutBranch(rpc: RpcClient): void {
    if (!this.cwd) return;
    const input: RootEntriesRequest = { cwd: this.cwd };
    rpc.callStream('subscribeVcsBranch', input, (values: object[]) => {
      if (!this.active || this.rpc !== rpc) return;
      for (const value of values) {
        const status = value as CheckoutBranchStatus;
        this.checkoutBranch = status.isRepo === false ? '' : status.refName ?? '';
      }
    }).catch(() => { if (this.active && this.rpc === rpc) this.checkoutBranch = ''; });
  }

  private dismissBranchChange(): void {
    if (this.branchChange === null) return;
    this.branchNotice.dismiss(this.branchChange.key);
    this.updateBranchNotice();
  }

  private async restoreThreadBranch(): Promise<void> {
    const rpc = this.rpc;
    const environment = EnvironmentSession.current;
    const mismatch = checkoutBranchMismatch(this.state.thread, this.checkoutBranch);
    if (!this.active || !this.loaded || rpc === null || environment?.descriptor.environmentId !== this.params.environmentId ||
      !this.cwd || mismatch === null || this.settingsBusy || this.settingsPending || this.running || this.sending || this.hasPendingSend) return;
    this.settingsBusy = true; this.restoringBranch = true; this.operationError = '';
    try {
      const input: SwitchRefRequest = { cwd: this.cwd, refName: mismatch.threadBranch };
      const result = await rpc.call<CheckoutBranchStatus>('vcs.switchRef', input);
      if (this.active && this.rpc === rpc && EnvironmentSession.current === environment &&
        this.state.thread?.branch === mismatch.threadBranch && this.checkoutBranch === mismatch.currentBranch) {
        this.checkoutBranch = result.refName ?? mismatch.threadBranch;
      }
    } catch (error) {
      if (this.active && this.rpc === rpc && EnvironmentSession.current === environment) {
        this.operationError = `恢复分支失败：${error instanceof Error ? error.message : String(error)}`;
      }
    } finally { this.settingsBusy = false; this.restoringBranch = false; }
  }

  private async syncCheckoutBranch(rpc: RpcClient): Promise<void> {
    const mismatch = checkoutBranchMismatch(this.state.thread, this.checkoutBranch);
    if (mismatch === null) return;
    const command: ComposerSettingCommand = { type: 'thread.metadata.update', commandId: util.generateRandomUUID(true),
      threadId: this.params.threadId, branch: mismatch.currentBranch, worktreePath: null };
    await rpc.call(WS.threadStartTurn, command);
  }

  private async chooseMachine(saved: SavedEnvironment): Promise<void> {
    if (EnvironmentSession.current?.matchesSaved(saved) || !this.draftReady || this.draftStore === null || this.hasPendingSend || this.sending) return;
    try {
      const text = quotedMessageText(this.draft, this.draftQuote);
      await this.draftStore.save(this.editingQueue ? queuedDraftText(this.editingQueue, text, this.queueAttachments) : text);
      router.back({ url: 'pages/Index', params: { homeRequest: util.generateRandomUUID(true), view: 'connections', selectConnection: saved.connectionId ?? saved.environmentId } });
    } catch (error) { this.settingsError = `切换前保存草稿失败：${error instanceof Error ? error.message : String(error)}`; }
  }

  private async chooseBranch(ref: WorkspaceRef): Promise<void> {
    const connection = EnvironmentSession.current;
    const rpc = this.rpc;
    if (!this.active || rpc === null || connection === null || connection.descriptor.environmentId !== this.params.environmentId || !this.loaded || this.settingsBusy || this.settingsPending || this.running || this.sending || this.hasPendingSend) return;
    const previousBranch = this.state.thread?.branch;
    const previousWorktree = this.state.thread?.worktreePath;
    const previousCheckout = this.checkoutBranch;
    this.settingsBusy = true; this.operationError = '';
    let checkedOut = '';
    let updatingThread = false;
    try {
      const cwd = this.state.thread?.worktreePath ?? this.cwd;
      let branch = ref.name;
      if (!ref.worktreePath || ref.worktreePath === cwd) {
        const switchInput: SwitchRefRequest = { cwd: cwd, refName: ref.name };
        const result = await rpc.call<CheckoutBranchStatus>('vcs.switchRef', switchInput);
        branch = result.refName ?? ref.name;
        checkedOut = branch;
      }
      if (!this.active || this.rpc !== rpc || EnvironmentSession.current !== connection) return;
      const worktreePath = ref.worktreePath ?? this.state.thread?.worktreePath ?? null;
      if (checkedOut && worktreePath === null && this.checkoutBranch === previousCheckout) this.checkoutBranch = checkedOut;
      updatingThread = true;
      const command: ComposerSettingCommand = { type: 'thread.metadata.update', commandId: util.generateRandomUUID(true),
        threadId: this.params.threadId, branch: branch, worktreePath: worktreePath };
      await rpc.call(WS.threadStartTurn, command);
      if (!this.active || this.rpc !== rpc || EnvironmentSession.current !== connection) return;
      if (this.state.thread !== null &&
        (this.state.thread.branch === previousBranch || this.state.thread.branch === branch) &&
        (this.state.thread.worktreePath === previousWorktree || this.state.thread.worktreePath === worktreePath)) {
        this.state.thread.branch = branch; this.state.thread.worktreePath = worktreePath;
        this.syncComposerMetadata();
      }
    } catch (error) {
      if (this.active && this.rpc === rpc && EnvironmentSession.current === connection) {
        if (updatingThread) {
          this.operationError = checkedOut ? `工作区已切换到 ${checkedOut}，会话分支尚未确认更新。` : '会话工作区尚未确认更新，请核对后重试。';
        } else {
          this.operationError = `分支切换失败：${error instanceof Error ? error.message : String(error)}`;
        }
      }
    } finally { this.settingsBusy = false; }
  }

  private async updateComposerSetting(kind: string, value: string, selection: ModelSelection | null = null): Promise<void> {
    const thread = this.state.thread;
    const environment = EnvironmentSession.current, box = this.outbox;
    if (!this.active || this.settingsBusy || this.sending || this.hasPendingSend || thread === null || thread.id !== this.params.threadId ||
      box === null || (environment !== null && environment.descriptor.environmentId !== this.params.environmentId)) return;
    const command: ComposerSettingCommand = { type: '', commandId: util.generateRandomUUID(true), threadId: this.params.threadId };
    if (kind === 'model' || kind === 'options') {
      if (!this.modelDraftReady || selection === null || !this.models.some((model: ModelChoice) => model.instanceId === selection.instanceId && model.model === selection.model)) return;
      command.type = 'thread.model-selection.set'; command.modelSelection = selection;
    } else if (kind === 'runtime') {
      if (!['full-access', 'approval-required', 'auto-accept-edits', 'auto'].includes(value)) return;
      command.type = 'thread.runtime-mode.set'; command.runtimeMode = value; command.createdAt = new Date().toISOString();
    } else if (kind === 'interaction') {
      if (!['default', 'plan'].includes(value)) return;
      command.type = 'thread.interaction-mode.set'; command.interactionMode = value; command.createdAt = new Date().toISOString();
    } else return;
    const currentModel = box.receipts(this.params.threadId, this.state.composerMetadataSequence()).find(c => c.modelSelection !== undefined)?.modelSelection ?? thread.modelSelection;
    await box.enqueue(command, command.modelSelection !== undefined && command.modelSelection.instanceId !== currentModel?.instanceId);
  }

  private async copyMessage(text: string, messageId: string = ''): Promise<void> {
    try {
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, quoteMessageCopyText(text)));
      this.copiedMessageId = messageId;
      if (this.copyTimer !== -1) clearTimeout(this.copyTimer);
      this.copyTimer = setTimeout(() => { this.copiedMessageId = ''; this.copyTimer = -1; }, 1500);
      promptAction.showToast({ message: '消息已复制' });
    } catch (_) { promptAction.showToast({ message: '消息复制失败，请重试' }); }
  }

  private targetForHistoryEdit(message: ChatMessage | undefined): HistoryEditTarget | null {
    const target = historyEditTarget(this.state.thread, message);
    return target !== null && this.rollbackProviders.includes(target.providerInstanceId) ? target : null;
  }

  private canStartHistoryEdit(): boolean {
    return this.active && this.readVisible && this.loaded && !this.running && !this.state.thread?.session?.activeTurnId &&
      this.draftReady && this.imagesReady && this.journalReady &&
      !this.nativeSubagent && !this.editingQueue && !this.sending && !this.settingsBusy && !this.settingsPending && !this.hasPendingSend && !this.pickingImage && !this.selectingMessages;
  }

  private confirmHistoryEdit(row: TimelineRow): void {
    if (!this.canStartHistoryEdit()) return;
    const message = this.state.messages.find((entry: ChatMessage) => entry.id === row.id);
    const target = this.targetForHistoryEdit(message);
    if (message === undefined || target === null) return;
    this.getUIContext().showAlertDialog({ title: '从此处编辑？',
      message: '会话将回退到这条消息之前，原文字和附件会回到输入框。' + (target.canRestoreFiles ?
        '\n\n“同时还原文件”也会撤回你自己的文件改动。' : '\n\n当前会话可以保留文件继续编辑，但无法同时还原文件。'),
      buttons: [
        { value: '取消', action: () => {} },
        { value: '同时还原文件', enabled: target.canRestoreFiles, fontColor: target.canRestoreFiles ? this.color('danger-foreground') : undefined,
          action: () => { this.rewindMessage(message, target, true); } },
        { value: '回退对话，保留文件', style: DialogButtonStyle.HIGHLIGHT,
          action: () => { this.rewindMessage(message, target, false); } }
      ], buttonDirection: DialogButtonDirection.VERTICAL });
  }

  private waitForRewind(rpc: RpcClient, command: RollbackCommand, target: HistoryEditTarget): Promise<string | null> {
    return new Promise<string | null>((resolve, reject) => {
      let finished = false;
      const finish = (reason: string | null = null, error?: Error): void => {
        if (finished) return;
        finished = true;
        clearTimeout(timeout); this.observeRewind = null; this.stopRewindObservation = null;
        if (error !== undefined) reject(error); else resolve(reason);
      };
      const timeout = setTimeout(() => { finish(null, new Error('未确认回退结果，请检查当前会话')); }, 120000);
      const inspect = (): void => {
        const failure = this.state.thread?.rollbackFailure;
        if (failure?.requestId === command.commandId) finish(failure.message);
        else if (historyEditCompleted(this.state.thread, target)) finish();
      };
      this.observeRewind = inspect;
      this.stopRewindObservation = () => { finish(null, new Error('已离开会话，回退结果未确认')); };
      rpc.call(WS.threadStartTurn, command).then(inspect, (error: Error) => {
        if (error instanceof RpcRemoteError && error.definitivelyRejected) finish(error.message);
        else inspect();
      });
    });
  }

  private openSubagent(agent: SubagentSummary): void {
    if (this.selectingMessages) return;
    const remote = agent.childThreadId ? undefined : agent.remoteChild;
    if (remote && remote.environmentId !== this.params.environmentId) {
      loadEnvironments().then(async (saved: SavedEnvironment[]) => {
        if (!this.active || !this.readVisible) return;
        if (!saved.some(entry => entry.environmentId === remote.environmentId)) { this.operationError = '请先添加子代理所在的环境'; this.agentsOpen = false; return; }
        this.agentsOpen = false;
        await openThreadReference({ environmentId: remote.environmentId, threadId: remote.threadId, title: subagentTitle(agent), available: true,
          projectTitle: '', cwd: '' }, this.params.environmentId, this.params.threadId);
      }).catch(() => { this.operationError = '子代理详情暂时无法打开'; });
      return;
    }
    const child = agent.childThreadId || remote?.threadId;
    if (!child || child === this.params.threadId) return;
    this.agentsOpen = false;
    const parentTitle = agent.threadId === this.params.threadId ? this.composerThread?.title || this.cachedTitle :
      this.cache?.shell()?.threads.find((entry: ThreadShell) => entry.id === agent.threadId)?.title ?? '';
    router.pushUrl({ url: 'pages/Thread', params: { environmentId: this.params.environmentId, threadId: child,
      title: subagentTitle(agent), projectTitle: this.projectTitle, cwd: this.state.thread?.worktreePath ?? this.cwd,
      parentThreadId: agent.threadId, parentTitle: parentTitle, openedFromThreadId: this.params.threadId,
      nativeSubagent: String(agent.origin === 'provider_native') } })
      .catch(() => { this.operationError = '子代理详情暂时无法打开'; });
  }

  private openParentThread(): void {
    if (!this.parentThreadId || this.parentThreadId === this.params.threadId) return;
    if (this.openedFromThreadId === this.parentThreadId) { router.back(); return; }
    router.pushUrl({ url: 'pages/Thread', params: { environmentId: this.params.environmentId, threadId: this.parentThreadId,
      title: this.parentTitle || '父会话', projectTitle: this.projectTitle, cwd: this.cwd } })
      .catch(() => { this.operationError = '父会话暂时无法打开'; });
  }

  private async rewindMessage(message: ChatMessage, target: HistoryEditTarget, restoreFiles: boolean): Promise<void> {
    const rpc = this.rpc, environment = EnvironmentSession.current, images = this.imageStore, store = this.draftStore;
    if (!this.canStartHistoryEdit() || rpc === null || environment?.descriptor.environmentId !== this.params.environmentId ||
      images === null || store === null || (restoreFiles && !target.canRestoreFiles)) return;
    const originalAttachments = message.attachments ?? [];
    if (images.images.length + originalAttachments.length > 8) {
      this.operationError = '请先为原消息的附件腾出空间（每条消息最多 8 个附件）'; return;
    }
    const previousDraft = this.draft, previousQuote = this.draftQuote;
    const text = recalledHistoryText(message);
    const recalled = parseQuotedMessage(text);
    const recalledBody = previousQuote !== null && recalled.quote !== null ? quoteMessageCopyText(text) : recalled.text;
    const next = [previousDraft, recalledBody].filter((part: string) => !!part).join('\n\n');
    const quote = previousQuote ?? recalled.quote;
    const added: DraftImage[] = [];
    let saved = false, dispatched = false;
    this.sending = true; this.rewindStatus = '正在恢复原消息…'; this.operationError = ''; this.cancelPaths();
    try {
      if (this.draftTimer !== -1) clearTimeout(this.draftTimer);
      this.draftTimer = -1;
      await this.imageUpload;
      for (const attachment of originalAttachments) {
        if (!this.active || !this.readVisible || this.rpc !== rpc || !this.loaded) throw new Error('连接已变化，请重新打开编辑');
        if (attachment.type !== 'image' && attachment.type !== 'file') throw new Error(`无法恢复附件：${attachment.name}`);
        const download = new FileDownload();
        try {
          await download.fetch(rpc, environment.httpBaseUrl, { _tag: 'attachment', attachmentId: attachment.id,
            fileName: attachment.name, mimeType: attachment.mimeType }, getContext(this).cacheDir);
          const local = download.localFile();
          added.push(await (attachment.type === 'image' ? images.add(local, attachment.name) : images.addFile(local, attachment.name, this.maxFileBytes, true)));
        } finally { await download.dispose(); }
      }
      // Persist the recalled prompt before dispatch, even if the connection drops during rollback.
      await store.save(quotedMessageText(next, quote));
      saved = true;
      if (!this.active || !this.readVisible || !this.loaded || this.rpc !== rpc || EnvironmentSession.current !== environment) throw new Error('连接已变化，未发起回退');
      const currentMessage = this.state.messages.find((entry: ChatMessage) => entry.id === message.id);
      const currentTarget = this.targetForHistoryEdit(currentMessage);
      if (this.running || this.state.thread?.session?.activeTurnId || currentMessage === undefined ||
        JSON.stringify(currentMessage) !== JSON.stringify(message) || currentTarget === null ||
        currentTarget.checkpoint.id !== target.checkpoint.id || currentTarget.checkpoint.scopeId !== target.checkpoint.scopeId ||
        currentTarget.providerThreadId !== target.providerThreadId || currentTarget.turnCount !== target.turnCount ||
        currentTarget.witnessRunId !== target.witnessRunId || (restoreFiles && !currentTarget.canRestoreFiles)) {
        throw new Error('会话已变化，请重新选择要编辑的消息');
      }
      this.draft = next; this.draftQuote = quote; this.imageUris = images.images.map((image: DraftImage) => image.uri);
      this.rewindStatus = '正在回退对话…';
      const command: RollbackCommand = { type: 'checkpoint.rollback', commandId: util.generateRandomUUID(true), threadId: this.params.threadId,
        scopeId: target.checkpoint.scopeId, checkpointId: target.checkpoint.id, restoreFiles: restoreFiles };
      dispatched = true;
      const failure = await this.waitForRewind(rpc, command, target);
      if (failure !== null) { dispatched = false; throw new Error(failure); }
      this.jumpToLatest();
      this.getUIContext().postFrameCallback(new TranscriptFrame(() => {
        if (this.active && this.readVisible) this.composerController.requestFocus?.();
      }));
    } catch (error) {
      const knownFailure = !dispatched;
      this.operationError = (error instanceof Error ? error.message : String(error)) + (knownFailure ? '' : '；原消息已保存在草稿中');
      if (knownFailure) {
        try {
          if (saved || previousDraft || previousQuote !== null) await store.save(quotedMessageText(previousDraft, previousQuote));
          this.draft = previousDraft; this.draftQuote = previousQuote;
          for (const image of added) await images.remove(image.uri);
        } catch (_) { this.operationError += '；草稿清理未完成，请检查输入框'; }
      }
    } finally {
      this.imageUris = images.images.map((image: DraftImage) => image.uri);
      this.rewindStatus = ''; this.sending = false;
      if (this.active) this.uploadDraftImages();
    }
  }

  private async forkMessage(row: TimelineRow): Promise<void> {
    const rpc = this.rpc;
    if (!this.loaded || rpc === null || this.forkingMessageId || !this.assistantActions.includes(row.id)) return;
    this.forkingMessageId = row.id; this.operationError = '';
    try {
      let command = this.forks.get(row.id);
      if (command === undefined) {
        command = forkFromMessage(this.params.threadId, row, util.generateRandomUUID(true), util.generateRandomUUID(true), this.composerThread?.title ?? this.cachedTitle);
        this.forks.set(row.id, command);
      }
      await rpc.call(WS.threadStartTurn, command);
      if (this.active) router.pushUrl({ url: 'pages/Thread', params: { environmentId: this.params.environmentId,
        threadId: command.targetThreadId, title: command.title, projectTitle: this.projectTitle, cwd: this.state.thread?.worktreePath ?? this.cwd } });
    } catch (error) { this.operationError = error instanceof Error ? error.message : String(error); }
    finally { this.forkingMessageId = ''; }
  }

  private async quoteMessage(row: TimelineRow): Promise<void> {
    if (!this.active || !this.draftReady || this.sending || this.hasPendingSend || this.pickingImage) return;
    const quote = createMessageQuote(row, this.params.environmentId, this.params.threadId);
    if (quote === null) return;
    this.cancelPaths();
    this.draftQuote = quote;
    this.quoteFocusPending = true;
    await this.saveDraft();
  }

  private focusQuotedMessage(): void {
    if (!this.quoteFocusPending) return;
    this.quoteFocusPending = false;
    const quote = this.draftQuote;
    // Open the keyboard in the page after the native menu closes and the quote is laid out.
    this.getUIContext().postFrameCallback(new TranscriptFrame(() => {
      if (this.active && this.readVisible && quote !== null && this.draftQuote === quote) this.composerController.requestFocus?.();
    }));
  }

  private async removeQuote(): Promise<void> {
    if (this.sending || this.hasPendingSend) return;
    this.quoteFocusPending = false;
    this.draftQuote = null;
    await this.saveDraft();
  }

  private cancelQuoteNavigation(): void {
    this.quoteTargetId = '';
    this.quoteNavigationVersion++;
  }

  private async locateQuote(quote: MessageQuote | null): Promise<void> {
    if (quote === null || !this.active) return;
    if (quote.environmentId !== this.params.environmentId) {
      promptAction.showToast({ message: '请切换到引用消息所在的环境查看' }); return;
    }
    this.cancelQuoteNavigation();
    if (quote.threadId !== this.params.threadId && !this.entries.some((row: TimelineRow) => row.id === quote.messageId && row.sourceThreadId === quote.threadId)) {
      await this.saveDraft();
      if (this.active) router.pushUrl({ url: 'pages/Thread', params: { environmentId: quote.environmentId, threadId: quote.threadId, quoteMessageId: quote.messageId } });
      return;
    }
    this.cancelPaths(); this.follow.pause(); this.cancelFollowScroll(); this.showingHistory = true;
    this.quoteTargetId = quote.messageId; this.quoteTargetThreadId = quote.threadId;
    this.navigateToQuote();
  }

  private navigateToQuote(): void {
    if (!this.active || !this.readVisible || !this.quoteTargetId) return;
    this.follow.pause(); this.cancelFollowScroll(); this.showingHistory = true;
    const target = this.quoteTargetId;
    const index = this.entries.findIndex((row: TimelineRow) => row.id === target && (row.sourceThreadId ?? this.params.threadId) === this.quoteTargetThreadId);
    if (index >= 0) {
      this.quoteTargetId = '';
      const version = ++this.quoteNavigationVersion;
      this.getUIContext().postFrameCallback(new TranscriptFrame(() => {
        if (!this.active || !this.readVisible || version !== this.quoteNavigationVersion) return;
        const currentIndex = this.entries.findIndex((row: TimelineRow) => row.id === target && (row.sourceThreadId ?? this.params.threadId) === this.quoteTargetThreadId);
        if (currentIndex < 0) return;
        this.scroller.scrollToIndex(currentIndex + (this.hasMoreHistory ? 1 : 0), false, ScrollAlign.START);
        this.highlightedMessageId = target;
        if (this.quoteHighlightTimer !== -1) clearTimeout(this.quoteHighlightTimer);
        this.quoteHighlightTimer = setTimeout(() => { this.highlightedMessageId = ''; this.quoteHighlightTimer = -1; }, 1600);
      }));
    } else if (!this.historyLoading && !this.pendingHistory && this.loaded) {
      if (this.hasMoreHistory && !this.historyError) this.loadOlderHistory().then(() => { if (this.quoteTargetId && this.historyError) this.navigateToQuote(); });
      else { this.quoteTargetId = ''; promptAction.showToast({ message: this.historyError || '原消息已不可用，仍可查看引用内容' }); }
    }
  }

  private selectMessage(row: TimelineRow): void {
    if (!canForwardMessage(row)) return;
    this.selectedMessageIds = this.selectedMessageIds.includes(row.id)
      ? this.selectedMessageIds.filter((id: string) => id !== row.id) : this.selectedMessageIds.concat(row.id);
  }
  private beginMessageSelection(row?: TimelineRow): void {
    this.cancelPaths(); this.follow.pause(); this.showingHistory = true;
    this.selectingMessages = true;
    this.selectedMessageIds = row !== undefined && canForwardMessage(row) ? [row.id] : [];
  }
  private cancelMessageSelection(): void { this.selectingMessages = false; this.selectedMessageIds = []; }
  onBackPress(): boolean {
    if (!this.selectingMessages) return false;
    this.cancelMessageSelection(); return true;
  }
  private openForward(ids: string[]): void {
    if (this.forwardBusy || this.forwardOpen) return;
    try {
      this.forwardContent = forwardContent(this.entries, ids, this.composerThread?.title || this.cachedTitle);
      const shell = this.cache?.shell();
      this.forwardThreads = shell?.threads ?? [];
      this.forwardProjects = shell?.projects ?? [];
      this.cancelPaths(); this.follow.pause(); this.showingHistory = true;
      this.forwardOpen = true;
    } catch (error) { this.operationError = error instanceof Error ? error.message : '请选择要转发的消息'; }
  }
  private async prepareForward(targetId: string, content: ForwardContent): Promise<StartTurnCommand> {
    const environment = EnvironmentSession.current;
    const rpc = this.rpc;
    if (!this.active || !this.readVisible || !this.loaded || rpc === null || environment?.descriptor.environmentId !== this.params.environmentId || targetId === this.params.threadId) {
      throw new Error('请恢复当前环境连接后转发');
    }
    const path = `/api/orchestration/threads/${encodeURIComponent(targetId)}`;
    let snapshot = await environment.loadSnapshot<ThreadSnapshotResponse>(path + '/bounded');
    if (snapshot === null) snapshot = await environment.loadSnapshot<ThreadSnapshotResponse>(path);
    if (!this.active || !this.readVisible || !this.loaded || this.rpc !== rpc || EnvironmentSession.current !== environment) throw new Error('连接已变化，转发尚未发送');
    const target = new ThreadState();
    if (snapshot !== null && Number.isSafeInteger(snapshot.snapshotSequence)) {
      if (snapshot.projection?.thread.id === targetId && Array.isArray(snapshot.projection.messages) && Array.isArray(snapshot.projection.runs)) {
        target.apply({ kind: 'snapshot', snapshotSequence: snapshot.snapshotSequence, projection: snapshot.projection });
      } else if (snapshot.thread?.id === targetId && Array.isArray(snapshot.thread.messages)) {
        target.apply({ kind: 'snapshot', snapshot: { snapshotSequence: snapshot.snapshotSequence, thread: snapshot.thread } });
      }
    }
    if (target.thread === null) throw new Error('无法核对目标会话，请恢复连接后重试');
    return forwardCommand(target.thread, content, util.generateRandomUUID(true), util.generateRandomUUID(true), new Date().toISOString());
  }
  private async dispatchForward(command: StartTurnCommand): Promise<void> {
    if (!this.active || !this.readVisible || !this.loaded || this.rpc === null ||
      EnvironmentSession.current?.descriptor.environmentId !== this.params.environmentId || command.threadId === this.params.threadId) {
      throw new Error('请恢复当前环境连接后重试转发');
    }
    await this.rpc.call(WS.threadStartTurn, command);
  }

  private async htmlPreviewSource(reference: HtmlRenderReference): Promise<string> {
    const environment = EnvironmentSession.current;
    if (environment === null || environment.descriptor.environmentId !== this.params.environmentId || this.rpc === null) {
      throw new Error('请恢复连接后加载预览');
    }
    const request: InlineHtmlAssetRequest = { resource: { _tag: 'attachment', attachmentId: reference.attachmentId,
      fileName: 'Preview.html', mimeType: 'text/html', disposition: 'inline' } };
    const asset = await this.rpc.call<InlineHtmlAsset>('assets.createUrl', request);
    if (!asset.relativeUrl.startsWith('/') || asset.relativeUrl.startsWith('//') || /[\\\r\n]/.test(asset.relativeUrl)) throw new Error('预览地址无效');
    return environment.httpBaseUrl.replace(/\/$/, '') + asset.relativeUrl;
  }

  private originalPreviewImage(entry: TimelineRow): MarkdownImageFile | null {
    return entry.originalImageHref ? markdownImageFileLink(entry.originalImageHref, this.state.thread?.worktreePath ?? this.cwd) : null;
  }

  private openOriginalPreviewImage(entry: TimelineRow): void {
    if (this.selectingMessages) return;
    const image = this.originalPreviewImage(entry);
    if (image === null) return;
    router.pushUrl({ url: 'pages/ImagePreview', params: { environmentId: this.params.environmentId,
      mediaPath: image.path, mediaThreadId: entry.sourceThreadId ?? this.params.threadId, name: image.name } })
      .catch(() => { promptAction.showToast({ message: '原图打开失败，请重试' }); });
  }

  private async imageSource(attachment: ChatAttachment, refresh: boolean, image: ViewedImage | null = null): Promise<string> {
    const filesDir = getContext(this).filesDir;
    if (!refresh) {
      const cached = await ImageAssets.cached(filesDir, this.params.environmentId, attachment.id);
      if (cached) return cached;
    }
    const environment = EnvironmentSession.current;
    if (environment === null || environment.descriptor.environmentId !== this.params.environmentId || this.rpc === null) throw new Error('请恢复连接后加载图片');
    if (image !== null) return ImageAssets.mediaSource(this.rpc, this.params.environmentId, environment.httpBaseUrl,
      image.threadId || this.params.threadId, image.path, refresh, filesDir);
    return ImageAssets.source(this.rpc, this.params.environmentId, environment.httpBaseUrl, attachment, refresh, filesDir);
  }

  private viewedAttachment(image: ViewedImage): ChatAttachment {
    return { type: 'image', id: ImageAssets.mediaId(image.threadId || this.params.threadId, image.path),
      name: image.path.split(/[\\/]/).pop() || '图片', mimeType: '', sizeBytes: 0 };
  }

  private async stop(): Promise<void> {
    if (!this.loaded || this.rpc === null || this.state.thread === null || this.stopping) return;
    const command = interruptTurnCommand(this.state.thread, util.generateRandomUUID(true), this.threadStopSupported);
    if (command === null) {
      if (this.running) this.operationError = '尚未获取当前执行的轮次，请稍后重试';
      return;
    }
    this.operationError = ''; this.stopping = command;
    try { await this.rpc.call(WS.threadStartTurn, command); }
    catch (error) {
      if (this.stopping?.commandId !== command.commandId) return;
      this.stopping = null;
      this.operationError = error instanceof Error ? error.message : String(error);
    }
  }

  private async respond(request: PendingRequest, decision: string, answers: Record<string, string | string[]>,
    attachments: Record<string, ChatAttachment[]> = {}, dismiss: boolean = false): Promise<boolean> {
    if (this.rpc === null || !this.loaded || this.responding || (dismiss && !request.dismissible)) return false;
    const command: ResponseCommand = {
      type: dismiss ? 'thread.user-input.dismiss' : request.kind === 'approval' ? 'thread.approval.respond' : 'thread.user-input.respond',
      commandId: util.generateRandomUUID(true), threadId: this.params.threadId,
      requestId: request.requestId, createdAt: new Date().toISOString()
    };
    if (request.kind === 'approval') command.decision = decision;
    else if (!dismiss) {
      command.answers = answers;
      if (Object.keys(attachments).length > 0) command.attachmentsByQuestionId = attachments;
    }
    this.responding = true;
    this.responseError = '';
    try { await this.rpc.call(WS.threadStartTurn, command); return true; }
    catch (error) { this.responseError = error instanceof Error ? error.message : String(error); return false; }
    finally { this.responding = false; }
  }

  private async loadJournal(): Promise<void> {
    if (this.journal !== null) { this.reconcilePending(); return; }
    try {
      const journal = await SendJournal.open(getContext(this).filesDir, this.params.environmentId, this.params.threadId);
      if (!this.active) return;
      this.journal = journal;
      this.hasPendingSend = journal.pending !== null;
      this.journalReady = true;
      this.reconcilePending();
      this.uploadDraftImages();
    } catch (error) { this.operationError = error instanceof Error ? error.message : String(error); }
  }

  private async finishPending(): Promise<void> {
    const pending = this.journal?.pending;
    if (pending === undefined || pending === null || this.imageStore === null || this.journal === null) return;
    await this.imageStore.clear();
    this.imageUris = [];
    this.imageProgress = [];
    if (quotedMessageText(this.draft, this.draftQuote) === (pending.composerText ?? pending.message.text)) {
      if (this.draftStore === null) throw new Error('消息已送达，但草稿存储尚未就绪');
      await this.draftStore.save('');
      this.draft = '';
      this.draftQuote = null;
      this.draftStatus = '';
    }
    if (pending.modelSelection !== undefined && JSON.stringify(pending.modelSelection) === JSON.stringify(this.pendingModelSelection)) {
      await this.outbox!.consume(this.params.threadId, pending.modelSelection);
    }
    await this.journal.clear();
    this.hasPendingSend = false;
    this.sendError = '';
    if (pending.sideThreadId && this.active) {
      router.pushUrl({ url: 'pages/Thread', params: { environmentId: this.params.environmentId, threadId: pending.sideThreadId,
        title: parseQuotedMessage(pending.message.text).text.slice(0, 72) || '旁支对话', cwd: this.state.thread?.worktreePath ?? this.cwd } });
    }
  }

  private async dispatchPending(command: StartTurnCommand): Promise<void> {
    if (this.rpc === null) throw new Error('请恢复连接后重试');
    if (command.sideThreadId && command.sideForkCommandId) {
      const fork: SideChatCommand = { type: 'thread.fork', commandId: command.sideForkCommandId,
        sourceThreadId: command.threadId, targetThreadId: command.sideThreadId, sourcePoint: { type: 'latest_stable' },
        sideChat: true, title: parseQuotedMessage(command.message.text).text.slice(0, 72) || '旁支对话', createdBy: 'user', creationSource: 'mobile' };
      await this.rpc.call(WS.threadStartTurn, fork);
    }
    await this.rpc.call(WS.threadStartTurn, command);
  }

  private reconcilePending(): void {
    const pending = this.journal?.pending;
    if (!this.active || !this.loaded || !this.imagesReady || !this.draftReady || !this.modelDraftReady || this.sending || !pending) return;
    if (!this.state.messages.some((message) => message.role === 'user' && message.id === pending.message.messageId)) return;
    this.sending = true;
    this.finishPending().catch((error: Error) => { this.operationError = `消息已送达，本地清理待重试：${error.message}`; })
      .finally(() => { this.sending = false; });
  }

  private async handleSendError(error: Error): Promise<void> {
    this.sendError = error.message;
    if (!(error instanceof RpcRemoteError) || !error.definitivelyRejected || this.journal?.pending == null) return;
    try {
      if (this.draftStore === null || this.journal === null) return;
      await this.draftStore.save(quotedMessageText(this.draft, this.draftQuote));
      await this.journal.clear();
      this.hasPendingSend = false;
      this.draftStatus = '发送被拒绝，草稿已保留，可修改后重发';
    } catch (storageError) {
      this.operationError = `发送被拒绝，恢复草稿失败：${storageError instanceof Error ? storageError.message : String(storageError)}`;
    }
  }

  private async retryPending(): Promise<void> {
    const pending = this.journal?.pending;
    if (!pending || !this.loaded || !this.imagesReady || !this.draftReady || !this.modelDraftReady || this.rpc === null || this.sending) return;
    this.sending = true;
    try {
      if (!this.state.messages.some((message) => message.role === 'user' && message.id === pending.message.messageId)) {
        await this.dispatchPending(pending);
      }
      await this.finishPending();
    } catch (error) { await this.handleSendError(error instanceof Error ? error : new Error(String(error))); }
    finally { this.sending = false; this.reconcilePending(); }
  }

  private async loadImages(): Promise<void> {
    if (this.imageStore !== null) return;
    try {
      const store = await AttachmentDraftStore.open(getContext(this).filesDir, this.params.environmentId, this.params.threadId);
      if (!this.active) return;
      this.imageStore = store;
      this.imageUris = store.images.map((image: DraftImage) => image.uri);
      this.imagesReady = true;
      this.imageProgress = store.images.map((image: DraftImage): DraftImageProgress => ({ uri: image.uri,
        status: image.uploaded ? 'uploaded' : 'waiting', progress: image.uploaded ? 100 : 0, error: '' }));
      this.uploadDraftImages();
      this.reconcilePending();
    } catch (error) { this.operationError = `附件草稿读取失败：${error instanceof Error ? error.message : String(error)}`; }
  }

  private async removeImage(uri: string): Promise<void> {
    const store = this.imageStore;
    if (store === null || this.hasPendingSend || this.sending || this.pickingImage) return;
    if (this.editingQueue && uri.startsWith('queued:')) {
      const previous = this.queueAttachments;
      this.queueAttachments = previous.filter((image: ChatAttachment) => 'queued:' + image.id !== uri);
      try { await this.draftStore?.save(queuedDraftText(this.editingQueue, quotedMessageText(this.draft, this.draftQuote), this.queueAttachments)); }
      catch (error) { this.queueAttachments = previous; this.operationError = error instanceof Error ? error.message : String(error); }
      return;
    }
    this.pickingImage = true;
    this.removingImages.add(uri);
    try {
      const uploaded = store.images.find((image: DraftImage) => image.uri === uri)?.uploaded;
      if (uploaded !== undefined && !this.pendingQueueEdit?.attachments?.some((image: ChatAttachment) => image.id === uploaded.id)) {
        if (this.rpc === null) throw new Error('请恢复连接后移除此附件');
        await deleteImageUpload(this.rpc, uploaded.id);
      }
      await store.remove(uri);
      this.imageUris = store.images.map((image: DraftImage) => image.uri);
      this.imageProgress = this.imageProgress.filter((image: DraftImageProgress) => image.uri !== uri);
    } catch (error) { this.operationError = error instanceof Error ? error.message : String(error); }
    finally { this.removingImages.delete(uri); this.pickingImage = false; }
  }

  private async receiveImageComment(): Promise<void> {
    if (!this.active || !this.readVisible || this.nativeSubagent) return;
    const params = router.getParams() as Record<string, string> | null;
    if (!params?.['imageComment'] || params['threadId'] !== this.params.threadId || params['environmentId'] !== this.params.environmentId) return;
    const comment = parseImageComment(params['imageComment'], getContext(this).filesDir);
    if (!comment || this.receivedImageComments.has(comment.id) || this.receivingImageComment) return;
    if ((params['draftScope'] ?? '') !== (this.editingQueue?.runId ?? '')) return;
    if (comment.action === 'send') {
      if (this.attemptedImageRequest === comment.id) return;
      const environment = EnvironmentSession.current, rpc = this.rpc, thread = this.state.thread;
      if (!this.loaded || !rpc || !thread || environment?.descriptor.environmentId !== this.params.environmentId || this.sending || this.hasPendingSend) {
        this.operationError = '图片编辑请求尚未发送，请连接后点击重试'; return;
      }
      this.receivingImageComment = true;
      this.attemptedImageRequest = comment.id; this.imageRequestBusy = true;
      try {
        await ImageEditRequests.send(rpc, getContext(this).filesDir, this.params.environmentId, environment.httpBaseUrl, thread, comment);
        this.receivedImageComments.add(comment.id); this.operationError = ''; this.jumpToLatest();
        fs.unlink(comment.uri).catch(() => {});
        if (comment.maskUri) fs.unlink(comment.maskUri).catch(() => {});
        this.clearImageExtras(comment.attachmentDraftId).catch(() => {});
      } catch (error) { this.operationError = `图片编辑请求未确认，点击重试可继续：${error instanceof Error ? error.message : String(error)}`; }
      finally { this.receivingImageComment = false; this.imageRequestBusy = false; }
      return;
    }
    if (!this.active || !this.readVisible || !this.draftReady || !this.imagesReady || !this.journalReady ||
      this.hasPendingSend || this.sending || this.pickingImage || this.imageStore === null || this.draftStore === null) return;
    this.receivingImageComment = true;
    this.pickingImage = true;
    this.draftReady = false;
    let added: DraftImage | null = null;
    let mask: DraftImage | null = null;
    const extras: DraftImage[] = [];
    const previous = this.queueAttachments;
    const quotedDraft = quotedMessageText(this.draft, this.draftQuote);
    const originalDraft = this.editingQueue ? queuedDraftText(this.editingQueue, quotedDraft, previous) : quotedDraft;
    let textSaved: boolean = false;
    try {
      await this.imageUpload;
      if (!this.active || !this.readVisible) return;
      const target = comment.target ?? '';
      const remote = target.startsWith('queued:') && this.queueAttachments.some((image: ChatAttachment) => 'queued:' + image.id === target);
      if (target && !remote && !this.imageStore.images.some((image: DraftImage) => image.uri === target)) throw new Error('待编辑的图片已移除');
      if (this.attachmentCount() + (target ? 0 : 1) + (comment.maskUri ? 1 : 0) + (comment.extras?.length ?? 0) > 8) throw new Error('每条消息最多 8 个附件，请先移除一个附件');
      if (comment.action !== 'replace' && (comment.action !== 'draft' || !target)) added = await this.imageStore.add(comment.uri, comment.name, target && !remote ? target : '');
      if (remote && comment.action === 'replace') this.queueAttachments = previous.filter((image: ChatAttachment) => 'queued:' + image.id !== target);
      if (comment.maskUri) mask = await this.imageStore.add(comment.maskUri, '擦除选区.png');
      for (const extra of comment.extras ?? []) {
        const image = extra.type === 'file' ? await this.imageStore.addFile(extra.uri, extra.name ?? '附件', this.maxFileBytes) : await this.imageStore.add(extra.uri, extra.name ?? '图片');
        extras.push(image);
        if (extra.uploaded) await this.imageStore.setUploaded(image.uri, extra.uploaded as UploadedImage);
      }
      const text = comment.action === 'replace' && !comment.text.trim() ? this.draft : comment.action === 'draft' || comment.action === 'replace' ? `${this.draft}${this.draft ? '\n\n' : ''}${comment.text}` : appendImageComment(this.draft, comment.name, comment.text);
      if (this.draftTimer !== -1) clearTimeout(this.draftTimer);
      this.draftTimer = -1;
      if (comment.action !== 'replace' || remote || text !== this.draft) {
        const serialized = quotedMessageText(text, this.draftQuote);
        await this.draftStore.save(this.editingQueue ? queuedDraftText(this.editingQueue, serialized, this.queueAttachments) : serialized); textSaved = true;
      }
      if (comment.action === 'replace') added = await this.imageStore.add(comment.uri, comment.name, target && !remote ? target : '');
      this.draft = text;
      this.receivedImageComments.add(comment.id);
      this.draftStatus = '草稿已保存';
      fs.unlink(comment.uri).catch(() => {});
      if (comment.maskUri) fs.unlink(comment.maskUri).catch(() => {});
      this.clearImageExtras(comment.attachmentDraftId).catch(() => {});
    } catch (error) {
      this.queueAttachments = previous;
      if (textSaved) await this.draftStore.save(originalDraft).catch(() => {});
      if (added !== null && !comment.target?.startsWith(getContext(this).filesDir + '/draft-images/')) await this.imageStore.remove(added.uri).catch(() => {});
      if (mask !== null) await this.imageStore.remove(mask.uri).catch(() => {});
      for (const extra of extras) await this.imageStore.remove(extra.uri).catch(() => {});
      this.operationError = `图片评论未加入草稿：${error instanceof Error ? error.message : String(error)}`;
    } finally {
      this.imageUris = this.imageStore.images.map((image: DraftImage) => image.uri);
      this.receivingImageComment = false; this.pickingImage = false; this.draftReady = true;
      this.uploadDraftImages();
    }
  }

  private async clearImageExtras(id: string | undefined): Promise<void> {
    if (!id) return;
    const store = await AttachmentDraftStore.open(getContext(this).filesDir, this.params.environmentId, 'image-editor:' + id);
    await store.clear();
  }

  private async subscribeBrowser(rpc: RpcClient): Promise<void> {
    this.browserTabs = [];
    const sessions = new BrowserSessions(this.params.threadId);
    rpc.callStream('subscribePreviewEvents', new EmptyPayload(), (values: object[]) => {
      if (!this.active || this.rpc !== rpc) return;
      for (const value of values) sessions.event(value as BrowserEvent);
      this.browserTabs = sessions.tabs();
    }).catch(() => {});
    try {
      const target: BrowserThreadRequest = { threadId: this.params.threadId };
      const list = await rpc.call<BrowserList>('preview.list', target);
      if (this.active && this.rpc === rpc) { sessions.list(list); this.browserTabs = sessions.tabs(); }
    } catch (_) {}
  }

  private resumeImageRequest(): void {
    if (!this.loaded || !this.readVisible) return;
    const raw = (router.getParams() as Record<string, string> | null)?.['imageComment'];
    if (!raw) return;
    const request = parseImageComment(raw, getContext(this).filesDir);
    if (request?.action === 'send' && this.attemptedImageRequest !== request.id) this.receiveImageComment();
  }

  private async pickImages(): Promise<void> {
    if (!this.journalReady || this.hasPendingSend || !this.imagesReady || this.imageStore === null || this.pickingImage || this.sending || this.attachmentCount() >= 8) return;
    this.pickingImage = true;
    try {
      const picker = new photoAccessHelper.PhotoViewPicker();
      const result = await picker.select({ MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 8 - this.attachmentCount() });
      for (const uri of result.photoUris) {
        let name = '';
        try { name = new fileUri.FileUri(uri).name; } catch (_) {}
        await this.imageStore.add(uri, name);
        this.imageUris = this.imageStore.images.map((image: DraftImage) => image.uri);
        this.uploadDraftImages();
      }
    } catch (error) {
      this.operationError = error instanceof Error ? error.message : String(error);
    } finally { this.pickingImage = false; }
  }

  private async pickFiles(): Promise<void> {
    if (!this.journalReady || this.hasPendingSend || !this.imagesReady || this.imageStore === null || this.pickingImage || this.sending || this.attachmentCount() >= 8) return;
    this.pickingImage = true; this.operationError = '';
    try {
      const documents = new picker.DocumentViewPicker();
      const uris = await documents.select({ maxSelectNumber: 8 - this.attachmentCount() });
      for (const uri of uris) {
        const name = new fileUri.FileUri(uri).name;
        await this.imageStore.addFile(uri, name, this.maxFileBytes);
        this.imageUris = this.imageStore.images.map((image: DraftImage) => image.uri);
        this.uploadDraftImages();
      }
    } catch (error) { this.operationError = error instanceof Error ? error.message : String(error); }
    finally { this.pickingImage = false; }
  }

  private setImageProgress(uri: string, status: string, progress: number, error: string = ''): void {
    if (!this.imageStore?.images.some((image: DraftImage) => image.uri === uri)) return;
    const existing = this.imageProgress.find((image: DraftImageProgress) => image.uri === uri);
    if (existing?.status === status && existing.progress === progress && existing.error === error) return;
    this.imageProgress = this.imageProgress.filter((image: DraftImageProgress) => image.uri !== uri)
      .concat([{ uri: uri, status: status, progress: progress, error: error }]);
  }
  private imageItems(): DraftImageProgress[] {
    const retained = (this.editingQueue ? this.queueAttachments : []).map((image: ChatAttachment): DraftImageProgress => ({
      uri: 'queued:' + image.id, attachment: image, name: image.name, type: image.type, sizeBytes: image.sizeBytes, status: 'uploaded', progress: 100, error: '' }));
    return retained.concat(this.imageUris.map((uri: string): DraftImageProgress => {
      const progress = this.imageProgress.find((image: DraftImageProgress) => image.uri === uri);
      const image = this.imageStore?.images.find((entry: DraftImage) => entry.uri === uri);
      return { uri: uri, status: progress?.status ?? 'waiting', progress: progress?.progress ?? 0, error: progress?.error ?? '',
        type: image?.type ?? 'image', name: image?.name, sizeBytes: image?.sizeBytes };
    }));
  }
  private attachmentCount(): number { return this.imageUris.length + (this.editingQueue ? this.queueAttachments.length : 0); }
  private imagesUploaded(): boolean {
    return this.imageUris.every((uri: string) => this.imageStore?.images.some((image: DraftImage) => image.uri === uri && !!image.uploaded));
  }
  private retryImage(uri: string): void {
    this.setImageProgress(uri, 'waiting', 0); this.uploadDraftImages();
  }
  private uploadDraftImages(): Promise<void> {
    if (this.imageUpload !== null) return this.imageUpload;
    if (this.rewindStatus || !this.loaded || !this.journalReady || this.hasPendingSend || this.imageStore === null || this.rpc === null) return Promise.resolve();
    const pending: Promise<void> = this.uploadImages().finally(() => { if (this.imageUpload === pending) this.imageUpload = null; });
    this.imageUpload = pending;
    return pending;
  }
  private async uploadImages(): Promise<void> {
    const store = this.imageStore;
    if (store === null) return;
      while (this.active && this.loaded && !this.hasPendingSend && this.rpc !== null) {
        const image = store.images.find((image: DraftImage) => !image.uploaded &&
          this.imageProgress.find((progress: DraftImageProgress) => progress.uri === image.uri)?.status !== 'failed' &&
          (image.type !== 'file' || this.catalogLoaded));
        const environment = EnvironmentSession.current;
        if (!image || environment?.descriptor.environmentId !== this.params.environmentId) break;
        const rpc = this.rpc;
        this.setImageProgress(image.uri, 'uploading', 0);
        try {
          const uploaded = await uploadImage(rpc, environment.httpBaseUrl, image.uri, image.name ?? '',
            (progress: number) => { this.setImageProgress(image.uri, 'uploading', progress); }, image.type ?? 'image', image.type === 'file' ? this.maxFileBytes : 10 * 1024 * 1024);
          try {
            await store.setUploaded(image.uri, uploaded);
            if (this.removingImages.has(image.uri) || !store.images.some((entry: DraftImage) => entry.uri === image.uri)) await deleteImageUpload(rpc, uploaded.id);
            else this.setImageProgress(image.uri, 'uploaded', 100);
          } catch (error) { await deleteImageUpload(rpc, uploaded.id); throw new Error(error instanceof Error ? error.message : String(error)); }
        } catch (error) {
          this.setImageProgress(image.uri, 'failed', 0, error instanceof Error ? error.message : String(error));
        }
      }
  }

  private async send(delivery: string = 'steer'): Promise<void> {
    if (!this.active || this.nativeSubagent) return;
    if (this.editingQueue) { await this.saveQueueEdit(); return; }
    if (!this.canSend() || this.journal === null || this.imageStore === null || this.rpc === null || this.state.thread === null) return;
    if (this.draft.trim() === '/model') {
      this.editDraft(''); this.modelPickerRequest++; return;
    }
    const text = this.draft;
    const images = this.imageUris.slice();
    this.cancelPaths();
    this.sending = true;
    try {
      this.sendError = '';
      const environment = EnvironmentSession.current;
      const rpc = this.rpc;
      if (environment?.descriptor.environmentId !== this.params.environmentId) throw new Error('连接已关闭');
      await this.uploadDraftImages();
      if (!this.active || !this.loaded || this.rpc !== rpc || EnvironmentSession.current !== environment ||
        environment.descriptor.environmentId !== this.params.environmentId) throw new Error('连接已变化，草稿已保留，请恢复连接后发送');
      const command = startTurnCommand(this.state.thread, text, util.generateRandomUUID(true),
        util.generateRandomUUID(true), new Date().toISOString(), delivery, this.pendingModelSelection);
      // The receipt can precede its feed event; send with the modes already shown in the composer.
      for (const saved of this.outbox?.receipts(this.params.threadId, this.state.composerMetadataSequence()) ?? []) {
        if (saved.runtimeMode) command.runtimeMode = saved.runtimeMode;
        if (saved.interactionMode) command.interactionMode = saved.interactionMode;
      }
      if (!command.message.text.trim() && images.length === 0) throw new Error('请在命令后输入消息');
      if (this.draftQuote) {
        command.message.text = quotedMessageText(command.message.text, this.draftQuote);
        command.composerText = quotedMessageText(text, this.draftQuote);
      }
      for (const uri of images) {
        if (this.imageProgress.some((image: DraftImageProgress) => image.uri === uri && image.status === 'failed')) {
          throw new Error('附件上传失败，草稿已保留，请点击附件重试');
        }
        let uploaded = this.imageStore.images.find((image: DraftImage) => image.uri === uri)?.uploaded;
        if (uploaded !== undefined && !await imageUploadExists(this.rpc, uploaded.id)) uploaded = undefined;
        if (uploaded === undefined) {
          const image = this.imageStore.images.find((image: DraftImage) => image.uri === uri);
          uploaded = await uploadImage(this.rpc, environment.httpBaseUrl, uri,
            image?.name ?? '', (progress: number) => { this.setImageProgress(uri, 'uploading', progress); },
            image?.type ?? 'image', image?.type === 'file' ? this.maxFileBytes : 10 * 1024 * 1024);
          try { await this.imageStore.setUploaded(uri, uploaded); }
          catch (error) {
            await deleteImageUpload(this.rpc, uploaded.id);
            throw new Error(error instanceof Error ? error.message : String(error));
          }
          this.setImageProgress(uri, 'uploaded', 100);
        }
        command.message.attachments.push(uploaded);
      }
      if (!this.active || !this.loaded || this.rpc !== rpc || EnvironmentSession.current !== environment) throw new Error('连接已变化，草稿已保留，请重试');
      await this.syncCheckoutBranch(rpc);
      if (!this.active || !this.loaded || this.rpc !== rpc || EnvironmentSession.current !== environment) throw new Error('连接已变化，草稿已保留，请重试');
      await this.journal.save(command);
      this.hasPendingSend = true;
      this.jumpToLatest();
      await this.dispatchPending(command);
      await this.finishPending();
    } catch (error) {
      await this.handleSendError(error instanceof Error ? error : new Error(String(error)));
    } finally {
      this.sending = false;
      this.reconcilePending();
    }
  }

  private canContinue(): boolean {
    return !this.editingQueue && this.active && this.interrupted && !this.running && !this.settingsBusy && !this.settingsPending && this.journalReady && !this.hasPendingSend && this.loaded &&
      this.draftReady && this.modelDraftReady && this.imagesReady && !this.pickingImage && !this.sending && !this.draftQuote && !this.draft.trim() && this.imageUris.length === 0;
  }
  private async continueInterrupted(): Promise<void> {
    if (!this.canContinue()) return;
    this.editDraft('Continue where you left off.');
    await this.send();
  }

  private touchMessage(key: string, event: TouchEvent): void {
    if (this.selectingMessages) return;
    if (event.type === TouchType.Down) this.pressedMessageKey = key;
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.pressedMessageKey = '';
  }
  private openMessageMenu(key: string): void { this.menuMessageKey = key; this.pressedMessageKey = ''; }
  private closeMessageMenu(): void { this.menuMessageKey = ''; this.pressedMessageKey = ''; this.focusQuotedMessage(); }

  @Builder
  messageMenu(row: TimelineRow) {
    Menu() {
      if (this.historyEditIds.includes(row.id)) {
        MenuItem({ content: '从此处编辑', symbolStartIcon: menuIcon($r('sys.symbol.square_and_pencil')) }).enabled(this.canStartHistoryEdit()).onClick(() => { this.confirmHistoryEdit(row); })
      }
      MenuItem({ content: '复制消息', symbolStartIcon: menuIcon($r('sys.symbol.doc_text_on_doc_text')) }).onClick(() => { this.copyMessage(row.text, row.id); })
      MenuItem({ content: '引用回复', symbolStartIcon: menuIcon($r('sys.symbol.quote')) }).enabled(!this.nativeSubagent && canQuoteMessage(row) && this.draftReady && !this.sending && !this.hasPendingSend && !this.pickingImage)
        .onClick(() => { this.quoteMessage(row); })
      MenuItem({ content: '转发', symbolStartIcon: menuIcon($r('sys.symbol.arrowshape_turn_up_right')) }).enabled(canForwardMessage(row)).onClick(() => { this.openForward([row.id]); })
      MenuItem({ content: '批量转发', symbolStartIcon: menuIcon($r('sys.symbol.checkmark_square_on_square')) }).enabled(canForwardMessage(row)).onClick(() => { this.beginMessageSelection(row); })
    }
  }

  private canSend(): boolean {
    // Bind the button to @State readiness; plain RPC and store handles cannot trigger an ArkUI redraw.
    return this.loaded && this.journalReady && this.draftReady && this.modelDraftReady && this.imagesReady &&
      (!this.fileLimitsPending || !this.imageUris.length || !this.imageStore?.images.some((image: DraftImage) => image.type === 'file')) &&
      !this.nativeSubagent && !this.hasPendingSend && !this.settingsBusy && !this.settingsPending &&
      !this.pickingImage && !this.sending && (this.draft.trim().length > 0 || this.imageUris.length > 0);
  }
  private messageTime(value: string): string {
    const date = new Date(value);
    if (!Number.isFinite(date.getTime())) return '';
    return `${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}`;
  }
  private needsThinking(): boolean {
    const last = this.entries[this.entries.length - 1];
    return this.loaded && this.running && this.requests.length === 0 && !last?.streaming && !['thinking', 'tool', 'tools', 'activity'].includes(last?.kind ?? '');
  }
  @Builder
  private sendMenu() {
    Menu() {
      MenuItem({ content: this.running ? '立即插队发送' : '发送', symbolStartIcon: menuIcon(this.running ? $r('sys.symbol.arrowshape_turn_up_left') : $r('sys.symbol.paperplane')) }).enabled(this.canSend()).onClick(() => { this.send('steer'); })
      if (this.running) {
        MenuItem({ content: '排队发送', symbolStartIcon: menuIcon($r('sys.symbol.list_bullet')) }).enabled(this.canSend()).onClick(() => { this.send('queue'); })
        MenuItem({ content: '停止当前执行', symbolStartIcon: menuIcon($r('sys.symbol.stop_circle')) }).enabled(this.loaded && !this.stopping).onClick(() => { this.stop(); })
      }
    }
  }
  @Builder
  private threadMenu() {
    Menu() {
      ForEach(this.cache?.sideChats(this.params.threadId) ?? [], (chat: ThreadShell) => {
        MenuItem({ content: `旁聊：${chat.title || '未命名旁聊'}`, symbolStartIcon: menuIcon($r('sys.symbol.message')) }).onClick(() => {
          router.pushUrl({ url: 'pages/Thread', params: { environmentId: this.params.environmentId, threadId: chat.id,
            title: chat.title || '旁聊', projectTitle: this.projectTitle, cwd: chat.worktreePath ?? this.cwd } })
            .catch(() => { this.operationError = '旁聊暂时无法打开'; });
        })
      }, (chat: ThreadShell) => JSON.stringify([chat.id, chat.title]))
      MenuItem({ content: '批量转发', symbolStartIcon: menuIcon($r('sys.symbol.checkmark_square_on_square')) }).onClick(() => { this.beginMessageSelection(); })
      MenuItem({ content: '重新连接', symbolStartIcon: menuIcon($r('sys.symbol.arrow_2_circlepath')) }).onClick(() => { this.connection?.start(); })
      MenuItem({ content: '最新消息', symbolStartIcon: menuIcon($r('sys.symbol.arrow_down_to_line')) }).onClick(() => { this.jumpToLatest(); })
    }
  }

  private async pullOlderHistory(): Promise<void> {
    try { await this.loadOlderHistory(); }
    finally { this.refreshingHistory = false; }
  }

  private async loadOlderHistory(): Promise<void> {
    const environment = EnvironmentSession.current;
    const cursor = this.state.thread?.historyCursor;
    const rpc = this.rpc;
    if (!this.active || !this.loaded || this.historyLoading || !this.hasMoreHistory || !cursor || rpc === null ||
      environment?.descriptor.environmentId !== this.params.environmentId) return;
    this.follow.pause(); this.showingHistory = true;
    this.historyLoading = true; this.historyError = '';
    const epoch = this.state.historyVersion();
    let page: ThreadHistoryPage | null = null;
    try {
      page = await environment.loadSnapshot<ThreadHistoryPage>(`/api/orchestration/threads/${encodeURIComponent(this.params.threadId)}/history?cursor=${encodeURIComponent(cursor)}`);
    } catch (_) {}
    if (!this.active || this.rpc !== rpc) { this.historyLoading = false; return; }
    if (page === null || !Number.isSafeInteger(page.snapshotSequence) || !Array.isArray(page.items) ||
      (page.nextCursor !== null && typeof page.nextCursor !== 'string')) {
      this.historyLoading = false; this.historyError = '历史消息加载失败，点按重试'; return;
    }
    this.pendingHistory = page; this.pendingHistoryCursor = cursor; this.pendingHistoryEpoch = epoch;
    if (this.finishOlderHistory()) this.refreshTranscript();
  }

  private finishOlderHistory(): boolean {
    const page = this.pendingHistory;
    if (page === null) return false;
    if (this.state.historyVersion() !== this.pendingHistoryEpoch || this.state.thread?.historyCursor !== this.pendingHistoryCursor) {
      this.pendingHistory = null; this.historyLoading = false; return false;
    }
    const anchor = this.entries[Math.max(0, this.firstVisibleIndex - (this.hasMoreHistory ? 1 : 0))]?.id ?? '';
    if (!this.state.mergeHistory(page, this.pendingHistoryCursor, this.pendingHistoryEpoch)) return false;
    this.historyAnchor = anchor; this.pendingHistory = null; this.historyLoading = false;
    return true;
  }

  private refreshTranscript(): void {
    this.hasMoreHistory = this.state.thread?.hasMoreHistory === true;
    const queue = queuedMessages(this.state.thread, this.state.messages);
    if (JSON.stringify(queue) !== JSON.stringify(this.queue)) this.queue = queue;
    const entries = reconcileTranscriptRows(this.entries, transcriptRows(this.state.messages, this.state.activities, this.state.thread?.session ?? null,
      this.state.thread?.latestTurn ?? null, this.expandedRows, this.state.thread?.turns ?? [], this.state.thread?.subagents ?? []));
    this.entries = entries;
    const agents = turnSubagents(this.state.thread, this.state.activities);
    if (JSON.stringify(agents) !== JSON.stringify(this.turnAgents)) this.turnAgents = agents;
    if (!agents.length && this.agentsOpen) this.agentsOpen = false;
    this.transcriptSource.update(entries);
    this.assistantActions = assistantActionIds(this.entries, this.state.thread?.session?.activeTurnId ?? null);
    const thread = this.state.thread;
    let editable: string[] = [];
    if (thread && this.rollbackProviders.length && !thread.session?.activeTurnId &&
      !['running', 'starting'].includes(thread.session?.status ?? '')) {
      const index = this.historyEditIndex?.matches(thread) ? this.historyEditIndex : new HistoryEditIndex(thread);
      this.historyEditIndex = index;
      editable = this.state.messages.filter((message: ChatMessage) => {
        const target = index.target(message);
        return target !== null && this.rollbackProviders.includes(target.providerInstanceId);
      }).map((message: ChatMessage) => message.id);
    }
    if (editable.length !== this.historyEditIds.length || editable.some((id, i) => id !== this.historyEditIds[i])) this.historyEditIds = editable;
    this.follow.update(JSON.stringify([this.entries.length, this.entries[this.entries.length - 1],
      this.requests.map((request: PendingRequest) => request.requestId)]));
    this.scheduleFollowScroll();
    if (this.historyAnchor) {
      const index = this.entries.findIndex((row: TimelineRow) => row.id === this.historyAnchor);
      this.historyAnchor = '';
      const generation = this.followGeneration;
      this.getUIContext().postFrameCallback(new TranscriptFrame(() => {
        if (this.active && generation === this.followGeneration && !this.follow.following && index >= 0) {
          this.scroller.scrollToIndex(index + (this.hasMoreHistory ? 1 : 0), false, ScrollAlign.START);
        }
      }));
    }
    if (this.quoteTargetId) this.navigateToQuote();
  }
  private scheduleTranscriptRefresh(): void {
    if (this.transcriptTimer !== -1) return;
    this.transcriptTimer = setTimeout(() => { this.flushTranscriptRefresh(); }, 32);
  }
  private flushTranscriptRefresh(): void {
    if (this.transcriptTimer === -1) return;
    clearTimeout(this.transcriptTimer); this.transcriptTimer = -1;
    if (!this.active || this.rpc === null) return;
    this.finishOlderHistory();
    this.requests = pendingRequests(this.state.activities);
    RequestDrafts.retain(this.params.environmentId, this.params.threadId, this.requests.map((request: PendingRequest) => request.requestId));
    if (this.readVisible === false) this.hiddenTranscriptChanged = true;
    else this.refreshTranscript();
    this.syncComposerMetadata();
    this.threadStatus = this.state.thread?.session?.status ?? '';
    this.running = this.threadStatus === 'running' || this.threadStatus === 'starting';
    this.updateElapsed();
    if (this.loaded && this.state.thread !== null) {
      this.cache?.setThread(this.state.thread, this.state.messages, this.state.activities, this.state.checkpointCount,
        this.state.cursor(), !this.running && !this.state.messages.some((message) => message.streaming === true), this.cacheEpoch);
    }
    this.uploadDraftImages();
    if (this.stopping && (!this.running || this.stopping.runId !== (this.state.thread?.session?.activeTurnId ?? undefined))) this.stopping = null;
    this.reconcilePending();
  }
  onDidBuild(): void { this.scheduleFollowScroll(); }
  private cancelFollowScroll(): void {
    this.followGeneration++; this.followQueued = false;
  }
  private scheduleFollowScroll(): void {
    if (this.followQueued || !this.active || !this.follow.following || this.entries.length + this.requests.length === 0) return;
    this.followQueued = true;
    const generation = this.followGeneration;
    this.getUIContext().postFrameCallback(new TranscriptFrame(() => {
      if (generation !== this.followGeneration) return;
      this.followQueued = false;
      if (this.active && this.follow.takeRequest()) {
        const last = this.entries.length + (this.hasMoreHistory ? 1 : 0) + (this.needsThinking() ? 1 : 0) - 1;
        if (last >= 0) this.scroller.scrollToIndex(last, false, ScrollAlign.END);
      }
      this.markCurrentRead();
    }));
  }
  private jumpToLatest(): void {
    this.cancelQuoteNavigation();
    this.follow.jump(); this.showingHistory = false; this.scheduleFollowScroll();
  }
  private foregroundChanged(): void { this.updateElapsed(); this.markCurrentRead(); }
  private markCurrentRead(): void {
    if (!this.active || !this.readVisible || !this.foreground || !this.follow.following || !this.entries.length || !this.scroller.isAtEnd()) return;
    const thread = this.state.thread;
    if (thread === null) return;
    ThreadReads.mark(this.params.environmentId, this.params.threadId, threadReadRevision(thread.latestTurn)).catch(() => {});
  }
  private stopElapsedTimer(): void {
    if (this.elapsedTimer !== -1) clearInterval(this.elapsedTimer);
    this.elapsedTimer = -1;
  }
  private updateElapsed(): void {
    this.elapsed = this.running ? this.activeWorkLabel() : '';
    if (!this.running || !this.readVisible || !this.foreground) { this.stopElapsedTimer(); return; }
    if (this.elapsedTimer === -1) this.elapsedTimer = setInterval(() => {
      this.elapsed = this.activeWorkLabel();
    }, 1000);
  }
  private activeWorkLabel(): string {
    const thread = this.state.thread;
    const turn = thread?.turns?.find((entry) => entry.turnId === thread?.session?.activeTurnId) ?? thread?.latestTurn ?? null;
    return workDuration(turn, new Date().toISOString());
  }
  private toggleTranscript(id: string): void {
    this.follow.pause(); this.showingHistory = true;
    this.expandedRows = this.expandedRows.includes(id) ? this.expandedRows.filter((entry: string) => entry !== id) : this.expandedRows.concat([id]);
    this.refreshTranscript();
    const entry = this.entries.find((row: TimelineRow) => row.id === id);
    if (entry !== undefined && entry.itemId && this.expandedRows.includes(id) && entry.detailOmitted) this.loadTurnItem(entry);
  }
  private async loadTurnItem(entry: TimelineRow): Promise<void> {
    const rpc = this.rpc;
    if (rpc === null || !this.loaded || !entry.itemId || this.detailLoading.includes(entry.id)) return;
    this.detailLoading = this.detailLoading.concat([entry.id]);
    this.detailError = '';
    try {
      const request: TurnItemRequest = { threadId: entry.sourceThreadId ?? this.params.threadId, itemId: entry.itemId };
      const result = await rpc.call<TurnItemResult>('orchestration.getTurnItem', request);
      if (!this.active || this.rpc !== rpc) return;
      if (result.item === null) throw new Error('该执行记录已不可用');
      this.state.applyTurnItemDetail(result.item);
      this.refreshTranscript();
    } catch (error) {
      if (this.active && this.rpc === rpc) this.detailError = error instanceof Error ? error.message : String(error);
    } finally { this.detailLoading = this.detailLoading.filter((id: string) => id !== entry.id); }
  }

  private async beginQueueEdit(message: QueuedMessage): Promise<void> {
    if (this.editingQueue || !this.loaded || this.queueBusy || this.sending || this.hasPendingSend || this.pickingImage ||
      !this.draftReady || !this.imagesReady || this.draftStore === null || this.imageStore === null || !message.canEdit) return;
    this.queueBusy = true; this.pickingImage = true; this.draftReady = false; this.queueError = '';
    try {
      await this.imageUpload;
      if (this.draftTimer !== -1) clearTimeout(this.draftTimer);
      this.draftTimer = -1;
      await this.draftStore.save(quotedMessageText(this.draft, this.draftQuote));
      const scope = `queue:${this.params.threadId}:${message.runId}`, filesDir = getContext(this).filesDir;
      const store = await DraftStore.open(filesDir, this.params.environmentId, scope);
      const images = await AttachmentDraftStore.open(filesDir, this.params.environmentId, scope);
      const restored = restoreQueuedDraft(message, await store.load());
      if (!restored) await images.clear();
      if (!this.active || !this.readVisible) return;
      this.mainDraft = { text: this.draft, quote: this.draftQuote, store: this.draftStore, images: this.imageStore, progress: this.imageProgress, status: this.draftStatus };
      this.cancelPaths();
      this.editingQueue = message; this.pendingQueueEdit = null;
      this.queueAttachments = restored?.attachments ?? message.attachments.slice();
      const restoredText = parseQuotedMessage(restored?.text ?? message.text);
      this.draftStore = store; this.imageStore = images; this.draft = restoredText.text; this.draftQuote = restoredText.quote;
      this.imageUris = images.images.map((image: DraftImage) => image.uri);
      this.imageProgress = images.images.map((image: DraftImage): DraftImageProgress => ({ uri: image.uri, status: image.uploaded ? 'uploaded' : 'waiting', progress: image.uploaded ? 100 : 0, error: '' }));
      this.draftStatus = ''; this.operationError = ''; this.queueOpen = false;
    } catch (error) { this.queueError = error instanceof Error ? error.message : String(error); }
    finally { this.queueBusy = false; this.pickingImage = false; this.draftReady = true; this.uploadDraftImages(); }
  }
  private async finishQueueEdit(): Promise<void> {
    const original = this.mainDraft;
    if (original === null) return;
    await this.imageUpload;
    if (this.draftTimer !== -1) clearTimeout(this.draftTimer);
    this.draftTimer = -1;
    await this.draftStore?.save('');
    await this.imageStore?.clear();
    this.cancelPaths();
    this.draft = original.text; this.draftQuote = original.quote ?? null; this.draftStore = original.store; this.imageStore = original.images;
    this.imageUris = original.images.images.map((image: DraftImage) => image.uri); this.imageProgress = original.progress; this.draftStatus = original.status;
    this.editingQueue = null; this.queueAttachments = []; this.pendingQueueEdit = null; this.mainDraft = null;
    this.operationError = '';
  }
  private async cancelQueueEdit(): Promise<void> {
    if (!this.editingQueue || this.sending || this.pickingImage || this.queueBusy) return;
    this.pickingImage = true;
    try { await this.finishQueueEdit(); }
    catch (error) { this.operationError = error instanceof Error ? error.message : String(error); }
    finally { this.pickingImage = false; }
  }
  private canSaveQueueEdit(): boolean {
    return !!this.editingQueue && this.loaded && this.draftReady && this.imagesReady && !this.sending && !this.pickingImage && !this.queueBusy &&
      (!!this.draft.trim() || this.queueAttachments.length > 0 || this.imageUris.length > 0) &&
      this.queue.some((message: QueuedMessage) => message.runId === this.editingQueue?.runId && message.canEdit);
  }
  private async saveQueueEdit(): Promise<void> {
    if (!this.canSaveQueueEdit() || this.editingQueue === null || this.rpc === null || this.state.thread === null || this.imageStore === null) return;
    const rpc = this.rpc, edited = this.editingQueue;
    this.sending = true; this.queueBusy = true; this.operationError = '';
    try {
      await this.saveDraft();
      await this.uploadDraftImages();
      if (!this.imagesUploaded()) throw new Error('附件上传未完成，修改已保留，请点击附件重试');
      const attachments = this.queueAttachments.concat(this.imageStore.images.map((image: DraftImage): ChatAttachment => image.uploaded!));
      const current = this.queue.find((message: QueuedMessage) => message.runId === edited.runId);
      if (!current) throw new Error('这条消息已离开队列，编辑内容已保留');
      const text = quotedMessageText(this.draft, this.draftQuote);
      const pendingMatches = this.pendingQueueEdit?.text === text && JSON.stringify(this.pendingQueueEdit?.attachments) === JSON.stringify(attachments);
      if (queuedDraftBase(current) !== queuedDraftBase(edited) && !(pendingMatches && current.text === text && JSON.stringify(current.attachments) === JSON.stringify(attachments))) {
        throw new Error('这条消息已被其他设备修改，请先保留当前内容，再取消并重新打开编辑');
      }
      const command = pendingMatches ? this.pendingQueueEdit : queuedMessageCommand(this.state.thread, this.state.messages, edited.runId, 'edit', util.generateRandomUUID(true), text, attachments);
      if (!command) throw new Error('这条消息的状态已改变，修改已保留');
      if (!this.active || !this.loaded || this.rpc !== rpc || EnvironmentSession.current?.descriptor.environmentId !== this.params.environmentId) throw new Error('连接已变化，修改已保留');
      this.pendingQueueEdit = command;
      await rpc.call(WS.threadStartTurn, command);
      await this.finishQueueEdit();
    } catch (error) { this.operationError = error instanceof Error ? error.message : String(error); }
    finally { this.sending = false; this.queueBusy = false; }
  }

  private async queueAction(runId: string, action: string, text: string): Promise<boolean> {
    const rpc = this.rpc;
    if (rpc === null || !this.loaded || this.queueBusy || this.state.thread === null) return false;
    const command = queuedMessageCommand(this.state.thread, this.state.messages, runId, action, util.generateRandomUUID(true), text);
    if (command === null) { this.queueError = '该消息的状态已改变，请等待队列同步后重试'; return false; }
    this.queueBusy = true; this.queueError = '';
    try {
      await rpc.call(WS.threadStartTurn, command);
      return true;
    } catch (error) {
      if (this.active) this.queueError = error instanceof Error ? error.message : String(error);
      return false;
    } finally { this.queueBusy = false; }
  }
  @Builder
  queueSheet() {
    QueuedMessages({ messages: this.queue, online: this.loaded, running: this.running, busy: this.queueBusy,
      error: this.queueError, environmentId: this.params.environmentId,
      onEdit: (message: QueuedMessage) => { this.beginQueueEdit(message); },
      loadSource: (image: ChatAttachment, refresh: boolean) => this.imageSource(image, refresh),
      onAction: (runId: string, action: string, text: string) => this.queueAction(runId, action, text) })
  }

  @Builder
  private forwardSheet() {
    MessageForwarder({ environmentId: this.params.environmentId, sourceThreadId: this.params.threadId,
      content: this.forwardContent, threads: this.forwardThreads, projects: this.forwardProjects, online: this.loaded,
      prepare: (targetId: string, content: ForwardContent) => this.prepareForward(targetId, content),
      dispatch: (command: StartTurnCommand) => this.dispatchForward(command),
      onBusy: (busy: boolean) => { this.forwardBusy = busy; },
      onDone: () => { this.forwardOpen = false; this.cancelMessageSelection(); } })
  }

  @Builder
  private selectionActions() {
    Row({ space: 10 }) {
      Button({ type: ButtonType.Circle }) { AppIcon({ name: 'close', iconSize: 21, tint: this.color('foreground-secondary') }) }
        .width(40).height(40).padding(0).backgroundColor(Color.Transparent).accessibilityText('取消选择')
        .onClick(() => { this.cancelMessageSelection(); })
      Text(`已选 ${this.selectedMessageIds.length} 条`).fontSize(this.font(14)).fontColor(this.color('foreground')).layoutWeight(1)
      Button({ type: ButtonType.Circle }) { AppIcon({ name: 'check-all', iconSize: 22, tint: this.color('foreground-secondary') }) }
        .width(40).height(40).padding(0).backgroundColor(Color.Transparent).accessibilityText('全选或取消全选已加载消息')
        .onClick(() => {
          const ids = this.entries.filter((row: TimelineRow) => canForwardMessage(row)).map((row: TimelineRow) => row.id);
          this.selectedMessageIds = ids.every((id: string) => this.selectedMessageIds.includes(id)) ? [] : ids;
        })
      Button({ type: ButtonType.Circle }) { AppIcon({ name: 'forward', iconSize: 21, tint: '#FFFFFF' }) }
        .width(40).height(40).padding(0).backgroundColor('#3268F5').accessibilityText('转发所选消息')
        .enabled(this.selectedMessageIds.length > 0).onClick(() => { this.openForward(this.selectedMessageIds); })
    }.width('100%').padding(8).borderRadius(24).backgroundColor(this.color('card'))
  }

  private openChanges(row: TimelineRow): void {
    if (!this.loaded) return;
    router.pushUrl({ url: 'pages/Diff', params: { threadId: row.sourceThreadId ?? this.params.threadId,
      cwd: this.state.thread?.worktreePath ?? this.cwd, runId: row.turnId ?? '', toTurnCount: String(row.checkpointTurnCount ?? '') } });
  }
  private noticeColor(row: TimelineRow): string {
    if (row.tone === 'warning') return statusColor('waiting', this.color('screen'));
    if (row.tone === 'error') return this.color('danger-foreground');
    if (row.tone === 'success') return statusColor('completed', this.color('screen'));
    return this.color('foreground-secondary');
  }
  @Builder
  private runtimeNotice(row: TimelineRow) {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        AppIcon({ name: row.icon ?? 'info', iconSize: 16, tint: this.noticeColor(row) })
        Text(row.text).fontSize(this.font(13)).fontColor(this.noticeColor(row))
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        AppIcon({ name: this.expandedRows.includes(row.id) ? 'down' : 'chevron', iconSize: 14, tint: this.color('foreground-muted') })
      }.width('100%').constraintSize({ minHeight: 36 }).padding({ left: 4, right: 4, top: 6, bottom: 6 })
        .onClick(() => { this.toggleTranscript(row.id); })
        .accessibilityText(`${this.expandedRows.includes(row.id) ? '收起' : '展开'} ${row.text}`)
      if (this.expandedRows.includes(row.id)) {
        Column({ space: 4 }) {
          Row() {
            Text('详细信息').fontSize(this.font(11)).fontColor(this.color('foreground-muted')).layoutWeight(1)
            Button({ type: ButtonType.Circle }) {
              AppIcon({ name: this.copiedMessageId === row.id ? 'check' : 'copy', iconSize: 15, tint: this.color('foreground-secondary') })
            }.width(32).height(32).padding(0).backgroundColor(Color.Transparent).accessibilityText('复制完整提示')
              .onClick(() => { this.copyMessage(row.detail || row.text, row.id); })
          }.width('100%')
          Scroll() {
            Text(row.detail || row.text).fontSize(this.sizes.codeFontSize).fontFamily('monospace')
              .fontColor(this.color('chat-secondary')).copyOption(CopyOptions.LocalDevice).width('100%')
          }.nestedScroll({ scrollForward: NestedScrollMode.PARENT_FIRST, scrollBackward: NestedScrollMode.PARENT_FIRST })
            .constraintSize({ maxHeight: 260 }).width('100%')
        }.width('100%').padding({ left: 12, right: 8, top: 4, bottom: 12 }).backgroundColor(this.color('chat-reply')).borderRadius(10)
      }
    }.width('100%').padding({ bottom: 4 })
  }
  @Builder
  private toolImageGallery(row: TimelineRow) {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignItems: ItemAlign.Start }) {
      ForEach(row.viewedImages ?? [], (image: ViewedImage, index: number) => {
        ChatImage({ attachment: this.viewedAttachment(image), environmentId: this.params.environmentId,
          gallery: JSON.stringify(viewedImageGallery(row.viewedImages ?? [], this.params.threadId)), galleryIndex: index, commentThreadId: this.params.threadId,
          mediaPath: image.path, mediaThreadId: image.threadId || this.params.threadId, tileWidth: 128, maxHeight: 180,
          online: this.loaded || this.connectionState === 'syncing',
          loadSource: (attachment: ChatAttachment, refresh: boolean) => this.imageSource(attachment, refresh, image) })
          .margin({ right: 8, bottom: 8 })
      }, (image: ViewedImage) => JSON.stringify([image.threadId, image.path]))
    }.width('100%').padding({ left: 4, top: 2 })
  }

  @Builder
  private changesCard(row: TimelineRow) {
    Column({ space: 0 }) {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 8 }) {
          AppIcon({ name: 'branch', iconSize: 17, tint: this.color('foreground-secondary') })
          Text(row.text).fontSize(this.font(14)).fontWeight(FontWeight.Medium).fontColor(this.color('foreground')).layoutWeight(1).textAlign(TextAlign.Start)
          Text(`+${(row.changedFiles ?? []).reduce((sum: number, file: ChangedFile) => sum + (file.additions ?? 0), 0)}`)
            .fontSize(this.font(13)).fontColor('#22A06B')
          Text(`−${(row.changedFiles ?? []).reduce((sum: number, file: ChangedFile) => sum + (file.deletions ?? 0), 0)}`)
            .fontSize(this.font(13)).fontColor(this.color('danger-foreground'))
          AppIcon({ name: 'chevron', iconSize: 13, tint: this.color('foreground-muted') })
        }.width('100%')
      }.width('100%').height(48).padding({ left: 12, right: 12 }).backgroundColor(Color.Transparent)
        .enabled(this.loaded).accessibilityText(`查看${row.text}的差异`).onClick(() => { this.openChanges(row); })
      ForEach((row.changedFiles ?? []).slice(0, 5), (file: ChangedFile) => {
        Row({ space: 8 }) {
          AppIcon({ name: 'file', iconSize: 14, tint: this.color('foreground-muted') })
          Text(file.path).fontSize(this.font(12)).fontColor(this.color('foreground-secondary')).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          Text(`+${file.additions ?? 0}`).fontSize(this.font(12)).fontColor('#22A06B')
          Text(`−${file.deletions ?? 0}`).fontSize(this.font(12)).fontColor(this.color('danger-foreground'))
        }.width('100%').padding({ left: 12, right: 12, top: 8, bottom: 8 })
      }, (file: ChangedFile) => file.path)
      if ((row.changedFiles?.length ?? 0) > 5) {
        Button(`查看全部 ${row.changedFiles?.length ?? 0} 个文件`).fontSize(this.font(12)).fontColor(this.color('md-link'))
          .width('100%').height(36).backgroundColor(Color.Transparent).enabled(this.loaded).onClick(() => { this.openChanges(row); })
      }
    }.width('100%').padding({ bottom: 8 }).margin({ top: 4, bottom: 12 }).borderRadius(16)
      .backgroundColor(this.color('chat-reply')).border({ width: 0.75, color: this.color('chat-outline') })
  }

  @Builder
  private agentsSheet() {
    Column() {
      if (this.turnAgents.length > 0) {
        SubagentGroup({ agents: this.turnAgents, providers: this.timelineProviders, listOnly: true,
          onOpen: (agent: SubagentSummary) => { this.openSubagent(agent); } })
      } else {
        Text('本轮暂无子代理').fontSize(this.font(14)).fontColor(this.color('foreground-secondary')).padding(16)
      }
    }.width('100%').padding({ left: 16, right: 16, top: 4, bottom: 12 })
  }

  @Builder
  private modelSwitchDivider(label: string) {
    if (label) {
      Row({ space: 8 }) {
        Divider().strokeWidth(0.5).color(this.color('border')).layoutWeight(1)
        Text(label).fontSize(this.font(12)).fontColor(this.color('foreground-muted')).textAlign(TextAlign.Center)
          .constraintSize({ maxWidth: '84%' }).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        Divider().strokeWidth(0.5).color(this.color('border')).layoutWeight(1)
      }.width('100%').padding({ top: 8, bottom: 2 })
    }
  }

  private showMessageBody(row: TimelineRow): boolean {
    return row.automationPreview === undefined || this.expandedRows.includes(row.id);
  }

  @Builder
  private automationPromptHeader(row: TimelineRow) {
    Row() {
      Button({ type: ButtonType.Capsule }) {
        Row({ space: 6 }) {
          AppIcon({ name: 'clock', iconSize: 15, tint: this.color('foreground-muted') })
          Text('自动化').fontSize(this.font(12)).fontColor(this.color('foreground-muted')).maxLines(1)
          Text(row.automationPreview ?? '').fontSize(this.font(13)).fontColor(this.color('foreground'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          AppIcon({ name: 'down', iconSize: 13, tint: this.color('foreground-muted') })
            .rotate({ angle: this.expandedRows.includes(row.id) ? 180 : 0 })
        }.width('100%')
      }.width('88%').constraintSize({ minHeight: 40 }).padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .backgroundColor(this.color('chat-user'))
        .border({ width: 0.75, color: this.color('chat-outline') })
        .id(`automation-prompt-${row.id}`).enabled(!this.selectingMessages)
        .accessibilityText(`${this.expandedRows.includes(row.id) ? '收起' : '展开'}自动化提示词：${row.automationPreview ?? ''}`)
        .onClick(() => { this.toggleTranscript(row.id); })
        .bindContextMenu(this.messageMenu(row), ResponseType.LongPress, {
          modalMode: menuModalMode(), hapticFeedbackMode: menuHapticFeedbackMode(),
          onAppear: () => { this.openMessageMenu(row.id + ':automation'); },
          onDisappear: () => { this.closeMessageMenu(); }
        })
        .hitTestBehavior(this.selectingMessages ? HitTestMode.None : HitTestMode.Default)
    }.width('100%').justifyContent(FlexAlign.End).margin({ top: 8, bottom: 6 })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
    Column() {}.width('100%').height('100%').backgroundColor(this.color('card'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM]).hitTestBehavior(HitTestMode.None)
    Column({ space: 8 }) {
      ChatPageHeader() {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Circle }) { AppIcon({ name: 'back', iconSize: 21, tint: this.color('glass-label') }) }.width(36).height(36).padding(0)
          .fontColor(this.color('foreground')).backgroundColor(Color.Transparent).accessibilityText('返回')
          .onClick(() => { if (this.selectingMessages) this.cancelMessageSelection(); else router.back(); })
        Column({ space: 3 }) {
          if (connectionProgressLabel(this.connectionState)) {
            ConnectionProgressBadge({ label: connectionProgressLabel(this.connectionState) }).id('thread-connection-progress')
              .accessibilityDescription(this.cached && this.entries.length > 0 ? '可继续浏览已有消息' : '')
          } else {
            Text(this.parentThreadId ? subagentDisplayTitle(this.composerThread?.title || this.cachedTitle || '子代理', this.cachedTitle) :
              this.composerThread?.title || this.cachedTitle || '对话').fontSize(this.font(16)).fontWeight(FontWeight.Medium)
              .fontColor(this.color('foreground')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
            if (this.loaded && this.elapsed && this.requests.length === 0) {
              Row({ space: 5 }) {
                AppIcon({ name: 'clock', iconSize: 12, tint: this.color('glass-label') })
                Text(this.elapsed.replace('工作了 ', '工作中 ')).fontSize(this.font(12)).fontColor(this.color('glass-label'))
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).flexShrink(1)
              }.id('thread-work-duration')
            } else {
              Row({ space: 8 }) {
                Text(this.projectTitle && this.projectTitle !== 'No project' ? this.projectTitle : '独立任务').fontSize(this.font(11)).fontColor(this.color('glass-label')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: '45%' })
                if (this.composerThread?.branch) {
                  AppIcon({ name: 'branch', iconSize: 12, tint: this.color('glass-label') })
                  Text(this.composerThread?.branch ?? '').fontSize(this.font(11)).fontColor(this.color('glass-label')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                }
                AppIcon({ name: 'down', iconSize: 10, tint: this.color('glass-label') })
              }.width('100%').accessibilityText('切换分支或工作树').onClick(() => { this.branchPickerRequest++; })
            }
          }
        }.alignItems(HorizontalAlign.Start).layoutWeight(1).bindContextMenu(this.threadMenu(), ResponseType.LongPress, { modalMode: menuModalMode() })
        Button({ type: ButtonType.Circle }) { AppIcon({ name: 'folder', iconSize: 21, tint: this.color('glass-label') }) }
          .width(36).height(36).padding(0).backgroundColor(Color.Transparent).accessibilityText('文件')
          .onClick(() => { router.pushUrl({ url: 'pages/Files', params: { cwd: this.state.thread?.worktreePath ?? this.cwd,
            environmentId: this.params.environmentId, threadId: this.params.threadId } }); })
        WorkspaceContext({ iconOnly: true, worktree: !!this.composerThread?.worktreePath, cwd: this.composerThread?.worktreePath ?? this.cwd,
          project: this.workspaceProject, branchPickerRequest: this.branchPickerRequest, getRpc: () => this.rpc,
          threadId: this.params.threadId, pullRequests: this.composerThread?.pullRequests ?? [],
          selectedBranch: this.composerThread?.branch ?? '', showConnection: false,
          disabled: !this.loaded || this.settingsBusy || this.settingsPending || this.sending || this.hasPendingSend, branchDisabled: this.running,
          onMachine: (saved: SavedEnvironment) => { this.chooseMachine(saved); }, onBranch: (ref: WorkspaceRef) => { this.chooseBranch(ref); },
          onFiles: () => { router.pushUrl({ url: 'pages/Files', params: { cwd: this.state.thread?.worktreePath ?? this.cwd,
            environmentId: this.params.environmentId, threadId: this.params.threadId } }); },
          onTerminal: (terminalId: string) => { router.pushUrl({ url: 'pages/Terminal', params: { threadId: this.params.threadId,
            cwd: this.state.thread?.worktreePath ?? this.cwd, terminalId: terminalId } }); },
          onReview: (scope: string) => { router.pushUrl({ url: 'pages/Diff', params: { threadId: this.params.threadId, cwd: this.state.thread?.worktreePath ?? this.cwd,
            scope: scope, toTurnCount: '0' } }); }
        })
        Button({ type: ButtonType.Circle }) { AppIcon({ name: 'terminal', iconSize: 21, tint: this.color('glass-label') }) }
          .width(36).height(36).padding(0).backgroundColor(Color.Transparent).accessibilityText('终端')
          .onClick(() => { router.pushUrl({ url: 'pages/Terminal', params: { threadId: this.params.threadId, cwd: this.state.thread?.worktreePath ?? this.cwd } }); })
      }.width('100%').padding({ left: 8, right: 8 })
      }
      Column({ space: 8 }) {
        if (this.parentThreadId && this.parentThreadId !== this.params.threadId) {
          Button({ type: ButtonType.ROUNDED_RECTANGLE }) {
            Row({ space: 6 }) {
              AppIcon({ name: 'branch', iconSize: 14, tint: this.color('foreground-secondary') })
              Text(this.parentTitle ? `父会话 · ${this.parentTitle}` : '返回父会话')
                .fontSize(this.font(12)).fontColor(this.color('foreground-secondary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).flexShrink(1)
              AppIcon({ name: 'chevron', iconSize: 12, tint: this.color('foreground-muted') })
            }
          }.id('subagent-parent-thread').margin({ top: 8 }).constraintSize({ minHeight: 40, maxWidth: '90%' })
            .padding({ left: 12, right: 12, top: 5, bottom: 5 }).border({ width: 0.75, color: this.color('border'), radius: 14 })
            .backgroundColor(this.color('subtle')).clip(true).accessibilityText(`打开父会话：${this.parentTitle || '父会话'}`)
            .onClick(() => { this.openParentThread(); })
        }
        if (this.responseError) { Text(this.responseError).fontColor(this.color('danger-foreground')).fontSize(this.font(12)).padding({ left: 16, right: 16, top: 8 }) }
        if (this.detailError) { Text(this.detailError).fontColor(this.color('danger-foreground')).fontSize(this.font(12)).padding({ left: 16, right: 16, top: 8 }) }
      Stack({ alignContent: Alignment.Bottom }) {
      Refresh({ refreshing: $$this.refreshingHistory, promptText: '加载更早消息' }) {
      List({ space: 6, scroller: this.scroller }) {
        if (this.hasMoreHistory) {
          ListItem() {
            Button(this.historyLoading ? '正在加载更早消息…' : this.historyError || '加载更早消息')
              .fontSize(this.font(12)).fontColor(this.color('foreground-muted')).backgroundColor(Color.Transparent)
              .width('100%').enabled(this.loaded && !this.historyLoading).onClick(() => { this.loadOlderHistory(); })
          }
        }
        LazyForEach(this.transcriptSource, (entry: TimelineRow) => {
          ListItem() {
            if (entry.kind === 'changes') {
              this.changesCard(entry)
            } else if (entry.kind === 'notice') {
              this.runtimeNotice(entry)
            } else if (entry.kind === 'subagents') {
              SubagentGroup({ agents: entry.subagents ?? [], providers: this.timelineProviders, groupId: entry.id, expanded: this.expandedRows.includes(entry.id),
                disabled: this.selectingMessages, onToggle: () => { this.toggleTranscript(entry.id); },
                onOpen: (agent: SubagentSummary) => { this.openSubagent(agent); } })
            } else if (entry.htmlRender !== undefined) {
              InlineHtmlPreview({ reference: entry.htmlRender, online: this.loaded || this.connectionState === 'syncing',
                originalImageName: this.originalPreviewImage(entry)?.name ?? '',
                loadSource: (reference: HtmlRenderReference) => this.htmlPreviewSource(reference),
                onOpenOriginal: () => { this.openOriginalPreviewImage(entry); } })
                .hitTestBehavior(this.selectingMessages ? HitTestMode.None : HitTestMode.Default)
            } else if (entry.itemType === 'compaction') {
              Column({ space: 4 }) {
                this.modelSwitchDivider(entry.text)
                if (entry.detail && this.expandedRows.includes(entry.id)) {
                  Text(entry.detail).fontSize(this.font(12)).fontColor(this.color('foreground-secondary')).copyOption(CopyOptions.LocalDevice).padding(8)
                }
              }.width('100%').onClick(() => { if (entry.detail) this.toggleTranscript(entry.id); })
                .accessibilityText(entry.detail ? `${entry.text}，${this.expandedRows.includes(entry.id) ? '收起' : '展开'}摘要` : entry.text)
            } else if (entry.kind === 'duration') {
              Text(entry.text).fontSize(this.font(12)).fontColor(this.color('foreground-muted')).width('100%').padding({ top: 3, bottom: 12 })
            } else if (entry.kind === 'tool' || entry.kind === 'tools' || entry.kind === 'turn' || entry.kind === 'activity' || entry.kind === 'thinking' || entry.kind === 'question') {
              Column({ space: 4 }) {
                Row({ space: 8 }) {
                  if (entry.kind === 'thinking' && entry.streaming === true) {
                    WorkStatus({ label: reasoningTitle(entry.text, true), active: this.loaded && this.running }).layoutWeight(1)
                  } else {
                  if (entry.kind !== 'turn') {
                    AppIcon({ name: entry.icon ?? (entry.kind === 'thinking' ? 'thinking' : 'terminal'), iconSize: 15, tint: this.color('foreground-muted') })
                  }
                  Text(entry.kind === 'thinking' ? reasoningTitle(entry.text, entry.streaming === true) + ((entry.groupCount ?? 0) > 1 ? ` (${entry.groupCount} 段)` : '') : entry.text.replace(/\s+/g, ' ')).fontSize(this.font(13)).fontColor(this.color('foreground-muted'))
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                  if (entry.kind === 'question' && entry.answerPreview) {
                    Text(entry.answerPreview).fontSize(this.font(13)).fontColor(this.color('foreground'))
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: '42%' })
                  }
                  }
                  if (entry.kind !== 'thinking' || entry.streaming !== true) {
                    AppIcon({ name: this.expandedRows.includes(entry.id) ? 'down' : 'chevron', iconSize: 14, tint: this.color('foreground-muted') })
                  }
                }.constraintSize({ minHeight: 32 }).width('100%').padding({ left: 4, right: 4, top: 7, bottom: 7 })
                  .onClick(() => { if (entry.kind !== 'thinking' || entry.streaming !== true) this.toggleTranscript(entry.id); })
                  .accessibilityText(entry.kind === 'thinking' && entry.streaming ? '正在思考' : `${this.expandedRows.includes(entry.id) ? '收起' : '展开'} ${entry.text}${entry.answerPreview ? '，' + entry.answerPreview : ''}`)
                if ((entry.viewedImages?.length ?? 0) > 0) { this.toolImageGallery(entry) }
                if ((entry.kind === 'tool' || entry.kind === 'activity' || entry.kind === 'question' || (entry.kind === 'thinking' && entry.streaming !== true)) && this.expandedRows.includes(entry.id)) {
                  if (entry.kind === 'thinking') {
                    Text(reasoningBody(entry.text)).fontSize(this.font(13)).lineHeight(this.font(21)).fontColor(this.color('chat-secondary'))
                      .copyOption(CopyOptions.LocalDevice).padding(12).width('100%').backgroundColor(this.color('chat-reply')).borderRadius(10)
                      .border({ width: { left: 2 }, color: this.color('border') })
                  } else {
                  Text(entry.status).fontSize(this.font(11)).fontColor(this.color('foreground-muted')).width('100%')
                  if (entry.kind === 'question' && (entry.attachments ?? []).some((attachment: ChatAttachment) => attachment.type === 'image')) {
                    AttachmentGallery({ attachments: (entry.attachments ?? []).filter((attachment: ChatAttachment) => attachment.type === 'image'),
                      environmentId: this.params.environmentId, threadId: this.params.threadId, online: this.loaded || this.connectionState === 'syncing',
                      loadSource: (image: ChatAttachment, refresh: boolean) => this.imageSource(image, refresh) })
                  }
                  if (this.detailLoading.includes(entry.id)) {
                    Text('正在读取详细输出…').fontSize(this.font(12)).fontColor(this.color('foreground-muted'))
                  } else {
                    Scroll() {
                      if (entry.itemType === 'proposed_plan') {
                        MarkdownText({ content: entry.detail, inBubble: true, cwd: this.state.thread?.worktreePath ?? this.cwd, environmentId: this.params.environmentId, threadId: entry.sourceThreadId ?? this.params.threadId })
                      } else {
                        Text(entry.detail || '暂无详细输出').fontFamily(entry.kind === 'question' ? 'sans-serif' : 'monospace')
                          .fontSize(entry.kind === 'question' ? this.font(13) : this.sizes.codeFontSize)
                          .fontColor(this.color('chat-secondary')).copyOption(CopyOptions.LocalDevice).width('100%').padding(12)
                      }
                    }.nestedScroll({ scrollForward: NestedScrollMode.PARENT_FIRST, scrollBackward: NestedScrollMode.PARENT_FIRST }).constraintSize({ maxHeight: 240 }).width('100%').backgroundColor(this.color('chat-reply')).borderRadius(8)
                  }
                  }
                }
              }.width('100%').padding({ left: entry.depth === 1 ? 14 : 0, bottom: 2 })
            } else {
              Column({ space: 3 }) {
              if (entry.modelSwitch !== undefined) {
                this.modelSwitchDivider(modelSwitchLabel(entry.modelSwitch, this.timelineProviders))
              }
              if (this.selectingMessages && canForwardMessage(entry)) {
                Row() {
                  Button({ type: ButtonType.Circle }) {
                    if (this.selectedMessageIds.includes(entry.id)) { AppIcon({ name: 'check', iconSize: 17, tint: '#FFFFFF' }) }
                    else { Circle().width(20).height(20).fill(Color.Transparent).stroke(this.color('foreground-muted')).strokeWidth(1.5) }
                  }.width(36).height(36).padding(0).backgroundColor(this.selectedMessageIds.includes(entry.id) ? '#3268F5' : Color.Transparent)
                    .accessibilityText(this.selectedMessageIds.includes(entry.id) ? '取消选择消息' : '选择消息')
                    .onClick(() => { this.selectMessage(entry); })
                  Blank()
                }.width('100%')
              }
              if (entry.automationPreview !== undefined) {
                this.automationPromptHeader(entry)
              }
              if (this.showMessageBody(entry) && (entry.attachments ?? []).some((attachment: ChatAttachment) => attachment.type === 'image')) {
                Row() {
                  Column() {
                    AttachmentGallery({ attachments: (entry.attachments ?? []).filter((attachment: ChatAttachment) => attachment.type === 'image'),
                      environmentId: this.params.environmentId, threadId: this.params.threadId, online: this.loaded || this.connectionState === 'syncing',
                      loadSource: (image: ChatAttachment, refresh: boolean) => this.imageSource(image, refresh) })
                  }.width('88%').constraintSize({ maxWidth: 400 }).borderRadius(16)
                    .border({ width: (entry.attachments ?? []).filter((image: ChatAttachment) => image.type === 'image').length > 1 ? 0.75 : 0, color: this.color('chat-outline') })
                    .scale({ x: this.pressedMessageKey === entry.id + ':images' ? 0.985 : 1, y: this.pressedMessageKey === entry.id + ':images' ? 0.985 : 1 })
                    .animation({ duration: 120, curve: Curve.EaseOut })
                    .onTouch((event: TouchEvent) => { this.touchMessage(entry.id + ':images', event); })
                    .bindContextMenu(this.messageMenu(entry), ResponseType.LongPress, {
                      modalMode: menuModalMode(), hapticFeedbackMode: menuHapticFeedbackMode(),
                      onAppear: () => { this.openMessageMenu(entry.id + ':images'); },
                      onDisappear: () => { this.closeMessageMenu(); }
                    })
                    .hitTestBehavior(this.selectingMessages ? HitTestMode.None : HitTestMode.Default)
                }.width('100%').justifyContent(entry.role === 'user' ? FlexAlign.End : FlexAlign.Start)
                  .margin({ top: entry.automationPreview === undefined ? 16 : 0, bottom: 8 })
              }
              if (this.showMessageBody(entry) && (entry.text.trim().length > 0 || this.messageFiles(entry).length > 0 || entry.status === 'queued')) {
              Row() {
              Column({ space: 8 }) {
                if (parseQuotedMessage(entry.text).quote !== null) {
                  MessageQuoteCard({ quote: parseQuotedMessage(entry.text).quote, disabled: this.selectingMessages,
                    images: messageQuoteImages(parseQuotedMessage(entry.text).quote, this.entries, this.params.environmentId, this.params.threadId),
                    online: this.loaded, loadSource: (image: ChatAttachment, refresh: boolean) => this.imageSource(image, refresh),
                    locating: this.quoteTargetId === parseQuotedMessage(entry.text).quote?.messageId,
                    onLocate: () => { this.locateQuote(parseQuotedMessage(entry.text).quote); } })
                }
                if (this.messageFiles(entry).length > 0) {
                  AttachmentText({ attachments: this.messageFiles(entry), environmentId: this.params.environmentId, threadId: entry.sourceThreadId ?? this.params.threadId })
                }

                ForEach(parseCommentMessage(parseQuotedMessage(entry.text).text), (part: CommentSegment) => {
                  if (part.kind === 'comment') {
                    Column({ space: 8 }) {
                      Text(part.filePath ?? '').fontSize(this.font(14)).fontWeight(FontWeight.Medium)
                        .fontColor(this.color('foreground')).width('100%').copyOption(CopyOptions.None)
                      Text(part.rangeLabel ?? '').fontSize(this.font(12)).fontColor(this.color('foreground-muted')).width('100%')
                      Text(part.diff ?? '').fontFamily('monospace').fontSize(this.sizes.codeFontSize).fontColor(this.color('md-code-text'))
                        .width('100%').padding(8).backgroundColor(this.color('screen')).copyOption(CopyOptions.None)
                      MarkdownText({ content: part.text, selectable: false, cwd: this.state.thread?.worktreePath ?? this.cwd, environmentId: this.params.environmentId, threadId: entry.sourceThreadId ?? this.params.threadId })
                    }.padding(10).width('100%').borderRadius(8).backgroundColor(this.color('card'))
                  } else if (entry.role === 'user' && ((entry.attachments?.length ?? 0) > 0 || (this.hasMessageSkill(part.text) && !/[\[\]`*_#<>~]/.test(part.text)))) {
                    AttachmentText({ text: part.text, selectable: false, referencesDisabled: this.selectingMessages, skills: this.messageSkills(), messageContext: entry.context, attachments: entry.attachments ?? [], showFiles: false,
                      environmentId: this.params.environmentId, threadId: entry.sourceThreadId ?? this.params.threadId })
                  } else if (entry.role === 'user' && !/[\[\]`*_#<>~]/.test(part.text)) {
                    Text(part.text).fontSize(this.sizes.baseFontSize).lineHeight(this.font(24)).fontColor(this.color('foreground'))
                      .copyOption(CopyOptions.None)
                  } else {
                    MarkdownText({ content: part.text, inBubble: true, selectable: false, referencesDisabled: this.selectingMessages, skills: entry.role === 'user' ? this.messageSkills() : [], messageContext: entry.context, cwd: this.state.thread?.worktreePath ?? this.cwd,
                      environmentId: this.params.environmentId, threadId: entry.sourceThreadId ?? this.params.threadId })
                  }
                })
                if (entry.status === 'queued') {
                  StatusIndicator({ label: '排队中 · 当前回复结束后继续', tint: statusColor('queued', this.color('screen')) })
                }
              }
              .alignItems(HorizontalAlign.Start)
              .padding(13)
              .borderRadius(16)
              .backgroundColor(this.color(entry.role === 'user' ? 'chat-user' : 'chat-reply'))
              .border({ width: 0.75, color: this.color(this.pressedMessageKey === entry.id + ':text' || this.menuMessageKey === entry.id + ':text' ? 'foreground-secondary' : 'chat-outline') })
              .scale({ x: this.pressedMessageKey === entry.id + ':text' ? 0.985 : 1, y: this.pressedMessageKey === entry.id + ':text' ? 0.985 : 1 })
              .animation({ duration: 120, curve: Curve.EaseOut })
              .onTouch((event: TouchEvent) => { this.touchMessage(entry.id + ':text', event); })
              .bindContextMenu(this.messageMenu(entry), ResponseType.LongPress, {
                modalMode: menuModalMode(), hapticFeedbackMode: menuHapticFeedbackMode(),
                onAppear: () => { this.openMessageMenu(entry.id + ':text'); },
                onDisappear: () => { this.closeMessageMenu(); }
              })
              .width(entry.role === 'user' && entry.automationPreview === undefined && !/[\[\]`*_#<>~]/.test(entry.text) &&
                (entry.attachments?.length ?? 0) === 0 ? undefined : '88%')
              .constraintSize({ maxWidth: '88%' })
              .margin({ top: entry.automationPreview === undefined ? 16 : 0, bottom: 12 })
              }.width('100%').justifyContent(entry.role === 'user' ? FlexAlign.End : FlexAlign.Start)
              }
              if (entry.role === 'user' && !this.selectingMessages && this.showMessageBody(entry)) {
                Row({ space: 7 }) {
                  if (entry.delivery === 'steer') {
                    AppIcon({ name: 'steer', iconSize: 13, tint: this.color('foreground-muted') })
                    Text('插队').fontSize(this.font(11)).fontColor(this.color('foreground-muted'))
                  }
                  Text(this.messageTime(messageTimeValue(entry))).fontSize(this.font(11)).fontColor(this.color('foreground-muted'))
                  if (this.historyEditIds.includes(entry.id)) {
                    Button({ type: ButtonType.Circle }) { AppIcon({ name: 'edit', iconSize: 15, tint: this.color('foreground-muted') }) }
                      .width(36).height(36).padding(0).backgroundColor(Color.Transparent).id(`edit-history-${entry.id}`)
                      .enabled(this.canStartHistoryEdit()).accessibilityText('从此处编辑').onClick(() => { this.confirmHistoryEdit(entry); })
                  }
                  Button({ type: ButtonType.Circle }) { AppIcon({ name: this.copiedMessageId === entry.id ? 'check' : 'copy', iconSize: 13, tint: this.color('foreground-muted') }) }
                    .width(30).height(30).padding(0).backgroundColor(Color.Transparent).accessibilityText('复制消息')
                    .onClick(() => { this.copyMessage(entry.text, entry.id); })
                }.width('100%').justifyContent(FlexAlign.End).padding({ bottom: 8, right: 4 })
              } else if (!this.selectingMessages && this.assistantActions.includes(entry.id)) {
                Row({ space: 8 }) {
                  Button({ type: ButtonType.Circle }) { AppIcon({ name: this.copiedMessageId === entry.id ? 'check' : 'copy', iconSize: 14, tint: this.color('foreground-muted') }) }
                    .width(30).height(30).padding(0).backgroundColor(Color.Transparent).accessibilityText('复制回复')
                    .onClick(() => { this.copyMessage(entry.text, entry.id); })
                  Button({ type: ButtonType.Circle }) {
                    if (this.forkingMessageId === entry.id) { LoadingProgress().width(15).height(15).color(this.color('foreground-muted')) }
                    else { AppIcon({ name: 'branch', iconSize: 15, tint: this.color('foreground-muted') }) }
                  }.width(30).height(30).padding(0).backgroundColor(Color.Transparent).accessibilityText('从这条回复分叉会话')
                    .enabled(this.loaded && !this.forkingMessageId && !!entry.turnId).onClick(() => { this.forkMessage(entry); })
                  Text(this.messageTime(messageTimeValue(entry))).fontSize(this.font(11)).fontColor(this.color('foreground-muted'))
                }.width('100%').padding({ bottom: 8, left: 4 })
              }
              }.width('100%')
                .backgroundColor(this.highlightedMessageId === entry.id ? this.color('subtle-strong') :
                  this.selectingMessages && this.selectedMessageIds.includes(entry.id) ? this.color('subtle') : Color.Transparent)
                .borderRadius(16).onClick(() => { if (this.selectingMessages) this.selectMessage(entry); })
            }
          }.onAreaChange(() => {
            if (entry.id === this.entries[this.entries.length - 1]?.id) { this.follow.resized(); this.scheduleFollowScroll(); }
          })
        }, (entry: TimelineRow) => this.transcriptSource.key(entry))
        if (this.needsThinking()) {
          ListItem() {
            Row({ space: 8 }) {
              WorkStatus({ active: this.loaded && this.running }).layoutWeight(1)
            }.padding({ top: 8, bottom: 12 }).width('100%')
          }
        }
      }
      .height('100%').width('100%').padding({ left: 16, right: 16 }).contentStartOffset(8)
      .contentEndOffset(this.composerHeight + 8)
      // The list, refresh viewport and rounded card all need to draw past the composer’s safe bounds.
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .scrollBar(BarState.Auto).scrollBarWidth(2)
      .scrollBarColor('#66' + this.color('foreground-muted').slice(1))
      .onScrollIndex((start: number) => { this.firstVisibleIndex = start; })
      .onReachStart(() => { if (!this.follow.following && this.entries.length > 0 && !this.historyError) this.loadOlderHistory(); })
      .onWillScroll((offset: number, _state: ScrollState, source: ScrollSource) => {
        if (offset !== 0) this.pressedMessageKey = '';
        this.userScrolling = offset !== 0 && [ScrollSource.DRAG, ScrollSource.FLING, ScrollSource.OTHER_USER_INPUT, ScrollSource.SCROLL_BAR, ScrollSource.SCROLL_BAR_FLING].includes(source);
      })
      .onDidScroll((offset: number) => {
        this.follow.viewport(this.scroller.isAtEnd(), this.userScrolling && offset !== 0);
        this.userScrolling = false;
        this.showingHistory = !this.follow.following;
        this.markCurrentRead();
      })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) { this.cancelQuoteNavigation(); this.follow.touchStart(); }
        if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.follow.touchEnd(); this.scheduleFollowScroll();
        }
      })
      .onScrollStop(() => { this.userScrolling = false; this.markCurrentRead(); })
      .onAreaChange(() => { this.follow.resized(); this.scheduleFollowScroll(); })
      }.width('100%').height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        .refreshOffset(64).pullToRefresh(this.loaded && this.hasMoreHistory && !this.historyLoading)
        .onRefreshing(() => { this.pullOlderHistory(); })

      Column({ space: 8 }) {
        if (this.imageRequestBusy) {
          FloatingNotice({ text: '正在提交图片编辑请求…', busy: true })
        } else if (this.sending) {
          FloatingNotice({ text: this.imagesUploaded() ? '正在发送…' : '正在上传附件，完成后发送…', busy: true })
        } else if (this.sendError) {
          FloatingNotice({ text: this.sendError, danger: true })
        } else if (this.operationError) {
          FloatingNotice({ text: this.operationError, danger: true })
          if (this.operationError.startsWith('图片编辑请求')) {
            Button('重试图片编辑请求').fontSize(this.font(12)).height(34).onClick(() => { this.attemptedImageRequest = ''; this.receiveImageComment(); })
          }
        }
        if (this.showingHistory) {
          ChatGlass({ capsule: true, compact: true, radius: 18 }) {
            Button({ type: ButtonType.Circle }) { AppIcon({ name: 'latest', iconSize: 18, tint: this.color('foreground-secondary') }) }
              .width(36).height(36).padding(0).backgroundColor(Color.Transparent)
              .accessibilityText('回到最新消息').onClick(() => { this.jumpToLatest(); })
          }
        }
      }.width('100%').padding({ bottom: 8 }).margin({ bottom: this.composerHeight }).responseRegion({ width: 0, height: 0 })

      // Only the overlay's visible children own touches; empty margins still reach the transcript.
      Column({ space: 8 }) {
      if (this.selectingMessages) {
        this.selectionActions()
      } else if (!this.nativeSubagent) {
      if (this.rewindStatus) {
        Text(this.rewindStatus).fontSize(this.font(12)).fontColor(this.color('foreground-secondary')).width('100%').padding(8)
      }
      if (this.hasPendingSend && !this.sending) {
        Row({ space: 8 }) {
          Text('发送结果待确认，重试不会重复发送').fontColor(this.color('foreground-muted')).fontSize(this.font(12)).layoutWeight(1)
          Button({ type: ButtonType.Circle }) { AppIcon({ name: 'refresh', iconSize: 18, tint: this.color('foreground-secondary') }) }
            .width(36).height(36).padding(0).backgroundColor(this.color('card')).enabled(this.loaded)
            .accessibilityText('重试发送').onClick(() => { this.retryPending(); })
        }.width('100%').padding({ left: 10, right: 4 })
      }
      if (this.requests.length === 0 && (this.turnAgents.length > 0 || this.queue.length > 0 || this.browserTabs.length > 0)) {
        ChatGlass({ capsule: true, compact: true, radius: 20 }) {
          Row({ space: 8 }) {
            if (this.turnAgents.length > 0) {
              Button({ type: ButtonType.Normal }) {
                Row({ space: 5 }) {
                  AppIcon({ name: 'agents', iconSize: 15, tint: this.color('foreground-secondary') })
                  Text(subagentPillLabel(this.turnAgents)).fontSize(this.font(12)).fontColor(this.color('foreground-secondary'))
                }
              }.id('thread-agents').height(32).padding({ left: 7, right: 7 }).backgroundColor(Color.Transparent)
                .accessibilityText(`查看子代理，${subagentPillLabel(this.turnAgents)}`).onClick(() => { this.agentsOpen = true; })
            }
            if (this.browserTabs.length > 0) {
              Button({ type: ButtonType.Normal }) {
                Row({ space: 5 }) {
                  AppIcon({ name: 'globe', iconSize: 15, tint: this.color('foreground-secondary') })
                  if (this.browserTabs.length) { Text(String(this.browserTabs.length)).fontSize(this.font(12)).fontColor(this.color('foreground-secondary')) }
                }
              }.id('thread-browser').height(32).padding({ left: 7, right: 7 }).backgroundColor(Color.Transparent).accessibilityText(`浏览器，${this.browserTabs.length} 个标签页`)
                .onClick(() => { router.pushUrl({ url: 'pages/Browser', params: { threadId: this.params.threadId, environmentId: this.params.environmentId } }); })
            }
            if (this.queue.length > 0) {
              Button({ type: ButtonType.Normal }) {
                Row({ space: 6 }) {
                  AppIcon({ name: 'queue', iconSize: 15, tint: statusColor('queued', this.color('screen')) })
                  Text(`${this.queue.length}`).fontSize(this.font(13)).fontColor(this.color('foreground-secondary'))
                }
              }.backgroundColor(Color.Transparent).height(32).padding({ left: 6, right: 6 })
                .accessibilityText(`查看 ${this.queue.length} 条排队消息`).onClick(() => { this.queueOpen = true; this.queueError = ''; })
            }
          }.height(38).padding({ left: 14, right: 14 }).borderRadius(20)
            .bindSheet($$this.queueOpen, this.queueSheet(), { systemMaterial: immersiveMaterial('popup'), height: SheetSize.LARGE, title: { title: '排队消息' },
              dragBar: true, showClose: true })
        }
      }
      if (this.requests.length > 0 && !this.editingQueue) {
        ForEach(this.requests.slice(0, 1), (request: PendingRequest) => {
          RequestCard({ request: request, busy: this.responding, online: this.loaded, environmentId: this.params.environmentId, threadId: this.params.threadId,
            canAttach: this.canAttachQuestions, maxFileBytes: this.maxFileBytes, maxHeight: Math.max(220, this.viewportHeight * 0.76), canStop: this.running,
            onStop: () => { this.stop(); },
            onRespond: (decision: string, answers: Record<string, string | string[]>, attachments: Record<string, ChatAttachment[]>, dismiss: boolean) =>
              this.respond(request, decision, answers, attachments, dismiss) })
        }, (request: PendingRequest) => request.requestId)
      } else {
      if (this.branchChange !== null) {
        ChatGlass() {
          Row({ space: 8 }) {
            AppIcon({ name: 'branch', iconSize: 16, tint: this.color('foreground-muted') })
            Column({ space: 3 }) {
              Text(`原分支 ${this.branchChange.threadBranch}`).fontSize(this.font(12)).fontColor(this.color('foreground-secondary'))
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(`继续发送将使用 ${this.branchChange.currentBranch}`).fontSize(this.font(11)).fontColor(this.color('foreground-muted'))
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Button(this.restoringBranch ? '恢复中…' : '恢复分支').fontSize(this.font(12)).height(36)
              .padding({ left: 8, right: 8 }).backgroundColor(Color.Transparent).fontColor(this.color('foreground'))
              .enabled(this.loaded && !this.settingsBusy && !this.settingsPending && !this.running && !this.sending && !this.hasPendingSend)
              .accessibilityText(`恢复原分支 ${this.branchChange.threadBranch}`).onClick(() => { this.restoreThreadBranch(); })
            Button({ type: ButtonType.Circle }) { AppIcon({ name: 'close', iconSize: 15, tint: this.color('foreground-muted') }) }
              .width(32).height(32).padding(0).backgroundColor(Color.Transparent).accessibilityText('关闭分支变更提示')
              .onClick(() => { this.dismissBranchChange(); })
          }.width('100%').padding({ left: 12, right: 6, top: 7, bottom: 7 }).borderRadius(16)
        }
      }
      Column({ space: 0 }) {
      CommandSuggestions({ availableHeight: this.viewportHeight, text: this.draft, start: this.pathStart, end: this.pathEnd,
        commands: commandsFor(this.commandCatalog, this.composerThread?.modelSelection?.instanceId ?? '', this.state.thread?.worktreePath ?? this.cwd,
          true, this.state.thread?.lineage?.sideChat !== true && this.state.thread?.lineage?.relationshipToParent !== 'subagent'),
        disabled: !this.draftReady || this.hasPendingSend || this.sending,
        paths: this.pathEntries, pathActive: this.pathActive, pathLoading: this.pathLoading, pathStatus: this.pathStatus,
        onSelectPath: (entry: ComposerPathEntry) => { this.selectPath(entry); },
        onSelect: (command: SlashCommand) => { this.selectCommand(command); } })
      ChatGlass() {
      Column({ space: 4 }) {
      if (this.settingsError) {
        Text(this.settingsError).fontColor(this.color('danger-foreground')).fontSize(this.font(12))
          .onClick(() => { if (!this.modelDraftReady) this.loadModelDraft(); else this.outbox?.flush(this.params.threadId); })
      }
      if (this.draftStatus.length > 0 && this.draftStatus !== '草稿已保存' && this.draftStatus !== '正在保存草稿…') { Text(this.draftStatus).fontSize(this.font(12)).fontColor(this.color('glass-label')) }
      if (this.editingQueue) {
        Row({ space: 8 }) {
          AppIcon({ name: 'edit', iconSize: 16, tint: this.color('primary') })
          Text(this.queue.some((message: QueuedMessage) => message.runId === this.editingQueue?.runId) ? '编辑排队消息 · 保存后继续排队' : '消息已离开队列 · 修改已保留').fontSize(this.font(12)).fontColor(this.color('glass-label')).layoutWeight(1)
          Button({ type: ButtonType.Circle }) { AppIcon({ name: 'close', iconSize: 17, tint: this.color('glass-label') }) }.width(32).height(32).padding(0).backgroundColor(Color.Transparent)
            .enabled(!this.sending && !this.pickingImage).accessibilityText('取消编辑，恢复原草稿').onClick(() => { this.cancelQueueEdit(); })
        }.width('100%').padding({ left: 8, right: 4 })
      }
      if (this.attachmentCount() > 0) {
        DraftImages({ environmentId: this.params.environmentId, threadId: this.params.threadId, draftScope: this.editingQueue?.runId ?? '', online: this.loaded,
          loadSource: (image: ChatAttachment, refresh: boolean) => this.imageSource(image, refresh), images: this.imageItems(), disabled: this.hasPendingSend || this.sending || this.pickingImage,
          onRemove: (uri: string) => { this.removeImage(uri); }, onRetry: (uri: string) => { this.retryImage(uri); } })
      }
      if (this.draftQuote !== null) {
        MessageQuoteCard({ quote: this.draftQuote, removable: true, disabled: this.hasPendingSend || this.sending,
          images: messageQuoteImages(this.draftQuote, this.entries, this.params.environmentId, this.params.threadId),
          online: this.loaded, loadSource: (image: ChatAttachment, refresh: boolean) => this.imageSource(image, refresh),
          locating: this.quoteTargetId === this.draftQuote.messageId,
          onLocate: () => { this.locateQuote(this.draftQuote); }, onRemove: () => { this.removeQuote(); } })
      }
      Row({ space: 4 }) {
        ComposerActions({ disabled: !this.draftReady || !this.journalReady || this.hasPendingSend || this.sending,
          canAttach: this.imagesReady && !this.pickingImage && this.attachmentCount() < 8, canAttachFiles: true,
          onPhotos: () => { this.pickImages(); }, onFiles: () => { this.pickFiles(); },
          onInsert: (trigger: string) => { this.insertShortcut(trigger); } })
        ComposerEditor({ text: this.draft, control: this.composerController, placeholderColor: this.color('glass-label'),
          commands: commandsFor(this.commandCatalog, this.composerThread?.modelSelection?.instanceId ?? '', this.state.thread?.worktreePath ?? this.cwd),
          disabled: !this.draftReady || !this.journalReady || this.hasPendingSend || this.sending,
          onChange: (value: string) => { this.sendError = ''; this.editDraft(value); },
          onSelection: (start: number, end: number) => { this.updatePathSearch(start, end); }, onSend: () => { this.send(); }
        }).layoutWeight(1)

        if (this.editingQueue) {
          Button({ type: ButtonType.Circle }) {
            if (this.sending) { LoadingProgress().width(19).height(19).color('#FFFFFF') }
            else { AppIcon({ name: 'check', iconSize: 22, tint: '#FFFFFF' }) }
          }.height(40).width(40).padding(0).backgroundColor('#3268F5').accessibilityText('保存排队消息修改').enabled(this.canSaveQueueEdit()).onClick(() => { this.saveQueueEdit(); })
        } else if (this.running && !this.draftQuote && !this.draft.trim() && this.imageUris.length === 0) {
          Button({ type: ButtonType.Circle }) {
            if (this.stopping) { LoadingProgress().width(19).height(19).color(this.color('danger-foreground')) }
            else { AppIcon({ name: 'stop', iconSize: 17, tint: this.color('danger-foreground') }) }
          }.height(40).width(40).padding(0).backgroundColor('#33EF4444').accessibilityText(this.stopping ? '停止中' : '停止当前执行')
            .enabled(this.loaded && !this.stopping).onClick(() => { this.stop(); })
        } else if (this.interrupted && !this.draftQuote && !this.draft.trim() && this.imageUris.length === 0) {
          Button({ type: ButtonType.Circle }) { AppIcon({ name: 'play', iconSize: 21, tint: '#FFFFFF' }) }
            .width(40).height(40).padding(0).backgroundColor('#3268F5').accessibilityText('继续已中断的任务')
            .enabled(this.canContinue()).onClick(() => { this.continueInterrupted(); })
        } else {
          Button({ type: ButtonType.Circle }) {
            if (this.sending) { LoadingProgress().width(19).height(19).color('#FFFFFF') }
            else { AppIcon({ name: this.running ? 'steer' : 'send', iconSize: 21, tint: '#FFFFFF' }) }
          }.width(40).height(40).padding(0).backgroundColor('#3268F5')
            .accessibilityText(this.running ? '立即插队发送，长按选择排队' : '发送')
            .enabled(this.canSend()).onClick(() => { this.send(); })
            .bindContextMenu(this.sendMenu(), ResponseType.LongPress, { modalMode: menuModalMode() })
        }
      }.width('100%').alignItems(VerticalAlign.Center)
        if (!this.editingQueue) {
        ComposerSettings({ models: this.models, iconOnly: false, selection: this.composerThread?.modelSelection ?? null, modelPickerRequest: this.modelPickerRequest,
          runtimeMode: this.composerThread?.runtimeMode ?? '', interactionMode: this.composerThread?.interactionMode ?? '',
          disabled: this.composerThread === null || !this.modelDraftReady || this.settingsBusy || this.sending || this.hasPendingSend,
          error: this.settingsError,
          statusMessage: !this.loaded ? '正在同步会话…' : !this.modelDraftReady ? '正在读取模型选择…' :
            this.pendingModelSelection !== null ? this.running ? '下一条消息使用所选模型；当前任务继续运行' : '下一条消息使用所选模型' : '',
          onModel: (selection: ModelSelection) => { this.updateComposerSetting('model', '', selection); },
          onOptions: (selection: ModelSelection) => { this.updateComposerSetting('options', '', selection); },
          onMode: (kind: string, value: string) => { this.updateComposerSetting(kind, value); }
        })
        }
      }.padding({ left: 6, right: 8, top: 6, bottom: 6 }).width('100%')
      }
      }.width('100%')
      }
      }
      }.width('100%').padding({ left: 16, right: 16, bottom: this.nativeSubagent && !this.selectingMessages ? 0 : 12 }).responseRegion({ width: 0, height: 0 })
        .onAreaChange((_old: Area, area: Area) => {
          const height = Number(area.height);
          if (height >= 0 && height !== this.composerHeight) {
            this.composerHeight = height;
            this.follow.resized(); this.scheduleFollowScroll();
          }
        })
      }.layoutWeight(1).width('100%')
      }.layoutWeight(1).width('100%').borderRadius({ topLeft: 28, topRight: 28 }).backgroundColor(this.color('card')).clip(true)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])

    }
    .width('100%')
    .height('100%')
    .onAreaChange((_old: Area, area: Area) => { const height = Number(area.height); if (height > 0 && height !== this.viewportHeight) this.viewportHeight = height; })
    .backgroundColor(this.color('screen'))
    .bindSheet($$this.agentsOpen, this.agentsSheet(), { systemMaterial: immersiveMaterial('popup'), height: SheetSize.FIT_CONTENT, detents: [SheetSize.FIT_CONTENT, SheetSize.LARGE],
      title: { title: '子代理' }, showClose: true, dragBar: true })
    }.width('100%').height('100%').backgroundColor(this.color('screen'))
    .bindSheet($$this.forwardOpen, this.forwardSheet(), { systemMaterial: immersiveMaterial('popup'), height: SheetSize.LARGE, title: { title: '转发消息' },
      dragBar: true, showClose: true,
      onWillDismiss: () => { if (!this.forwardBusy) this.forwardOpen = false; } })
  }
}
