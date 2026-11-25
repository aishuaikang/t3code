import router from '@ohos.router';
import { ChatAttachment } from '../model/Models';
import { ThemeRuntime } from '../connection/ThemeRuntime';

@Component
export struct ChatImage {
  @Prop attachment: ChatAttachment;
  @Prop environmentId: string = '';
  @Prop tileWidth: number = 240;
  @Prop maxHeight: number = 480;
  @Prop mediaPath: string = '';
  @Prop mediaThreadId: string = '';
  @Prop gallery: string = '';
  @Prop galleryIndex: number = 0;
  @Prop commentThreadId: string = '';
  @Prop square: boolean = false;
  @Prop tileAspect: number = 0;
  @Prop revalidateOnConnect: boolean = false;
  @Prop @Watch('connectionChanged') online: boolean = false;
  @StorageLink('themeKey') themeKey: string = 't3-code-light';
  loadSource: (attachment: ChatAttachment, refresh: boolean) => Promise<string> = async () => '';
  onPreview: (() => void) | null = null;
  @State source: string = '';
  @State loading: boolean = true;
  @State error: string = '';
  @State aspect: number = 1.5;
  private active: boolean = false;
  private revision: number = 0;
  private fetching: boolean = false;
  private retryAfterLoad: boolean = false;
  aboutToAppear(): void { this.active = true; this.load(false); }
  aboutToDisappear(): void { this.active = false; this.revision++; }
  private connectionChanged(): void {
    if (!this.active || !this.online || (this.source && !this.error && !this.revalidateOnConnect)) return;
    // A download already in progress on the old network may still fail after reconnection.
    if (this.fetching) this.retryAfterLoad = true;
    else this.load(!!this.error && !!this.source);
  }
  private imageWidth(): number { return this.square || this.tileAspect > 0 ? this.tileWidth : Math.min(this.tileWidth, this.maxHeight * this.aspect); }
  private imageHeight(): number { return this.square ? this.tileWidth : this.tileAspect > 0 ? this.tileWidth / this.tileAspect : this.imageWidth() / this.aspect; }
  private async load(refresh: boolean): Promise<void> {
    const revision = ++this.revision;
    this.fetching = true; this.retryAfterLoad = false;
    this.loading = !this.source; this.error = '';
    try {
      const source = await this.loadSource(this.attachment, refresh);
      if (this.active && revision === this.revision) { if (this.source === source) this.loading = false; this.source = source; }
    } catch (_) {
      if (this.active && revision === this.revision) { this.loading = false; this.error = this.online ? '图片加载失败，点此重试' : '此图片尚未缓存，联网后加载'; }
    } finally {
      if (this.active && revision === this.revision) {
        this.fetching = false;
        if (this.retryAfterLoad && this.online && (this.error || this.revalidateOnConnect)) this.load(!!this.error && !!this.source);
      }
    }
  }
  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.source) {
        Image(this.source).width(this.imageWidth()).height(this.imageHeight())
          .objectFit(this.square || this.tileAspect > 0 ? ImageFit.Cover : ImageFit.Contain)
          .onComplete((event) => {
            if (!event || event.width <= 0 || event.height <= 0) return;
            const aspect = event.width / event.height;
            if (this.aspect !== aspect) this.aspect = aspect;
            this.loading = false; this.error = '';
          })
          .onError(() => { this.loading = false; this.error = '图片加载失败，点此重试'; })
      }
      if (this.loading || this.error) {
        Text(this.error || '正在加载图片…').fontSize(13).fontColor(ThemeRuntime.color(this.themeKey, 'foreground-muted'))
          .padding(12).maxLines(2)
      }
    }.width(this.imageWidth()).height(this.imageHeight())
      .backgroundColor(ThemeRuntime.color(this.themeKey, 'input')).borderRadius(this.tileAspect > 0 ? 0 : this.square ? 10 : 14).clip(true)
      .border({ width: this.tileAspect > 0 ? 0 : 0.75, color: ThemeRuntime.color(this.themeKey, 'chat-outline') })
      .accessibilityText(`图片 ${this.attachment.name}${this.error ? '，' + this.error : ''}`)
      .onClick(() => {
        if (this.error) { this.load(true); return; }
        if (this.loading) return;
        if (this.onPreview !== null) { this.onPreview(); return; }
        router.pushUrl({ url: 'pages/ImagePreview', params: { environmentId: this.environmentId,
          mediaPath: this.mediaPath, mediaThreadId: this.mediaThreadId,
          gallery: this.gallery, imageIndex: String(this.galleryIndex), commentThreadId: this.commentThreadId,
          attachmentId: this.attachment.id, name: this.attachment.name, mimeType: this.attachment.mimeType } });
      })
  }
}
