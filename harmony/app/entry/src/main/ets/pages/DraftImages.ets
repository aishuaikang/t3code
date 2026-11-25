import { ThemeRuntime } from '../connection/ThemeRuntime';
import { AppIcon } from './AppIcon';
import { attachmentSize } from '../model/AttachmentLabels';
import router from '@ohos.router';
import { PreviewImage } from '../model/ImageGallery';
import { ChatAttachment } from '../model/Models';
import { ChatImage } from './ChatImage';

export interface DraftImageProgress { uri: string; status: string; progress: number; error: string; type?: string; name?: string; sizeBytes?: number; attachment?: ChatAttachment; }

@Component
export struct DraftImages {
  @Prop images: DraftImageProgress[] = [];
  @Prop disabled: boolean = false;
  @Prop environmentId: string = '';
  @Prop threadId: string = '';
  @Prop draftScope: string = '';
  @Prop online: boolean = false;
  @StorageLink('themeKey') themeKey: string = 't3-code-light';
  onRemove: (uri: string) => void = () => {};
  onRetry: (uri: string) => void = () => {};
  loadSource: (attachment: ChatAttachment, refresh: boolean) => Promise<string> = async () => '';
  private color(role: string): string { return ThemeRuntime.color(this.themeKey, role); }
  private open(image: DraftImageProgress): void {
    const pictures = this.images.filter((entry: DraftImageProgress) => entry.type !== 'file');
    const images: PreviewImage[] = pictures.map((entry: DraftImageProgress): PreviewImage => entry.attachment ?
      { attachmentId: entry.attachment.id, mimeType: entry.attachment.mimeType, name: entry.attachment.name, draftTarget: entry.uri } :
      { localUri: entry.uri, name: entry.name ?? '图片', draftTarget: entry.uri });
    router.pushUrl({ url: 'pages/ImagePreview', params: { localUri: image.uri, name: image.name ?? '图片',
      environmentId: this.environmentId, commentThreadId: this.threadId, draftScope: this.draftScope,
      gallery: JSON.stringify(images), imageIndex: String(pictures.findIndex((entry: DraftImageProgress) => entry.uri === image.uri)) } });
  }
  build() {
    Scroll() {
      Row({ space: 10 }) {
        ForEach(this.images, (image: DraftImageProgress) => {
          Stack({ alignContent: Alignment.TopEnd }) {
            Stack({ alignContent: Alignment.BottomStart }) {
              if (image.type === 'file') {
                Column({ space: 4 }) {
                  Row({ space: 6 }) {
                    AppIcon({ name: 'file', iconSize: 22, tint: this.color('foreground-secondary') })
                    Text(image.name ?? '附件').fontSize(12).fontColor(this.color('foreground')).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                  }.width('100%')
                  Text(attachmentSize(image.sizeBytes ?? 0)).fontSize(10).fontColor(this.color('foreground-muted')).width('100%')
                }.width(160).height(72).padding({ left: 10, right: 26, top: 8, bottom: 8 }).backgroundColor(this.color('subtle'))
              } else if (image.attachment) {
                ChatImage({ attachment: image.attachment, environmentId: this.environmentId, tileWidth: 72, square: true,
                  online: this.online, loadSource: this.loadSource, onPreview: () => { this.open(image); } })
              } else {
                Image(`file://${image.uri}`).width(72).height(72).objectFit(ImageFit.Cover)
                  .onClick(() => { this.open(image); })
                  .accessibilityText(`放大预览 ${image.name ?? '图片'}`)
              }
              if (image.status !== 'uploaded') {
                Row({ space: 3 }) {
                  AppIcon({ name: image.status === 'failed' ? 'refresh' : 'send', iconSize: 10, tint: '#FFFFFF' })
                  Text(image.status === 'failed' ? '重试' : image.status === 'uploading' ? `${image.progress}%` : '等待上传')
                    .fontSize(10).fontColor('#FFFFFF')
                }.padding({ left: 5, right: 5, top: 3, bottom: 3 }).margin(4).borderRadius(10)
                  .backgroundColor(image.status === 'failed' ? '#CC991B1B' : '#B3000000')
                  .onClick(() => { if (image.status === 'failed' && !this.disabled) this.onRetry(image.uri); })
              }
            }.width(image.type === 'file' ? 160 : 72).height(72).borderRadius(16).clip(true)
              .border({ width: 0.5, color: this.color('border') })
              .accessibilityText(image.status === 'failed' ? `附件上传失败，点击重试：${image.error}` : `${image.name ?? '图片'} ${image.progress}%`)
            Button({ type: ButtonType.Circle }) { AppIcon({ name: 'close', iconSize: 10, tint: '#FFFFFF' }) }
              .width(22).height(22).padding(0).margin({ top: 4, right: 4 }).backgroundColor('#99000000')
              .enabled(!this.disabled).accessibilityText('移除此附件').onClick(() => { this.onRemove(image.uri); })
          }.width(image.type === 'file' ? 160 : 72).height(72)
        }, (image: DraftImageProgress) => image.uri + ':' + image.status + ':' + image.progress)
      }.padding({ left: 4, right: 4, top: 4, bottom: 4 })
    }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%').height(80).align(Alignment.Start)
  }
}
