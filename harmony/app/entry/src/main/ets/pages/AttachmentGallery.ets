import { ChatAttachment } from '../model/Models';
import { ChatImage } from './ChatImage';
import { attachmentGallery, attachmentTileLayout } from '../model/ImageGallery';

@Component
export struct AttachmentGallery {
  @Prop attachments: ChatAttachment[] = [];
  @Prop environmentId: string = '';
  @Prop threadId: string = '';
  @Prop online: boolean = false;
  loadSource: (attachment: ChatAttachment, refresh: boolean) => Promise<string> = async () => '';
  @State contentWidth: number = 260;

  @Builder
  private tile(attachment: ChatAttachment, index: number, width: number, aspect: number) {
    ChatImage({ attachment: attachment, environmentId: this.environmentId, online: this.online,
      gallery: JSON.stringify(attachmentGallery(this.attachments)), galleryIndex: index, commentThreadId: this.threadId,
      tileWidth: width, tileAspect: aspect, loadSource: this.loadSource })
      .margin({ right: this.attachments.length === 3 ? 0 : attachmentTileLayout(this.attachments.length, index, this.contentWidth).right,
        bottom: this.attachments.length === 3 ? 0 : attachmentTileLayout(this.attachments.length, index, this.contentWidth).bottom })
  }

  build() {
    Column() {
    if (this.attachments.length === 3) {
      Row({ space: 2 }) {
        ForEach(this.attachments.slice(0, 1), (attachment: ChatAttachment) => {
          this.tile(attachment, 0, (this.contentWidth - 2) * 0.6, (this.contentWidth - 2) / this.contentWidth)
        }, (attachment: ChatAttachment) => attachment.id)
        Column({ space: 2 }) {
          ForEach(this.attachments.slice(1), (attachment: ChatAttachment, index: number) => {
            this.tile(attachment, index + 1, (this.contentWidth - 2) * 0.4,
              (this.contentWidth - 2) * 0.4 / ((this.contentWidth * 0.6 - 2) / 2))
          }, (attachment: ChatAttachment) => attachment.id)
        }
      }.width('100%').height(this.contentWidth * 0.6)
    } else {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
      ForEach(this.attachments, (attachment: ChatAttachment, index: number) => {
        this.tile(attachment, index, attachmentTileLayout(this.attachments.length, index, this.contentWidth).width,
          attachmentTileLayout(this.attachments.length, index, this.contentWidth).aspect)
      }, (attachment: ChatAttachment) => attachment.id)
    }.width('100%')
    }
    }.width('100%').borderRadius(16).clip(true)
      .onAreaChange((_old: Area, area: Area) => {
        const width = Number(area.width);
        if (width > 0 && Math.abs(width - this.contentWidth) > 1) this.contentWidth = width;
      })
  }
}
