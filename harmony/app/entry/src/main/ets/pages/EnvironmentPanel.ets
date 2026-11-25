import router from '@ohos.router';
import { PreparedConnection } from '../connection/Environment';
import { SavedEnvironment, routeAddress } from '../connection/EnvironmentStore';
import { ThemeRuntime } from '../connection/ThemeRuntime';
import { Typography, resolveTypography, scaledFontSize } from '../model/Typography';
import { connectionProgressLabel, statusLabel } from '../model/StatusVisuals';
import { AppIcon } from './AppIcon';
import { ChatGlass } from './ChatGlass';
import { ConnectionSpinner } from './StatusIndicator';

export interface EnvironmentPanelActions {
  reload: () => void;
  back: () => void;
  add: (routed: boolean) => void;
  tasks: (routed: boolean) => void;
  toggle: (saved: SavedEnvironment, enabled: boolean, routed: boolean) => void;
  reconnect: (saved: SavedEnvironment, routed: boolean) => void;
  prefer: (saved: SavedEnvironment) => void;
  forget: (saved: SavedEnvironment) => void;
  connect: () => void;
}

@Component
export struct EnvironmentPanel {
  @Prop routed: boolean = false;
  @Prop canReturnHome: boolean = false;
  @StorageLink('themeKey') themeKey: string = 't3-code-light';
  @StorageLink('textSizes') sizes: Typography = resolveTypography(16, null, null);
  @State expandedEnvironmentId: string = '';
  @LocalStorageLink('environment.direct') direct: boolean = true;
  @LocalStorageLink('environment.environmentUrl') environmentUrl: string = '';
  @LocalStorageLink('environment.pairingToken') pairingToken: string = '';
  @LocalStorageLink('environment.hostname') hostname: string = '';
  @LocalStorageLink('environment.port') port: string = '22';
  @LocalStorageLink('environment.username') username: string = '';
  @LocalStorageLink('environment.password') password: string = '';
  @LocalStorageLink('environment.hostFingerprint') hostFingerprint: string = '';
  @LocalStorageLink('environment.packageSpec') packageSpec: string = 't3@nightly';
  @LocalStorageLink('environment.existingSshServer') existingSshServer: boolean = true;
  @LocalStorageLink('environment.serverPort') serverPort: string = '3773';
  @LocalStorageLink('environment.serverHost') serverHost: string = '';
  @LocalStorageLink('environment.connecting') connecting: boolean = false;
  @LocalStorageLink('environment.forgetting') forgetting: boolean = false;
  @LocalStorageLink('environment.connected') connected: PreparedConnection | null = null;
  @LocalStorageLink('environment.saved') saved: SavedEnvironment[] = [];
  @LocalStorageLink('environment.status') status: string = '';
  @LocalStorageLink('environment.connectionState') connectionState: string = 'offline';
  @LocalStorageLink('environment.restoringConnectionId') restoringConnectionId: string = '';
  @LocalStorageLink('environment.environmentFormOpen') environmentFormOpen: boolean = false;

  private actions(): EnvironmentPanelActions | undefined { return this.getUIContext().getSharedLocalStorage()?.get<EnvironmentPanelActions>('environment.actions'); }
  private color(role: string): string { return ThemeRuntime.color(this.themeKey, role); }
  private font(size: number): number { return scaledFontSize(size, this.sizes.baseFontSize); }

  @Builder
  private environmentHeader() {
    Row({ space: 12 }) {
      Button({ type: ButtonType.Circle }) {
        AppIcon({ name: this.environmentFormOpen || this.routed || this.canReturnHome ? 'back' : 'settings', iconSize: 22, tint: this.color('foreground') })
      }.width(44).height(44).padding(0).backgroundColor(Color.Transparent)
        .accessibilityText(this.environmentFormOpen ? '返回环境列表' : this.routed ? '返回' : this.canReturnHome ? '返回任务' : '设置')
        .onClick(() => { if (this.routed && !this.environmentFormOpen) router.back(); else this.actions()?.back(); })
      Text(this.environmentFormOpen ? '添加环境' : '环境').fontSize(this.font(22)).fontWeight(FontWeight.Bold)
        .fontColor(this.color('foreground')).layoutWeight(1)
      if (!this.environmentFormOpen) {
        Button({ type: ButtonType.Circle }) { AppIcon({ name: 'plus', iconSize: 23, tint: this.color('foreground') }) }
          .width(44).height(44).padding(0).backgroundColor(Color.Transparent).enabled(!this.forgetting)
          .accessibilityText('添加环境').onClick(() => { this.actions()?.add(this.routed); })
      }
    }.height(56).width('100%')
  }

  private routeStatus(saved: SavedEnvironment): string {
    return this.connected?.matchesSaved(saved) || this.restoringConnectionId === (saved.connectionId ?? saved.environmentId) ? this.connectionState : 'offline';
  }

  @Builder
  private environmentList() {
    Column({ space: 0 }) {
      if (this.saved.length === 0) {
        Column({ space: 12 }) {
          AppIcon({ name: 'machine', iconSize: 26, tint: this.color('foreground-muted') })
          Text(this.connecting ? '正在读取已保存的环境…' : '尚未添加环境，点击右上角添加')
            .fontSize(this.font(14)).fontColor(this.color('foreground-muted')).textAlign(TextAlign.Center)
        }.width('100%').padding({ left: 24, right: 24, top: 32, bottom: 32 })
      }
      ForEach(this.saved, (saved: SavedEnvironment, index: number) => {
        Column({ space: 0 }) {
          Row({ space: 8 }) {
            Button({ type: ButtonType.Normal }) {
              Column({ space: 5 }) {
                Row({ space: 6 }) {
                  if (connectionProgressLabel(this.routeStatus(saved))) { ConnectionSpinner({ status: this.routeStatus(saved) }) }
                  AppIcon({ name: saved.ssh === undefined ? 'machine' : 'terminal', iconSize: 15, tint: this.color('foreground-muted') })
                  Text(saved.label).fontSize(this.font(16)).fontWeight(FontWeight.Bold).fontColor(this.color('foreground'))
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                  if (saved.sshRole) { Text(saved.sshRole === 'primary' ? '主用' : '备用').fontSize(this.font(12)).fontColor(this.color('foreground-muted')) }
                }.width('100%')
                Text(routeAddress(saved))
                  .fontSize(this.font(12)).fontColor(this.color('foreground-muted')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                Text(statusLabel(this.routeStatus(saved)))
                  .fontSize(this.font(12)).fontColor(this.color('foreground-muted'))
              }.alignItems(HorizontalAlign.Start).width('100%')
            }.layoutWeight(1).padding(0).backgroundColor(Color.Transparent).borderRadius(8)
              .accessibilityText(`管理环境 ${saved.label}，${routeAddress(saved)}`).onClick(() => { this.expandedEnvironmentId = this.expandedEnvironmentId === (saved.connectionId ?? saved.environmentId) ? '' : saved.connectionId ?? saved.environmentId; })
              .gesture(LongPressGesture().onAction(() => { this.expandedEnvironmentId = saved.connectionId ?? saved.environmentId; }))
            Toggle({ type: ToggleType.Switch, isOn: this.connected?.matchesSaved(saved) === true })
              .enabled(!this.forgetting && this.restoringConnectionId !== (saved.connectionId ?? saved.environmentId)).selectedColor(this.color('primary')).accessibilityText(`${saved.label}，${routeAddress(saved)} 连接开关`)
              .onChange((enabled: boolean) => { this.actions()?.toggle(saved, enabled, this.routed); })
            Button({ type: ButtonType.Circle }) {
              AppIcon({ name: this.expandedEnvironmentId === (saved.connectionId ?? saved.environmentId) ? 'down' : 'chevron', iconSize: 15, tint: this.color('foreground-muted') })
            }.height(40).width(28).padding(0).backgroundColor(Color.Transparent).accessibilityText(`展开 ${routeAddress(saved)} 操作`)
              .onClick(() => { this.expandedEnvironmentId = this.expandedEnvironmentId === (saved.connectionId ?? saved.environmentId) ? '' : saved.connectionId ?? saved.environmentId; })
          }.width('100%').padding(16)
          if (this.expandedEnvironmentId === (saved.connectionId ?? saved.environmentId)) {
            Row({ space: 10 }) {
              if (this.connected?.matchesSaved(saved)) {
                Button({ type: ButtonType.Circle }) { AppIcon({ name: 'chat', iconSize: 20, tint: this.color('foreground') }) }
                  .width(44).height(44).backgroundColor(this.color('input')).accessibilityText('打开此环境的任务')
                  .onClick(() => { this.actions()?.tasks(this.routed); })
              }
              if (saved.sshRole === 'backup') {
                Button('设为主用').height(36).fontSize(this.font(13)).backgroundColor(this.color('input')).fontColor(this.color('foreground'))
                  .enabled(!this.forgetting).onClick(() => { this.actions()?.prefer(saved); })
              }
              Blank()
              Button({ type: ButtonType.Circle }) { AppIcon({ name: 'refresh', iconSize: 20, tint: this.color('foreground') }) }
                .width(44).height(44).backgroundColor(this.color('input')).enabled(!this.forgetting && this.restoringConnectionId !== (saved.connectionId ?? saved.environmentId)).accessibilityText(`重连 ${routeAddress(saved)}`)
                .onClick(() => { this.actions()?.reconnect(saved, this.routed); })
              Button({ type: ButtonType.Circle }) { AppIcon({ name: 'trash', iconSize: 20, tint: this.color('danger-foreground') }) }
                .width(44).height(44).backgroundColor(this.color('input')).enabled(!this.connecting && !this.forgetting).accessibilityText(`移除 ${routeAddress(saved)}`)
                .onClick(() => { this.actions()?.forget(saved); })
            }.width('100%').padding({ left: 16, right: 16, bottom: 16 })
          }
          if (index < this.saved.length - 1) { Divider().color(this.color('border')).margin({ left: 16, right: 16 }) }
        }.width('100%')
      }, (saved: SavedEnvironment) => `${saved.connectionId ?? saved.environmentId}:${saved.sshRole ?? ''}`)
    }.width('100%').borderRadius(24).backgroundColor(this.color('card')).clip(true)
  }

  @Builder
  private environmentFieldLabel(label: string) {
    Text(label).fontSize(this.font(13)).fontColor(this.color('foreground-secondary')).margin({ top: 6 })
  }

  @Builder
  private environmentForm() {
    Column({ space: 12 }) {
      Row({ space: 4 }) {
        Button({ type: ButtonType.Normal }) {
          Row({ space: 7 }) {
            AppIcon({ name: 'machine', iconSize: 17, tint: this.color('foreground') })
            Text('直连').fontSize(this.font(14)).fontColor(this.color('foreground'))
          }
        }.height(42).layoutWeight(1).borderRadius(12).backgroundColor(this.direct ? this.color('card') : Color.Transparent)
          .enabled(!this.connecting).onClick(() => { this.direct = true; })
        Button({ type: ButtonType.Normal }) {
          Row({ space: 7 }) {
            AppIcon({ name: 'terminal', iconSize: 17, tint: this.color('foreground') })
            Text('SSH').fontSize(this.font(14)).fontColor(this.color('foreground'))
          }
        }.height(42).layoutWeight(1).borderRadius(12).backgroundColor(this.direct ? Color.Transparent : this.color('card'))
          .enabled(!this.connecting).onClick(() => { this.direct = false; })
      }.width('100%').padding(4).borderRadius(16).backgroundColor(this.color('input'))
      Column({ space: 10 }) {
        if (this.direct) {
          this.environmentFieldLabel('主机')
          TextInput({ placeholder: 'http://192.168.1.100:3773', text: this.environmentUrl }).fontSize(this.font(16)).height(48).borderRadius(12)
            .fontColor(this.color('foreground')).placeholderColor(this.color('foreground-muted')).backgroundColor(this.color('input'))
            .enabled(!this.connecting).onChange((value: string) => { this.environmentUrl = value; })
          this.environmentFieldLabel('配对码')
          TextInput({ placeholder: '输入环境的配对码', text: this.pairingToken }).fontSize(this.font(16)).height(48).borderRadius(12)
            .fontColor(this.color('foreground')).placeholderColor(this.color('foreground-muted')).backgroundColor(this.color('input'))
            .type(InputType.Password).enabled(!this.connecting).onChange((value: string) => { this.pairingToken = value; })
        } else {
          this.environmentFieldLabel('SSH 主机')
          TextInput({ placeholder: '主机名或 IP 地址', text: this.hostname }).fontSize(this.font(16)).height(48).borderRadius(12)
            .fontColor(this.color('foreground')).placeholderColor(this.color('foreground-muted')).backgroundColor(this.color('input'))
            .enabled(!this.connecting).onChange((value: string) => { this.hostname = value; })
          this.environmentFieldLabel('端口')
          TextInput({ placeholder: '22', text: this.port }).fontSize(this.font(16)).height(48).borderRadius(12).type(InputType.Number)
            .fontColor(this.color('foreground')).placeholderColor(this.color('foreground-muted')).backgroundColor(this.color('input'))
            .enabled(!this.connecting).onChange((value: string) => { this.port = value; })
          this.environmentFieldLabel('用户名')
          TextInput({ placeholder: 'SSH 用户名', text: this.username }).fontSize(this.font(16)).height(48).borderRadius(12)
            .fontColor(this.color('foreground')).placeholderColor(this.color('foreground-muted')).backgroundColor(this.color('input'))
            .enabled(!this.connecting).onChange((value: string) => { this.username = value; })
          this.environmentFieldLabel('主机指纹')
          TextInput({ placeholder: 'SHA256:…', text: this.hostFingerprint }).fontSize(this.font(16)).height(48).borderRadius(12)
            .fontColor(this.color('foreground')).placeholderColor(this.color('foreground-muted')).backgroundColor(this.color('input'))
            .enabled(!this.connecting).onChange((value: string) => { this.hostFingerprint = value; })
          this.environmentFieldLabel('密码')
          TextInput({ placeholder: 'SSH 密码', text: this.password }).fontSize(this.font(16)).height(48).borderRadius(12).type(InputType.Password)
            .fontColor(this.color('foreground')).placeholderColor(this.color('foreground-muted')).backgroundColor(this.color('input'))
            .enabled(!this.connecting).onChange((value: string) => { this.password = value; })
          Row({ space: 8 }) {
            Text('连接已有 T3 服务').fontSize(this.font(14)).fontColor(this.color('foreground')).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.existingSshServer }).selectedColor(this.color('primary')).enabled(!this.connecting)
              .onChange((enabled: boolean) => { this.existingSshServer = enabled; })
          }.width('100%').padding({ top: 8, bottom: 4 })
          if (this.existingSshServer) {
            this.environmentFieldLabel('T3 服务主机（从 SSH 服务器访问）')
            TextInput({ placeholder: '127.0.0.1', text: this.serverHost }).fontSize(this.font(16)).height(48).borderRadius(12)
              .fontColor(this.color('foreground')).placeholderColor(this.color('foreground-muted')).backgroundColor(this.color('input'))
              .enabled(!this.connecting).onChange((value: string) => { this.serverHost = value; })
            this.environmentFieldLabel('T3 服务端口')
            TextInput({ placeholder: '3773', text: this.serverPort }).fontSize(this.font(16)).height(48).borderRadius(12).type(InputType.Number)
              .fontColor(this.color('foreground')).placeholderColor(this.color('foreground-muted')).backgroundColor(this.color('input'))
              .enabled(!this.connecting).onChange((value: string) => { this.serverPort = value; })
            this.environmentFieldLabel('配对码')
            TextInput({ placeholder: 'T3 配对码', text: this.pairingToken }).fontSize(this.font(16)).height(48).borderRadius(12).type(InputType.Password)
              .fontColor(this.color('foreground')).placeholderColor(this.color('foreground-muted')).backgroundColor(this.color('input'))
              .enabled(!this.connecting).onChange((value: string) => { this.pairingToken = value; })
          } else {
            this.environmentFieldLabel('远端 T3 包')
            TextInput({ placeholder: 't3@nightly', text: this.packageSpec }).fontSize(this.font(16)).height(48).borderRadius(12)
              .fontColor(this.color('foreground')).placeholderColor(this.color('foreground-muted')).backgroundColor(this.color('input'))
              .enabled(!this.connecting).onChange((value: string) => { this.packageSpec = value; })
          }
        }
        Button({ type: ButtonType.Normal }) {
          Row({ space: 8 }) {
            if (this.connecting) { LoadingProgress().width(18).height(18).color(this.color('primary-foreground')) }
            else { AppIcon({ name: 'plus', iconSize: 18, tint: this.color('primary-foreground') }) }
            Text(this.connecting ? '连接中…' : '添加环境').fontSize(this.font(15)).fontColor(this.color('primary-foreground'))
          }
        }.height(48).width('100%').borderRadius(14).margin({ top: 8 }).backgroundColor(this.color('primary'))
          .enabled(!this.connecting && (this.direct ? this.environmentUrl.trim().length > 0 && this.pairingToken.trim().length > 0 : this.hostname.trim().length > 0))
          .onClick(() => { this.actions()?.connect(); })
      }.width('100%').padding(16).alignItems(HorizontalAlign.Start).borderRadius(24).backgroundColor(this.color('card'))
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    Column({ space: 8 }) {
      ChatGlass({ capsule: true, radius: 26 }) { this.environmentHeader() }
      Scroll() {
        Column({ space: 16 }) {
          if (this.environmentFormOpen) { this.environmentForm() }
          else { this.environmentList() }
          if (this.status && (this.connectionState === 'failed' || this.connecting)) {
            Text(this.status).fontSize(this.font(13))
              .fontColor(this.connectionState === 'failed' ? this.color('danger-foreground') : this.color('foreground-muted'))
              .width('100%')
          }
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 12, bottom: 24 })
      }.layoutWeight(1).width('100%').align(Alignment.TopStart)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    }.width('100%').layoutWeight(1)
  }
}
