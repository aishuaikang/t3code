import { ThemeRuntime } from '../connection/ThemeRuntime';
import { statusColor } from '../model/StatusVisuals';
import { Typography, resolveTypography, scaledFontSize } from '../model/Typography';

@Component
export struct StatusIndicator {
  @StorageLink('textSizes') sizes: Typography = resolveTypography(16, null, null);
  @Prop label: string = '';
  @Prop tint: string = '#71717A';
  build() {
    Text(this.label).fontSize(scaledFontSize(11, this.sizes.baseFontSize)).fontColor(this.tint).maxLines(1)
  }
}

@Component
export struct ConnectionSpinner {
  @Prop status: string = 'offline';
  @StorageLink('themeKey') themeKey: string = 't3-code-light';
  private tint(): string { return statusColor(this.status, ThemeRuntime.color(this.themeKey, 'screen')); }

  build() {
    LoadingProgress().width(14).height(14).color(this.tint())
      .accessibilityLevel('no').hitTestBehavior(HitTestMode.None)
  }
}

@Component
export struct ConnectionProgressBadge {
  @Prop label: string = '';
  @StorageLink('themeKey') themeKey: string = 't3-code-light';
  @StorageLink('textSizes') sizes: Typography = resolveTypography(16, null, null);

  build() {
    Row({ space: 6 }) {
      LoadingProgress().width(17).height(17).color(ThemeRuntime.color(this.themeKey, 'progress-foreground')).accessibilityLevel('no')
      Text(this.label).fontSize(scaledFontSize(13, this.sizes.baseFontSize)).fontWeight(FontWeight.Medium)
        .fontColor(ThemeRuntime.color(this.themeKey, 'progress-foreground')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).flexShrink(1)
    }.constraintSize({ minHeight: 26, maxWidth: '100%' }).padding({ left: 9, right: 11, top: 3, bottom: 3 })
      .linearGradient({ angle: 100, colors: [[ThemeRuntime.color(this.themeKey, 'progress-start'), 0],
        [ThemeRuntime.color(this.themeKey, 'progress-end'), 1]] }).borderRadius(24).clip(true)
      .accessibilityGroup(true).accessibilityText(this.label).hitTestBehavior(HitTestMode.None)
  }
}
