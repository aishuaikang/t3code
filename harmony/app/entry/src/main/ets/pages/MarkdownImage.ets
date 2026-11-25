import { ChatGlass } from './ChatGlass';
import { ChatImage } from './ChatImage';
import { AppIcon } from './AppIcon';
import { ChatAttachment } from '../model/Models';
import { loadMarkdownImage } from '../connection/MarkdownImages';
import { ThemeRuntime } from '../connection/ThemeRuntime';

@Component
export struct MarkdownImage {
  @StorageProp('onlineEnvironmentId') onlineEnvironmentId: string = '';
  @Prop href: string = '';
  @Prop label: string = '';
  @Prop environmentId: string = '';
  @Prop threadId: string = '';
  @Prop cwd: string = '';
  @Prop baseDir: string = '';
  @StorageLink('themeKey') themeKey: string = 't3-code-light';
  @State contentWidth: number = 280;
  @State source: string = '';
  @State previewOpen: boolean = false;
  @State zoom: number = 1;
  @State offsetX: number = 0;
  @State offsetY: number = 0;
  private active: boolean = false;
  aboutToAppear(): void { this.active = true; }
  aboutToDisappear(): void { this.active = false; }
  private startZoom: number = 1;
  private startX: number = 0;
  private startY: number = 0;
  private attachment(): ChatAttachment {
    return { type: 'image', id: this.href, name: this.label || '文档图片', mimeType: 'image/png', sizeBytes: 0 };
  }
  private online(): boolean { return !!this.environmentId && this.onlineEnvironmentId === this.environmentId; }
  private async load(refresh: boolean): Promise<string> {
    const source = await loadMarkdownImage(getContext(this).filesDir, this.environmentId, this.threadId,
      this.cwd, this.baseDir, this.href, refresh, this.online());
    if (this.active) this.source = source;
    return source;
  }
  @Builder
  private preview() {
    Column() {
      ChatGlass() {
        Row({ space: 12 }) {
          Text(this.label || '文档图片').fontSize(16).fontColor(ThemeRuntime.color(this.themeKey, 'foreground')).layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          Button({ type: ButtonType.Circle }) { AppIcon({ name: 'close', iconSize: 24, tint: ThemeRuntime.color(this.themeKey, 'foreground') }) }
            .width(44).height(44).backgroundColor(Color.Transparent).accessibilityText('关闭图片').onClick(() => { this.previewOpen = false; })
        }.width('100%').padding({ left: 16, right: 8, top: 6, bottom: 6 })
      }
      Stack() {
        Image(this.source).width('100%').height('100%').objectFit(ImageFit.Contain)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
          .scale({ x: this.zoom, y: this.zoom }).translate({ x: this.offsetX, y: this.offsetY })
      }.layoutWeight(1).width('100%').clip(true)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        .gesture(PinchGesture().onActionStart(() => { this.startZoom = this.zoom; })
          .onActionUpdate((event: GestureEvent) => { this.zoom = Math.max(1, Math.min(6, this.startZoom * event.scale));
            if (this.zoom === 1) { this.offsetX = 0; this.offsetY = 0; } }))
        .parallelGesture(PanGesture().onActionStart(() => { this.startX = this.offsetX; this.startY = this.offsetY; })
          .onActionUpdate((event: GestureEvent) => { if (this.zoom > 1) { this.offsetX = this.startX + event.offsetX; this.offsetY = this.startY + event.offsetY; } }))
    }.width('100%').height('100%').backgroundColor(ThemeRuntime.color(this.themeKey, 'screen'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
  build() {
    Column() {
      ChatImage({ attachment: this.attachment(), environmentId: this.environmentId, tileWidth: this.contentWidth, online: this.online(),
        revalidateOnConnect: !/^(?:https?:)?\/\//i.test(this.href),
        loadSource: (_attachment: ChatAttachment, refresh: boolean) => this.load(refresh),
        onPreview: () => { this.zoom = 1; this.offsetX = 0; this.offsetY = 0; this.previewOpen = true; } })
    }.width('100%').alignItems(HorizontalAlign.Start)
      .onAreaChange((_old: Area, area: Area) => { const width = Number(area.width); if (width > 0 && width !== this.contentWidth) this.contentWidth = width; })
      .bindContentCover($$this.previewOpen, this.preview())
  }
}
