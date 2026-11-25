import { menuIcon, menuModalMode } from './MenuIcon';
import util from '@ohos.util';
import common from '@ohos.app.ability.common';
import { AppIcon } from './AppIcon';
import { EnvironmentSession } from '../connection/Environment';
import { RpcClient } from '../connection/Rpc';
import { WorkspaceGitStatus, WorkspaceGitResult, WorkspaceGitAction, workspaceGitActions, workspaceGitRequest, workspaceGitDisabled } from '../model/WorkspaceActions';
import { ThemeRuntime } from '../connection/ThemeRuntime';
import { Typography, resolveTypography, scaledFontSize } from '../model/Typography';

interface GitStatusRequest { cwd: string; localOnly?: boolean; }
interface GitBranchMetadata { type: string; commandId: string; threadId: string; branch: string; worktreePath: string | null; }

@Component
export struct WorkspaceGit {
  @StorageLink('themeKey') themeKey: string = 't3-code-light';
  @StorageLink('textSizes') sizes: Typography = resolveTypography(16, null, null);
  @Prop cwd: string = '';
  @Prop threadId: string = '';
  @Prop projectId: string = '';
  @Prop branch: string = '';
  @Prop worktreePath: string | null = null;
  @Prop disabled: boolean = false;
  @Prop branchDisabled: boolean = false;
  getRpc: () => RpcClient | null = () => EnvironmentSession.current?.rpc ?? null;
  onBranch: () => void = () => {};
  onReview: (scope: string) => void = () => {};
  @State status: WorkspaceGitStatus | null = null;
  @State loading: boolean = false;
  @State busy: boolean = false;
  @State error: string = '';
  @State resultText: string = '';
  @State resultUrl: string = '';
  @State expanded: boolean = false;
  @State action: string = 'commit_push_pr';
  @State message: string = '';
  @State featureBranch: boolean = false;
  private active: boolean = false;
  private revision: number = 0;
  private color(role: string): string { return ThemeRuntime.color(this.themeKey, role); }
  private font(size: number): number { return scaledFontSize(size, this.sizes.baseFontSize); }
  private actionLabel(): string { return workspaceGitActions().find((entry: WorkspaceGitAction) => entry.id === this.action)?.label ?? '选择操作'; }
  private disabledReason(): string {
    return this.branchDisabled ? '当前任务运行中，结束后可操作 Git' : workspaceGitDisabled(this.status, this.action, this.featureBranch);
  }
  aboutToAppear(): void { this.active = true; this.refresh(); }
  aboutToDisappear(): void { this.active = false; ++this.revision; }

  private async refresh(): Promise<void> {
    const rpc = this.getRpc(), connection = EnvironmentSession.current, revision = ++this.revision;
    if (rpc === null || !this.cwd) return;
    this.loading = true;
    try {
      // Show local data first; remote hosts can take longer over a weak connection.
      const local: GitStatusRequest = { cwd: this.cwd, localOnly: true };
      const status = await rpc.call<WorkspaceGitStatus>('vcs.refreshStatus', local);
      if (!this.active || revision !== this.revision || this.getRpc() !== rpc || EnvironmentSession.current !== connection) return;
      this.status = status; this.loading = false;
      const full: GitStatusRequest = { cwd: this.cwd };
      const remote = await rpc.call<WorkspaceGitStatus>('vcs.refreshStatus', full);
      if (this.active && revision === this.revision && this.getRpc() === rpc && EnvironmentSession.current === connection) this.status = remote;
    } catch (error) {
      if (this.active && revision === this.revision) this.error = `刷新 Git 状态失败：${error instanceof Error ? error.message : String(error)}`;
    } finally { if (this.active && revision === this.revision) this.loading = false; }
  }

  private async run(): Promise<void> {
    const rpc = this.getRpc(), connection = EnvironmentSession.current;
    if (rpc === null || connection === null || !this.active || this.disabled || this.busy || !this.threadId || this.disabledReason()) return;
    this.busy = true; this.error = ''; this.resultText = ''; this.resultUrl = ''; ++this.revision;
    try {
      const input = workspaceGitRequest(this.action, util.generateRandomUUID(true), this.cwd, this.threadId, this.projectId, this.message, this.featureBranch);
      const result = await rpc.call<WorkspaceGitResult>('git.runStackedAction', input);
      if (!this.active || this.getRpc() !== rpc || EnvironmentSession.current !== connection) return;
      this.resultText = 'Git 操作已完成'; this.resultUrl = result.pr.url ?? '';
      this.expanded = false; this.message = '';
      if (result.branch.status === 'created' && result.branch.name) {
        const metadata: GitBranchMetadata = { type: 'thread.metadata.update', commandId: util.generateRandomUUID(true),
          threadId: this.threadId, branch: result.branch.name, worktreePath: this.worktreePath };
        try { await rpc.call('orchestration.dispatchCommand', metadata); }
        catch (error) { if (this.active) this.error = `Git 操作已完成，但会话分支更新失败：${error instanceof Error ? error.message : String(error)}`; }
      }
      if (this.active && this.getRpc() === rpc && EnvironmentSession.current === connection) this.refresh();
    } catch (error) {
      if (this.active) this.error = `Git 操作未完成或结果尚未确认，请刷新状态后再操作：${error instanceof Error ? error.message : String(error)}`;
    } finally { if (this.active) this.busy = false; }
  }

  private openAction(action: string): void {
    this.action = action; this.featureBranch = this.status?.isDefaultRef === true && action !== 'commit';
    this.expanded = true; this.error = ''; this.resultText = '';
  }
  private openUrl(url: string): void {
    if (!/^https?:\/\//i.test(url)) return;
    const context = getContext(this) as common.UIAbilityContext;
    context.startAbility({ action: 'ohos.want.action.viewData', uri: url })
      .catch(() => { this.error = '无法打开变更请求，请复制链接后重试'; });
  }

  build() {
    Column({ space: 0 }) {
      Row({ space: 12 }) {
        AppIcon({ name: 'branch', iconSize: 21, tint: this.color('foreground-secondary') })
        Column({ space: 4 }) {
          Text(this.status?.refName || this.branch || '选择分支').fontSize(this.font(15)).fontColor(this.color('foreground')).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          Text(this.branchDisabled ? '任务运行中，结束后可切换' : '切换分支或工作树').fontSize(this.font(11)).fontColor(this.color('foreground-muted')).width('100%')
        }.layoutWeight(1)
        AppIcon({ name: 'down', iconSize: 15, tint: this.color('foreground-muted') })
      }.width('100%').padding(16).accessibilityText('切换分支或工作树').onClick(() => { if (!this.busy) this.onBranch(); })
      Divider().color(this.color('border'))
      Row({ space: 12 }) {
        AppIcon({ name: 'pull-request', iconSize: 21, tint: this.color('foreground-secondary') })
        Text('创建变更请求').fontSize(this.font(15)).fontColor(this.color('foreground')).layoutWeight(1)
        if (this.busy || this.loading) { LoadingProgress().width(20).height(20) }
        else { AppIcon({ name: 'down', iconSize: 15, tint: this.color('foreground-muted') }) }
      }.padding(16).width('100%').enabled(!this.disabled && !this.busy && !this.branchDisabled)
        .bindMenu(workspaceGitActions().map((entry: WorkspaceGitAction): MenuElement => ({ value: entry.label,
          symbolIcon: menuIcon(entry.icon === 'check' ? $r('sys.symbol.checkmark_clipboard') : entry.icon === 'send' ? $r('sys.symbol.arrow_up_to_line') : $r('sys.symbol.arrow_triangle_merge')),
          action: () => { this.openAction(entry.id); } })), { modalMode: menuModalMode() })
      Row({ space: 12 }) {
        AppIcon({ name: 'diff', iconSize: 21, tint: this.color('foreground-secondary') })
        Text(this.status?.branchChanges?.baseRef ? `改动 · 对比 ${this.status.branchChanges.baseRef}` : '查看改动')
          .fontSize(this.font(15)).fontColor(this.color('foreground')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        if (this.status !== null) {
          Text(`+${(this.status.branchChanges ?? this.status.workingTree).insertions}`).fontSize(this.font(12)).fontColor(ThemeRuntime.palette(this.themeKey).diff['addText'])
          Text(`−${(this.status.branchChanges ?? this.status.workingTree).deletions}`).fontSize(this.font(12)).fontColor(this.color('danger-foreground'))
        }
        AppIcon({ name: 'chevron', iconSize: 14, tint: this.color('foreground-muted') })
      }.padding(16).width('100%').onClick(() => { this.onReview(this.status?.branchChanges?.baseRef ? 'branch' : 'workspace'); })
      if (this.status?.pr?.state === 'open') {
        Row({ space: 10 }) {
          AppIcon({ name: 'pull-request', iconSize: 18, tint: this.color('primary') })
          Text(`#${this.status.pr.number} ${this.status.pr.title}`).fontSize(this.font(13)).fontColor(this.color('primary')).maxLines(2).layoutWeight(1)
        }.padding(16).width('100%').onClick(() => { this.openUrl(this.status?.pr?.url ?? ''); })
      }
      if (this.expanded) {
        Column({ space: 12 }) {
          Text(this.actionLabel()).fontSize(this.font(15)).fontColor(this.color('foreground')).width('100%')
          if (this.action.startsWith('commit')) {
            TextArea({ text: this.message, placeholder: '提交说明（可选，留空时自动生成）' }).height(90).maxLength(10000)
              .fontColor(this.color('foreground')).backgroundColor(this.color('input')).enabled(!this.busy)
              .onChange((value: string) => { this.message = value; })
          }
          if (this.action !== 'commit') {
            Row() {
              Checkbox().select(this.featureBranch).enabled(!this.busy).onChange((value: boolean) => { this.featureBranch = value; })
              Text('在新分支上发布').fontSize(this.font(13)).fontColor(this.color('foreground')).layoutWeight(1)
            }.width('100%')
          }
          if (this.disabledReason()) { Text(this.disabledReason()).fontSize(this.font(12)).fontColor(this.color('foreground-muted')).width('100%') }
          Row({ space: 10 }) {
            Button('取消').layoutWeight(1).enabled(!this.busy).onClick(() => { this.expanded = false; })
            Button(this.busy ? '正在执行…' : this.actionLabel()).layoutWeight(2).backgroundColor(this.color('primary')).fontColor(this.color('primary-foreground'))
              .enabled(!this.disabled && !this.busy && !this.disabledReason()).onClick(() => { this.run(); })
          }.width('100%')
        }.padding(16).width('100%')
      }
      if (this.resultText) { Text(this.resultText).fontSize(this.font(13)).fontColor(this.color('foreground-secondary')).padding(12).width('100%') }
      if (this.resultUrl) {
        Text(this.resultUrl).fontSize(this.font(13)).fontColor(this.color('primary')).padding(12).width('100%').copyOption(CopyOptions.LocalDevice)
          .onClick(() => { this.openUrl(this.resultUrl); })
      }
      if (this.error) { Text(this.error).fontSize(this.font(12)).fontColor(this.color('danger-foreground')).padding(12).width('100%') }
      Row({ space: 6 }) {
        Text(this.status?.isRepo === false ? '当前目录不是 Git 仓库' : this.status ? `领先 ${this.status.aheadCount ?? 0} · 落后 ${this.status.behindCount ?? 0}` : '正在读取仓库状态')
          .fontSize(this.font(11)).fontColor(this.color('foreground-muted')).layoutWeight(1)
        Button({ type: ButtonType.Circle }) { AppIcon({ name: 'refresh', iconSize: 16, tint: this.color('foreground-muted') }) }
          .width(32).height(32).padding(0).backgroundColor(Color.Transparent).enabled(!this.loading && !this.busy).accessibilityText('刷新 Git 状态')
          .onClick(() => { this.error = ''; this.refresh(); })
      }.padding({ left: 16, right: 12, bottom: 8 }).width('100%')
    }.width('100%').backgroundColor(this.color('card')).borderRadius(20)
  }
}
