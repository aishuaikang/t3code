import { ChatGlass } from './ChatGlass';
import { AppIcon } from './AppIcon';
import { ThemeRuntime } from '../connection/ThemeRuntime';
import { Typography, resolveTypography, scaledFontSize } from '../model/Typography';

@Component
export struct FloatingNotice {
  @Prop text: string = '';
  @Prop busy: boolean = false;
  @Prop danger: boolean = false;
  @StorageLink('themeKey') themeKey: string = 't3-code-light';
  @StorageLink('textSizes') sizes: Typography = resolveTypography(16, null, null);
  build() {
    Column() {
      ChatGlass({ compact: true }) {
        Row({ space: 8 }) {
          if (this.busy) { LoadingProgress().width(16).height(16).color(ThemeRuntime.color(this.themeKey, 'foreground-secondary')) }
          else { AppIcon({ name: this.danger ? 'close' : 'refresh', iconSize: 16, tint: ThemeRuntime.color(this.themeKey, this.danger ? 'danger-foreground' : 'foreground-secondary') }) }
          Text(this.text).fontSize(scaledFontSize(12, this.sizes.baseFontSize)).maxLines(2)
            .fontColor(ThemeRuntime.color(this.themeKey, this.danger ? 'danger-foreground' : 'foreground'))
        }.padding({ left: 14, right: 14, top: 9, bottom: 9 })
      }
    }.constraintSize({ maxWidth: '94%' }).hitTestBehavior(HitTestMode.Block).accessibilityText(this.text)
  }
}
