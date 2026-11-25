import { EnvironmentPanel, EnvironmentPanelActions } from './EnvironmentPanel';
import { ThemeRuntime } from '../connection/ThemeRuntime';

@Entry({ useSharedStorage: true })
@Component
struct EnvironmentsPage {
  @StorageLink('themeKey') themeKey: string = 't3-code-light';
  @LocalStorageLink('environment.environmentFormOpen') formOpen: boolean = false;
  private actions(): EnvironmentPanelActions | undefined { return this.getUIContext().getSharedLocalStorage()?.get<EnvironmentPanelActions>('environment.actions'); }

  onPageShow(): void { this.actions()?.reload(); }
  onBackPress(): boolean {
    if (!this.formOpen) return false;
    this.actions()?.back();
    return true;
  }
  build() {
    Column() { EnvironmentPanel({ routed: true }) }
      .width('100%').height('100%').padding({ left: 16, right: 16 }).backgroundColor(ThemeRuntime.color(this.themeKey, 'screen'))
  }
}
