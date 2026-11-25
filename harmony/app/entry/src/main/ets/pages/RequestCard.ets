import { ChatGlass, immersiveMaterial } from './ChatGlass';
import { statusColor } from '../model/StatusVisuals';
import { menuIcon, menuModalMode } from './MenuIcon';
import { Typography, resolveTypography, scaledFontSize } from '../model/Typography';
import { RequestDrafts } from '../model/RequestDrafts';
import { ThemeRuntime } from '../connection/ThemeRuntime';
import { PendingRequest, ApprovalOption, InputQuestion, InputOption, AnswerDraft, questionAnswers } from '../model/Models';
import { ChatAttachment } from '../model/Models';
import { AppIcon } from './AppIcon';
import { DraftImages, DraftImageProgress } from './DraftImages';
import { AttachmentDraftStore, DraftImage } from '../connection/AttachmentDraftStore';
import { uploadImage, deleteImageUpload, imageUploadExists } from '../connection/ImageAttachment';
import { EnvironmentSession } from '../connection/Environment';
import photoAccessHelper from '@ohos.file.photoAccessHelper';
import picker from '@ohos.file.picker';
import fileUri from '@ohos.file.fileuri';

interface QuestionFiles { questionId: string; images: DraftImageProgress[]; }

@Component
export struct RequestCard {
  private font(size: number): number { return scaledFontSize(size, this.sizes.baseFontSize); }
  @StorageLink('textSizes') sizes: Typography = resolveTypography(16, null, null);
  @StorageLink('themeKey') themeKey: string = 't3-code-light';
  private color(role: string): string { return ThemeRuntime.color(this.themeKey, role); }
  @Prop request: PendingRequest = { requestId: '', kind: '', title: '', detail: '', options: [], questions: [] };
  @Prop busy: boolean = false;
  @Prop environmentId: string = '';
  @Prop threadId: string = '';
  @Prop online: boolean = true;
  @Prop maxHeight: number = 520;
  @Prop @Watch('loadAttachments') canAttach: boolean = false;
  @Prop maxFileBytes: number = 0;
  @Prop canStop: boolean = false;
  @State drafts: AnswerDraft[] = [];
  @State collapsed: boolean = false;
  @State approvalDetailsOpen: boolean = false;
  @State picking: boolean = false;
  @State attachmentsReady: boolean = false;
  @State attachmentGroups: QuestionFiles[] = [];
  @State attachmentError: string = '';
  @State resolved: boolean = false;
  private active: boolean = false;
  private loadingAttachments: boolean = false;
  private stores: Map<string, AttachmentDraftStore> = new Map();
  private progress: Map<string, number> = new Map();
  private failures: Map<string, string> = new Map();
  private upload: Promise<void> | null = null;
  onStop: () => void = () => {};
  onRespond: (decision: string, answers: Record<string, string | string[]>, attachments: Record<string, ChatAttachment[]>, dismiss: boolean) => Promise<boolean> = async () => false;

  private waitingTint(): string { return statusColor('waiting', this.color('card')); }
  private detailFont(): number { return this.request.approvalKind === 'command' ? this.sizes.codeFontSize : this.font(14); }
  private approvalStatus(): string {
    return this.resolved ? '已提交' : this.picking || this.busy ? '正在提交…' : this.online ? '等待审批' : '等待连接';
  }
  private decisionInk(decision: string): string {
    return this.color(decision === 'accept' ? 'primary-foreground' : decision === 'decline' ? 'danger-foreground' : 'foreground');
  }
  private decisionIcon(decision: string): string {
    switch (decision) {
      case 'accept': return 'check';
      case 'acceptForSession': return 'clock';
      case 'acceptAlways': return 'check-all';
      case 'decline': return 'close';
      default: return 'back';
    }
  }

  aboutToAppear(): void {
    this.active = true;
    this.drafts = RequestDrafts.read(this.environmentId, this.threadId, this.request.requestId);
    this.loadAttachments();
  }
  aboutToDisappear(): void { this.active = false; }

  private draftFor(id: string): AnswerDraft {
    return this.drafts.find((draft: AnswerDraft) => draft.questionId === id) ?? {
      questionId: id, selected: [], custom: this.request.questions.find((question: InputQuestion) => question.id === id)?.initialAnswer ?? '' };
  }

  private save(draft: AnswerDraft): void {
    this.drafts = this.drafts.filter((entry: AnswerDraft) => entry.questionId !== draft.questionId).concat([draft]);
    RequestDrafts.save(this.environmentId, this.threadId, this.request.requestId, this.drafts);
  }

  private select(question: InputQuestion, label: string): void {
    const prior = this.draftFor(question.id);
    const selected = question.multiSelect
      ? (prior.selected.includes(label) ? prior.selected.filter((value: string) => value !== label) : prior.selected.concat([label]))
      : [label];
    const draft: AnswerDraft = { questionId: question.id, selected: selected, custom: '' };
    this.save(draft);
  }

  private async loadAttachments(): Promise<void> {
    if (!this.active || this.loadingAttachments) return;
    this.attachmentsReady = !this.canAttach;
    if (!this.canAttach || this.request.kind === 'approval') return;
    this.loadingAttachments = true;
    try {
      for (const question of this.request.questions) {
        if (question.allowCustomAnswer === false || this.stores.has(question.id)) continue;
        const store = await AttachmentDraftStore.open(getContext(this).filesDir, this.environmentId,
          `question:${this.threadId}:${this.request.requestId}:${question.id}`);
        if (!this.active) return;
        this.stores.set(question.id, store);
      }
      this.attachmentsReady = true; this.refreshAttachments(); this.uploadAttachments();
    } catch (error) { this.attachmentError = error instanceof Error ? error.message : String(error); }
    finally { this.loadingAttachments = false; }
  }
  private refreshAttachments(): void {
    this.attachmentGroups = this.request.questions.map((question: InputQuestion): QuestionFiles => ({ questionId: question.id,
      images: (this.stores.get(question.id)?.images ?? []).map((image: DraftImage): DraftImageProgress => ({
        uri: image.uri, name: image.name, type: image.type ?? 'image', sizeBytes: image.sizeBytes,
        status: image.uploaded ? 'uploaded' : this.failures.has(image.uri) ? 'failed' : this.progress.has(image.uri) ? 'uploading' : 'waiting',
        progress: image.uploaded ? 100 : this.progress.get(image.uri) ?? 0, error: this.failures.get(image.uri) ?? '' })) }));
  }
  private filesFor(questionId: string): DraftImageProgress[] { return this.attachmentGroups.find((group: QuestionFiles) => group.questionId === questionId)?.images ?? []; }
  private fileCount(): number { return this.attachmentGroups.reduce((count: number, group: QuestionFiles) => count + group.images.length, 0); }
  private attachments(): Record<string, ChatAttachment[]> {
    const result: Record<string, ChatAttachment[]> = {};
    this.stores.forEach((store: AttachmentDraftStore, id: string) => {
      const uploaded: ChatAttachment[] = [];
      for (const image of store.images) if (image.uploaded) uploaded.push({ type: image.uploaded.type, id: image.uploaded.id,
        name: image.uploaded.name, mimeType: image.uploaded.mimeType, sizeBytes: image.uploaded.sizeBytes });
      if (uploaded.length > 0) result[id] = uploaded;
    });
    return result;
  }
  private ready(): boolean {
    return this.online && !this.busy && !this.picking && !this.resolved && this.attachmentsReady &&
      this.attachmentGroups.every((group: QuestionFiles) => group.images.every((image: DraftImageProgress) => image.status === 'uploaded'));
  }
  private answers(): Record<string, string | string[]> | null {
    return questionAnswers(this.request.questions, this.request.questions.map((question: InputQuestion) => this.draftFor(question.id)), this.attachments());
  }
  private async pick(questionId: string, files: boolean): Promise<void> {
    const store = this.stores.get(questionId), connection = EnvironmentSession.current;
    if (!store || !this.canAttach || !this.online || this.busy || this.picking || this.resolved || this.fileCount() >= 8 || connection?.descriptor.environmentId !== this.environmentId) return;
    this.picking = true; this.attachmentError = '';
    try {
      const count = 8 - this.fileCount();
      const uris = files ? await new picker.DocumentViewPicker().select({ maxSelectNumber: count }) :
        (await new photoAccessHelper.PhotoViewPicker().select({ MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE, maxSelectNumber: count })).photoUris;
      for (const uri of uris) {
        if (!this.active || connection !== EnvironmentSession.current) return;
        const name = new fileUri.FileUri(uri).name;
        if (files) await store.addFile(uri, name, this.maxFileBytes); else await store.add(uri, name);
        this.refreshAttachments(); this.uploadAttachments();
      }
    } catch (error) { this.attachmentError = error instanceof Error ? error.message : String(error); }
    finally { this.picking = false; }
  }
  private uploadAttachments(): Promise<void> {
    if (this.upload !== null) return this.upload;
    const pending: Promise<void> = this.transferAttachments().finally(() => { if (this.upload === pending) this.upload = null; });
    this.upload = pending; return pending;
  }
  private async transferAttachments(): Promise<void> {
    const connection = EnvironmentSession.current;
    if (!connection || connection.descriptor.environmentId !== this.environmentId || !this.online) return;
    while (this.active && !this.resolved && connection === EnvironmentSession.current) {
      const group = this.request.questions.find((question: InputQuestion) => this.stores.get(question.id)?.images.some((image: DraftImage) => !image.uploaded && !this.failures.has(image.uri)));
      const store = group ? this.stores.get(group.id) : undefined;
      const image = store?.images.find((entry: DraftImage) => !entry.uploaded && !this.failures.has(entry.uri));
      if (!store || !image) return;
      try {
        const uploaded = await uploadImage(connection.rpc, connection.httpBaseUrl, image.uri, image.name ?? '', (percent: number) => {
          if (!this.active || this.progress.get(image.uri) === percent) return;
          this.progress.set(image.uri, percent); this.refreshAttachments();
        }, image.type ?? 'image', image.type === 'file' ? this.maxFileBytes : 10 * 1024 * 1024);
        try { await store.setUploaded(image.uri, uploaded); }
        catch (error) { await deleteImageUpload(connection.rpc, uploaded.id); throw new Error(error instanceof Error ? error.message : String(error)); }
        if (!store.images.some((entry: DraftImage) => entry.uri === image.uri)) await deleteImageUpload(connection.rpc, uploaded.id);
      } catch (error) { this.failures.set(image.uri, error instanceof Error ? error.message : String(error)); }
      if (this.active) this.refreshAttachments();
    }
  }
  private async remove(questionId: string, uri: string): Promise<void> {
    const store = this.stores.get(questionId), connection = EnvironmentSession.current;
    if (!store || !connection || connection.descriptor.environmentId !== this.environmentId || this.busy || this.resolved || this.picking) return;
    this.picking = true;
    try {
      const uploaded = store.images.find((image: DraftImage) => image.uri === uri)?.uploaded;
      if (uploaded) await deleteImageUpload(connection.rpc, uploaded.id);
      await store.remove(uri); this.failures.delete(uri); this.progress.delete(uri); this.refreshAttachments();
    } catch (error) { this.attachmentError = error instanceof Error ? error.message : String(error); }
    finally { this.picking = false; }
  }
  private async submit(decision: string = '', dismiss: boolean = false): Promise<void> {
    if (!this.online || this.busy || this.resolved || this.picking || (dismiss && !this.request.dismissible)) return;
    const approval = this.request.kind === 'approval';
    const answers: Record<string, string | string[]> | null = approval || dismiss ? {} : this.answers();
    if (answers === null || (!approval && !dismiss && !this.ready())) return;
    this.picking = true;
    try {
      const connection = EnvironmentSession.current;
      if (!connection || connection.descriptor.environmentId !== this.environmentId) throw new Error('连接已关闭，回答已保留');
      if (!dismiss) for (const store of this.stores.values()) for (const image of store.images) {
        if (image.uploaded && !await imageUploadExists(connection.rpc, image.uploaded.id)) {
          await store.setUploaded(image.uri, undefined); this.refreshAttachments(); this.uploadAttachments();
          throw new Error('附件已过期，正在重新上传，请完成后提交');
        }
      }
      if (await this.onRespond(decision, answers, dismiss ? {} : this.attachments(), dismiss)) {
        this.resolved = true;
        for (const store of this.stores.values()) await store.clear();
      }
    } catch (error) { this.attachmentError = error instanceof Error ? error.message : String(error); }
    finally { this.picking = false; }
  }
  @Builder
  private attachmentMenu(questionId: string) {
    Menu() {
      MenuItem({ content: '照片', symbolStartIcon: menuIcon($r('sys.symbol.picture')) }).onClick(() => { this.pick(questionId, false); })
      MenuItem({ content: '文件附件', symbolStartIcon: menuIcon($r('sys.symbol.paperclip')) }).enabled(this.maxFileBytes > 0).onClick(() => { this.pick(questionId, true); })
    }
  }

  @Builder
  private approvalDetailSheet() {
    Scroll() {
      Text(this.request.detail).fontFamily(this.request.approvalKind === 'command' ? 'monospace' : 'sans-serif')
        .fontSize(this.detailFont()).lineHeight(this.detailFont() + 7).fontColor(this.color('foreground'))
        .wordBreak(WordBreak.BREAK_WORD).copyOption(CopyOptions.LocalDevice).width('100%')
        .padding(14).backgroundColor(this.color('md-code-bg')).borderRadius(14)
    }.width('100%').height('100%').align(Alignment.TopStart).padding({ left: 16, right: 16, bottom: 16 })
      .scrollBar(BarState.Auto).scrollBarWidth(2)
  }

  @Builder
  private approvalPreview() {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 5 }) {
        Row({ space: 6 }) {
          AppIcon({ name: this.request.approvalKind === 'command' ? 'terminal' : 'file', iconSize: 14, tint: this.color('glass-label') })
          Text(this.request.approvalKind === 'command' ? '命令预览' : '请求详情').fontSize(this.font(12)).fontColor(this.color('glass-label')).layoutWeight(1)
          Text('查看全文').fontSize(this.font(12)).fontColor(this.color('chat-link'))
          AppIcon({ name: 'chevron', iconSize: 12, tint: this.color('chat-link') })
        }.width('100%')
        Text(this.request.detail.length > 240 ? this.request.detail.slice(0, 240) + '…' : this.request.detail)
          .fontFamily(this.request.approvalKind === 'command' ? 'monospace' : 'sans-serif').fontSize(this.detailFont()).lineHeight(this.detailFont() + 5)
          .fontColor(this.color('foreground')).width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.width('100%').alignItems(HorizontalAlign.Start)
    }.width('100%').height(LayoutPolicy.wrapContent).padding({ left: 12, right: 12, top: 9, bottom: 9 })
      .backgroundColor('#CC' + this.color('card').slice(1)).borderRadius(12).clip(true)
      .accessibilityText(this.request.approvalKind === 'command' ? '查看完整命令' : '查看完整请求').onClick(() => { this.approvalDetailsOpen = true; })
      .bindSheet($$this.approvalDetailsOpen, this.approvalDetailSheet(), { systemMaterial: immersiveMaterial('popup'), height: SheetSize.LARGE,
        title: { title: this.request.approvalKind === 'command' ? '完整命令' : '审批详情' }, dragBar: true, showClose: true })
  }

  @Builder
  private approvalCard() {
    ChatGlass({ radius: 20 }) {
      Column({ space: 8 }) {
        Row({ space: 6 }) {
          Button({ type: ButtonType.Normal }) {
            Row({ space: 10 }) {
              Stack() { AppIcon({ name: 'shield', iconSize: 19, tint: this.waitingTint() }) }
                .width(34).height(34).borderRadius(12).backgroundColor('#22' + this.waitingTint().slice(1))
              Column({ space: 2 }) {
                Text(this.approvalStatus()).fontSize(this.font(12)).fontWeight(FontWeight.Medium).fontColor(this.waitingTint())
                Text(this.request.title).fontSize(this.font(16)).fontWeight(FontWeight.Bold).fontColor(this.color('foreground'))
                  .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              AppIcon({ name: 'down', iconSize: 15, tint: this.color('glass-label') }).rotate({ angle: this.collapsed ? 180 : 0 })
            }.width('100%')
          }.layoutWeight(1).height(LayoutPolicy.wrapContent).constraintSize({ minHeight: 44 }).padding({ left: 2, right: 6 })
            .borderRadius(12).backgroundColor(Color.Transparent).accessibilityText(`${this.approvalStatus()}，${this.request.title}，${this.collapsed ? '展开' : '收起'}`)
            .onClick(() => { this.collapsed = !this.collapsed; })
          if (this.collapsed && this.canStop) {
            Button({ type: ButtonType.Circle }) { AppIcon({ name: 'stop', iconSize: 16, tint: this.color('danger-foreground') }) }
              .width(44).height(44).padding(0).backgroundColor(this.color('danger')).accessibilityText('停止任务').onClick(() => { this.onStop(); })
          }
        }.width('100%')
        if (!this.collapsed) {
          Scroll() {
            Column({ space: 8 }) {
              if (this.request.detail) { this.approvalPreview() }
              ForEach(this.request.options.filter((option: ApprovalOption) => !!option.warning), (option: ApprovalOption) => {
                Text(`${option.label}：${option.warning}`).fontSize(this.font(13)).fontColor(this.waitingTint()).width('100%')
              }, (option: ApprovalOption) => option.decision + ':' + option.warning)
              GridRow({ columns: { xs: 1, sm: Math.min(2, this.request.options.length), md: Math.min(3, this.request.options.length) },
                breakpoints: { value: [`${this.font(98) * 2 + 6}vp`, `${this.font(98) * 3 + 12}vp`], reference: BreakpointsReference.ComponentSize }, gutter: 6 }) {
                ForEach(this.request.options, (option: ApprovalOption, index: number) => {
                  GridCol({ span: option.label.length > 14 ? 3 : { xs: 1, sm: index === this.request.options.length - 1 && index % 2 === 0 ? 2 : 1, md: 1 } }) {
                    Button({ type: ButtonType.Normal }) {
                      Row({ space: 4 }) {
                        AppIcon({ name: this.decisionIcon(option.decision), iconSize: 15, tint: this.decisionInk(option.decision) })
                        Text(option.label).fontSize(this.font(13)).fontWeight(FontWeight.Medium).fontColor(this.decisionInk(option.decision))
                          .textAlign(TextAlign.Center).wordBreak(WordBreak.BREAK_WORD).flexShrink(1)
                      }.width('100%').justifyContent(FlexAlign.Center)
                    }.width('100%').height(LayoutPolicy.wrapContent).constraintSize({ minHeight: 44 })
                      .padding({ left: 6, right: 6, top: 7, bottom: 7 }).borderRadius(12).clip(true)
                      .backgroundColor(this.color(option.decision === 'accept' ? 'primary' : option.decision === 'decline' ? 'danger' : 'chat-reply'))
                      .accessibilityText(option.label).enabled(this.online && !this.busy && !this.picking && !this.resolved).onClick(() => { this.submit(option.decision); })
                  }
                }, (option: ApprovalOption) => option.decision + ':' + option.label)
              }.width('100%')
              if (this.attachmentError) { Text(this.attachmentError).fontSize(this.font(12)).fontColor(this.color('danger-foreground')).width('100%') }
            }.width('100%').alignItems(HorizontalAlign.Start)
          }.width('100%').constraintSize({ maxHeight: Math.max(88, this.maxHeight - this.font(68) - 28) }).scrollBar(BarState.Auto).scrollBarWidth(2)
        }
      }.width('100%').padding(this.collapsed ? 8 : 12).border({ width: 0.5, radius: 20, color: this.color('chat-outline') }).clip(true)
        .hitTestBehavior(HitTestMode.Default)
    }
  }

  @Builder
  private questionCard() {
    Column({ space: 10 }) {
      if (this.collapsed) {
        Row({ space: 8 }) {
          Text('等待回答').fontSize(this.font(11)).fontWeight(FontWeight.Bold).fontColor(this.color('foreground-secondary'))
          Text(`${this.request.questions.length} 个问题`).fontSize(this.font(12)).fontColor(this.color('foreground-muted')).layoutWeight(1)
          AppIcon({ name: 'down', iconSize: 14, tint: this.color('foreground-muted') }).rotate({ angle: 180 })
          if (this.canStop) {
            Button({ type: ButtonType.Circle }) { AppIcon({ name: 'stop', iconSize: 16, tint: this.color('danger-foreground') }) }
              .width(36).height(36).padding(0).backgroundColor(this.color('danger')).accessibilityText('停止任务').onClick(() => { this.onStop(); })
          }
        }.width('100%').constraintSize({ minHeight: 36 }).onClick(() => { this.collapsed = false; }).accessibilityText('展开待处理请求')
      } else {
        Row({ space: 8 }) {
          Column({ space: 10 }) {
            Text('等待回答').fontSize(this.font(11)).fontWeight(FontWeight.Bold).fontColor(this.color('foreground-secondary')).width('100%')
            Text('请回答以下问题').fontSize(this.font(18)).fontWeight(FontWeight.Bold).fontColor(this.color('foreground')).width('100%')
          }.layoutWeight(1)
          AppIcon({ name: 'down', iconSize: 14, tint: this.color('foreground-muted') }).width(32).height(32)
        }.width('100%').alignItems(VerticalAlign.Top).onClick(() => { this.collapsed = true; }).accessibilityText('折叠待处理请求')
        Scroll() {
          Column({ space: 10 }) {
            if (this.request.detail) { Text(this.request.detail).fontSize(this.font(14)).fontColor(this.color('foreground')).width('100%').copyOption(CopyOptions.LocalDevice) }
            ForEach(this.request.questions, (question: InputQuestion) => {
              Column({ space: 8 }) {
                Text(question.header.trim().toLowerCase() === 'question' ? '问题' : question.header).fontSize(this.font(12)).fontWeight(FontWeight.Bold).fontColor(this.color('foreground-muted')).width('100%')
                Text(question.question).fontSize(this.font(16)).lineHeight(this.font(22)).fontColor(this.color('foreground')).width('100%')
                if (question.multiSelect) { Text('可选择多项').fontSize(this.font(12)).fontColor(this.color('foreground-muted')).width('100%') }
                ForEach(question.options, (option: InputOption) => {
                  Button({ type: ButtonType.Normal }) {
                    Column({ space: 2 }) {
                      Text(option.label).fontSize(this.font(14)).fontWeight(FontWeight.Bold).fontColor(this.color(this.draftFor(question.id).selected.includes(option.value ?? option.label.trim()) ? 'foreground' : 'foreground-secondary')).width('100%')
                      if (option.description && option.description !== option.label) { Text(option.description).fontSize(this.font(14)).fontColor(this.color('foreground-muted')).width('100%') }
                    }.width('100%').alignItems(HorizontalAlign.Start)
                  }.width('100%').constraintSize({ minHeight: 48 }).padding({ left: 14, right: 14, top: 12, bottom: 12 }).borderRadius(16)
                    .backgroundColor(this.draftFor(question.id).selected.includes(option.value ?? option.label.trim()) ? '#1A' + this.color('primary').slice(1) : this.color('input'))
                    .border({ width: 1, color: this.color(this.draftFor(question.id).selected.includes(option.value ?? option.label.trim()) ? 'primary' : 'border') })
                    .enabled(this.online && !this.busy && !this.picking && !this.resolved).onClick(() => { this.select(question, option.value ?? option.label.trim()); })
                    .accessibilityText(option.label + (this.draftFor(question.id).selected.includes(option.value ?? option.label.trim()) ? '，已选择' : ''))
                }, (option: InputOption) => option.value ?? option.label)
                if (question.allowCustomAnswer !== false) {
                  if (this.canAttach) {
                    Button({ type: ButtonType.Circle }) { AppIcon({ name: 'plus', iconSize: 22, tint: this.color('foreground') }) }
                      .width(44).height(44).padding(0).backgroundColor(Color.Transparent).accessibilityText('添加回答附件')
                      .enabled(this.attachmentsReady && this.online && !this.busy && !this.picking && !this.resolved && this.fileCount() < 8).bindMenu(this.attachmentMenu(question.id), { modalMode: menuModalMode() })
                  }
                  if (this.filesFor(question.id).length > 0) {
                    DraftImages({ images: this.filesFor(question.id), disabled: this.busy || this.picking || this.resolved,
                      onRemove: (uri: string) => { this.remove(question.id, uri); },
                      onRetry: (uri: string) => { this.failures.delete(uri); this.progress.delete(uri); this.attachmentError = ''; this.refreshAttachments(); this.uploadAttachments(); } })
                  }
                  TextInput({ text: this.draftFor(question.id).custom, placeholder: '也可以输入自定义回答' }).fontSize(this.font(16)).fontColor(this.color('foreground'))
                    .backgroundColor(this.color('input')).placeholderColor(this.color('placeholder')).height(54).borderRadius(16).border({ width: 1, color: this.color('border') }).padding({ left: 14, right: 14 })
                    .enabled(this.online && !this.busy && !this.picking && !this.resolved).onChange((value: string) => { this.save({ questionId: question.id, selected: [], custom: value }); })
                    .accessibilityText(question.header + '，自定义回答')
                }
              }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 4 })
            }, (question: InputQuestion) => question.id)
            if (this.attachmentError) { Text(this.attachmentError).fontSize(this.font(12)).fontColor(this.color('danger-foreground')).width('100%') }
          }.width('100%').alignItems(HorizontalAlign.Start).padding({ bottom: 4 })
        }.width('100%').constraintSize({ maxHeight: Math.max(80, this.maxHeight - (this.request.dismissible ? 200 : 155)) }).nestedScroll({ scrollForward: NestedScrollMode.SELF_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
        Button(this.busy ? '正在提交…' : '提交回答', { type: ButtonType.Normal }).fontSize(this.font(14)).fontWeight(FontWeight.Bold)
          .fontColor(this.color(this.answers() !== null ? 'primary-foreground' : 'foreground')).backgroundColor(this.color(this.answers() !== null ? 'primary' : 'subtle-strong'))
          .width('100%').height(48).borderRadius(16).opacity(this.ready() && this.answers() !== null ? 1 : 0.5)
          .enabled(this.ready() && this.answers() !== null).onClick(() => { this.submit(); })
        if (this.request.dismissible) {
          Button('暂不回答', { type: ButtonType.Normal }).fontSize(this.font(14)).fontWeight(FontWeight.Bold)
            .fontColor(this.color('foreground-muted')).backgroundColor(Color.Transparent).width('100%').height(44).borderRadius(16)
            .enabled(this.online && !this.busy && !this.picking && !this.resolved).onClick(() => { this.submit('', true); })
        }
      }
    }.width('100%').padding(this.collapsed ? 8 : 16).borderRadius(this.collapsed ? 28 : 20)
      .backgroundColor(this.color('card-alt')).border({ width: 1, color: this.color('border') }).alignItems(HorizontalAlign.Start)
  }

  build() {
    if (this.request.kind === 'approval') { this.approvalCard() } else { this.questionCard() }
  }
}
