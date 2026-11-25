import { ChatAttachment, QueuedMessage } from '../model/Models';
import { ThemeRuntime } from '../connection/ThemeRuntime';
import { AppIcon } from './AppIcon';
import { ChatImage } from './ChatImage';
import { MessageQuoteCard } from './MessageQuoteCard';
import { parseQuotedMessage } from '../model/MessageQuote';

@Component
export struct QueuedMessages {
  @Prop messages: QueuedMessage[] = [];
  @Prop online: boolean = false;
  @Prop running: boolean = false;
  @Prop busy: boolean = false;
  @Prop error: string = '';
  @Prop environmentId: string = '';
  @StorageLink('themeKey') themeKey: string = 't3-code-light';
  onAction: (runId: string, action: string, text: string) => Promise<boolean> = async () => false;
  onEdit: (message: QueuedMessage) => void = () => {};
  loadSource: (attachment: ChatAttachment, refresh: boolean) => Promise<string> = async () => '';
  private color(role: string): string { return ThemeRuntime.color(this.themeKey, role); }
  build() {
    Column({ space: 12 }) {
      if (!this.online) { Text('连接后可管理队列').fontSize(13).fontColor(this.color('foreground-muted')) }
      if (this.error) { Text(this.error).fontSize(13).fontColor(this.color('danger-foreground')).width('100%') }
      if (this.messages.length === 0) {
        Blank()
        Text('没有排队消息').fontSize(16).fontColor(this.color('foreground-muted'))
        Blank()
      } else {
        Text(`${this.messages.length} 条消息将按顺序发送`).fontSize(13).fontColor(this.color('foreground-muted')).width('100%')
        List({ space: 12 }) {
          ForEach(this.messages, (message: QueuedMessage) => {
            ListItem() {
              Column({ space: 12 }) {
                if (parseQuotedMessage(message.text).quote !== null) { MessageQuoteCard({ quote: parseQuotedMessage(message.text).quote, disabled: true }) }
                Row({ space: 10 }) {
                  ForEach(message.attachments.filter((attachment: ChatAttachment) => attachment.type === 'image').slice(0, 2), (attachment: ChatAttachment) => {
                    ChatImage({ attachment: attachment, tileWidth: 44, square: true, environmentId: this.environmentId,
                      online: this.online, loadSource: this.loadSource })
                  }, (attachment: ChatAttachment) => attachment.id)
                  Text(parseQuotedMessage(message.text).text || `${message.attachments.length} 个附件`).fontSize(15).fontColor(this.color('foreground'))
                    .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                }.width('100%')
                if (message.held || message.freshContext) {
                  Text(message.freshContext ? '新会话 · 当前任务结束后发送' : '队列已暂停，可立即发送以继续')
                    .fontSize(12).fontColor(this.color('foreground-muted')).width('100%')
                }
                Row({ space: 8 }) {
                  Button({ type: ButtonType.Circle }) { AppIcon({ name: 'send', iconSize: 18, tint: this.color('primary-foreground') }) }
                    .height(36).width(36).padding(0).accessibilityText('立即发送此排队消息').backgroundColor(this.color('primary')).fontColor(this.color('primary-foreground'))
                    .enabled(this.online && !this.busy && !message.automatic && !(this.running && message.freshContext))
                    .onClick(() => { this.onAction(message.runId, 'send', ''); })
                  Blank()
                  Button({ type: ButtonType.Circle }) { AppIcon({ name: 'edit', iconSize: 17, tint: this.color('foreground-secondary') }) }
                    .width(36).height(36).padding(0).backgroundColor(this.color('input')).accessibilityText('编辑排队消息')
                    .enabled(this.online && !this.busy && message.canEdit).onClick(() => { this.onEdit(message); })
                  Button({ type: ButtonType.Circle }) { AppIcon({ name: 'close', iconSize: 17, tint: this.color('foreground-muted') }) }
                    .width(36).height(36).padding(0).backgroundColor(this.color('input')).accessibilityText('删除排队消息')
                    .enabled(this.online && !this.busy).onClick(() => { this.onAction(message.runId, 'delete', ''); })
                }.width('100%')
              }.padding(14).width('100%').borderRadius(16).backgroundColor(this.color('card'))
                .border({ width: 1, color: this.color('border') })
            }
          }, (message: QueuedMessage) => JSON.stringify(message))
        }.layoutWeight(1).width('100%')
      }
    }.padding({ left: 16, right: 16, top: 8, bottom: 24 }).width('100%').height('100%')
  }
}
