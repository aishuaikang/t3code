import pasteboard from '@ohos.pasteboard';
import util from '@ohos.util';
import { KeyCode } from '@ohos.multimodalInput.keyCode';
import { ComposerSpan, ComposerSkill, composerSpans, composerRawText, composerRawOffset, composerViewOffset, editComposerSpans } from '../model/ComposerDocument';
import { SlashCommand } from '../model/ComposerCommands';
import { ThemeRuntime } from '../connection/ThemeRuntime';
import { Typography, resolveTypography, scaledFontSize } from '../model/Typography';
import { AppIcon } from './AppIcon';

export class ComposerEditorController {
  requestFocus: (() => void) | null = null;
  move: ((offset: number) => void) | null = null;
  caretPosition(offset: number): void { this.move?.(offset); }
}

@Component
export struct ComposerEditor {
  @Prop @Watch('syncText') text: string = '';
  @Prop @Watch('refreshStyle') commands: SlashCommand[] = [];
  @Prop disabled: boolean = false;
  @Prop placeholder: string = '发消息、@ 引用或 / 命令';
  @Prop placeholderColor: string = '';
  control: ComposerEditorController = new ComposerEditorController();
  onChange: (text: string) => void = () => {};
  onSelection: (start: number, end: number) => void = () => {};
  onSend: () => void = () => {};
  @StorageLink('themeKey') @Watch('refreshStyle') themeKey: string = 't3-code-light';
  @StorageLink('textSizes') @Watch('refreshStyle') sizes: Typography = resolveTypography(16, null, null);
  @State editorHeight: number = 28;
  private controller: RichEditorController = new RichEditorController();
  private spans: ComposerSpan[] = [];
  private ready: boolean = false;
  private rendering: boolean = false;
  private changing: boolean = false;
  private cancelMeasure: (() => void) | null = null;
  private styleKey: string = '';
  private focusKey: string = 'composer-' + util.generateRandomUUID(true);
  private color(role: string): string { return ThemeRuntime.color(this.themeKey, role); }
  private lineHeight(): number { return scaledFontSize(this.spans.some((span: ComposerSpan) => span.kind !== 'text') ? 30 : 24, this.sizes.baseFontSize); }
  private skills(): ComposerSkill[] {
    return this.commands.filter((command: SlashCommand) => command.kind === 'skill' && !!command.insertion)
      .map((command: SlashCommand): ComposerSkill => ({ insertion: command.insertion!, label: command.displayName ?? command.name.replace(/^skill:/, ''), icon: command.icon ?? 'skill' }));
  }
  aboutToAppear(): void {
    this.control.move = (offset: number) => { this.syncText(); this.controller.setCaretOffset(composerViewOffset(this.spans, offset)); };
    this.control.requestFocus = () => {
      if (!this.ready || this.disabled) return;
      this.getUIContext().getFocusController().requestFocus(this.focusKey);
      this.control.caretPosition(this.text.length);
    };
  }
  aboutToDisappear(): void { this.cancelMeasure?.(); this.ready = false; this.control.move = null; this.control.requestFocus = null; }
  private syncText(): void {
    if (!this.ready || this.text === composerRawText(this.spans)) return;
    const caret = composerRawOffset(this.spans, this.controller.getCaretOffset());
    this.render(this.text, Math.min(caret, this.text.length));
  }
  private refreshStyle(): void {
    if (!this.ready || this.changing) return;
    const key = `${this.themeKey}:${this.sizes.baseFontSize}:${JSON.stringify(this.skills())}`;
    if (key === this.styleKey) return;
    this.styleKey = key;
    const caret = composerRawOffset(this.spans, this.controller.getCaretOffset());
    this.render(composerRawText(this.spans), caret);
  }
  private render(text: string, caret: number): void {
    this.rendering = true;
    this.styleKey = `${this.themeKey}:${this.sizes.baseFontSize}:${JSON.stringify(this.skills())}`;
    this.spans = composerSpans(text, this.skills());
    this.controller.deleteSpans();
    let offset = 0;
    const style: RichEditorTextStyle = { fontSize: scaledFontSize(16, this.sizes.baseFontSize), fontColor: this.color('foreground'), lineHeight: this.lineHeight() };
    for (const span of this.spans) {
      if (span.kind === 'text') this.controller.addTextSpan(span.raw, { offset: offset, style: style });
      else this.controller.addBuilderSpan(this.chip.bind(this, span), { offset: offset });
      offset += span.kind === 'text' ? span.raw.length : 1;
    }
    this.controller.setTypingStyle(style);
    this.controller.setCaretOffset(composerViewOffset(this.spans, caret));
    this.rendering = false;
    this.measure();
  }
  private measure(): void {
    if (this.cancelMeasure !== null || !this.ready) return;
    const observer = this.getUIContext().getUIObserver();
    // The frame starts before RichEditor lays out a paste or a wrapping edit.
    const afterLayout = (): void => {
      this.cancelMeasure?.();
      if (!this.ready) return;
      const layout = this.controller.getLayoutManager();
      const lines = layout.getLineCount();
      // Builder spans can be taller than text. Use native line metrics, including their ascent and descent.
      const placeholderHeight = !composerRawText(this.spans) && lines === 1 ? this.getUIContext().px2vp(layout.getLineMetrics(0).height) + 4 : 0;
      let height = 4;
      for (let line = 0; line < Math.min(lines, 4); line++) {
        height += Math.max(this.lineHeight(), this.getUIContext().px2vp(layout.getLineMetrics(line).height));
      }
      this.editorHeight = placeholderHeight > 4 ? placeholderHeight : Math.max(28, height);
    };
    this.cancelMeasure = () => { observer.off('didLayout', afterLayout); this.cancelMeasure = null; };
    observer.on('didLayout', afterLayout);
  }
  private selection(range: RichEditorRange): void {
    if (this.rendering || this.changing) return;
    this.onSelection(composerRawOffset(this.spans, range.start ?? 0), composerRawOffset(this.spans, range.end ?? range.start ?? 0));
  }
  private changed(before: TextRange, after: TextRange): void {
    if (this.rendering) return;
    const inserted = after.start === after.end ? '' : this.controller.getSpans({ start: after.start, end: after.end })
      .map((span: RichEditorImageSpanResult | RichEditorTextSpanResult): string => {
        const text = span as RichEditorTextSpanResult;
        return typeof text.value === 'string' ? text.value.substring(text.offsetInSpan[0], text.offsetInSpan[1]) : '';
      }).join('');
    this.spans = editComposerSpans(this.spans, before.start ?? 0, before.end ?? before.start ?? 0, inserted);
    this.changing = false;
    this.onChange(composerRawText(this.spans));
    this.selection({ start: after.end, end: after.end });
    this.measure();
  }
  private copy(): boolean {
    const range = this.controller.getSelection();
    const raw = composerRawText(this.spans).substring(composerRawOffset(this.spans, range.selection[0]), composerRawOffset(this.spans, range.selection[1]));
    if (!raw) return false;
    try { pasteboard.getSystemPasteboard().setDataSync(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, raw)); return true; }
    catch (_) { return false; }
  }
  private replaceSelection(text: string): void {
    const range = this.controller.getSelection();
    const start = range.selection[0] >= 0 ? range.selection[0] : this.controller.getCaretOffset();
    const end = range.selection[1] >= 0 ? range.selection[1] : start;
    const caret = composerRawOffset(this.spans, start) + text.length;
    const raw = composerRawText(editComposerSpans(this.spans, start, end, text));
    this.render(raw, caret);
    this.onChange(raw);
    this.onSelection(caret, caret);
  }
  @Builder
  private chip(span: ComposerSpan) {
    Row({ space: 4 }) {
      AppIcon({ name: span.icon, iconSize: scaledFontSize(14, this.sizes.baseFontSize), tint: span.kind === 'skill' ? '#9B6DE3' : this.color('md-link') })
      Text(span.label).fontSize(scaledFontSize(14, this.sizes.baseFontSize)).fontWeight(FontWeight.Medium)
        .lineHeight(scaledFontSize(20, this.sizes.baseFontSize))
        .fontColor(span.kind === 'skill' ? '#9B6DE3' : this.color('md-link')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: 164 })
    }.height(scaledFontSize(26, this.sizes.baseFontSize)).alignItems(VerticalAlign.Center).padding({ left: 6, right: 6 }).margin({ left: 2, right: 2 }).borderRadius(7)
      .backgroundColor(span.kind === 'skill' ? '#189B6DE3' : '#18' + this.color('md-link').slice(1)).accessibilityText(span.label)
  }
  build() {
    Stack({ alignContent: Alignment.Center }) {
    RichEditor({ controller: this.controller }).id(this.focusKey).height(this.editorHeight).width('100%')
      .padding({ left: 4, right: 4, top: 2, bottom: 2 }).backgroundColor(Color.Transparent)
      .placeholder(this.placeholder, { font: { size: scaledFontSize(15, this.sizes.baseFontSize) }, fontColor: this.placeholderColor || this.color('placeholder') })
      .caretColor(this.color('primary')).enterKeyType(EnterKeyType.NEW_LINE).enablePreviewText(true).barState(BarState.Off).enabled(!this.disabled)
      .onReady(() => { this.ready = true; this.render(this.text, this.text.length); })
      .onWillChange((): boolean => { if (!this.rendering) this.changing = true; return true; })
      .onDidChange((before: TextRange, after: TextRange) => { this.changed(before, after); })
      .onSelectionChange((range: RichEditorRange) => { this.selection(range); })
      .onFocus(() => { this.measure(); })
      .onCopy((event: CopyEvent) => { if (this.copy()) event.preventDefault?.(); })
      .onCut((event: CutEvent) => { event.preventDefault?.(); if (this.copy()) this.replaceSelection(''); })
      .onPaste((event) => {
        try { const raw = pasteboard.getSystemPasteboard().getDataSync().getPrimaryText(); event?.preventDefault?.(); this.replaceSelection(raw); }
        catch (_) {}
      })
      .onKeyPreIme((event: KeyEvent): boolean => {
        if ((event.keyCode !== KeyCode.KEYCODE_ENTER && event.keyCode !== KeyCode.KEYCODE_NUMPAD_ENTER) ||
          !event.getModifierKeyState?.(['ctrl']) || event.getModifierKeyState?.(['alt']) || event.getModifierKeyState?.(['shift'])) return false;
        if (event.type === KeyType.Down) this.onSend();
        return true;
      })
    }.width('100%').constraintSize({ minHeight: 40 })
  }
}
