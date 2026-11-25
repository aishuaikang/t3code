import { AppIcon } from './AppIcon';
import { MarkdownImage } from './MarkdownImage';
import { Typography, resolveTypography, scaledFontSize, MarkdownMetrics, markdownMetrics } from '../model/Typography';
import { ThemeRuntime } from '../connection/ThemeRuntime';
import router from '@ohos.router';
import { MarkdownImageFile, markdownFileLink, markdownImageFileLink } from '../model/MarkdownLink';
import { parse } from 'libt3markdown.so';
import common from '@ohos.app.ability.common';
import pasteboard from '@ohos.pasteboard';
import promptAction from '@ohos.promptAction';
import { MarkdownBlock, MarkdownRun, MarkdownRow, MarkdownCell, MarkdownPart, markdownBlocks, markdownParts } from '../model/MarkdownBlocks';
import { ComposerSkill, ComposerSpan, messageSkillSpans } from '../model/ComposerDocument';
import { CodeToken, highlightCode } from '../model/CodeHighlight';
import { MessageContext } from '../model/Models';
import { ThreadReference, ThreadReferenceLink, threadReferenceTarget, presentThreadReference, threadReferenceIconTint } from '../model/ThreadReferences';
import { loadThreadReferences } from '../connection/ThreadReferences';
import { EnvironmentSession } from '../connection/Environment';
import { openThreadReference } from './ThreadReferenceNavigation';

@Component
export struct MarkdownText {
  private font(size: number): number { return scaledFontSize(size, this.sizes.baseFontSize); }
  @StorageLink('textSizes') sizes: Typography = resolveTypography(16, null, null);
  @StorageLink('themeKey') themeKey: string = 't3-code-light';
  @Prop user: boolean = false;
  @Prop inBubble: boolean = false;
  @Prop selectable: boolean = true;
  @Prop referencesDisabled: boolean = false;
  @Prop skills: ComposerSkill[] = [];
  private color(role: string): string {
    let token = role;
    if (this.user) {
      if (role === 'md-body' || role === 'md-link' || role === 'foreground-secondary') token = 'user-bubble-foreground';
      if (role === 'foreground-muted') token = 'user-bubble-foreground-muted';
      if (role === 'md-code-text') token = 'md-user-fence-text';
      if (role === 'md-code-bg' || role === 'subtle-strong') token = 'md-user-fence-bg';
    }
    if (this.inBubble && !this.user) {
      if (role === 'md-link') token = 'chat-link';
      if (role === 'foreground-muted' || role === 'foreground-secondary') token = 'chat-secondary';
    }
    return ThemeRuntime.color(this.themeKey, token);
  }
  @Prop cwd: string = '';
  @Prop baseDir: string = '';
  @Prop @Watch('update') environmentId: string = '';
  @Prop threadId: string = '';
  @Prop @Watch('update') messageContext: MessageContext | undefined = undefined;
  @Prop @Watch('update') content: string = '';
  @State blocks: MarkdownBlock[] = [];
  @State failed: boolean = false;
  @State actionError: string = '';
  @State references: ThreadReference[] = [];
  private referenceRevision: number = 0;
  private active: boolean = false;
  private codeCache: Map<string, CodeToken[]> = new Map();
  aboutToAppear(): void { this.active = true; this.update(); }
  aboutToDisappear(): void { this.active = false; ++this.referenceRevision; }
  private update(): void {
    const revision = ++this.referenceRevision, connection = EnvironmentSession.current;
    this.codeCache.clear();
    this.references = [];
    try { this.blocks = markdownBlocks(parse(this.content)); this.failed = false; }
    catch (_) { this.failed = true; }
    const links: ThreadReferenceLink[] = [];
    this.collectReferenceLinks(this.blocks, links);
    if (links.length > 0) loadThreadReferences(getContext(this).filesDir, this.environmentId, links, this.messageContext).then((references: ThreadReference[]) => {
      if (this.active && revision === this.referenceRevision && connection === EnvironmentSession.current) this.references = references;
    }).catch(() => {});
  }
  private collectReferenceLinks(blocks: MarkdownBlock[], links: ThreadReferenceLink[]): void {
    for (const block of blocks) {
      if (block.children) this.collectReferenceLinks(block.children, links);
      const runs = block.runs.concat(...block.rows.map((row: MarkdownRow) => row.cells.flatMap((cell: MarkdownCell) => cell.runs)));
      for (const run of runs) if (!run.code && threadReferenceTarget(run.href, this.environmentId, this.messageContext) !== null &&
        !links.some((link: ThreadReferenceLink) => link.href === run.href)) links.push({ href: run.href, label: run.text });
    }
  }
  private reference(href: string, label: string): ThreadReference | null {
    const target = threadReferenceTarget(href, this.environmentId, this.messageContext);
    return target === null ? null : this.references.find((entry: ThreadReference) => entry.href === href) ??
      presentThreadReference(href, label, target, [], [], {});
  }
  private threadTint(): string { return ThemeRuntime.palette(this.themeKey).scheme === 'dark' ? '#5EEAD4' : '#0F766E'; }
  private referenceTint(href: string): string { return threadReferenceIconTint(this.reference(href, '')?.iconColor ?? '', ThemeRuntime.palette(this.themeKey).scheme === 'dark'); }
  private codeTokens(block: MarkdownBlock): CodeToken[] {
    const text = block.runs.map((run: MarkdownRun) => run.text).join('');
    const key = block.language + '\n' + text;
    let tokens = this.codeCache.get(key);
    if (tokens === undefined) { tokens = highlightCode(text, block.language); this.codeCache.set(key, tokens); }
    return tokens;
  }
  private codeColor(kind: string): string {
    const dark = ThemeRuntime.palette(this.themeKey).scheme === 'dark';
    if (kind === 'keyword') return dark ? '#C4A7E7' : '#7042A8';
    if (kind === 'string') return dark ? '#A8D5A2' : '#287D3C';
    if (kind === 'number') return dark ? '#F4BA8B' : '#A85A14';
    if (kind === 'function' || kind === 'variable') return this.color('md-link');
    return this.color(kind === 'comment' ? 'foreground-muted' : 'md-code-text');
  }
  private imageLink(href: string): MarkdownImageFile | null {
    return this.environmentId && this.threadId ? markdownImageFileLink(href, this.cwd, this.baseDir) : null;
  }
  private openLink(href: string): void {
    const reference = this.reference(href, '会话');
    if (reference !== null) {
      if (this.referencesDisabled) return;
      openThreadReference(reference, this.environmentId, this.threadId).catch((error: Error) => { this.actionError = error.message; });
      return;
    }
    const image = this.imageLink(href);
    if (image !== null) {
      if (this.referencesDisabled) return;
      router.pushUrl({ url: 'pages/ImagePreview', params: { environmentId: this.environmentId,
        mediaPath: image.path, mediaThreadId: this.threadId, name: image.name } })
        .catch(() => { this.actionError = '原图打开失败，请重试'; });
      return;
    }
    const file = markdownFileLink(href, this.cwd, this.baseDir);
    if (file !== null) {
      router.pushUrl({ url: 'pages/Files', params: { cwd: this.cwd, path: file.path, line: String(file.line ?? 0),
        environmentId: this.environmentId, threadId: this.threadId } });
      return;
    }
    if (!/^https?:\/\//i.test(href)) return;
    const context = getContext(this) as common.UIAbilityContext;
    context.startAbility({ action: 'ohos.want.action.viewData', uri: href })
      .catch(() => { this.actionError = '链接打开失败，可复制地址后重试'; });
  }
  private async copyCode(block: MarkdownBlock): Promise<void> {
    try {
      const text = block.runs.map((run: MarkdownRun) => run.text).join('');
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text));
      promptAction.showToast({ message: '代码已复制' });
    } catch (_) { this.actionError = '代码复制失败，请重试'; }
  }
  private markdown(): MarkdownMetrics { return markdownMetrics(this.sizes.baseFontSize); }
  private headingSize(level: number): number {
    const m = this.markdown();
    const headings: number[] = [m.h1, m.h2, m.h3, m.h4, m.h5, m.h6];
    return headings[Math.max(0, Math.min(5, level - 1))];
  }
  @Builder
  rich(runs: MarkdownRun[], size: number = 16, bold: boolean = false) {
    Column({ space: 8 }) {
      ForEach(markdownParts(runs), (part: MarkdownPart) => {
        if (part.image !== undefined) {
          MarkdownImage({ href: part.image.imageSource ?? '', label: part.image.text, environmentId: this.environmentId,
            threadId: this.threadId, cwd: this.cwd, baseDir: this.baseDir })
        } else { this.richText(part.runs, size, bold) }
      }, (part: MarkdownPart, index: number) => JSON.stringify([this.environmentId, this.threadId, this.cwd, this.baseDir]) + ':' + index + ':' + JSON.stringify(part))
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
  @Builder
  private richText(runs: MarkdownRun[], size: number, bold: boolean) {
    Text() {
      ForEach(runs, (run: MarkdownRun) => {
        if (!run.code && this.reference(run.href, run.text) !== null) {
          ContainerSpan() {
            Span(' ')
            if (this.reference(run.href, run.text)?.iconText) {
              Span(` ${this.reference(run.href, run.text)?.iconText ?? ''} `)
                .fontSize(size * 0.58).fontWeight(FontWeight.Medium)
                .fontColor(this.referenceTint(run.href))
                .textBackgroundStyle({ color: '#22' + this.referenceTint(run.href).slice(1), radius: 3 })
                .onClick(() => { this.openLink(run.href); })
            } else {
              ImageSpan($r('app.media.thread_reference')).width(size).height(size).verticalAlign(ImageSpanAlignment.CENTER)
                .onClick(() => { this.openLink(run.href); })
            }
            Span(` ${this.reference(run.href, run.text)?.title ?? run.text} `).fontWeight(FontWeight.Medium)
              .fontColor(this.reference(run.href, run.text)?.available ? this.threadTint() : this.color('foreground-muted'))
              .onClick(() => { this.openLink(run.href); })
          }.textBackgroundStyle({ color: '#12' + this.threadTint().slice(1), radius: 5 })
        } else if (!run.code && this.imageLink(run.href) !== null) {
          if (run.text !== this.imageLink(run.href)?.name) {
            Span(run.text + ' ').fontColor(this.color('md-body')).onClick(() => { this.openLink(run.href); })
          }
          Span(` 🖼 ${this.imageLink(run.href)?.name ?? run.text} `).fontColor(this.color('md-link'))
            .textBackgroundStyle({ color: this.color('subtle-strong'), radius: 5 })
            .onClick(() => { this.openLink(run.href); })
        } else {
        ForEach(messageSkillSpans(run.text, this.skills, run.code || !!run.href), (span: ComposerSpan) => {
          if (span.kind === 'skill') {
            ContainerSpan() {
              Span(' ')
              ImageSpan($r('app.media.skill_reference')).width(15).height(15).verticalAlign(ImageSpanAlignment.CENTER)
              Span(` ${span.label} `).fontColor('#9B6DE3').fontWeight(FontWeight.Medium)
            }.textBackgroundStyle({ color: '#189B6DE3', radius: 6 })
          } else {
            Span(span.raw).fontWeight(run.bold || bold ? FontWeight.Bold : FontWeight.Normal)
              .fontStyle(run.italic ? FontStyle.Italic : FontStyle.Normal)
              .fontFamily(run.code ? 'monospace' : 'sans-serif')
              .fontColor(run.code ? this.color('md-code-text') : (/^https?:\/\//i.test(run.href) || markdownFileLink(run.href, this.cwd, this.baseDir) !== null) ? this.color('md-link') : this.color('md-body'))
              .textBackgroundStyle({ color: run.code ? this.color('md-code-bg') : Color.Transparent, radius: 4 })
              .decoration({ type: run.strike ? TextDecorationType.LineThrough : TextDecorationType.None })
              .onClick(() => { this.openLink(run.href); })
          }
        })
        }
      })
    }.fontSize(size).lineHeight(Math.max(size + 4, this.markdown().bodyLineHeight)).copyOption(this.selectable ? CopyOptions.LocalDevice : CopyOptions.None).width('100%')
  }
  @Builder
  private renderBlock(block: MarkdownBlock) {
    if (block.kind === 'horizontal_rule') {
      Divider().color(this.color('border')).margin({ top: 8, bottom: 8 })
    } else if (block.kind === 'code_block') {
      Column({ space: 6 }) {
        Row() {
          Text(block.language || '代码').fontSize(this.font(12)).fontColor(this.color('foreground-muted')).layoutWeight(1)
          Button({ type: ButtonType.Normal }) { AppIcon({ name: 'copy', iconSize: 14, tint: this.color('foreground-muted') }) }.accessibilityText('复制代码').backgroundColor(Color.Transparent).width(32).height(28).padding(0).onClick(() => { this.copyCode(block); })
        }.width('100%')
        Scroll() {
          Text() {
            ForEach(this.codeTokens(block), (token: CodeToken) => { Span(token.text).fontColor(this.codeColor(token.kind)) })
          }.fontFamily('monospace')
            .fontSize(this.markdown().codeBlockFontSize).lineHeight(this.markdown().codeBlockLineHeight).fontColor(this.color('md-code-text')).copyOption(this.selectable ? CopyOptions.LocalDevice : CopyOptions.None)
        }.scrollable(ScrollDirection.Horizontal).align(Alignment.TopStart).width('100%')
      }.padding(10).width('100%').alignItems(HorizontalAlign.Start).backgroundColor(this.color('md-code-bg')).borderRadius(6)
    } else if (block.kind === 'table') {
      Scroll() {
        Column() {
          ForEach(block.rows, (row: MarkdownRow) => {
            Flex({ direction: FlexDirection.Row, alignItems: ItemAlign.Stretch }) {
              ForEach(row.cells, (cell: MarkdownCell) => {
                Column() { this.rich(cell.runs, this.markdown().s, cell.header) }
                  .width(180).padding(8).border({ width: 0.5, color: this.color('border') })
                  .backgroundColor(cell.header ? this.color('subtle-strong') : this.color('md-code-bg'))
              })
            }.width(row.cells.length * 180)
          })
        }
      }.scrollable(ScrollDirection.Horizontal).width('100%')
    } else {
      Row({ space: 8 }) {
        if (block.marker) { Text(block.marker).fontSize(this.markdown().m).fontColor(this.color('foreground-secondary')).width(25) }
        Column() {
          if (block.kind === 'blockquote') {
            Column({ space: 10 }) {
              ForEach(block.children ?? [], (child: MarkdownBlock) => { this.renderBlock(child) })
            }.alignItems(HorizontalAlign.Start).width('100%').padding({ left: 12 })
              .borderWidth({ left: 2 }).borderColor(this.color(this.inBubble || this.user ? 'chat-outline' : 'md-blockquote-border'))
          } else { this.rich(block.runs, block.kind === 'heading' ? this.headingSize(block.level) : this.markdown().m, block.kind === 'heading') }
        }.layoutWeight(1)
      }.alignItems(VerticalAlign.Top).width('100%').padding({ left: Math.min(block.depth, 6) * 12 })
    }
  }
  build() {
    Column({ space: 10 }) {
      if (this.failed) {
        Text(this.content).fontSize(this.markdown().m).fontColor(this.color('md-body')).width('100%').copyOption(this.selectable ? CopyOptions.LocalDevice : CopyOptions.None)
      } else {
        ForEach(this.blocks, (block: MarkdownBlock) => { this.renderBlock(block) })
      }
      if (this.actionError) { Text(this.actionError).fontSize(this.font(12)).fontColor(this.color('danger-foreground')) }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
