import { menuIcon, menuModalMode } from './MenuIcon';
import { ChatGlass, immersiveMaterial } from './ChatGlass';
import { ProjectPicker } from './ProjectPicker';
import { ComposerEditor, ComposerEditorController } from './ComposerEditor';
import { ProjectIcon } from './ProjectIcon';
import { AppIcon } from './AppIcon';
import { DraftImages, DraftImageProgress } from './DraftImages';
import { AttachmentDraftStore, DraftImage } from '../connection/AttachmentDraftStore';
import { uploadImage, imageUploadExists, deleteImageUpload } from '../connection/ImageAttachment';
import { fileUploadLimit } from '../model/FileAttachments';
import picker from '@ohos.file.picker';
import photoAccessHelper from '@ohos.file.photoAccessHelper';
import fileUri from '@ohos.file.fileuri';
import { CommandSuggestions } from './CommandSuggestions';
import { ClientCache } from '../connection/ClientCache';
import { ProviderCommandCatalog, SlashCommand, commandCatalog as buildCommandCatalog, commandsFor, commandQuery, insertCommand } from '../model/ComposerCommands';
import { ComposerSettings } from './ComposerSettings';
import { ComposerActions } from './ComposerActions';
import { insertComposerTrigger } from '../model/ComposerCommands';
import { WorkspaceContext, WorkspaceRef } from './WorkspaceContext';
import { SavedEnvironment } from '../connection/EnvironmentStore';
import { ComposerPathTrigger, ComposerPathEntry, composerPathTrigger, composerPathEntries, insertComposerEntry } from '../model/ComposerPath';
import { FileEntry } from '../model/FileEntries';
import { Typography, resolveTypography, scaledFontSize } from '../model/Typography';
import { ThemeRuntime } from '../connection/ThemeRuntime';
import util from '@ohos.util';
import { EnvironmentSession, PreparedConnection } from '../connection/Environment';
import { EmptyPayload, RpcRemoteError } from '../connection/Rpc';
import { CreateTaskCommand, NewTaskDraft, NewTaskDraftStore } from '../connection/NewTaskDraftStore';
import { ProjectShell, ModelChoice, ModelSelection, ModelOptionSelection, ServerConfig, ThreadDetail, StartTurnCommand, WS,
  availableModels, preferredModelIndex, initialTurnCommand } from '../model/Models';


interface WorktreeRequest { cwd: string; refName: string; newRefName: string; path: string | null; }
interface CreatedWorktree { path: string; refName: string; }
interface WorkspaceCatalogRequest { instanceId: string; cwd: string; }
interface WorktreeResult { worktree: CreatedWorktree; }
interface WorktreeLookup { cwd: string; query: string; limit: number; }
interface WorktreeRefs { refs: WorkspaceRef[]; isRepo: boolean; }
interface SwitchRefRequest { cwd: string; refName: string; }
interface SwitchRefResult { refName: string | null; }
interface PathSearchRequest { cwd: string; query: string; limit: number; }
interface RootEntriesRequest { cwd: string; }
interface PathSearchResult { entries?: FileEntry[]; truncated: boolean; }

@Component
export struct NewTask {
  @Prop @Watch('onDismissRequest') closeRequest: number = 0;
  initialProjectId: string = '';
  environmentId: string = '';
  private selectedProjectId: string = '';
  onClose: () => void = () => {};
  onCreated: (params: Record<string, string>) => void = () => {};
  onMachine: (saved: SavedEnvironment) => void = () => {};
  private onDismissRequest(): void { this.dismiss(); }
  private font(size: number): number { return scaledFontSize(size, this.sizes.baseFontSize); }
  @StorageLink('textSizes') sizes: Typography = resolveTypography(16, null, null);
  @StorageLink('themeKey') themeKey: string = 't3-code-light';
  private color(role: string): string { return ThemeRuntime.color(this.themeKey, role); }
  @Prop @Watch('reconcileProject') projects: ProjectShell[] = [];
  @Prop groupingMode: string = 'repository';
  @State projectsOpen: boolean = false;
  @Prop @Watch('resumeAttachmentUploads') connectionState: string = 'connected';
  @State commandCatalog: ProviderCommandCatalog[] = [];
  private cache: ClientCache | null = null;
  private explicitSelection: ModelSelection | null = null;
  @State projectIndex: number = 0;
  @State models: ModelChoice[] = [];
  @State modelIndex: number = -1;
  @State modelPickerRequest: number = 0;
  private workspaceCatalogKey: string = '';
  private workspaceCatalogAt: number = 0;
  @State selectedOptions: ModelOptionSelection[] = [];
  @State branch: string = '';
  @State newWorktree: boolean = false;
  @State worktreeRef: string = '';
  @State worktreePath: string | null = null;
  @State title: string = '';
  @State sheetHeight: number = 640;
  @State editingTitle: boolean = false;
  @State draft: string = '';
  @State runtimeMode: string = 'full-access';
  @State interactionMode: string = 'default';
  @State busy: boolean = false;
  @State error: string = '';
  private createdThreadId: string = '';
  @State pendingCreate: CreateTaskCommand | null = null;
  @State pendingTurn: StartTurnCommand | null = null;
  private draftStore: NewTaskDraftStore | null = null;
  private draftTimer: number = -1;
  private active: boolean = true;
  private finished: boolean = false;
  @State draftReady: boolean = false;
  @State draftStatus: string = '';
  @State attachments: DraftImageProgress[] = [];
  @State pickingAttachment: boolean = false;
  @State attachmentsReady: boolean = false;
  @State maxFileBytes: number = 0;
  private catalogLoaded: boolean = false;
  private attachmentEnvironmentId: string = '';
  private attachmentStore: AttachmentDraftStore | null = null;
  private attachmentUpload: Promise<void> | null = null;
  private composerController: ComposerEditorController = new ComposerEditorController();
  @State pathEntries: ComposerPathEntry[] = [];
  @State pathActive: boolean = false;
  @State pathLoading: boolean = false;
  @State pathStatus: string = '';
  @State pathStart: number = 0;
  @State pathEnd: number = 0;
  private pathTrigger: ComposerPathTrigger | null = null;
  private pathConnection: PreparedConnection | null = null;
  private pathRevision: number = 0;
  private pathTimer: number = -1;
  private pathCwd: string = '';


  private currentConnection(): PreparedConnection | null {
    const connection = EnvironmentSession.current;
    return connection?.descriptor.environmentId === this.environmentId ? connection : null;
  }

  private reconcileProject(): void {
    if (this.selectedProjectId) this.projectIndex = this.projects.findIndex(project => project.id === this.selectedProjectId);
    else if (this.projects.length) { this.projectIndex = 0; this.selectedProjectId = this.projects[0].id; }
    if (this.draftReady && !this.busy) this.applyModelSelection();
  }

  aboutToAppear(): void {
    const requested = this.projects.findIndex((project: ProjectShell) => project.id === this.initialProjectId);
    this.projectIndex = Math.max(0, requested);
    this.selectedProjectId = this.projects[this.projectIndex]?.id ?? '';
    if (!this.environmentId) { this.error = '请先选择环境'; return; }
    this.restoreDraft();
    this.loadAttachments();
  }

  aboutToDisappear(): void { this.active = false; this.cancelPaths(); this.saveDraft(); }

  private cancelPaths(): void {
    ++this.pathRevision;
    if (this.pathTimer !== -1) clearTimeout(this.pathTimer);
    this.pathTimer = -1;
    this.pathEntries = [];
    this.pathActive = false;
    this.pathLoading = false;
    this.pathStatus = '';
    this.pathTrigger = null;
    this.pathConnection = null;
    this.pathCwd = '';
  }

  private editDraft(text: string): void {
    this.draft = text;
    this.updatePathSearch(text.length, text.length);
    this.queueSave();
  }

  private selectCommand(command: SlashCommand): void {
    if (!this.draftReady || this.busy || this.pendingTurn !== null) return;
    const insertion = insertCommand(this.draft, this.pathStart, this.pathEnd, command);
    this.editDraft(insertion.text);
    if (command.kind === 'model') { this.modelPickerRequest++; return; }
    setTimeout(() => { if (this.active) this.composerController.caretPosition(insertion.cursor); }, 0);
  }
  private insertShortcut(trigger: string): void {
    if (!this.draftReady || this.busy || this.pendingTurn !== null) return;
    const insertion = insertComposerTrigger(this.draft, this.pathStart, this.pathEnd, trigger);
    this.editDraft(insertion.text);
    this.updatePathSearch(insertion.cursor, insertion.cursor);
    setTimeout(() => { if (this.active) this.composerController.caretPosition(insertion.cursor); }, 0);
  }

  private chooseProject(index: number): void {
    this.projectIndex = index;
    this.selectedProjectId = this.projects[index]?.id ?? '';
    this.branch = ''; this.worktreePath = null; this.newWorktree = false; this.worktreeRef = '';
    this.explicitSelection = null;
    this.applyModelSelection();
    this.updatePathSearch(this.pathStart, this.pathEnd);
    this.queueSave();
  }

  private applyModelSelection(): void {
    const preferred = this.projects[this.projectIndex]?.defaultModelSelection;
    const selection = this.explicitSelection ?? preferred;
    const exact = selection?.instanceId ? this.models.findIndex((model: ModelChoice) =>
      model.instanceId === selection.instanceId && model.model === selection.model) : -1;
    const allowFallback = !this.explicitSelection && (!preferred?.instanceId || this.catalogLoaded);
    this.modelIndex = exact < 0 && allowFallback ? preferredModelIndex(this.models, preferred ?? null) : exact;
    this.selectedOptions = exact >= 0 ? selection?.options ?? [] : [];
  }

  private selectModel(selection: ModelSelection): void {
    this.explicitSelection = selection;
    this.applyModelSelection();
    this.queueSave();
  }

  private updatePathSearch(start: number, end: number): void {
    if (commandQuery(this.draft, start, end) !== null) this.refreshWorkspaceCommands();
    const trigger = composerPathTrigger(this.draft, start, end);
    const project = this.projects[this.projectIndex];
    const connection = this.currentConnection();
    const cwd = this.worktreePath ?? project?.workspaceRoot ?? '';
    if (trigger !== null && this.pathTrigger !== null && trigger.start === this.pathTrigger.start && trigger.end === this.pathTrigger.end &&
      trigger.query === this.pathTrigger.query && this.pathConnection === connection && this.pathCwd === cwd) return;
    this.cancelPaths();
    this.pathStart = start;
    this.pathEnd = end;
    if (!this.active || !this.draftReady || this.busy || this.pendingTurn !== null || this.finished ||
      trigger === null) return;
    this.pathActive = true;
    if (trigger.query.length > 256) { this.pathStatus = '文件查询不能超过 256 个字符'; return; }
    this.pathTrigger = trigger;
    this.pathConnection = connection;
    this.pathCwd = cwd;
    this.pathEntries = composerPathEntries([], this.cache?.shell()?.threads ?? [], trigger.query);
    if (project === undefined || connection === null || !cwd) { this.pathStatus = '连接后可搜索项目文件'; return; }
    this.pathLoading = true;
    this.pathStatus = '正在搜索项目文件…';
    const revision = this.pathRevision;
    this.pathTimer = setTimeout(() => {
      this.pathTimer = -1;
      this.searchPaths(trigger, revision, project, connection);
    }, 200);
  }

  private async searchPaths(trigger: ComposerPathTrigger, revision: number, project: ProjectShell, connection: PreparedConnection): Promise<void> {
    if (!this.active || revision !== this.pathRevision) return;
    if (connection !== EnvironmentSession.current) { this.pathLoading = false; this.pathStatus = '连接已变化，请重新输入查询'; return; }
    try {
      const request: PathSearchRequest = { cwd: this.worktreePath ?? project.workspaceRoot, query: trigger.query.trim(), limit: 20 };
      const root: RootEntriesRequest = { cwd: request.cwd };
      const result = request.query ? await connection.rpc.call<PathSearchResult>('projects.searchEntries', request) :
        await connection.rpc.call<PathSearchResult>('projects.listEntries', root);
      if (!this.active || revision !== this.pathRevision) return;
      this.pathLoading = false;
      if (connection !== EnvironmentSession.current) { this.pathStatus = '连接已变化，请重新输入查询'; return; }
      this.pathEntries = composerPathEntries(result.entries, this.cache?.shell()?.threads ?? [], trigger.query);
      this.pathStatus = this.pathEntries.length === 0 ? '没有匹配的文件或会话' : result.truncated ? '仅显示前 20 项，请继续输入缩小范围' : '';
    } catch (_) {
      if (this.active && revision === this.pathRevision) { this.pathLoading = false; this.pathStatus = '文件搜索失败，请重新输入查询'; }
    }
  }

  private selectPath(entry: ComposerPathEntry): void {
    if (!this.pathEntries.some((candidate: FileEntry) => candidate.path === entry.path && candidate.kind === entry.kind)) return;
    const trigger = this.pathTrigger;
    const current = composerPathTrigger(this.draft, this.pathStart, this.pathEnd);
    if (!this.draftReady || this.busy || this.pendingTurn !== null || this.finished ||
      this.pathConnection !== EnvironmentSession.current ||
      trigger === null || current === null || trigger.start !== current.start || trigger.end !== current.end || trigger.query !== current.query) return;
    const insertion = insertComposerEntry(this.draft, trigger, entry);
    this.cancelPaths();
    this.editDraft(insertion.text);
    setTimeout(() => {
      if (this.active && this.draft === insertion.text) this.composerController.caretPosition(insertion.cursor);
    }, 0);
  }

  private async restoreDraft(): Promise<void> {
    try {
      const store = await NewTaskDraftStore.open(getContext(this).filesDir, this.environmentId);
      const saved = await store.load();
      try {
        this.cache = await ClientCache.open(getContext(this).filesDir, this.environmentId);
        this.models = this.cache.models();
        this.commandCatalog = this.cache.commands();
      } catch (_) {}
      if (!this.active) return;
      this.draftStore = store;
      if (saved !== null) {
        this.explicitSelection = saved.createCommand?.modelSelection ??
          ((saved.useProjectDefault && !saved.createdThreadId) || !saved.modelSelection.instanceId ? null : saved.modelSelection);
        this.branch = saved.branch ?? ''; this.worktreePath = saved.worktreePath ?? null;
        this.newWorktree = saved.newWorktree ?? false; this.worktreeRef = saved.worktreeRef ?? '';
        this.title = saved.title;
        this.draft = saved.text;
        this.runtimeMode = saved.runtimeMode;
        this.interactionMode = saved.interactionMode;
        this.createdThreadId = saved.createdThreadId;
        this.pendingTurn = saved.turnCommand;
        this.pendingCreate = saved.createCommand ?? null;
        this.selectedProjectId = saved.projectId;
        this.reconcileProject();
        this.applyModelSelection();
        this.draftStatus = '已恢复新任务草稿';
        if (this.projectIndex < 0) this.error = '草稿中的项目或模型不可用，请重新选择';
      } else {
        this.chooseProject(this.projectIndex);
      }
      this.draftReady = true;
      const connection = this.currentConnection();
      if (connection && this.connectionState === 'connected') this.refreshCatalog(connection);
    } catch (error) { this.error = error instanceof Error ? error.message : String(error); }
  }

  private async refreshCatalog(connection: PreparedConnection): Promise<void> {
    const rpc = connection.rpc;
    try {
      const config = await rpc.call<ServerConfig>(WS.serverGetConfig, new EmptyPayload());
      if (!this.active || connection !== EnvironmentSession.current || connection.rpc !== rpc) return;
      this.models = availableModels(config.providers);
      this.maxFileBytes = fileUploadLimit(config.environment?.capabilities?.fileAttachments?.maxUploadBytes);
      this.catalogLoaded = true;
      this.commandCatalog = buildCommandCatalog(config.providers);
      this.cache?.setCatalog(config);
      this.applyModelSelection();
      if (this.modelIndex < 0) this.error = '环境没有所选模型，请检查 provider 状态或重新选择';
      else if (this.error === '环境没有所选模型，请检查 provider 状态或重新选择' || this.error === '模型列表暂时无法同步，输入的草稿仍会保存') this.error = '';
      this.uploadAttachments();
    } catch (_) {
      if (this.active && this.models.length === 0) this.error = '模型列表暂时无法同步，输入的草稿仍会保存';
    }
  }

  private async refreshWorkspaceCommands(): Promise<void> {
    const connection = this.currentConnection();
    const instanceId = this.models[this.modelIndex]?.instanceId ?? '';
    const cwd = this.worktreePath ?? this.projects[this.projectIndex]?.workspaceRoot ?? '';
    if (!this.active || this.connectionState !== 'connected' || connection === null || !instanceId || !cwd) return;
    const key = JSON.stringify([instanceId, cwd]);
    if (this.workspaceCatalogKey === key && Date.now() - this.workspaceCatalogAt < 300000) return;
    this.workspaceCatalogKey = key; this.workspaceCatalogAt = Date.now();
    try {
      const request: WorkspaceCatalogRequest = { instanceId: instanceId, cwd: cwd };
      const config = await connection.rpc.call<ServerConfig>('server.refreshProviders', request);
      if (!this.active || connection !== EnvironmentSession.current || this.workspaceCatalogKey !== key) return;
      this.commandCatalog = buildCommandCatalog(config.providers);
      this.cache?.setCatalog(config);
    } catch (_) { if (this.workspaceCatalogKey === key) this.workspaceCatalogKey = ''; }
  }

  private queueSave(): void {
    if (!this.draftReady || this.finished) return;
    this.draftStatus = '正在保存草稿…';
    if (this.draftTimer !== -1) clearTimeout(this.draftTimer);
    this.draftTimer = setTimeout(() => { this.saveDraft(); }, 250);
  }

  private async loadAttachments(): Promise<void> {
    try {
      const store = await AttachmentDraftStore.open(getContext(this).filesDir, this.environmentId, 'new-task');
      if (!this.active) return;
      this.attachmentStore = store; this.attachmentEnvironmentId = this.environmentId;
      this.attachmentsReady = true; this.refreshAttachments(); this.uploadAttachments();
    } catch (error) { this.error = `附件草稿读取失败：${error instanceof Error ? error.message : String(error)}`; }
  }
  private refreshAttachments(): void {
    this.attachments = (this.attachmentStore?.images ?? []).map((image: DraftImage): DraftImageProgress => {
      const previous = this.attachments.find((entry: DraftImageProgress) => entry.uri === image.uri);
      return { uri: image.uri, name: image.name, type: image.type ?? 'image', sizeBytes: image.sizeBytes,
        status: image.uploaded ? 'uploaded' : previous?.status ?? 'waiting', progress: image.uploaded ? 100 : previous?.progress ?? 0, error: previous?.error ?? '' };
    });
  }
  private resumeAttachmentUploads(): void {
    this.catalogLoaded = false;
    if (this.connectionState !== 'connected' || !this.draftReady) return;
    const connection = this.currentConnection();
    if (!this.active || connection === null) return;
    const rpc = connection.rpc;
    (this.attachmentUpload ?? Promise.resolve()).then(() => {
      if (!this.active || this.connectionState !== 'connected' || connection !== EnvironmentSession.current || connection.rpc !== rpc) return;
      this.refreshCatalog(connection);
      this.uploadAttachments();
    });
  }
  private async pickAttachments(files: boolean): Promise<void> {
    const store = this.attachmentStore;
    if (store === null || this.busy || this.pickingAttachment || this.pendingTurn !== null || store.images.length >= 8) return;
    this.pickingAttachment = true; this.error = '';
    try {
      const remaining = 8 - store.images.length;
      const uris = files ? await new picker.DocumentViewPicker().select({ maxSelectNumber: remaining }) :
        (await new photoAccessHelper.PhotoViewPicker().select({ MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE, maxSelectNumber: remaining })).photoUris;
      for (const uri of uris) {
        const name = new fileUri.FileUri(uri).name;
        if (files) await store.addFile(uri, name, this.maxFileBytes); else await store.add(uri, name);
        this.refreshAttachments(); this.uploadAttachments();
      }
    } catch (error) { this.error = error instanceof Error ? error.message : String(error); }
    finally { this.pickingAttachment = false; }
  }
  private uploadAttachments(): Promise<void> {
    if (this.attachmentUpload !== null) return this.attachmentUpload;
    if (!this.attachmentStore?.images.some((image: DraftImage) => !image.uploaded && (image.type !== 'file' || this.catalogLoaded))) return Promise.resolve();
    const pending: Promise<void> = this.transferAttachments().finally(() => { if (this.attachmentUpload === pending) this.attachmentUpload = null; });
    this.attachmentUpload = pending; return pending;
  }
  private async transferAttachments(): Promise<void> {
    const connection = this.currentConnection(), store = this.attachmentStore;
    if (connection === null || store === null || this.pendingTurn !== null || this.connectionState !== 'connected' ||
      connection.descriptor.environmentId !== this.attachmentEnvironmentId) return;
    const failed: Set<string> = new Set();
    while (this.active && this.connectionState === 'connected' && connection === EnvironmentSession.current) {
      const image = store.images.find((entry: DraftImage) => !entry.uploaded && !failed.has(entry.uri) &&
        (entry.type !== 'file' || this.catalogLoaded));
      if (!image) return;
      try {
        const uploaded = await uploadImage(connection.rpc, connection.httpBaseUrl, image.uri, image.name ?? '', (percent: number) => {
          if (this.active) this.attachments = this.attachments.map((entry: DraftImageProgress): DraftImageProgress => ({
            uri: entry.uri, name: entry.name, type: entry.type, sizeBytes: entry.sizeBytes,
            status: entry.uri === image.uri ? 'uploading' : entry.status, progress: entry.uri === image.uri ? percent : entry.progress, error: entry.error }));
        }, image.type ?? 'image', image.type === 'file' ? this.maxFileBytes : 10 * 1024 * 1024);
        try { await store.setUploaded(image.uri, uploaded); }
        catch (error) { await deleteImageUpload(connection.rpc, uploaded.id); throw new Error(error instanceof Error ? error.message : String(error)); }
        if (!store.images.some((entry: DraftImage) => entry.uri === image.uri)) await deleteImageUpload(connection.rpc, uploaded.id);
        if (this.active) this.refreshAttachments();
      } catch (error) {
        failed.add(image.uri);
        if (this.active) {
          this.error = error instanceof Error ? error.message : String(error);
          this.attachments = this.attachments.map((entry: DraftImageProgress): DraftImageProgress => ({
            uri: entry.uri, name: entry.name, type: entry.type, sizeBytes: entry.sizeBytes,
            status: entry.uri === image.uri ? 'failed' : entry.status, progress: entry.progress, error: entry.uri === image.uri ? this.error : entry.error }));
        }
      }
    }
  }
  private async removeAttachment(uri: string): Promise<void> {
    const store = this.attachmentStore, connection = this.currentConnection();
    if (store === null || this.busy || this.pickingAttachment) return;
    this.pickingAttachment = true;
    try {
      const uploaded = store.images.find((entry: DraftImage) => entry.uri === uri)?.uploaded;
      if (uploaded && connection !== null && this.connectionState === 'connected') await deleteImageUpload(connection.rpc, uploaded.id);
      await store.remove(uri); this.refreshAttachments();
    } catch (error) { this.error = error instanceof Error ? error.message : String(error); }
    finally { this.pickingAttachment = false; }
  }
  private async dismiss(): Promise<void> {
    if (this.busy) return;
    try {
      if (this.draftReady) await this.persistDraft();
      this.onClose();
    } catch (error) { this.error = error instanceof Error ? error.message : String(error); }
  }

  @Builder
  private projectSheet() {
    ProjectPicker({ projects: this.projects, selectedId: this.projects[this.projectIndex]?.id ?? '',
      environmentId: this.environmentId, groupingMode: this.groupingMode, selectWorkspace: true,
      onSelect: (id: string) => {
        const index = this.projects.findIndex((project: ProjectShell) => project.id === id);
        if (index >= 0 && this.draftReady && !this.busy && !this.createdThreadId && this.pendingCreate === null) { this.chooseProject(index); this.projectsOpen = false; }
      }
    })
  }

  private async persistDraft(): Promise<void> {
    if (this.draftTimer !== -1) clearTimeout(this.draftTimer);
    this.draftTimer = -1;
    if (!this.draftReady || this.finished || this.draftStore === null) return;
    const project = this.projects[this.projectIndex];
    const model = this.models[this.modelIndex];
    const projectId = project?.id || this.selectedProjectId;
    if (!projectId) throw new Error('请先选择有效项目，原草稿已保留');
    const selection: ModelSelection = model === undefined ? this.explicitSelection ?? { instanceId: '', model: '' } :
      { instanceId: model.instanceId, model: model.model, options: this.selectedOptions };
    const draft: NewTaskDraft = {
      newWorktree: this.newWorktree, worktreeRef: this.worktreeRef,
      projectId: projectId, title: this.title, text: this.draft, branch: this.branch || null, worktreePath: this.worktreePath,
      modelSelection: selection, useProjectDefault: this.explicitSelection == null,
      runtimeMode: this.runtimeMode, interactionMode: this.interactionMode,
      createdThreadId: this.createdThreadId, turnCommand: this.pendingTurn, createCommand: this.pendingCreate
    };
    await this.draftStore.save(draft);
    if (this.active) this.draftStatus = '草稿已保存';
  }

  private async saveDraft(): Promise<void> {
    try { await this.persistDraft(); }
    catch (error) { if (this.active) this.draftStatus = `草稿保存失败：${error instanceof Error ? error.message : String(error)}`; }
  }

  private async prepareWorktree(): Promise<void> {
    if (!this.newWorktree || this.worktreePath) return;
    const connection = this.currentConnection();
    const project = this.projects[this.projectIndex];
    if (connection === null || project === undefined) throw new Error('请先选择项目');
    if (!this.worktreeRef) this.worktreeRef = `t3/harmony-${util.generateRandomUUID(true)}`;
    await this.persistDraft();
    const lookup: WorktreeLookup = { cwd: project.workspaceRoot, query: this.worktreeRef, limit: 50 };
    const refs = await connection.rpc.call<WorktreeRefs>('vcs.listRefs', lookup);
    if (!refs.isRepo) {
      this.worktreeRef = '';
      await this.persistDraft();
      throw new Error('当前项目不是 Git 仓库，无法新建工作树');
    }
    const existing = refs.refs.find((ref: WorkspaceRef) => ref.name === this.worktreeRef);
    if (existing !== undefined) {
      if (!existing.worktreePath) throw new Error('工作树分支已存在但目录不可用，请检查后重试');
      this.worktreePath = existing.worktreePath;
      this.branch = existing.name;
    } else {
      const request: WorktreeRequest = { cwd: project.workspaceRoot, refName: this.branch || 'HEAD', newRefName: this.worktreeRef, path: null };
      const result = await connection.rpc.call<WorktreeResult>('vcs.createWorktree', request);
      if (!result.worktree?.path || result.worktree.refName !== this.worktreeRef) throw new Error('工作树结果无法确认，请重试核对');
      this.worktreePath = result.worktree.path;
      this.branch = result.worktree.refName;
    }
    await this.persistDraft();
  }

  private async create(): Promise<void> {
    const connection = this.currentConnection();
    const project = this.projects[this.projectIndex];
    const model = this.models[this.modelIndex];
    const options = this.selectedOptions.slice();
    if (connection === null || this.connectionState !== 'connected' || project === undefined || model === undefined || this.busy || !this.draftReady || this.pickingAttachment || !this.attachmentsReady || (!this.draft.trim() && this.attachments.length === 0)) return;
    this.cancelPaths();
    this.busy = true;
    this.explicitSelection = { instanceId: model.instanceId, model: model.model, options: options };
    this.error = '';
    try {
      await this.persistDraft();
      if (this.pendingTurn === null && this.attachmentStore !== null) {
        for (const image of this.attachmentStore.images) {
          if (image.uploaded && !await imageUploadExists(connection.rpc, image.uploaded.id)) await this.attachmentStore.setUploaded(image.uri, undefined);
        }
      }
      await this.uploadAttachments();
      if (connection !== EnvironmentSession.current) throw new Error('连接已变化，草稿已保留');
      if (this.attachmentStore?.images.some((image: DraftImage) => !image.uploaded)) throw new Error('附件上传未完成，请重试');
      const title = this.title.trim() || this.draft.trim().split('\n')[0].slice(0, 80) || this.attachments[0]?.name || '新任务';
      if (!this.createdThreadId) {
        if (this.pendingCreate === null) {
          await this.prepareWorktree();
          if (this.branch && !this.worktreePath) {
            const switchInput: SwitchRefRequest = { cwd: project.workspaceRoot, refName: this.branch };
            const checkout = await connection.rpc.call<SwitchRefResult>('vcs.switchRef', switchInput);
            this.branch = checkout.refName ?? this.branch;
          }
          this.pendingCreate = {
          type: 'thread.create', commandId: util.generateRandomUUID(true),
          threadId: util.generateRandomUUID(true), projectId: project.id, title: title,
          modelSelection: { instanceId: model.instanceId, model: model.model, options: options },
          runtimeMode: this.runtimeMode, interactionMode: this.interactionMode,
          branch: this.branch || null, worktreePath: this.worktreePath ?? null, createdAt: new Date().toISOString()
          };
          await this.persistDraft();
        }
        await connection.rpc.call(WS.threadStartTurn, this.pendingCreate);
        this.createdThreadId = this.pendingCreate.threadId;
        this.pendingCreate = null;
        await this.persistDraft();
      }
      const thread: ThreadDetail = {
        id: this.createdThreadId, projectId: project.id, title: title,
        runtimeMode: this.runtimeMode, interactionMode: this.interactionMode, messages: []
      };
      if (this.pendingTurn === null) {
        this.pendingTurn = initialTurnCommand(thread, this.draft,
          util.generateRandomUUID(true), util.generateRandomUUID(true), new Date().toISOString());
        for (const image of this.attachmentStore?.images ?? []) if (image.uploaded) this.pendingTurn.message.attachments.push(image.uploaded);
        await this.persistDraft();
      }
      await connection.rpc.call(WS.threadStartTurn, this.pendingTurn);
      await this.attachmentStore?.clear();
      await this.draftStore?.clear();
      this.finished = true;
      const destination: Record<string, string> = {
        'environmentId': connection.descriptor.environmentId, 'threadId': this.createdThreadId,
        'cwd': this.worktreePath ?? project.workspaceRoot, 'title': title, 'projectTitle': project.title
      };
      this.onCreated(destination);
    } catch (error) {
      this.error = error instanceof Error ? error.message : String(error);
      if (error instanceof RpcRemoteError && error.definitivelyRejected) {
        this.pendingTurn = null;
        if (!this.createdThreadId) this.pendingCreate = null;
        await this.saveDraft();
      }
    } finally { this.busy = false; }
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Button('取消', { type: ButtonType.Normal }).fontSize(this.font(14)).fontColor(this.color('foreground-secondary'))
          .backgroundColor(Color.Transparent).height(40).padding({ left: 4, right: 12 }).enabled(!this.busy).onClick(() => { this.dismiss(); })
        Text('新任务').fontSize(this.font(16)).fontWeight(FontWeight.Medium).fontColor(this.color('foreground')).layoutWeight(1).textAlign(TextAlign.Center)
        Button({ type: ButtonType.Circle }) { AppIcon({ name: 'edit', iconSize: 20, tint: this.color('foreground-muted') }) }
          .width(40).height(40).backgroundColor(Color.Transparent).enabled(!this.busy).accessibilityText('任务标题选项')
          .bindMenu([{ value: '编辑任务标题', symbolIcon: menuIcon($r('sys.symbol.square_and_pencil')), action: () => { this.editingTitle = true; } }], { modalMode: menuModalMode() })
      }.width('100%')
      Scroll() {
        Column({ space: 16 }) {
          Column({ space: 6 }) {
          Button({ type: ButtonType.Normal }) {
            Row({ space: 10 }) {
              ProjectIcon({ cwd: this.projects[this.projectIndex]?.workspaceRoot ?? '', faviconPath: this.projects[this.projectIndex]?.faviconPath ?? '', iconSize: 24 })
              Text(this.projects[this.projectIndex]?.title === 'No project' ? '独立任务' : this.projects[this.projectIndex]?.title ?? '选择项目')
                .fontSize(this.font(16)).fontWeight(FontWeight.Medium).fontColor(this.color('foreground')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
              AppIcon({ name: 'down', iconSize: 13, tint: this.color('foreground-muted') })
            }.width('100%')
          }.height(52).width('100%').padding({ left: 14, right: 14 }).borderRadius(16).backgroundColor(this.color('card'))
            .enabled(this.draftReady && !this.busy && !this.createdThreadId && this.pendingCreate === null)
            .onClick(() => { this.projectsOpen = true; }).accessibilityText('选择项目')
            .bindSheet($$this.projectsOpen, this.projectSheet(), { systemMaterial: immersiveMaterial('popup'), height: SheetSize.LARGE, title: { title: '选择项目' }, dragBar: true, showClose: true })
          Text(this.projects[this.projectIndex]?.workspaceRoot ?? '').fontSize(this.font(12)).fontColor(this.color('foreground-muted')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          }.width('100%').padding({ left: 4, right: 4 })
          }.width('100%')
      }.layoutWeight(1).width('100%').align(Alignment.TopStart)
      Column({ space: 0 }) {
          CommandSuggestions({ availableHeight: this.sheetHeight, text: this.draft, start: this.pathStart, end: this.pathEnd,
            commands: commandsFor(this.commandCatalog, this.models[this.modelIndex]?.instanceId ?? '', this.worktreePath ?? this.projects[this.projectIndex]?.workspaceRoot ?? '', false),
            disabled: !this.draftReady || this.busy || this.pendingTurn !== null,
            paths: this.pathEntries, pathActive: this.pathActive, pathLoading: this.pathLoading, pathStatus: this.pathStatus,
            onSelectPath: (entry: ComposerPathEntry) => { this.selectPath(entry); },
            onSelect: (command: SlashCommand) => { this.selectCommand(command); } })
          ChatGlass() {
          Column() {
          Column({ space: 8 }) {
          if (this.editingTitle || this.title.length > 0) {
          TextInput({ placeholder: '任务标题（可选）', text: this.title }).fontSize(this.font(14)).fontColor(this.color('foreground')).backgroundColor(Color.Transparent).placeholderColor(this.color('glass-label')).onChange((text: string) => { this.title = text; this.queueSave(); })
            .enabled(this.draftReady && !this.busy && !this.createdThreadId && this.pendingCreate === null)
          }
          if (this.attachments.length > 0) {
            DraftImages({ images: this.attachments, disabled: this.busy || this.pickingAttachment || this.pendingTurn !== null,
              onRemove: (uri: string) => { this.removeAttachment(uri); }, onRetry: () => { this.error = ''; this.uploadAttachments(); } })
          }
          Row({ space: 4 }) {
          ComposerActions({ disabled: !this.draftReady || this.busy || this.pendingTurn !== null,
            canAttach: this.attachmentsReady && !this.pickingAttachment && this.attachments.length < 8, canAttachFiles: true,
            onPhotos: () => { this.pickAttachments(false); }, onFiles: () => { this.pickAttachments(true); },
            onInsert: (trigger: string) => { this.insertShortcut(trigger); } })
          ComposerEditor({ text: this.draft, control: this.composerController, placeholderColor: this.color('glass-label'),
            commands: commandsFor(this.commandCatalog, this.models[this.modelIndex]?.instanceId ?? '', this.worktreePath ?? this.projects[this.projectIndex]?.workspaceRoot ?? '', false),
            disabled: !this.draftReady || this.busy || this.pendingTurn !== null,
            onChange: (text: string) => { this.editDraft(text); },
            onSelection: (start: number, end: number) => { this.updatePathSearch(start, end); }, onSend: () => { this.create(); }
          }).layoutWeight(1)

          Button({ type: ButtonType.Circle }) {
            AppIcon({ name: 'send', iconSize: 21, tint: '#FFFFFF' })
          }.width(40).height(40).padding(0).backgroundColor('#3268F5')
            .accessibilityText(this.busy ? '正在创建' : this.createdThreadId ? '重试发送' : this.pendingCreate !== null ? '核对并重试创建' : '发送并开始任务')
            .enabled(this.connectionState === 'connected' && this.draftReady && this.attachmentsReady && !this.busy && !this.pickingAttachment && this.modelIndex >= 0 && this.projects.length > 0 && (this.draft.trim().length > 0 || this.attachments.length > 0))
            .onClick(() => { this.create(); })
          }.width('100%').alignItems(VerticalAlign.Center)
          ComposerSettings({ models: this.models, iconOnly: false, modelPickerRequest: this.modelPickerRequest, selection: this.models[this.modelIndex] === undefined ? null : {
            instanceId: this.models[this.modelIndex].instanceId, model: this.models[this.modelIndex].model, options: this.selectedOptions },
            runtimeMode: this.runtimeMode, interactionMode: this.interactionMode,
            disabled: !this.draftReady || this.busy || !!this.createdThreadId || this.pendingCreate !== null || !!this.worktreeRef,
            onModel: (selection: ModelSelection) => { this.selectModel(selection); },
            onOptions: (selection: ModelSelection) => { this.selectModel(selection); },
            onMode: (kind: string, value: string) => { if (kind === 'runtime') this.runtimeMode = value; else this.interactionMode = value; this.queueSave(); }
          })
          }.padding({ left: 6, right: 8, top: 6, bottom: 6 }).width('100%')
          Divider().strokeWidth(0.5).color(this.color('border')).width('calc(100% - 24vp)')
          WorkspaceContext({ worktree: !!this.worktreePath, newWorktree: this.newWorktree, canChooseWorktree: true,
            connectionState: this.connectionState,
            onWorktreeMode: (value: boolean) => { this.newWorktree = value; this.worktreePath = null; this.worktreeRef = ''; this.queueSave(); }, cwd: this.projects[this.projectIndex]?.workspaceRoot ?? '', selectedBranch: this.branch,
            disabled: !this.draftReady || this.busy || !!this.createdThreadId || this.pendingCreate !== null || !!this.worktreeRef,
            onMachine: (saved: SavedEnvironment) => {
              if (EnvironmentSession.current?.matchesSaved(saved)) return;
              this.persistDraft().then(() => { this.onMachine(saved); })
                .catch((error: Error) => { this.error = error.message; });
            },
            onBranch: (ref: WorkspaceRef) => { this.branch = ref.name; this.worktreePath = this.newWorktree ? null : ref.worktreePath; this.updatePathSearch(this.pathStart, this.pathEnd); this.queueSave(); }
          })
          }.width('100%').padding({ bottom: 4 })
          }
          }.width('100%')
          if (this.draftStatus && !['已恢复新任务草稿', '正在保存草稿…', '草稿已保存'].includes(this.draftStatus)) { Text(this.draftStatus).fontSize(this.font(12)).fontColor(this.color('foreground-muted')).width('100%') }
          if (this.error) { Text(this.error).fontColor(this.color('danger-foreground')).width('100%') }
    }.padding({ left: 16, right: 16, bottom: 12 }).width('100%').height('100%')
      .onAreaChange((_old: Area, area: Area) => {
        const height = Number(area.height);
        if (height > 0 && height !== this.sheetHeight) this.sheetHeight = height;
      })
  }
}
