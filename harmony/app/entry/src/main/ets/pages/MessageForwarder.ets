import { ChatAttachment, ProjectShell, StartTurnCommand, ThreadShell } from '../model/Models';
import { ForwardContent, forwardTargets } from '../model/MessageForwarding';
import { ForwardJournal } from '../connection/ForwardJournal';
import { RpcRemoteError } from '../connection/Rpc';
import { ThemeRuntime } from '../connection/ThemeRuntime';
import { Typography, resolveTypography, scaledFontSize } from '../model/Typography';
import { AppIcon } from './AppIcon';
import { ProjectIcon } from './ProjectIcon';
import promptAction from '@ohos.promptAction';

@Component
export struct MessageForwarder {
  @Prop environmentId: string = '';
  @Prop sourceThreadId: string = '';
  @Prop content: ForwardContent = { text: '', attachments: [], count: 0 };
  @Prop threads: ThreadShell[] = [];
  @Prop projects: ProjectShell[] = [];
  @Prop online: boolean = false;
  prepare: (targetId: string, content: ForwardContent) => Promise<StartTurnCommand> = async () => { throw new Error('请恢复连接后转发'); };
  dispatch: (command: StartTurnCommand) => Promise<void> = async () => { throw new Error('请恢复连接后转发'); };
  onBusy: (busy: boolean) => void = () => {};
  onDone: () => void = () => {};
  @StorageLink('themeKey') themeKey: string = 't3-code-light';
  @StorageLink('textSizes') sizes: Typography = resolveTypography(16, null, null);
  @State query: string = '';
  @State targetId: string = '';
  @State pending: StartTurnCommand | null = null;
  @State ready: boolean = false;
  @State busy: boolean = false;
  @State error: string = '';
  private journal: ForwardJournal | null = null;
  private active: boolean = true;
  private color(role: string): string { return ThemeRuntime.color(this.themeKey, role); }
  private font(size: number): number { return scaledFontSize(size, this.sizes.baseFontSize); }
  private targets(): ThreadShell[] { return forwardTargets(this.threads, this.projects, this.sourceThreadId, this.query); }
  private project(thread: ThreadShell): ProjectShell | undefined { return this.projects.find((project: ProjectShell) => project.id === thread.projectId); }
  private previewText(): string { return this.pending?.message.text ?? this.content.text; }
  private attachments(): ChatAttachment[] { return (this.pending?.message.attachments as ChatAttachment[] | undefined) ?? this.content.attachments; }
  private targetTitle(): string { return this.threads.find((thread: ThreadShell) => thread.id === this.targetId)?.title || '原目标会话'; }

  aboutToAppear(): void { this.active = true; this.load(); }
  aboutToDisappear(): void { this.active = false; }
  private async load(): Promise<void> {
    try {
      const journal = await ForwardJournal.open(getContext(this).filesDir, this.environmentId, this.sourceThreadId);
      if (!this.active) return;
      this.journal = journal; this.pending = journal.pending;
      if (this.pending !== null) this.targetId = this.pending.threadId;
      this.ready = true;
    } catch (error) { this.error = error instanceof Error ? error.message : '转发记录读取失败'; }
  }

  private async send(): Promise<void> {
    const journal = this.journal;
    if (!this.ready || !this.online || !this.targetId || this.busy || journal === null) return;
    this.busy = true; this.onBusy(true); this.error = '';
    try {
      await journal.submit(() => this.prepare(this.targetId, this.content), (command: StartTurnCommand) => this.dispatch(command));
      this.pending = null;
      if (this.active) { promptAction.showToast({ message: '已转发，目标正在执行时会排队处理' }); this.onDone(); }
    } catch (error) {
      if (error instanceof RpcRemoteError && error.definitivelyRejected) {
        try { await journal.clear(); } catch (_) {}
      }
      this.pending = journal.pending;
      this.error = this.pending !== null ? '转发结果待确认，重试会使用同一条消息，避免重复发送' :
        (error instanceof Error ? error.message : '转发失败，请重试');
    } finally { this.busy = false; this.onBusy(false); }
  }

  build() {
    Column({ space: 12 }) {
      if (this.pending !== null) {
        Text('上次转发结果待确认，目标和内容已保留').fontSize(this.font(13)).fontColor(this.color('foreground-muted')).width('100%')
      } else {
        Search({ value: this.query, placeholder: '搜索会话、项目或分支' }).height(42).borderRadius(14)
          .textFont({ size: this.font(15) }).fontColor(this.color('foreground')).backgroundColor(this.color('input'))
          .enabled(!this.busy).onChange((value: string) => { this.query = value; })
      }
      List({ space: 2 }) {
        ForEach(this.targets(), (thread: ThreadShell) => {
          ListItem() {
            Button({ type: ButtonType.Normal }) {
              Row({ space: 12 }) {
                ProjectIcon({ cwd: this.project(thread)?.workspaceRoot ?? '', faviconPath: this.project(thread)?.faviconPath ?? '',
                  label: this.project(thread)?.title ?? '', iconSize: 26, chatFallback: true })
                Column({ space: 5 }) {
                  Text(thread.title || '未命名会话').fontSize(this.font(16)).fontColor(this.color('foreground')).maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                  Text([this.project(thread)?.title === 'No project' ? '独立任务' : this.project(thread)?.title ?? '', thread.branch ?? ''].filter((part: string) => !!part).join(' · '))
                    .fontSize(this.font(12)).fontColor(this.color('foreground-muted')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                if (thread.id === this.targetId) { AppIcon({ name: 'check', iconSize: 20, tint: this.color('primary') }) }
              }.width('100%')
            }.width('100%').constraintSize({ minHeight: 72 }).borderRadius(14).padding(12)
              .backgroundColor(thread.id === this.targetId ? this.color('subtle-strong') : Color.Transparent)
              .enabled(!this.busy && this.pending === null).accessibilityText(`转发到 ${thread.title || '未命名会话'}`)
              .onClick(() => { this.targetId = thread.id; this.error = ''; })
          }
        }, (thread: ThreadShell) => thread.id)
        if (this.targets().length === 0) {
          ListItem() { Text('没有匹配的目标会话').fontSize(this.font(14)).fontColor(this.color('foreground-muted')).padding(24).width('100%').textAlign(TextAlign.Center) }
        }
      }.layoutWeight(1).width('100%').borderRadius(20).backgroundColor(this.color('card')).clip(true)
      Text(this.pending !== null ? '待确认的转发内容' : `${this.content.count} 条消息将合并转发`).fontSize(this.font(13)).fontColor(this.color('foreground-muted')).width('100%')
      Scroll() {
        Text(this.previewText()).fontSize(this.font(14)).fontColor(this.color('foreground')).width('100%').copyOption(CopyOptions.LocalDevice).padding(12)
      }.height(130).width('100%').borderRadius(14).backgroundColor(this.color('card')).align(Alignment.TopStart)
      if (this.attachments().length > 0) {
        Text(this.attachments().map((attachment: ChatAttachment) => attachment.name).join('、'))
          .fontSize(this.font(12)).fontColor(this.color('foreground-muted')).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      }
      if (this.targetId) { Text(`发送到「${this.targetTitle()}」`).fontSize(this.font(13)).fontColor(this.color('foreground')).maxLines(2).width('100%') }
      if (!this.online) { Text('连接恢复后可转发，当前草稿和附件会保留').fontSize(this.font(12)).fontColor(this.color('foreground-muted')).width('100%') }
      if (this.error) { Text(this.error).fontSize(this.font(13)).fontColor(this.color('danger-foreground')).width('100%') }
      Button({ type: ButtonType.Normal }) {
        Row({ space: 8 }) {
          if (this.busy) { LoadingProgress().width(18).height(18).color(this.color('primary-foreground')) }
          else { AppIcon({ name: 'forward', iconSize: 20, tint: this.color('primary-foreground') }) }
          Text(this.busy ? '转发中…' : this.pending !== null ? '重试确认转发' : '确认转发').fontSize(this.font(15)).fontColor(this.color('primary-foreground'))
        }
      }.height(48).width('100%').borderRadius(16).backgroundColor(this.color('primary')).enabled(this.ready && this.online && !!this.targetId && !this.busy)
        .onClick(() => { this.send(); })
    }.padding({ left: 16, right: 16, top: 8, bottom: 24 }).width('100%').height('100%')
  }
}
