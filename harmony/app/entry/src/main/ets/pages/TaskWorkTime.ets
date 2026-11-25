import { LatestTurn, workDuration } from '../model/Models';
import { ThemeRuntime } from '../connection/ThemeRuntime';
import { Typography, resolveTypography, scaledFontSize } from '../model/Typography';
import { AppIcon } from './AppIcon';

@Component
export struct TaskWorkTime {
  @Prop @Watch('updateClock') turn: LatestTurn = { turnId: '', state: 'running' };
  @StorageLink('themeKey') themeKey: string = 't3-code-light';
  @StorageLink('textSizes') sizes: Typography = resolveTypography(16, null, null);
  @StorageLink('appForeground') @Watch('updateClock') foreground: boolean = true;
  @State label: string = '';
  private mounted: boolean = false;
  private visible: boolean = true;
  private timer: number = -1;

  aboutToAppear(): void { this.mounted = true; this.updateClock(); }
  aboutToDisappear(): void { this.mounted = false; this.stopClock(); }
  private stopClock(): void {
    if (this.timer !== -1) clearInterval(this.timer);
    this.timer = -1;
  }
  private updateClock(): void {
    this.stopClock();
    this.updateLabel();
    if (this.mounted && this.visible && this.foreground) this.timer = setInterval(() => { this.updateLabel(); }, 1000);
  }
  private updateLabel(): void { this.label = workDuration(this.turn, new Date().toISOString()).replace('工作了 ', '工作中 '); }
  build() {
    Row({ space: 4 }) {
      if (this.label) {
        AppIcon({ name: 'clock', iconSize: 11, tint: ThemeRuntime.color(this.themeKey, 'foreground-muted') })
        Text(this.label).fontSize(scaledFontSize(11, this.sizes.baseFontSize)).fontColor(ThemeRuntime.color(this.themeKey, 'foreground-muted'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }.onVisibleAreaChange([0], (visible: boolean) => { this.visible = visible; this.updateClock(); })
  }
}
