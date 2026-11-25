import { MessageQuote, messageQuoteAuthor, messageQuotePreview } from '../model/MessageQuote';
import { ChatAttachment } from '../model/Models';
import { attachmentGallery } from '../model/ImageGallery';
import { ChatImage } from './ChatImage';
import { ThemeRuntime } from '../connection/ThemeRuntime';
import { Typography, resolveTypography, scaledFontSize } from '../model/Typography';
import { AppIcon } from './AppIcon';

@Component
export struct MessageQuoteCard {
  @Prop quote: MessageQuote | null = null;
  @Prop removable: boolean = false;
  @Prop disabled: boolean = false;
  @Prop locating: boolean = false;
  @Prop images: ChatAttachment[] = [];
  @Prop online: boolean = false;
  @StorageLink('themeKey') themeKey: string = 't3-code-light';
  @StorageLink('textSizes') sizes: Typography = resolveTypography(16, null, null);
  onLocate: () => void = () => {};
  onRemove: () => void = () => {};
  loadSource: (attachment: ChatAttachment, refresh: boolean) => Promise<string> = async () => '';
  private font(size: number): number { return scaledFontSize(size, this.sizes.baseFontSize); }
  private color(role: string): string { return ThemeRuntime.color(this.themeKey, role); }
  build() {
    if (this.quote !== null) {
      Row({ space: 8 }) {
        Row({ space: 10 }) {
          Column().width(3).height(38).borderRadius(2).backgroundColor(this.color('primary'))
          Column({ space: 3 }) {
            Row({ space: 5 }) {
              AppIcon({ name: 'quote', iconSize: 12, tint: this.color('foreground-muted') })
              Text(`引用 ${messageQuoteAuthor(this.quote)}`).fontSize(this.font(12)).fontWeight(FontWeight.Medium).fontColor(this.color('foreground-secondary'))
              if (this.locating) { LoadingProgress().width(12).height(12).color(this.color('foreground-muted')) }
            }
            Text(messageQuotePreview(this.quote)).fontSize(this.font(13)).fontColor(this.color('foreground'))
              .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }.layoutWeight(1).onClick(() => { if (!this.disabled) this.onLocate(); })
          .accessibilityText(`引用${messageQuoteAuthor(this.quote)}的消息，点击查看原消息`)
        ForEach(this.images.slice(0, 1), (image: ChatAttachment) => {
          Stack({ alignContent: Alignment.BottomEnd }) {
            ChatImage({ attachment: image, environmentId: this.quote?.environmentId ?? '', commentThreadId: this.quote?.threadId ?? '',
              tileWidth: 56, square: true, online: this.online, loadSource: this.loadSource,
              gallery: JSON.stringify(attachmentGallery(this.images)), galleryIndex: 0 })
            if (this.images.length > 1) {
              Text(`+${this.images.length - 1}`).fontSize(this.font(11)).fontColor(Color.White)
                .padding({ left: 4, right: 4 }).borderRadius(4).backgroundColor('#99000000').hitTestBehavior(HitTestMode.None)
            }
          }.width(56).height(56).hitTestBehavior(this.disabled ? HitTestMode.None : HitTestMode.Default)
        }, (image: ChatAttachment) => image.id)
        if (this.removable) {
          Button({ type: ButtonType.Circle }) { AppIcon({ name: 'close', iconSize: 16, tint: this.color('foreground-muted') }) }
            .width(32).height(32).padding(0).backgroundColor(Color.Transparent).enabled(!this.disabled)
            .accessibilityText('取消引用').onClick(() => { this.onRemove(); })
        }
      }.width('100%').padding(10).borderRadius(12).backgroundColor(this.color('card'))
        .border({ width: 0.75, color: this.color('chat-outline') })
    }
  }
}
