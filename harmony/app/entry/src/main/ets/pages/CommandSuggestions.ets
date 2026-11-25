import { ChatGlass } from './ChatGlass';
import { SlashCommand, commandSuggestions, commandQuery } from '../model/ComposerCommands';
import { ComposerPathEntry, composerEntryLabel, composerEntryDescription } from '../model/ComposerPath';
import { AppIcon } from './AppIcon';
import { ThemeRuntime } from '../connection/ThemeRuntime';
import { Typography, resolveTypography, scaledFontSize } from '../model/Typography';

@Component
export struct CommandSuggestions {
  @StorageLink('textSizes') sizes: Typography = resolveTypography(16, null, null);
  @StorageLink('themeKey') themeKey: string = 't3-code-light';
  @Prop text: string = '';
  @Prop start: number = 0;
  @Prop end: number = 0;
  @Prop commands: SlashCommand[] = [];
  @Prop disabled: boolean = false;
  @Prop paths: ComposerPathEntry[] = [];
  @Prop pathActive: boolean = false;
  @Prop pathLoading: boolean = false;
  @Prop pathStatus: string = '';
  @Prop availableHeight: number = 640;
  @State group: string = '全部';
  onSelect: (command: SlashCommand) => void = () => {};
  onSelectPath: (entry: ComposerPathEntry) => void = () => {};
  private color(role: string): string { return ThemeRuntime.color(this.themeKey, role); }
  private suggestions(): SlashCommand[] {
    return commandSuggestions(this.text, this.start, this.end, this.commands).filter((command: SlashCommand) =>
      this.group === '全部' || (this.group === '技能' ? command.kind === 'skill' : command.kind !== 'skill'));
  }
  private pathIcon(entry: ComposerPathEntry): string {
    if (entry.kind === 'directory') return 'folder';
    if (entry.kind === 'thread') return 'chat';
    return /\.(?:json|[cm]?[jt]sx?|ets|py|rs|go|sh|html|css)$/i.test(entry.path) ? 'code' : /\.(?:png|jpe?g|webp|gif|svg)$/i.test(entry.path) ? 'image' : 'file';
  }
  build() {
    if (!this.disabled && (this.pathActive || commandQuery(this.text, this.start, this.end) !== null)) {
      Column() {
        ChatGlass() {
          Column({ space: 0 }) {
            Row({ space: 6 }) {
              if (this.pathActive) {
                Text('引用文件或会话').fontSize(scaledFontSize(11, this.sizes.baseFontSize)).fontWeight(FontWeight.Medium).fontColor(this.color('foreground-muted'))
              } else {
                ForEach(['全部', '命令', '技能'], (group: string) => {
                  Button(group).fontSize(scaledFontSize(12, this.sizes.baseFontSize)).fontWeight(this.group === group ? FontWeight.Medium : FontWeight.Normal)
                    .fontColor(this.color(this.group === group ? 'foreground' : 'foreground-muted'))
                    .height(28).padding({ left: 10, right: 10 }).borderRadius(14).backgroundColor(this.group === group ? this.color('subtle-strong') : Color.Transparent)
                    .focusOnTouch(false).onClick(() => { this.group = group; })
                }, (group: string) => group)
              }
              if (this.pathActive && this.pathLoading) { LoadingProgress().width(12).height(12).color(this.color('foreground-muted')) }
            }.width('100%').padding({ left: 14, right: 14, top: 8, bottom: 4 })
            if (this.pathActive && this.paths.length > 0) {
              List() {
                ForEach(this.paths, (entry: ComposerPathEntry) => {
                  ListItem() {
                    Button({ type: ButtonType.Normal }) {
                      Row({ space: 9 }) {
                        AppIcon({ name: this.pathIcon(entry), iconSize: 16,
                          tint: entry.kind === 'thread' || entry.kind === 'directory' ? this.color('foreground-muted') : this.color('md-link') })
                        Text(composerEntryLabel(entry)).fontSize(scaledFontSize(14, this.sizes.baseFontSize)).fontWeight(FontWeight.Medium)
                          .fontColor(this.color('foreground')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1).textAlign(TextAlign.Start)
                        if (composerEntryDescription(entry)) {
                          Text(composerEntryDescription(entry)).fontSize(scaledFontSize(11, this.sizes.baseFontSize)).fontColor(this.color('foreground-muted'))
                            .maxLines(1).textAlign(TextAlign.End).textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: '40%' })
                        }
                      }.width('100%')
                    }.width('100%').height(44).borderRadius(10).padding({ left: 14, right: 14 }).backgroundColor(Color.Transparent)
                      .focusOnTouch(false).onClick(() => { this.onSelectPath(entry); }).accessibilityText(`引用 ${composerEntryLabel(entry)}`)
                  }
                }, (entry: ComposerPathEntry) => entry.kind + ':' + entry.path)
              }.width('100%').height(Math.min(176, this.availableHeight * 0.30, this.paths.length * 44)).scrollBar(BarState.Off)
            } else if (!this.pathActive && this.suggestions().length > 0) {
              List() {
                ForEach(this.suggestions(), (command: SlashCommand) => {
                  ListItem() {
                    Button({ type: ButtonType.Normal }) {
                      Row({ space: 9 }) {
                        AppIcon({ name: command.icon ?? (command.kind === 'skill' ? 'skill' : 'terminal'), iconSize: 15, tint: command.kind === 'skill' ? '#9B6DE3' : this.color('foreground-muted') })
                        Column({ space: 3 }) {
                          Text(command.displayName ?? (command.kind === 'skill' ? command.name.replace(/^skill:/, '') : `/${command.name}`))
                            .fontSize(scaledFontSize(14, this.sizes.baseFontSize)).fontWeight(FontWeight.Medium).fontColor(this.color('foreground'))
                            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                          if (command.description || command.input?.hint) {
                            Text(command.description ?? command.input?.hint ?? '').fontSize(scaledFontSize(11, this.sizes.baseFontSize))
                              .fontColor(this.color('foreground-muted')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                          }
                        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                        AppIcon({ name: 'chevron', iconSize: 12, tint: this.color('foreground-muted') })
                      }.width('100%')
                    }.width('100%').height(52).borderRadius(10).padding({ left: 14, right: 14 }).backgroundColor(Color.Transparent)
                      .focusOnTouch(false).onClick(() => { this.onSelect(command); }).accessibilityText(`插入命令 ${command.name}`)
                  }
                }, (command: SlashCommand) => command.name)
              }.width('100%').height(Math.min(208, this.availableHeight * 0.30, this.suggestions().length * 52)).scrollBar(BarState.Auto).scrollBarWidth(2).scrollBarColor('#66' + this.color('foreground-muted').slice(1))
            } else {
              Text(this.pathActive ? this.pathStatus || '没有匹配的文件或会话' : '没有匹配的命令')
                .fontSize(scaledFontSize(12, this.sizes.baseFontSize)).fontColor(this.color('foreground-muted')).width('100%')
                .padding({ left: 14, right: 14, top: 10, bottom: 12 })
            }
          }.width('100%').padding({ bottom: 4 }).borderRadius(16).clip(true)
            .accessibilityText(this.pathActive ? '文件与会话提示' : '命令提示')
        }
      }.width('100%').borderRadius(16).backgroundColor(this.color('card')).margin({ bottom: 8 })
    }
  }
}
