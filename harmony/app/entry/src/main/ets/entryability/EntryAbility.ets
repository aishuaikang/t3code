import { TypographyRuntime } from '../connection/TypographyRuntime';
import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { Configuration } from '@ohos.app.ability.Configuration';
import { ThemeRuntime } from '../connection/ThemeRuntime';
import { ThreadReads } from '../connection/ThreadReads';
import { TaskNotifications } from '../connection/TaskNotifications';
import { ReconnectingRpc } from '../connection/ReconnectingRpc';
import accessibility from '@ohos.accessibility';
import util from '@ohos.util';

export default class EntryAbility extends UIAbility {
  private mainWindow: window.Window | null = null;
  private abilityForeground: boolean = false;
  private windowVisible: boolean = false;
  private windowVisibilityChanged = (visible: boolean): void => {
    this.windowVisible = visible;
    this.updateConnectionVisibility();
  };

  private updateConnectionVisibility(): void {
    // A floating video can background the ability while the T3 window remains visible.
    const foreground = this.abilityForeground || this.windowVisible;
    ReconnectingRpc.setForeground(foreground);
    AppStorage.setOrCreate('appForeground', foreground);
    hilog.info(0x0000, 'T3Connection', 'window=%{public}s ability=%{public}s', String(this.windowVisible), String(this.abilityForeground));
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'T3Code', 'ability onCreate');
    this.notificationWant(want);
  }
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void { this.notificationWant(want); }
  private notificationWant(want: Want): void {
    const values = want.parameters;
    if (typeof values?.notificationThreadId !== 'string' || typeof values?.notificationEnvironmentId !== 'string') return;
    AppStorage.setOrCreate('notificationRoute', JSON.stringify({ request: util.generateRandomUUID(true),
      threadId: values.notificationThreadId, environmentId: values.notificationEnvironmentId,
      title: typeof values.notificationTitle === 'string' ? values.notificationTitle : '任务',
      cwd: typeof values.notificationCwd === 'string' ? values.notificationCwd : '',
      projectTitle: typeof values.notificationProject === 'string' ? values.notificationProject : '' }));
  }

  onDestroy(): void {
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.mainWindow = windowStage.getMainWindowSync();
    this.windowVisible = this.mainWindow.isWindowShowing();
    this.mainWindow.on('windowVisibilityChange', this.windowVisibilityChanged);
    this.updateConnectionVisibility();
    this.loadWindow(windowStage);
  }

  onConfigurationUpdate(configuration: Configuration): void {
    ThemeRuntime.configurationChanged(configuration.colorMode);
  }

  private async loadWindow(windowStage: window.WindowStage): Promise<void> {
    await ThemeRuntime.initialize(this.context);
    await TypographyRuntime.initialize(this.context);
    try { await ThreadReads.initialize(this.context.filesDir); }
    catch (_) { AppStorage.SetOrCreate('threadReadError', '已读记录读取失败，请重新打开应用重试'); }
    try { await TaskNotifications.initialize(this.context); } catch (_) {}
    windowStage.loadContent('pages/Index', new LocalStorage(), (error) => {
      if (error.code !== 0) {
        hilog.error(0x0000, 'T3Code', 'loadContent failed: %{public}s', JSON.stringify(error));
        return;
      }
      ThemeRuntime.attachWindow(windowStage.getMainWindowSync());
      TaskNotifications.requestOnce().catch(() => {});
    });
  }

  onWindowStageDestroy(): void {
    try { this.mainWindow?.off('windowVisibilityChange', this.windowVisibilityChanged); } catch (_) {}
    this.mainWindow = null;
    this.windowVisible = false;
    this.abilityForeground = false;
    this.updateConnectionVisibility();
    ThemeRuntime.detachWindow();
  }

  onForeground(): void {
    this.abilityForeground = true;
    this.updateConnectionVisibility();
    try {
      AppStorage.setOrCreate('reduceMotion', typeof accessibility.isAnimationReduceEnabledSync === 'function' && accessibility.isAnimationReduceEnabledSync());
    } catch (_) { AppStorage.setOrCreate('reduceMotion', false); }
  }

  onBackground(): void {
    this.abilityForeground = false;
    this.updateConnectionVisibility();
  }
}
