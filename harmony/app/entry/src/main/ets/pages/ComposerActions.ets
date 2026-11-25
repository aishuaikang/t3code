import { immersiveMaterial } from './ChatGlass';
import { AppIcon } from './AppIcon';
import { ThemeRuntime } from '../connection/ThemeRuntime';
import { Typography, resolveTypography, scaledFontSize } from '../model/Typography';

@Component
export struct ComposerActions {
  @StorageLink('themeKey') themeKey: string = 't3-code-light';
  @StorageLink('textSizes') sizes: Typography = resolveTypography(16, null, null);
  @Prop disabled: boolean = false;
  @Prop canAttach: boolean = false;
  @Prop canAttachFiles: boolean = false;
  @Prop references: boolean = true;
  onPhotos: () => void = () => {};
  onFiles: () => void = () => {};
  onInsert: (trigger: string) => void = () => {};
  @State open: boolean = false;
  private color(role: string): string { return ThemeRuntime.color(this.themeKey, role); }
  private font(size: number): number { return scaledFontSize(size, this.sizes.baseFontSize); }
  @Builder
  private action(icon: string, title: string, detail: string, trigger: string) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 12 }) {
        AppIcon({ name: icon, iconSize: 20, tint: this.color('foreground-secondary') })
        Column({ space: 4 }) {
          Text(title).fontSize(this.font(15)).fontColor(this.color('foreground')).width('100%')
          Text(detail).fontSize(this.font(11)).fontColor(this.color('foreground-muted')).width('100%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        AppIcon({ name: 'chevron', iconSize: 12, tint: this.color('foreground-muted') })
      }.width('100%')
    }.width('100%').height(62).borderRadius(12).padding(12).backgroundColor(Color.Transparent).focusOnTouch(false)
      .onClick(() => { this.open = false; this.onInsert(trigger); })
  }
  @Builder
  private menu() {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Normal }) {
          Column({ space: 8 }) {
            AppIcon({ name: 'image', iconSize: 24, tint: this.color('foreground-secondary') })
            Text('照片').fontSize(this.font(13)).fontColor(this.color('foreground'))
          }
        }.layoutWeight(1).height(76).padding(8).borderRadius(14).backgroundColor(this.color('subtle')).enabled(this.canAttach)
          .onClick(() => { this.open = false; this.onPhotos(); })
        Button({ type: ButtonType.Normal }) {
          Column({ space: 8 }) {
            AppIcon({ name: 'file', iconSize: 24, tint: this.color('foreground-secondary') })
            Text('文件').fontSize(this.font(13)).fontColor(this.color('foreground'))
          }
        }.layoutWeight(1).height(76).padding(8).borderRadius(14).backgroundColor(this.color('subtle')).enabled(this.canAttach && this.canAttachFiles)
          .onClick(() => { this.open = false; this.onFiles(); })
      }.width('100%').padding({ bottom: 6 })
      if (this.references) {
        Divider().color(this.color('border'))
        this.action('at', '引用文件或会话', '在当前位置插入 @，支持中文搜索', '@')
        this.action('terminal', '命令和技能', '查看当前提供方及项目的可用命令', '/')
      }
    }.width(292).padding(10)
  }
  build() {
    Button({ type: ButtonType.Circle }) { AppIcon({ name: 'plus', iconSize: 22, tint: this.color('glass-label') }) }
      .width(36).height(40).padding(0).backgroundColor(Color.Transparent).enabled(!this.disabled).focusOnTouch(false)
      .accessibilityText('附件、引用与命令').onClick(() => { this.open = !this.open; })
      .bindPopup(this.open, { builder: this.menu(), placement: Placement.TopLeft, enableArrow: false,
        systemMaterial: immersiveMaterial('popup'), radius: 22,
        onStateChange: (event: PopupStateChangeParam) => { this.open = event.isVisible; } })
  }
}
