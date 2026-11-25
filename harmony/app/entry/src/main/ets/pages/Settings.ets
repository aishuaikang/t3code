import { menuIcon } from './MenuIcon';
import { ChatPageHeader } from './ChatGlass';
import { AppIcon } from './AppIcon';
import { TaskNotifications } from '../connection/TaskNotifications';
import util from '@ohos.util';
import { EnvironmentSession } from '../connection/Environment';
import { AppearanceStore } from '../connection/AppearanceStore';
import { ThemeRuntime } from '../connection/ThemeRuntime';
import { ThemeSelection, THEME_IDS } from '../model/ThemeSelection';
import router from '@ohos.router';
import { TypographyRuntime } from '../connection/TypographyRuntime';
import { Typography, resolveTypography, MIN_BASE_FONT_SIZE, MAX_BASE_FONT_SIZE, MIN_CODE_FONT_SIZE, MAX_CODE_FONT_SIZE, scaledFontSize } from '../model/Typography';
import { MIN_TERMINAL_FONT_SIZE, MAX_TERMINAL_FONT_SIZE } from '../model/TerminalMetrics';

@Entry
@Component
struct SettingsPage {
  private font(size: number): number { return scaledFontSize(size, this.sizes.baseFontSize); }
  @StorageLink('themeKey') themeKey: string = 't3-code-light';
  @StorageLink('themeSelection') selection: ThemeSelection = { light: 't3-code', dark: 't3-code', mode: 'system' };
  @StorageLink('textSizes') sizes: Typography = resolveTypography(16, null, null);
  @State groupingMode: string = 'repository';
  @State ready: boolean = false;
  @State saving: boolean = false;
  @State error: string = '';
  @State section: string = 'main';
  @State notificationsEnabled: boolean = false;
  @StorageLink('taskNotificationError') notificationError: string = '';
  private active: boolean = false;

  aboutToAppear(): void { this.active = true; this.section = ((router.getParams() ?? {}) as Record<string, string>).section ?? 'main'; }
  onPageShow(): void { this.active = true; this.load(); }
  aboutToDisappear(): void { this.active = false; }
  private async load(): Promise<void> {
    this.ready = false;
    this.error = '';
    try {
      const grouping = await (await AppearanceStore.open(getContext(this))).projectGroupingMode();
      await TypographyRuntime.reload();
      const selection = await ThemeRuntime.reload();
      if (!this.active) return;
      this.groupingMode = grouping;
      this.selection = selection;
      this.notificationsEnabled = await TaskNotifications.isEnabled().catch(() => false);
      this.ready = true;
    } catch (_) { if (this.active) this.error = '设置读取失败，请重试'; }
  }
  private async saveGrouping(mode: string): Promise<void> {
    if (this.saving || !this.ready) return;
    this.saving = true;
    this.error = '';
    try {
      await (await AppearanceStore.open(getContext(this))).saveProjectGroupingMode(mode);
      if (this.active) this.groupingMode = mode;
    } catch (_) { if (this.active) this.error = '项目分组保存失败，请重试'; }
    finally { if (this.active) this.saving = false; }
  }
  private async saveFont(kind: string, value: number | null): Promise<void> {
    if (this.saving || !this.ready) return;
    this.saving = true;
    this.error = '';
    try {
      if (kind === 'base') await TypographyRuntime.saveBase(value ?? 16);
      else if (kind === 'code') await TypographyRuntime.saveCode(value);
      else await TypographyRuntime.saveTerminal(value);
    } catch (_) { if (this.active) this.error = '字号保存失败，请重试'; }
    finally { if (this.active) this.saving = false; }
  }
  private async toggleWordBreak(): Promise<void> {
    if (this.saving || !this.ready) return;
    this.saving = true;
    this.error = '';
    try { await TypographyRuntime.saveWordBreak(!this.sizes.codeWordBreak); }
    catch (_) { if (this.active) this.error = '代码换行设置保存失败，请重试'; }
    finally { if (this.active) this.saving = false; }
  }
  private async saveTheme(mode: string, light: string, dark: string): Promise<void> {
    if (this.saving || !this.ready) return;
    this.saving = true;
    this.error = '';
    const selection: ThemeSelection = { mode, light, dark };
    try {
      await ThemeRuntime.save(selection);
      if (this.active) this.selection = selection;
    } catch (_) { if (this.active) this.error = '主题保存失败，请重试'; }
    finally { if (this.active) this.saving = false; }
  }
  private color(role: string): string { return ThemeRuntime.color(this.themeKey, role); }
  private openSection(target: string): void {
    if (target === 'connections') {
      router.pushUrl({ url: 'pages/Environments' });
    } else if (target === 'archive') {
      router.back({ url: 'pages/Index', params: { homeRequest: util.generateRandomUUID(true), view: target,
        environmentId: EnvironmentSession.current?.descriptor.environmentId ?? '' } });
    } else router.pushUrl({ url: 'pages/Settings', params: { section: target } });
  }
  private async toggleNotifications(enabled: boolean): Promise<void> {
    if (this.saving) return;
    this.saving = true; this.error = '';
    try { await TaskNotifications.setEnabled(enabled); this.notificationsEnabled = await TaskNotifications.isEnabled(); }
    catch (error) { this.error = error instanceof Error ? error.message : String(error); }
    finally { this.saving = false; }
  }
  @Builder
  private sectionLabel(label: string) {
    Text(label).fontSize(this.font(12)).fontWeight(FontWeight.Medium).fontColor(this.color('foreground-muted'))
      .width('100%').padding({ left: 4, top: 12, bottom: 4 })
  }
  @Builder
  private settingsRow(icon: string, label: string, value: string, target: string) {
    Row({ space: 12 }) {
      AppIcon({ name: icon, iconSize: 20, tint: this.color('foreground-secondary') })
      Text(label).fontSize(this.font(15)).fontColor(this.color('foreground')).layoutWeight(1)
      if (value) { Text(target === 'notifications' ? (this.notificationsEnabled ? '已开启' : '未开启') : target === 'appearance' ?
        (this.selection.mode === 'system' ? '跟随系统' : this.selection.mode === 'dark' ? '深色' : '浅色') : target === 'grouping' ?
        (this.groupingMode === 'separate' ? '保持独立' : this.groupingMode === 'repository_path' ? '按路径' : '按仓库') : value)
        .fontSize(this.font(12)).fontColor(this.color('foreground-muted')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: '40%' }) }
      AppIcon({ name: 'chevron', iconSize: 15, tint: this.color('foreground-muted') })
    }.height(54).padding({ left: 14, right: 14 }).width('100%').backgroundColor(this.color('card')).borderRadius(12)
      .onClick(() => { this.openSection(target); }).accessibilityText(label)
  }
  @Builder
  private themePicker(dark: boolean) {
    Row({ space: 12 }) {
      Text(dark ? '深色主题' : '浅色主题').fontSize(this.font(14)).fontColor(this.color('foreground')).layoutWeight(1)
      Select([
        { value: 'T3 Code', symbolIcon: menuIcon($r('sys.symbol.code')) },
        { value: 'T3 Chat', symbolIcon: menuIcon($r('sys.symbol.message')) },
        { value: 'Grove', symbolIcon: menuIcon($r('sys.symbol.leaf')) },
        { value: 'Ocean', symbolIcon: menuIcon($r('sys.symbol.water_waves')) },
        { value: 'Ember', symbolIcon: menuIcon($r('sys.symbol.flame')) },
        { value: 'Iris', symbolIcon: menuIcon($r('sys.symbol.flower')) }
      ])
        .height(36).font({ size: this.font(13) }).optionFont({ size: this.font(16) }).selectedOptionFont({ size: this.font(13) })
        .selected(THEME_IDS.indexOf(dark ? this.selection.dark : this.selection.light))
        .value(ThemeRuntime.palette(`${dark ? this.selection.dark : this.selection.light}-${dark ? 'dark' : 'light'}`).label)
        .fontColor(this.color('foreground')).backgroundColor(Color.Transparent).enabled(this.ready && !this.saving)
        .onSelect((index: number) => { this.saveTheme(this.selection.mode, dark ? this.selection.light : THEME_IDS[index], dark ? THEME_IDS[index] : this.selection.dark); })
    }.height(50).padding({ left: 14, right: 10 }).width('100%')
  }
  @Builder
  private fontControl(kind: string, label: string, value: () => number, min: number, max: number, step: number, custom: () => boolean) {
    Row({ space: 8 }) {
      Column({ space: 3 }) {
        Text(label).fontSize(this.font(14)).fontColor(this.color('foreground'))
        Text(`${value()}${kind !== 'base' && !custom() ? ' · 自动' : ''}`).fontSize(this.font(12)).fontColor(this.color('foreground-muted'))
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Button({ type: ButtonType.Circle }) { AppIcon({ name: 'minus', iconSize: 17, tint: this.color('foreground-secondary') }) }
        .width(36).height(36).padding(0).backgroundColor(this.color('input')).accessibilityText(`减小${label}`).enabled(this.ready && !this.saving && value() > min)
        .onClick(() => { this.saveFont(kind, Math.max(min, value() - step)); })
      Button({ type: ButtonType.Circle }) { AppIcon({ name: 'plus', iconSize: 17, tint: this.color('foreground-secondary') }) }
        .width(36).height(36).padding(0).backgroundColor(this.color('input')).accessibilityText(`增大${label}`).enabled(this.ready && !this.saving && value() < max)
        .onClick(() => { this.saveFont(kind, Math.min(max, value() + step)); })
      Button({ type: ButtonType.Circle }) { AppIcon({ name: 'refresh', iconSize: 16, tint: this.color('foreground-muted') }) }
        .width(36).height(36).padding(0).backgroundColor(Color.Transparent).accessibilityText(`重置${label}`).enabled(this.ready && !this.saving && (kind === 'base' ? value() !== 16 : custom()))
        .onClick(() => { this.saveFont(kind, kind === 'base' ? 16 : null); })
    }.width('100%').padding(12).backgroundColor(this.color('card')).borderRadius(12)
  }
  build() {
    Column({ space: 0 }) {
      ChatPageHeader() {
        Row({ space: 12 }) {
          Button({ type: ButtonType.Circle }) { AppIcon({ name: 'back', iconSize: 21, tint: this.color('glass-label') }) }
            .accessibilityText('返回').width(36).height(36).padding(0).backgroundColor(Color.Transparent).onClick(() => { router.back(); })
          Text(this.section === 'appearance' ? '外观' : this.section === 'grouping' ? '项目分组' : this.section === 'notifications' ? '通知' : '设置')
            .fontSize(this.font(18)).fontWeight(FontWeight.Medium).fontColor(this.color('foreground')).layoutWeight(1)
        }.padding({ left: 12, right: 16 }).width('100%')
      }
      Scroll() {
        Column({ space: 10 }) {
          if (this.section === 'main') {
            this.sectionLabel('连接')
            this.settingsRow('machine', '环境', EnvironmentSession.current?.descriptor.label ?? '', 'connections')
            this.settingsRow('bell', '通知', this.notificationsEnabled ? '已开启' : '未开启', 'notifications')
            this.sectionLabel('界面')
            this.settingsRow('palette', '外观', this.selection.mode === 'system' ? '跟随系统' : this.selection.mode === 'dark' ? '深色' : '浅色', 'appearance')
            this.sectionLabel('项目与任务')
            this.settingsRow('folder', '项目分组', this.groupingMode === 'separate' ? '保持独立' : this.groupingMode === 'repository_path' ? '按路径' : '按仓库', 'grouping')
            this.settingsRow('archive', '已归档任务', '', 'archive')
            Text('T3 Code · HarmonyOS').fontSize(this.font(12)).fontColor(this.color('foreground-muted')).width('100%').textAlign(TextAlign.Center).padding({ top: 24 })
          } else if (this.section === 'grouping') {
            this.sectionLabel('项目分组方式')
            Select([
              { value: '按仓库分组', symbolIcon: menuIcon($r('sys.symbol.folder')) },
              { value: '按仓库内路径分组', symbolIcon: menuIcon($r('sys.symbol.doc_plaintext_and_folder')) },
              { value: '保持独立', symbolIcon: menuIcon($r('sys.symbol.square_grid_2x2')) }
            ])
              .height(48).font({ size: this.font(14) }).optionFont({ size: this.font(16) }).selectedOptionFont({ size: this.font(14) })
              .selected(['repository', 'repository_path', 'separate'].indexOf(this.groupingMode))
              .value(this.groupingMode === 'separate' ? '保持独立' : this.groupingMode === 'repository_path' ? '按仓库内路径分组' : '按仓库分组')
              .fontColor(this.color('foreground')).backgroundColor(this.color('card')).borderRadius(12).width('100%').enabled(this.ready && !this.saving)
              .onSelect((index: number) => { this.saveGrouping(['repository', 'repository_path', 'separate'][index]); })
            Text('合并同一仓库的项目；按路径分组可保留子目录差异。').fontSize(this.font(12)).fontColor(this.color('foreground-muted')).width('100%')
          } else if (this.section === 'notifications') {
            this.sectionLabel('任务通知')
            Row({ space: 12 }) {
              AppIcon({ name: 'bell', iconSize: 20, tint: this.color('foreground-secondary') })
              Text('系统任务通知').fontSize(this.font(15)).fontColor(this.color('foreground')).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.notificationsEnabled }).enabled(this.ready && !this.saving)
                .onChange((value: boolean) => { if (value !== this.notificationsEnabled) this.toggleNotifications(value); })
            }.width('100%').padding(14).borderRadius(12).backgroundColor(this.color('card'))
            Text('每个任务分别提示执行、待回答、完成和失败。点击通知打开对应会话。').fontSize(this.font(13)).fontColor(this.color('foreground-muted')).width('100%')
            Text('通知依赖环境连接；应用被系统挂起或关闭时，恢复连接后同步状态。').fontSize(this.font(12)).fontColor(this.color('foreground-muted')).width('100%')
            if (this.notificationError) { Text(this.notificationError).fontSize(this.font(12)).fontColor(this.color('danger-foreground')).width('100%') }
          } else {
            this.sectionLabel('主题')
            Row({ space: 4 }) {
              ForEach(['system', 'light', 'dark'], (mode: string) => {
                Button(mode === 'system' ? '跟随系统' : mode === 'light' ? '浅色' : '深色').fontSize(this.font(13)).height(36).layoutWeight(1).borderRadius(9)
                  .fontColor(this.color(this.selection.mode === mode ? 'primary-foreground' : 'foreground'))
                  .backgroundColor(this.color(this.selection.mode === mode ? 'primary' : 'card')).enabled(this.ready && !this.saving)
                  .onClick(() => { this.saveTheme(mode, this.selection.light, this.selection.dark); })
              })
            }.padding(4).width('100%').borderRadius(12).backgroundColor(this.color('card'))
            Column({ space: 0 }) { this.themePicker(false); this.themePicker(true) }.width('100%').borderRadius(12).backgroundColor(this.color('card'))
            this.sectionLabel('文字')
            this.fontControl('base', '文字大小', () => this.sizes.baseFontSize, MIN_BASE_FONT_SIZE, MAX_BASE_FONT_SIZE, 1, () => true)
            Text('你好，T3 Code。').fontSize(this.sizes.baseFontSize).fontColor(this.color('foreground')).padding(14).width('100%').borderRadius(12).backgroundColor(this.color('card'))
            this.sectionLabel('终端')
            this.fontControl('terminal', '终端字号', () => this.sizes.terminalFontSize, MIN_TERMINAL_FONT_SIZE, MAX_TERMINAL_FONT_SIZE, 0.5, () => this.sizes.isTerminalFontSizeCustom)
            Text('echo "Hello, T3 Code"\n0123456789  ABC abc').fontFamily('monospace').fontSize(this.sizes.terminalFontSize)
              .fontColor(this.color('foreground')).padding(14).width('100%').borderRadius(12).backgroundColor(this.color('card'))
            this.sectionLabel('代码')
            this.fontControl('code', '代码字号', () => this.sizes.codeFontSize, MIN_CODE_FONT_SIZE, MAX_CODE_FONT_SIZE, 1, () => this.sizes.isCodeFontSizeCustom)
            Text('const message = "你好，T3";').fontFamily('monospace').fontSize(this.sizes.codeFontSize).fontColor(this.color('foreground'))
              .padding(14).width('100%').borderRadius(12).backgroundColor(this.color('card'))
            Row({ space: 12 }) {
              Text('代码自动换行').fontSize(this.font(14)).fontColor(this.color('foreground')).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.sizes.codeWordBreak }).enabled(this.ready && !this.saving)
                .onChange((value: boolean) => { if (value !== this.sizes.codeWordBreak) this.toggleWordBreak(); })
            }.width('100%').padding(14).borderRadius(12).backgroundColor(this.color('card'))
          }
          if (this.error) {
            Text(this.error).fontSize(this.font(13)).fontColor(this.color('danger-foreground')).width('100%')
            if (!this.ready) { Button('重新读取').onClick(() => { this.load(); }) }
          }
        }.padding({ left: 20, right: 20, bottom: 28 }).width('100%')
      }.layoutWeight(1).align(Alignment.TopStart).width('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    }.width('100%').height('100%').backgroundColor(this.color('screen'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
