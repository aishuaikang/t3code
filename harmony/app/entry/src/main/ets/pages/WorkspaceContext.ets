import { menuIcon, menuModalMode } from './MenuIcon';
import { immersiveMaterial } from './ChatGlass';
import { AppIcon } from './AppIcon';
import { EnvironmentPicker } from './EnvironmentPicker';
import { ProjectScripts } from './ProjectScripts';
import { WorkspaceGit } from './WorkspaceGit';
import util from '@ohos.util';
import { ThreadPullRequestLink, ProjectShell, WS } from '../model/Models';
import { pullRequestLink, validBranchName } from '../model/WorkspaceActions';
import { ConnectionSpinner } from './StatusIndicator';
import { connectionProgressLabel } from '../model/StatusVisuals';
import { EnvironmentSession } from '../connection/Environment';
import { RpcClient } from '../connection/Rpc';
import { SavedEnvironment, loadEnvironments } from '../connection/EnvironmentStore';
import { ThemeRuntime } from '../connection/ThemeRuntime';
import { Typography, resolveTypography, scaledFontSize } from '../model/Typography';

export interface WorkspaceRef { name: string; current: boolean; isRemote?: boolean; isDefault?: boolean; worktreePath: string | null; }
interface CreateRefRequest { cwd: string; refName: string; switchRef: boolean; }
interface CreateRefResult { refName: string; }
interface CreateWorktreeRequest { cwd: string; refName: string; newRefName: string; path: string | null; }
interface CreatedWorktree { path: string; refName: string; }
interface CreateWorktreeResult { worktree: CreatedWorktree; }
interface ResolvePullRequest { cwd: string; reference: string; }
interface ResolvedPullRequestUrl { url: string; }
interface ResolvedPullRequest { pullRequest: ResolvedPullRequestUrl; }
interface LinkCommand extends ThreadPullRequestLink { type: string; commandId: string; threadId: string; }
interface UnlinkCommand { type: string; commandId: string; threadId: string; host: string; repository: string; number: number; }
interface RefRequest { cwd: string; limit: number; cursor?: number; query?: string; }
interface RefResult { refs: WorkspaceRef[]; isRepo: boolean; nextCursor: number | null; }

@Component
export struct WorkspaceContext {
  @StorageLink('themeKey') themeKey: string = 't3-code-light';
  @StorageLink('textSizes') sizes: Typography = resolveTypography(16, null, null);
  @Prop @Watch('contextChanged') cwd: string = '';
  @Prop worktree: boolean = false;
  @Prop newWorktree: boolean = false;
  @Prop canChooseWorktree: boolean = false;
  @Prop iconOnly: boolean = false;
  @Prop threadId: string = '';
  @Prop project: ProjectShell | null = null;
  @Prop @Watch('openBranches') branchPickerRequest: number = 0;
  @Prop pullRequests: ThreadPullRequestLink[] = [];
  @State actionView: string = '';
  @State actionInput: string = '';
  @State actionBusy: boolean = false;
  getRpc: () => RpcClient | null = () => EnvironmentSession.current?.rpc ?? null;
  onFiles: () => void = () => {};
  onTerminal: (terminalId: string) => void = () => {};
  onReview: (scope: string) => void = () => {};
  onWorktreeMode: (value: boolean) => void = () => {};
  @Prop selectedBranch: string = '';
  @Prop disabled: boolean = false;
  @Prop connectionState: string = 'connected';
  @Prop showConnection: boolean = true;
  @Prop branchDisabled: boolean = false;
  onMachine: (saved: SavedEnvironment) => void = () => {};
  onBranch: (ref: WorkspaceRef) => void = () => {};
  @State refs: WorkspaceRef[] = [];
  @State saved: SavedEnvironment[] = [];
  @State currentBranch: string = '';
  @State sheetOpen: boolean = false;
  @State machinePicker: boolean = false;
  @State choosingBranch: boolean = false;
  @State loading: boolean = false;
  @State error: string = '';
  @State query: string = '';
  @State nextCursor: number | null = null;
  @State isRepo: boolean = true;
  private revision: number = 0;
  private searchTimer: number = -1;
  private color(role: string): string { return ThemeRuntime.color(this.themeKey, role); }
  private font(size: number): number { return scaledFontSize(size, this.sizes.baseFontSize); }
  aboutToAppear(): void { this.loadRefs(); }
  aboutToDisappear(): void { ++this.revision; if (this.searchTimer !== -1) clearTimeout(this.searchTimer); }
  private contextChanged(): void { if (this.searchTimer !== -1) clearTimeout(this.searchTimer); this.searchTimer = -1; this.currentBranch = ''; this.query = ''; this.loadRefs(); }
  private openBranches(): void {
    if (this.disabled) return;
    this.machinePicker = false; this.actionView = ''; this.choosingBranch = true;
    this.sheetOpen = true; this.query = ''; this.loadRefs();
  }
  private async loadRefs(more: boolean = false): Promise<void> {
    const revision = ++this.revision;
    const connection = EnvironmentSession.current;
    const rpc = this.getRpc();
    if (connection === null || rpc === null || !this.cwd) return;
    this.loading = true; this.error = '';
    if (!more) { this.refs = []; this.nextCursor = null; }
    try {
      const input: RefRequest = { cwd: this.cwd, limit: 50 };
      if (this.query.trim()) input.query = this.query.trim();
      if (more && this.nextCursor !== null) input.cursor = this.nextCursor;
      const result = await rpc.call<RefResult>('vcs.listRefs', input);
      if (revision !== this.revision || connection !== EnvironmentSession.current || this.getRpc() !== rpc) return;
      this.refs = more ? this.refs.concat(result.refs) : result.refs;
      this.isRepo = result.isRepo; this.nextCursor = result.nextCursor;
      const current = result.refs.find((entry: WorkspaceRef) => entry.current);
      if (current !== undefined) this.currentBranch = current.name;
    } catch (error) {
      if (revision === this.revision) this.error = `分支读取失败：${error instanceof Error ? error.message : String(error)}`;
    } finally { if (revision === this.revision) this.loading = false; }
  }
  private async machines(): Promise<void> {
    this.actionView = ''; this.machinePicker = true; this.error = ''; this.sheetOpen = true;
    try { this.saved = await loadEnvironments(getContext(this)); }
    catch (error) { this.error = error instanceof Error ? error.message : String(error); }
  }
  private searchRefs(value: string): void {
    this.query = value; ++this.revision;
    if (this.searchTimer !== -1) clearTimeout(this.searchTimer);
    this.searchTimer = setTimeout(() => { this.searchTimer = -1; this.loadRefs(); }, 180);
  }
  private refDescription(ref: WorkspaceRef): string {
    const labels: string[] = [];
    if (ref.current) labels.push('当前分支');
    if (ref.isDefault) labels.push('默认');
    if (ref.isRemote) labels.push('远程');
    if (ref.worktreePath) labels.push(`工作树 · ${ref.worktreePath}`);
    return labels.join(' · ') || '本地分支';
  }
  private visiblePullRequests(): ThreadPullRequestLink[] { return this.pullRequests.filter((link: ThreadPullRequestLink) => link.source !== 'stack-dismissed'); }
  private openAction(action: string): void { this.actionView = action; this.actionInput = ''; this.error = ''; }
  private async submitAction(): Promise<void> {
    const connection = EnvironmentSession.current;
    const rpc = this.getRpc();
    const value = this.actionInput.trim();
    if (connection === null || rpc === null || this.disabled || this.actionBusy || !value || (!this.threadId && this.actionView === 'link')) return;
    if (this.actionView !== 'link' && (this.branchDisabled || !validBranchName(value))) { this.error = this.branchDisabled ? '当前任务运行中，请结束后再创建' : '分支名称无效'; return; }
    this.actionBusy = true; this.error = '';
    try {
      if (this.actionView === 'link') {
        const request: ResolvePullRequest = { cwd: this.cwd, reference: value };
        const resolved = await rpc.call<ResolvedPullRequest>('git.resolvePullRequest', request);
        if (connection !== EnvironmentSession.current || this.getRpc() !== rpc || this.disabled) return;
        const link = pullRequestLink(resolved.pullRequest.url);
        if (link === null) throw new Error('暂不支持此 PR 地址，请检查链接');
        const command: LinkCommand = { type: 'thread.pull-request.link', commandId: util.generateRandomUUID(true), threadId: this.threadId,
          host: link.host, repository: link.repository, number: link.number, url: link.url, source: 'manual' };
        await rpc.call(WS.threadStartTurn, command);
        this.actionView = '';
      } else {
        const lookup: RefRequest = { cwd: this.cwd, query: value, limit: 50 };
        const refs = await rpc.call<RefResult>('vcs.listRefs', lookup);
        if (connection !== EnvironmentSession.current || this.getRpc() !== rpc || this.disabled) return;
        if (!refs.isRepo) throw new Error('当前目录不是 Git 仓库');
        const existing = refs.refs.find((ref: WorkspaceRef) => ref.name === value);
        let ref: WorkspaceRef;
        if (this.actionView === 'worktree') {
          if (existing !== undefined) {
            if (!existing.worktreePath) throw new Error('分支已存在，请更换名称或从列表选择');
            ref = existing;
          } else {
            const request: CreateWorktreeRequest = { cwd: this.cwd, refName: this.selectedBranch || this.currentBranch || 'HEAD', newRefName: value, path: null };
            const created = await rpc.call<CreateWorktreeResult>('vcs.createWorktree', request);
            ref = { name: created.worktree.refName, worktreePath: created.worktree.path, current: false };
          }
        } else {
          if (existing !== undefined) throw new Error('分支已存在，请从列表选择');
          const request: CreateRefRequest = { cwd: this.cwd, refName: value, switchRef: false };
          const created = await rpc.call<CreateRefResult>('vcs.createRef', request);
          ref = { name: created.refName, worktreePath: null, current: false };
        }
        if (connection !== EnvironmentSession.current || this.getRpc() !== rpc || this.disabled) return;
        this.actionView = ''; this.loadRefs();
        if (this.branchDisabled) { this.error = '已创建，当前任务运行结束后可从列表切换'; return; }
        this.sheetOpen = false; this.onBranch(ref);
      }
    } catch (error) { this.error = error instanceof Error ? error.message : String(error); }
    finally { this.actionBusy = false; }
  }
  private async unlink(link: ThreadPullRequestLink): Promise<void> {
    const connection = EnvironmentSession.current;
    const rpc = this.getRpc();
    if (connection === null || rpc === null || !this.threadId || this.disabled || this.actionBusy) return;
    this.actionBusy = true; this.error = '';
    try {
      const command: UnlinkCommand = { type: 'thread.pull-request.unlink', commandId: util.generateRandomUUID(true), threadId: this.threadId,
        host: link.host, repository: link.repository, number: link.number };
      await rpc.call(WS.threadStartTurn, command);
    } catch (error) { this.error = error instanceof Error ? error.message : String(error); }
    finally { this.actionBusy = false; }
  }
  @Builder
  contextSheet() {
    Column({ space: 14 }) {
      if (this.machinePicker) {
        EnvironmentPicker({ environments: this.saved,
          selectedId: this.saved.find((saved: SavedEnvironment) => EnvironmentSession.current?.matchesSaved(saved))?.connectionId ?? EnvironmentSession.current?.descriptor.environmentId ?? '',
          connectionState: this.connectionState, disabled: this.disabled,
          onSelect: (saved: SavedEnvironment) => { this.sheetOpen = false; this.onMachine(saved); }
        }).layoutWeight(1)
      } else if (this.actionView === 'scripts' && this.project !== null) {
        ProjectScripts({ project: this.project, threadId: this.threadId, worktreePath: this.worktree ? this.cwd : null,
          disabled: this.disabled, getRpc: () => this.getRpc(), onBack: () => { this.actionView = ''; },
          onTerminal: (terminalId: string) => { this.sheetOpen = false; this.onTerminal(terminalId); }
        }).layoutWeight(1)
      } else if (this.actionView) {
        Row({ space: 10 }) {
          Button({ type: ButtonType.Circle }) { AppIcon({ name: 'back', iconSize: 20, tint: this.color('foreground') }) }
            .width(36).height(36).padding(0).backgroundColor(Color.Transparent).accessibilityText('返回工作区').enabled(!this.actionBusy).onClick(() => { this.actionView = ''; this.error = ''; })
          Text(this.actionView === 'link' ? '关联 Pull Request' : this.actionView === 'worktree' ? '新建工作树' : '新建分支')
            .fontSize(this.font(17)).fontColor(this.color('foreground')).layoutWeight(1)
        }.width('100%')
        TextInput({ text: this.actionInput, placeholder: this.actionView === 'link' ? 'PR 地址或编号' : '新分支名称' })
          .fontSize(this.font(16)).fontColor(this.color('foreground')).backgroundColor(this.color('input'))
          .maxLength(this.actionView === 'link' ? 2048 : 200).enabled(!this.actionBusy).onChange((value: string) => { this.actionInput = value; })
        if (this.actionView !== 'link') { Text('创建后将切换当前任务的工作目录或分支').fontSize(this.font(12)).fontColor(this.color('foreground-muted')).width('100%') }
        Button(this.actionBusy ? '正在处理…' : this.actionView === 'link' ? '关联' : '创建并使用').width('100%').height(46)
          .fontColor(this.color('primary-foreground')).backgroundColor(this.color('primary')).enabled(!this.actionBusy && !!this.actionInput.trim()).onClick(() => { this.submitAction(); })
        Blank().layoutWeight(1)
      } else if (this.iconOnly && !this.choosingBranch) {
        Scroll() {
        Column({ space: 14 }) {
        Column({ space: 4 }) {
          Row({ space: 12 }) {
            AppIcon({ name: 'machine', iconSize: 21, tint: this.color('foreground-secondary') })
            Text(EnvironmentSession.current?.descriptor.label ?? '选择机器').fontSize(this.font(14)).fontColor(this.color('foreground-muted')).layoutWeight(1)
            AppIcon({ name: 'down', iconSize: 14, tint: this.color('foreground-muted') })
          }.padding(16).width('100%').onClick(() => { this.machines(); })
          Row({ space: 12 }) {
            AppIcon({ name: 'folder', iconSize: 21, tint: this.color('foreground-secondary') })
            Text('浏览项目文件').fontSize(this.font(15)).fontColor(this.color('foreground')).layoutWeight(1)
            AppIcon({ name: 'chevron', iconSize: 15, tint: this.color('foreground-muted') })
          }.padding(16).width('100%').onClick(() => { this.sheetOpen = false; this.onFiles(); })
          if (this.project !== null) {
            Row({ space: 12 }) {
              AppIcon({ name: 'play', iconSize: 21, tint: this.color('foreground-secondary') })
              Text('项目脚本').fontSize(this.font(15)).fontColor(this.color('foreground')).layoutWeight(1)
              AppIcon({ name: 'plus', iconSize: 18, tint: this.color('foreground-muted') })
            }.padding(16).width('100%').onClick(() => { this.actionView = 'scripts'; })
          }
        }.width('100%').borderRadius(20).backgroundColor(this.color('card'))
        WorkspaceGit({ cwd: this.cwd, threadId: this.threadId, projectId: this.project?.id ?? '', branch: this.selectedBranch || this.currentBranch,
          worktreePath: this.worktree ? this.cwd : null, disabled: this.disabled, branchDisabled: this.branchDisabled,
          getRpc: () => this.getRpc(), onBranch: () => { this.openBranches(); },
          onReview: (scope: string) => { this.sheetOpen = false; this.onReview(scope); }
        })
        Column({ space: 4 }) {
          if (this.threadId) {
            Row({ space: 12 }) {
              AppIcon({ name: 'attach', iconSize: 22, tint: this.color('foreground-secondary') })
              Column({ space: 5 }) {
                Text('关联 Pull Request').fontSize(this.font(16)).fontColor(this.color('foreground')).width('100%')
                Text('通过地址或编号关联到当前任务').fontSize(this.font(12)).fontColor(this.color('foreground-muted')).width('100%')
              }.layoutWeight(1)
              AppIcon({ name: 'chevron', iconSize: 15, tint: this.color('foreground-muted') })
            }.padding(18).width('100%').onClick(() => { this.openAction('link'); })
          }
        }.width('100%').borderRadius(20).backgroundColor(this.color('card'))
        ForEach(this.visiblePullRequests(), (link: ThreadPullRequestLink) => {
          Row({ space: 10 }) {
            AppIcon({ name: 'attach', iconSize: 17, tint: this.color('primary') })
            Text(`${link.repository} #${link.number}`).fontSize(this.font(14)).fontColor(this.color('primary')).layoutWeight(1).copyOption(CopyOptions.LocalDevice)
            Button({ type: ButtonType.Circle }) { AppIcon({ name: 'close', iconSize: 17, tint: this.color('foreground-muted') }) }
              .width(34).height(34).padding(0).backgroundColor(Color.Transparent).enabled(!this.disabled && !this.actionBusy)
              .accessibilityText(`解除 PR #${link.number} 的关联`).onClick(() => { this.unlink(link); })
          }.padding(12).width('100%').backgroundColor(this.color('card')).borderRadius(14)
        }, (link: ThreadPullRequestLink) => `${link.host}/${link.repository}#${link.number}`)
        Text('工作目录').fontSize(this.font(13)).fontColor(this.color('foreground-muted')).width('100%').padding({ top: 8 })
        Text(this.cwd).fontSize(this.font(13)).fontColor(this.color('foreground-secondary')).width('100%').padding(16)
          .backgroundColor(this.color('card')).borderRadius(18).copyOption(CopyOptions.LocalDevice)
        }.width('100%')
        }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
      } else {
        if (this.iconOnly) {
          Row({ space: 8 }) {
            Button({ type: ButtonType.Circle }) { AppIcon({ name: 'back', iconSize: 20, tint: this.color('foreground') }) }
              .width(36).height(36).padding(0).backgroundColor(Color.Transparent).accessibilityText('返回工作区')
              .onClick(() => { this.choosingBranch = false; this.error = ''; })
            Text(this.branchDisabled ? '任务运行中，结束后可切换分支' : '选择分支或工作树').fontSize(this.font(14)).fontColor(this.color('foreground-muted')).layoutWeight(1)
          }.width('100%')
        }
        Text(this.cwd).fontSize(this.font(12)).fontColor(this.color('foreground-muted')).maxLines(2).width('100%')
        Row({ space: 8 }) {
        Search({ value: this.query, placeholder: '搜索分支' }).layoutWeight(1).textFont({ size: this.font(16) })
          .fontColor(this.color('foreground')).backgroundColor(this.color('input'))
          .onChange((value: string) => { this.searchRefs(value); }).onSubmit(() => { if (this.searchTimer !== -1) clearTimeout(this.searchTimer); this.searchTimer = -1; this.loadRefs(); })
        Button({ type: ButtonType.Circle }) { AppIcon({ name: 'plus', iconSize: 21, tint: this.color('foreground') }) }
          .width(40).height(40).padding(0).backgroundColor(this.color('card')).enabled(!this.disabled && !this.branchDisabled && this.isRepo)
          .accessibilityText('新建分支或工作树').bindMenu([
            { value: '新建分支', symbolIcon: menuIcon($r('sys.symbol.arrow_triangle_merge')), action: () => { this.openAction('branch'); } },
            { value: '新建工作树', symbolIcon: menuIcon($r('sys.symbol.folder_badge_plus')), action: () => { this.openAction('worktree'); } }
          ], { modalMode: menuModalMode() })
        }.width('100%')
        if (this.loading) { LoadingProgress().width(28).height(28) }
        if (!this.loading && this.refs.length === 0 && !this.error) {
          Text(this.isRepo ? '没有匹配的分支；新仓库需先有提交' : '当前目录不是 Git 仓库')
            .fontSize(this.font(14)).fontColor(this.color('foreground-muted'))
        }
        List() {
          ForEach(this.refs, (ref: WorkspaceRef) => {
            ListItem() {
              Button({ type: ButtonType.Normal }) {
                Row({ space: 12 }) {
                  AppIcon({ name: ref.worktreePath ? 'folder' : ref.isRemote ? 'cloud' : 'branch', iconSize: 22, tint: this.color('foreground-muted') })
                  Column({ space: 5 }) {
                    Text(ref.name).fontSize(this.font(16)).fontWeight(FontWeight.Medium).fontColor(this.color('foreground')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                    Text(this.refDescription(ref)).fontSize(this.font(12)).fontColor(this.color('foreground-muted')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                  }.layoutWeight(1)
                  if (ref.name === (this.selectedBranch || this.currentBranch)) { AppIcon({ name: 'check', iconSize: 20, tint: this.color('primary') }) }
                }.width('100%')
              }.height(72).width('100%').padding({ left: 16, right: 16 }).borderRadius(0).backgroundColor(Color.Transparent)
                .enabled(!this.disabled && !this.branchDisabled && !this.loading).onClick(() => { this.onBranch(ref); this.sheetOpen = false; })
                .accessibilityText(`选择分支 ${ref.name}，${this.refDescription(ref)}`)
            }
          }, (ref: WorkspaceRef) => `${ref.isRemote ? 'remote' : 'local'}:${ref.name}`)
          if (this.nextCursor !== null) {
            ListItem() { Button('加载更多分支').enabled(!this.loading).onClick(() => { this.loadRefs(true); }) }
          }
        }.layoutWeight(1).width('100%').borderRadius(20).backgroundColor('#B3' + this.color('card').slice(1)).clip(true)
      }
      if (this.error) {
        Text(this.error).fontColor(this.color('danger-foreground')).fontSize(this.font(13))
        Button('重试').enabled(!this.actionBusy).onClick(() => { if (this.actionView) this.submitAction(); else if (this.machinePicker) this.machines(); else this.loadRefs(); })
      }
    }.width('100%').height('100%').padding({ left: 20, right: 20, top: 8, bottom: 28 })
  }
  build() {
    Column() {
    if (this.iconOnly) {
      Button({ type: ButtonType.Circle }) { AppIcon({ name: 'branch', iconSize: 21, tint: this.color('glass-label') }) }
        .width(36).height(36).padding(0).backgroundColor(Color.Transparent).enabled(!this.disabled).accessibilityText('工作区与分支')
        .onClick(() => { this.machinePicker = false; this.actionView = ''; this.choosingBranch = false; this.sheetOpen = true; this.loadRefs(); })
    } else {
    Row({ space: 4 }) {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 5 }) {
          if (this.showConnection && connectionProgressLabel(this.connectionState)) {
            ConnectionSpinner({ status: this.connectionState })
          }
          AppIcon({ name: 'machine', iconSize: 13, tint: this.color('glass-label') })
          Text(EnvironmentSession.current?.descriptor.label ?? '选择机器').fontSize(this.font(11)).fontColor(this.color('glass-label'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }.backgroundColor(Color.Transparent).height(32).borderRadius(8).padding({ left: 6, right: 6 }).constraintSize({ maxWidth: 100 })
        .enabled(!this.disabled).onClick(() => { this.machines(); }).accessibilityText('选择机器')
      Divider().vertical(true).height(12).color(this.color('border'))
      if (this.canChooseWorktree) {
        Button({ type: ButtonType.Normal }) {
          Row({ space: 4 }) {
            AppIcon({ name: 'folder', iconSize: 14, tint: this.color('glass-label') })
            Text(this.newWorktree ? '新工作树' : this.worktree ? '工作树' : '本地').fontSize(this.font(12)).fontColor(this.color('glass-label'))
            AppIcon({ name: 'down', iconSize: 10, tint: this.color('glass-label') })
          }
        }.height(32).padding({ left: 4, right: 4 }).backgroundColor(Color.Transparent).enabled(!this.disabled && this.isRepo)
          .accessibilityText('执行位置：本地或新工作树').bindMenu([
            { value: '本地目录', symbolIcon: menuIcon($r('sys.symbol.folder')), action: () => { this.onWorktreeMode(false); } },
            { value: '新建工作树', symbolIcon: menuIcon($r('sys.symbol.folder_badge_plus')), action: () => { this.onWorktreeMode(true); } }
          ], { modalMode: menuModalMode() })
      } else {
        AppIcon({ name: 'folder', iconSize: 14, tint: this.color('glass-label') })
        Text(this.worktree ? '工作树' : '本地').fontSize(this.font(12)).fontColor(this.color('glass-label'))
      }
      Blank().layoutWeight(1)
      Button({ type: ButtonType.Normal }) {
        Row({ space: 5 }) {
          AppIcon({ name: 'branch', iconSize: 13, tint: this.color('glass-label') })
          Text(this.selectedBranch || this.currentBranch || '当前目录').fontSize(this.font(11)).fontColor(this.color('glass-label'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: 82 })
          AppIcon({ name: 'down', iconSize: 10, tint: this.color('glass-label') })
        }
      }.backgroundColor(Color.Transparent).height(32).borderRadius(8).padding({ left: 6, right: 6 })
        .enabled(!this.disabled && !this.branchDisabled).onClick(() => { this.machinePicker = false; this.actionView = ''; this.sheetOpen = true; this.query = ''; this.loadRefs(); })
        .accessibilityText('选择分支')
    }.width('100%').padding({ left: 12, right: 12, top: 2, bottom: 5 })
    }
    }.width(this.iconOnly ? 36 : '100%')
      .bindSheet($$this.sheetOpen, this.contextSheet(), { systemMaterial: immersiveMaterial('popup'), height: SheetSize.LARGE, title: { title: this.machinePicker ? '选择机器' : this.iconOnly && !this.choosingBranch ? this.selectedBranch || this.currentBranch || '工作区' : '选择分支' }, dragBar: true, showClose: true })
  }
}
