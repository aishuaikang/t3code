import router from '@ohos.router';
import { AppIcon } from './AppIcon';
import { ChatAttachment, MessageContext } from '../model/Models';
import { AttachmentPart, attachmentParts, attachmentSize, attachmentFileRows, attachmentFormat } from '../model/AttachmentLabels';
import { ThemeRuntime } from '../connection/ThemeRuntime';
import { Typography, resolveTypography, scaledFontSize } from '../model/Typography';
import { ComposerSkill, ComposerSpan, messageSkillSpans, messageReferenceSpans } from '../model/ComposerDocument';
import { attachmentGallery } from '../model/ImageGallery';
import { ThreadReference, ThreadReferenceLink, threadReferenceTarget, presentThreadReference, threadReferenceIconTint } from '../model/ThreadReferences';
import { loadThreadReferences } from '../connection/ThreadReferences';
import { EnvironmentSession } from '../connection/Environment';
import { openThreadReference } from './ThreadReferenceNavigation';

@Component
export struct AttachmentText {
  @Prop @Watch('reloadReferences') text: string = '';
  @Prop attachments: ChatAttachment[] = [];
  @Prop @Watch('reloadReferences') environmentId: string = '';
  @Prop threadId: string = '';
  @Prop @Watch('reloadReferences') messageContext: MessageContext | undefined = undefined;
  @Prop showFiles: boolean = true;
  @Prop selectable: boolean = true;
  @Prop referencesDisabled: boolean = false;
  @Prop skills: ComposerSkill[] = [];
  @StorageLink('themeKey') themeKey: string = 't3-code-light';
  @StorageLink('textSizes') sizes: Typography = resolveTypography(16, null, null);
  @State references: ThreadReference[] = [];
  @State actionError: string = '';
  private referenceRevision: number = 0;
  private active: boolean = false;
  aboutToAppear(): void { this.active = true; this.reloadReferences(); }
  aboutToDisappear(): void { this.active = false; ++this.referenceRevision; }
  private reloadReferences(): void {
    const revision = ++this.referenceRevision, connection = EnvironmentSession.current;
    this.references = [];
    const links = messageReferenceSpans(this.text, this.skills).filter((span: ComposerSpan) => span.kind === 'thread')
      .map((span: ComposerSpan): ThreadReferenceLink => ({ href: span.href ?? '', label: span.label }));
    if (links.length > 0) loadThreadReferences(getContext(this).filesDir, this.environmentId, links, this.messageContext).then((references: ThreadReference[]) => {
      if (this.active && revision === this.referenceRevision && connection === EnvironmentSession.current) this.references = references;
    }).catch(() => {});
  }
  private reference(span: ComposerSpan): ThreadReference {
    const href = span.href ?? '', target = threadReferenceTarget(href, this.environmentId, this.messageContext);
    return this.references.find((entry: ThreadReference) => entry.href === href) ?? presentThreadReference(href, span.label,
      target ?? { environmentId: '', threadId: '', title: '' }, [], [], {});
  }
  private threadTint(): string { return ThemeRuntime.palette(this.themeKey).scheme === 'dark' ? '#5EEAD4' : '#0F766E'; }
  private referenceTint(span: ComposerSpan): string { return threadReferenceIconTint(this.reference(span).iconColor, ThemeRuntime.palette(this.themeKey).scheme === 'dark'); }
  private openReference(span: ComposerSpan): void {
    if (this.referencesDisabled) return;
    openThreadReference(this.reference(span), this.environmentId, this.threadId).catch((error: Error) => { this.actionError = error.message; });
  }
  private singleSkill(): ComposerSpan | undefined {
    if (this.attachments.length > 0) return undefined;
    const spans = messageSkillSpans(this.text, this.skills);
    const skills = spans.filter((span: ComposerSpan) => span.kind === 'skill');
    return skills.length === 1 && spans.every((span: ComposerSpan) => span.kind === 'skill' || !span.raw.trim()) ? skills[0] : undefined;
  }
  private open(id: string): void {
    const attachment = this.attachments.find((image: ChatAttachment) => image.id === id);
    if (!attachment) return;
    if (attachment.type !== 'image') {
      router.pushUrl({ url: 'pages/Files', params: { environmentId: this.environmentId, threadId: this.threadId,
        attachmentId: attachment.id, name: attachment.name, mimeType: attachment.mimeType } });
      return;
    }
    router.pushUrl({ url: 'pages/ImagePreview', params: { environmentId: this.environmentId,
      gallery: JSON.stringify(attachmentGallery(this.attachments)), imageIndex: String(this.attachments.filter((image: ChatAttachment) => image.type === 'image').findIndex((image: ChatAttachment) => image.id === id)),
      commentThreadId: this.threadId,
      attachmentId: attachment.id, name: attachment.name, mimeType: attachment.mimeType } });
  }
  build() {
    Column({ space: 6 }) {
      if (this.showFiles) {
        ForEach(attachmentFileRows(this.text, this.attachments), (attachment: ChatAttachment) => {
          Button({ type: ButtonType.Normal }) {
            Row({ space: 12 }) {
              AppIcon({ name: 'file', iconSize: 28, tint: ThemeRuntime.color(this.themeKey, 'foreground-muted') })
              Column({ space: 5 }) {
                Text(attachment.name || '文件').fontSize(scaledFontSize(14, this.sizes.baseFontSize)).fontWeight(FontWeight.Medium)
                  .fontColor(ThemeRuntime.color(this.themeKey, 'foreground')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                Text(`${attachmentFormat(attachment)} · ${attachmentSize(attachment.sizeBytes)}`).fontSize(scaledFontSize(12, this.sizes.baseFontSize))
                  .fontColor(ThemeRuntime.color(this.themeKey, 'foreground-muted')).maxLines(1).width('100%')
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              AppIcon({ name: 'chevron', iconSize: 14, tint: ThemeRuntime.color(this.themeKey, 'foreground-muted') })
            }.width('100%')
          }.width('100%').height(this.sizes.baseFontSize * 3 + 24).padding({ left: 14, right: 14 }).borderRadius(12)
            .backgroundColor(ThemeRuntime.color(this.themeKey, 'screen')).border({ width: 0.5, color: ThemeRuntime.color(this.themeKey, 'border') })
            .onClick(() => { this.open(attachment.id); }).stateEffect(true)
            .accessibilityText(`打开 ${attachment.name || '文件'}，${attachmentFormat(attachment)}，${attachmentSize(attachment.sizeBytes)}`)
        }, (attachment: ChatAttachment) => attachment.id)
      }
      if (this.singleSkill() !== undefined) {
        Row({ space: 5 }) {
          AppIcon({ name: 'skill', iconSize: this.sizes.baseFontSize, tint: '#9B6DE3' })
          Text(this.singleSkill()?.label ?? '').fontSize(this.sizes.baseFontSize).lineHeight(this.sizes.baseFontSize + 6)
            .fontColor('#9B6DE3').fontWeight(FontWeight.Medium)
        }.alignItems(VerticalAlign.Center).padding({ left: 7, right: 7, top: 3, bottom: 3 })
          .borderRadius(6).backgroundColor('#189B6DE3')
      } else if (this.text) {
        Text() {
          ForEach(attachmentParts(this.text, this.attachments), (part: AttachmentPart) => {
            ForEach(messageReferenceSpans(part.text, this.skills, !!part.attachmentId), (span: ComposerSpan) => {
              if (span.kind === 'thread') {
                ContainerSpan() {
                  Span(' ')
                  if (this.reference(span).iconText) {
                    Span(` ${this.reference(span).iconText} `).fontSize(this.sizes.baseFontSize * 0.58).fontWeight(FontWeight.Medium)
                      .fontColor(this.referenceTint(span))
                      .textBackgroundStyle({ color: '#22' + this.referenceTint(span).slice(1), radius: 3 })
                      .onClick(() => { this.openReference(span); })
                  } else {
                    ImageSpan($r('app.media.thread_reference')).width(this.sizes.baseFontSize).height(this.sizes.baseFontSize).verticalAlign(ImageSpanAlignment.CENTER)
                      .onClick(() => { this.openReference(span); })
                  }
                  Span(` ${this.reference(span).title} `).fontWeight(FontWeight.Medium)
                    .fontColor(this.reference(span).available ? this.threadTint() : ThemeRuntime.color(this.themeKey, 'foreground-muted'))
                    .onClick(() => { this.openReference(span); })
                }.textBackgroundStyle({ color: '#12' + this.threadTint().slice(1), radius: 5 })
              } else if (span.kind === 'skill') {
                ContainerSpan() {
                  Span(' ')
                  ImageSpan($r('app.media.skill_reference')).width(15).height(15).verticalAlign(ImageSpanAlignment.CENTER)
                  Span(` ${span.label} `).fontColor('#9B6DE3').fontWeight(FontWeight.Medium)
                }.textBackgroundStyle({ color: '#189B6DE3', radius: 6 })
              } else {
                Span(span.raw).fontColor(ThemeRuntime.color(this.themeKey, part.attachmentId ? 'chat-link' : 'foreground'))
                  .onClick(() => { if (part.attachmentId) this.open(part.attachmentId); })
              }
            })
          })
        }.fontSize(this.sizes.baseFontSize).lineHeight(this.sizes.baseFontSize * 1.5).copyOption(this.selectable ? CopyOptions.LocalDevice : CopyOptions.None).width(this.attachments.length > 0 ? '100%' : undefined)
      }
      if (this.actionError) { Text(this.actionError).fontSize(scaledFontSize(12, this.sizes.baseFontSize)).fontColor(ThemeRuntime.color(this.themeKey, 'danger-foreground')) }
    }.width(this.attachments.length > 0 ? '100%' : undefined).alignItems(HorizontalAlign.Start)
  }
}
