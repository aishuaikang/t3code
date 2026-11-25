import { AppIcon } from './AppIcon';
import { ThemeRuntime } from '../connection/ThemeRuntime';
import { Typography, resolveTypography, scaledFontSize } from '../model/Typography';

@Component
export struct WorkStatus {
  @StorageLink('textSizes') sizes: Typography = resolveTypography(16, null, null);
  @StorageLink('themeKey') themeKey: string = 't3-code-light';
  @StorageLink('appForeground') @Watch('updateAnimation') foreground: boolean = true;
  @StorageLink('reduceMotion') @Watch('updateAnimation') reduceMotion: boolean = false;
  @Prop label: string = '思考中…';
  @Prop @Watch('updateAnimation') active: boolean = false;
  @State sweep: number = -56;
  private availableWidth: number = 0;
  private visible: boolean = false;
  private mounted: boolean = false;
  private revision: number = 0;
  private timer: number = -1;

  aboutToAppear(): void { this.mounted = true; }
  aboutToDisappear(): void { this.mounted = false; this.stopAnimation(); }
  private color(role: string): string { return ThemeRuntime.color(this.themeKey, role); }
  private canAnimate(): boolean {
    return this.mounted && this.visible && this.active && this.foreground && !this.reduceMotion && this.availableWidth > 0;
  }
  private stopAnimation(): void {
    ++this.revision;
    if (this.timer !== -1) clearTimeout(this.timer);
    this.timer = -1;
    this.getUIContext().animateTo({ duration: 0 }, () => { this.sweep = -56; });
  }
  private updateAnimation(): void {
    this.stopAnimation();
    if (!this.canAnimate()) return;
    const revision = this.revision;
    this.timer = setTimeout(() => { this.timer = -1; this.sweepOnce(revision); }, 0);
  }
  private sweepOnce(revision: number): void {
    if (revision !== this.revision || !this.canAnimate()) return;
    // Native transform animation; JavaScript only schedules the pause between sweeps.
    this.getUIContext().animateTo({ duration: 1350, curve: Curve.Linear,
      expectedFrameRateRange: { min: 15, max: 30, expected: 30 }, onFinish: () => {
        if (revision !== this.revision || !this.canAnimate()) return;
        this.getUIContext().animateTo({ duration: 0 }, () => { this.sweep = -56; });
        this.timer = setTimeout(() => { this.timer = -1; this.sweepOnce(revision); }, 1450);
      } }, () => { this.sweep = this.availableWidth; });
  }

  build() {
    Stack({ alignContent: Alignment.Start }) {
      Row({ space: 8 }) {
        AppIcon({ name: 'thinking', iconSize: 15, tint: this.color('foreground-muted') })
        Text(this.label).fontSize(scaledFontSize(13, this.sizes.baseFontSize)).fontColor(this.color('foreground-muted'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
      }.width('100%')
      if (this.active && this.foreground && !this.reduceMotion) {
        Rect().width(56).height('100%').linearGradient({ angle: 90, colors: [
          [Color.Transparent, 0], ['#88' + this.color('foreground').slice(1), 0.5], [Color.Transparent, 1]
        ] }).translate({ x: this.sweep }).blendMode(BlendMode.SRC_ATOP).hitTestBehavior(HitTestMode.None)
      }
    }.height(scaledFontSize(20, this.sizes.baseFontSize)).clip(true)
      .blendMode(BlendMode.SRC_OVER, BlendApplyType.OFFSCREEN).accessibilityText(this.label)
      .onAreaChange((_old: Area, area: Area) => {
        const width = Number(area.width);
        if (width === this.availableWidth) return;
        this.availableWidth = width; this.updateAnimation();
      })
      .onVisibleAreaChange([0, 1], (visible: boolean, ratio: number) => {
        const inView = visible && ratio > 0;
        if (inView === this.visible) return;
        this.visible = inView; this.updateAnimation();
      })
  }
}
