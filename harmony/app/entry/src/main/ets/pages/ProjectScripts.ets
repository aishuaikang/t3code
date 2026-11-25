import util from '@ohos.util';
import { AppIcon } from './AppIcon';
import { EnvironmentSession } from '../connection/Environment';
import { EmptyPayload, RpcClient } from '../connection/Rpc';
import { ProjectScript, ProjectShell, ServerConfig } from '../model/Models';
import { WorkspaceSettings, resolveProjectScripts, projectScriptsPatch, upsertProjectScript } from '../model/WorkspaceActions';
import { ThemeRuntime } from '../connection/ThemeRuntime';
import { Typography, resolveTypography, scaledFontSize } from '../model/Typography';

interface ScriptTerminal { threadId: string; terminalId: string; cwd: string; worktreePath: string | null; env: Record<string, string>; stopOnSettle: boolean; }
interface ScriptInput { threadId: string; terminalId: string; data: string; }
interface ScriptIconChoice { id: string; label: string; icon: string; }
const SCRIPT_ICONS: ScriptIconChoice[] = [
  { id: 'play', label: '运行', icon: 'play' }, { id: 'test', label: '测试', icon: 'check' },
  { id: 'lint', label: '检查', icon: 'shield' }, { id: 'configure', label: '配置', icon: 'settings' },
  { id: 'build', label: '构建', icon: 'code' }, { id: 'debug', label: '调试', icon: 'terminal' }
];

@Component
export struct ProjectScripts {
  @StorageLink('themeKey') themeKey: string = 't3-code-light';
  @StorageLink('textSizes') sizes: Typography = resolveTypography(16, null, null);
  @Prop project: ProjectShell = { id: '', title: '', workspaceRoot: '' };
  @Prop threadId: string = '';
  @Prop worktreePath: string | null = null;
  @Prop disabled: boolean = false;
  getRpc: () => RpcClient | null = () => EnvironmentSession.current?.rpc ?? null;
  onBack: () => void = () => {};
  onTerminal: (terminalId: string) => void = () => {};
  @State scripts: ProjectScript[] = [];
  @State loading: boolean = true;
  @State busy: boolean = false;
  @State error: string = '';
  @State editing: boolean = false;
  @State editId: string = '';
  @State deleteId: string = '';
  @State name: string = '';
  @State command: string = '';
  @State icon: string = 'play';
  @State setup: boolean = false;
  @State terminalId: string = '';
  private active: boolean = false;
  private color(role: string): string { return ThemeRuntime.color(this.themeKey, role); }
  private font(size: number): number { return scaledFontSize(size, this.sizes.baseFontSize); }
  private scriptIcon(icon: string): string { return SCRIPT_ICONS.find((entry: ScriptIconChoice) => entry.id === icon)?.icon ?? 'play'; }
  aboutToAppear(): void { this.active = true; this.load(); }
  aboutToDisappear(): void { this.active = false; }

  private async load(): Promise<void> {
    const rpc = this.getRpc();
    if (rpc === null) { this.loading = false; this.error = '请先连接环境'; return; }
    this.loading = true; this.error = '';
    try {
      const settings = await rpc.call<WorkspaceSettings>('server.getSettings', new EmptyPayload());
      if (this.active && this.getRpc() === rpc) this.scripts = resolveProjectScripts(settings, this.project);
    } catch (error) { if (this.active) this.error = `读取项目脚本失败：${error instanceof Error ? error.message : String(error)}`; }
    finally { if (this.active) this.loading = false; }
  }

  private edit(script: ProjectScript | null): void {
    this.editId = script?.id ?? ''; this.name = script?.name ?? ''; this.command = script?.command ?? '';
    this.icon = script?.icon ?? 'play'; this.setup = script?.runOnWorktreeCreate ?? false;
    this.error = ''; this.deleteId = ''; this.editing = true;
  }

  private async save(remove: boolean = false): Promise<void> {
    const rpc = this.getRpc(), connection = EnvironmentSession.current;
    if (rpc === null || connection === null || this.disabled || this.busy || !this.project.id ||
      (!remove && (!this.name.trim() || !this.command.trim()))) return;
    const project = this.project;
    this.busy = true; this.error = '';
    try {
      const settings = await rpc.call<WorkspaceSettings>('server.getSettings', new EmptyPayload());
      const config = await rpc.call<ServerConfig>('server.getConfig', new EmptyPayload());
      if (!this.active || this.getRpc() !== rpc || EnvironmentSession.current !== connection || this.project.id !== project.id || this.disabled) return;
      const scripts = resolveProjectScripts(settings, project);
      let next: ProjectScript[];
      if (remove) next = scripts.filter((entry: ProjectScript) => entry.id !== this.deleteId);
      else {
        const existing = scripts.find((entry: ProjectScript) => entry.id === this.editId);
        if (this.editId && existing === undefined) throw new Error('此脚本已被删除，请刷新后重试');
        const script: ProjectScript = existing ? JSON.parse(JSON.stringify(existing)) as ProjectScript :
          { id: util.generateRandomUUID(true), name: '', command: '', icon: 'play', runOnWorktreeCreate: false };
        script.name = this.name.trim(); script.command = this.command.trim(); script.icon = this.icon; script.runOnWorktreeCreate = this.setup;
        next = upsertProjectScript(scripts, script);
      }
      await rpc.call('server.updateSettings', projectScriptsPatch(settings, project.id, next, config.environment.capabilities.projectSettingsOverrides === true));
      if (!this.active || this.getRpc() !== rpc || EnvironmentSession.current !== connection) return;
      this.scripts = next; this.editing = false; this.deleteId = '';
    } catch (error) { if (this.active) this.error = `保存脚本失败：${error instanceof Error ? error.message : String(error)}`; }
    finally { if (this.active) this.busy = false; }
  }

  private async run(script: ProjectScript): Promise<void> {
    const rpc = this.getRpc(), connection = EnvironmentSession.current;
    if (rpc === null || connection === null || this.disabled || this.busy || !this.threadId) return;
    const threadId = this.threadId;
    const terminalId = `script-${util.generateRandomUUID(true)}`;
    this.busy = true; this.error = ''; this.terminalId = '';
    try {
      const env: Record<string, string> = {};
      env['T3CODE_PROJECT_ROOT'] = this.project.workspaceRoot;
      if (this.worktreePath) env['T3CODE_WORKTREE_PATH'] = this.worktreePath;
      const input: ScriptTerminal = { threadId: threadId, terminalId: terminalId, cwd: this.project.workspaceRoot,
        worktreePath: this.worktreePath, env: env, stopOnSettle: script.stopOnSettle === true };
      await rpc.call('terminal.open', input);
      if (!this.active || this.getRpc() !== rpc || EnvironmentSession.current !== connection || this.disabled) return;
      this.terminalId = terminalId;
      const write: ScriptInput = { threadId: threadId, terminalId: terminalId, data: ` ${script.command}\r` };
      await rpc.call('terminal.write', write);
      if (this.active && this.getRpc() === rpc && EnvironmentSession.current === connection) this.onTerminal(terminalId);
    } catch (error) {
      if (this.active) this.error = `${this.terminalId ? '运行状态未确认，请先查看终端，避免重复运行' : '运行脚本失败'}：${error instanceof Error ? error.message : String(error)}`;
    } finally { if (this.active) this.busy = false; }
  }

  build() {
    Column({ space: 14 }) {
      Row({ space: 10 }) {
        Button({ type: ButtonType.Circle }) { AppIcon({ name: 'back', iconSize: 20, tint: this.color('foreground') }) }
          .width(36).height(36).padding(0).backgroundColor(Color.Transparent).enabled(!this.busy).accessibilityText('返回')
          .onClick(() => { if (this.editing) this.editing = false; else this.onBack(); })
        Text(this.editing ? this.editId ? '编辑项目脚本' : '添加项目脚本' : '项目脚本').fontSize(this.font(17)).fontColor(this.color('foreground')).layoutWeight(1)
        if (!this.editing) {
          Button({ type: ButtonType.Circle }) { AppIcon({ name: 'plus', iconSize: 22, tint: this.color('foreground') }) }
            .width(36).height(36).padding(0).backgroundColor(Color.Transparent).enabled(!this.loading && !this.busy && !this.disabled)
            .accessibilityText('添加项目脚本').onClick(() => { this.edit(null); })
        }
      }.width('100%')
      if (this.error) { Text(this.error).fontSize(this.font(13)).fontColor(this.color('danger-foreground')).width('100%') }
      if (this.terminalId && this.error) { Button('查看终端').enabled(!this.busy).onClick(() => { this.onTerminal(this.terminalId); }) }
      if (this.editing) {
        Scroll() {
          Column({ space: 14 }) {
            TextInput({ text: this.name, placeholder: '脚本名称，例如：启动开发服务' }).fontColor(this.color('foreground')).backgroundColor(this.color('input'))
              .enabled(!this.busy).onChange((value: string) => { this.name = value; })
            TextArea({ text: this.command, placeholder: '要执行的命令，例如：pnpm dev' }).height(140).fontColor(this.color('foreground')).backgroundColor(this.color('input'))
              .fontFamily('monospace').enabled(!this.busy).onChange((value: string) => { this.command = value; })
            Row({ space: 8 }) {
              ForEach(SCRIPT_ICONS, (entry: ScriptIconChoice) => {
                Button({ type: ButtonType.Circle }) { AppIcon({ name: entry.icon, iconSize: 20, tint: this.color(this.icon === entry.id ? 'primary' : 'foreground-muted') }) }
                  .width(40).height(40).padding(0).backgroundColor(this.icon === entry.id ? this.color('card') : Color.Transparent)
                  .enabled(!this.busy).accessibilityText(entry.label).onClick(() => { this.icon = entry.id; })
              }, (entry: ScriptIconChoice) => entry.id)
            }.width('100%')
            Row() {
              Checkbox().select(this.setup).enabled(!this.busy).onChange((value: boolean) => { this.setup = value; })
              Text('创建工作树时运行').fontSize(this.font(14)).fontColor(this.color('foreground')).layoutWeight(1)
            }.width('100%')
            Text('保存后会同步到 PC；运行时使用当前会话的工作目录。').fontSize(this.font(12)).fontColor(this.color('foreground-muted')).width('100%')
            Button(this.busy ? '正在保存…' : '保存').width('100%').height(44).backgroundColor(this.color('primary')).fontColor(this.color('primary-foreground'))
              .enabled(!this.busy && !this.disabled && !!this.name.trim() && !!this.command.trim()).onClick(() => { this.save(); })
          }.width('100%')
        }.layoutWeight(1).width('100%')
      } else if (this.loading) { LoadingProgress().width(32).height(32) }
      else {
        List({ space: 8 }) {
          ForEach(this.scripts, (script: ProjectScript) => {
            ListItem() {
              Column({ space: 8 }) {
                Row({ space: 10 }) {
                  AppIcon({ name: this.scriptIcon(script.icon), iconSize: 22, tint: this.color('foreground-secondary') })
                  Column({ space: 4 }) {
                    Text(script.name).fontSize(this.font(15)).fontColor(this.color('foreground')).width('100%')
                    Text(script.command).fontSize(this.font(12)).fontFamily('monospace').fontColor(this.color('foreground-muted')).maxLines(2).width('100%')
                  }.layoutWeight(1)
                  Button({ type: ButtonType.Circle }) { AppIcon({ name: 'play', iconSize: 19, tint: this.color('primary') }) }
                    .width(36).height(36).padding(0).backgroundColor(Color.Transparent).enabled(!this.busy && !this.disabled && !!this.threadId)
                    .accessibilityText(`运行 ${script.name}`).onClick(() => { this.run(script); })
                  Button({ type: ButtonType.Circle }) { AppIcon({ name: 'edit', iconSize: 18, tint: this.color('foreground-muted') }) }
                    .width(32).height(36).padding(0).backgroundColor(Color.Transparent).enabled(!this.busy && !this.disabled)
                    .accessibilityText(`编辑 ${script.name}`).onClick(() => { this.edit(script); })
                  Button({ type: ButtonType.Circle }) { AppIcon({ name: 'trash', iconSize: 18, tint: this.color('foreground-muted') }) }
                    .width(32).height(36).padding(0).backgroundColor(Color.Transparent).enabled(!this.busy && !this.disabled)
                    .accessibilityText(`删除 ${script.name}`).onClick(() => { this.deleteId = script.id; })
                }.width('100%')
                if (this.deleteId === script.id) {
                  Row({ space: 12 }) {
                    Text('删除此脚本？').fontSize(this.font(13)).fontColor(this.color('foreground')).layoutWeight(1)
                    Button('取消').enabled(!this.busy).onClick(() => { this.deleteId = ''; })
                    Button('删除').fontColor(this.color('danger-foreground')).enabled(!this.busy && !this.disabled).onClick(() => { this.save(true); })
                  }.width('100%')
                }
              }.padding(14).width('100%').backgroundColor(this.color('card')).borderRadius(16)
            }
          }, (script: ProjectScript) => script.id)
          if (this.scripts.length === 0) {
            ListItem() { Text('暂无项目脚本，点击 + 添加。').fontColor(this.color('foreground-muted')).fontSize(this.font(14)).padding(20) }
          }
          if (this.error) { ListItem() { Button('重新读取').enabled(!this.busy).onClick(() => { this.load(); }) } }
        }.layoutWeight(1).width('100%')
      }
    }.width('100%').height('100%')
  }
}
