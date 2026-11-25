import { SavedEnvironment, routeAddress } from '../connection/EnvironmentStore';
import { ConnectionSpinner } from './StatusIndicator';
import { connectionProgressLabel, statusLabel } from '../model/StatusVisuals';
import { ThemeRuntime } from '../connection/ThemeRuntime';
import { Typography, resolveTypography, scaledFontSize } from '../model/Typography';
import { AppIcon } from './AppIcon';

@Component
export struct EnvironmentPicker {
  @Prop environments: SavedEnvironment[] = [];
  @Prop selectedId: string = '';
  @Prop connectionState: string = 'offline';
  @Prop disabled: boolean = false;
  @Prop canManage: boolean = false;
  onSelect: (saved: SavedEnvironment) => void = () => {};
  onManage: () => void = () => {};
  @StorageLink('themeKey') themeKey: string = 't3-code-light';
  @StorageLink('textSizes') sizes: Typography = resolveTypography(16, null, null);
  @State query: string = '';
  private color(role: string): string { return ThemeRuntime.color(this.themeKey, role); }
  private font(size: number): number { return scaledFontSize(size, this.sizes.baseFontSize); }
  private selected(saved: SavedEnvironment): boolean { return (saved.connectionId ?? saved.environmentId) === this.selectedId; }
  private visible(): SavedEnvironment[] { return this.environments.filter((saved: SavedEnvironment) => `${saved.label} ${routeAddress(saved)}`.toLocaleLowerCase().includes(this.query.trim().toLocaleLowerCase())); }
  build() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Search({ value: this.query, placeholder: '搜索环境' }).height(42).borderRadius(14).textFont({ size: this.font(15) })
          .fontColor(this.color('foreground')).backgroundColor(this.color('input')).layoutWeight(1).onChange((value: string) => { this.query = value; })
        if (this.canManage) {
          Button({ type: ButtonType.Circle }) { AppIcon({ name: 'sliders', iconSize: 21, tint: this.color('foreground') }) }
            .width(40).height(40).padding(0).backgroundColor(Color.Transparent).accessibilityText('管理环境').onClick(() => { this.onManage(); })
        }
      }.width('100%')
      List() {
        ForEach(this.visible(), (saved: SavedEnvironment) => {
          ListItem() {
            Button({ type: ButtonType.Normal }) {
              Row({ space: 12 }) {
                Stack({ alignContent: Alignment.BottomEnd }) {
                  AppIcon({ name: saved.ssh ? 'terminal' : 'machine', iconSize: 25, tint: this.color('foreground-secondary') })
                  if (this.selected(saved) && connectionProgressLabel(this.connectionState)) {
                    ConnectionSpinner({ status: this.connectionState }).backgroundColor(this.color('card')).borderRadius(7)
                  }
                }.width(30).height(30)
                Column({ space: 5 }) {
                  Text(saved.label).fontSize(this.font(16)).fontWeight(FontWeight.Medium).fontColor(this.color('foreground')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                  Text(`${this.selected(saved) ? statusLabel(this.connectionState) : '未连接'} · ${saved.sshRole === 'primary' ? '主用 · ' : saved.sshRole === 'backup' ? '备用 · ' : ''}${routeAddress(saved)}`)
                    .fontSize(this.font(12)).fontColor(this.color('foreground-muted')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                }.layoutWeight(1)
                if (this.selected(saved)) { AppIcon({ name: 'check', iconSize: 20, tint: this.color('primary') }) }
              }.width('100%')
            }.height(76).width('100%').borderRadius(0).padding({ left: 16, right: 16 }).backgroundColor(Color.Transparent).enabled(!this.disabled)
              .onClick(() => { this.onSelect(saved); }).accessibilityText(`选择环境 ${saved.label}，${routeAddress(saved)}${this.selected(saved) ? '，已选中' : ''}`)
          }
        }, (saved: SavedEnvironment) => `${saved.connectionId ?? saved.environmentId}:${saved.sshRole ?? ''}`)
        if (this.visible().length === 0) {
          ListItem() { Text(this.query ? '没有匹配的环境' : '尚未添加环境').fontSize(this.font(14)).fontColor(this.color('foreground-muted')).width('100%').textAlign(TextAlign.Center).padding(24) }
        }
      }.layoutWeight(1).width('100%').borderRadius(20).backgroundColor('#B3' + this.color('card').slice(1)).clip(true)
    }.width('100%').height('100%')
  }
}
