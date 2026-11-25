import webview from '@ohos.web.webview';
import { HtmlRenderReference } from '../model/Models';
import { ThemeRuntime } from '../connection/ThemeRuntime';

@Component
export struct InlineHtmlPreview {
  @Prop @Watch('reload') reference: HtmlRenderReference;
  @Prop @Watch('connectionChanged') online: boolean = false;
  @Prop originalImageName: string = '';
  @StorageLink('themeKey') themeKey: string = 't3-code-light';
  loadSource: (reference: HtmlRenderReference) => Promise<string> = async () => '';
  onOpenOriginal: () => void = () => {};
  @State source: string = '';
  @State error: boolean = false;
  @State painted: boolean = false;
  @State viewport: number = 0;
  private controller: webview.WebviewController = new webview.WebviewController();
  private revision: number = 0;
  private active: boolean = false;
  private paintTimeout: number = -1;

  aboutToAppear(): void { this.active = true; this.reload(); }
  aboutToDisappear(): void { this.active = false; this.revision++; clearTimeout(this.paintTimeout); }
  private connectionChanged(): void { if (this.online && (!this.source || this.error)) this.reload(); }
  private fail(): void { if (this.active) { clearTimeout(this.paintTimeout); this.error = true; } }
  private reload(): void {
    const revision = ++this.revision;
    clearTimeout(this.paintTimeout);
    this.source = ''; this.error = false; this.painted = false;
    if (!this.active || !this.online) return;
    this.loadSource(this.reference).then((source: string) => {
      if (!this.active || revision !== this.revision) return;
      if (!source) { this.fail(); return; }
      this.source = source;
      this.paintTimeout = setTimeout(() => { if (revision === this.revision && !this.painted) this.fail(); }, 20000);
    }).catch(() => { if (revision === this.revision) this.fail(); });
  }
  private previewHeight(): number {
    let measured = this.reference.height;
    let distance = Number.MAX_VALUE;
    for (const pair of this.reference.heights ?? []) {
      if (this.viewport > 0 && Math.abs(pair[0] - this.viewport) < distance) {
        distance = Math.abs(pair[0] - this.viewport); measured = pair[1];
      }
    }
    return Math.min(2000, Math.max(80, Math.ceil(measured)));
  }
  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.source && !this.error) {
        // The signed attachment response isolates authored scripts with a CSP sandbox.
        Web({ src: this.source, controller: this.controller, renderMode: RenderMode.SYNC_RENDER })
          .width('100%').constraintSize({ maxHeight: 20000 }).layoutMode(WebLayoutMode.FIT_CONTENT)
          .javaScriptAccess(true).fileAccess(false).domStorageAccess(false)
          .multiWindowAccess(false).allowWindowOpenMethod(false)
          .nestedScroll({ scrollForward: NestedScrollMode.PARENT_FIRST, scrollBackward: NestedScrollMode.PARENT_FIRST })
          .onLoadIntercept((event) => event.data.isMainFrame() &&
            event.data.getRequestUrl().split('#')[0] !== this.source.split('#')[0])
          .onFirstContentfulPaint(() => { clearTimeout(this.paintTimeout); this.painted = true; })
          .onErrorReceive((event) => { if (event.request.isMainFrame()) this.fail(); })
          .onHttpErrorReceive((event) => { if (event.request.isMainFrame()) this.fail(); })
          .onRenderExited(() => { this.fail(); })
          .accessibilityText(this.reference.title)
          .hitTestBehavior(this.originalImageName ? HitTestMode.None : HitTestMode.Default)
      }
      if (!this.painted || this.error) {
        Text(this.error ? '预览加载失败，点此重试' : this.online ? '正在加载预览…' : '连接后查看预览')
          .fontSize(13).fontColor(ThemeRuntime.color(this.themeKey, 'foreground-muted'))
          .width('100%').height(this.previewHeight()).textAlign(TextAlign.Center)
          .backgroundColor(ThemeRuntime.color(this.themeKey, 'screen'))
          .onClick(() => { if (this.error) this.reload(); })
      }
    }.width('100%').constraintSize({ minHeight: 80 }).clip(true).borderRadius(8)
      .onAreaChange((_old: Area, area: Area) => { const width = Math.round(Number(area.width)); if (width > 0 && width !== this.viewport) this.viewport = width; })
      .accessibilityText(this.originalImageName ? `查看原图 ${this.originalImageName}` : '')
      .onClick(() => { if (this.originalImageName && this.painted && !this.error) this.onOpenOriginal(); })
  }
}
