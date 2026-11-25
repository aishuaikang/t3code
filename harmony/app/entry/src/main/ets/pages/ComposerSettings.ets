import { immersiveMaterial } from './ChatGlass';
import { ProviderIcon } from './ProviderIcon';
import { AppIcon } from './AppIcon';
import { ModelChoice, ModelSelection, ModelOptionDescriptor, ModelOptionChoice } from '../model/Models';
import { modelOptionChoices, modelOptionValue, withModelOption, reasoningOption, fastModeOption, fastModeEnabled, ultracodeOption, ultracodeEnabled } from '../model/ModelOptions';
import { ThemeRuntime } from '../connection/ThemeRuntime';
import { Typography, resolveTypography, scaledFontSize } from '../model/Typography';

interface PermissionItem { value: string; label: string; detail: string; icon: string; }

@Component
export struct ComposerSettings {
  @Prop iconOnly: boolean = false;
  @StorageLink('themeKey') themeKey: string = 't3-code-light';
  @StorageLink('textSizes') sizes: Typography = resolveTypography(16, null, null);
  @Prop models: ModelChoice[] = [];
  @Prop selection: ModelSelection | null = null;
  @Prop runtimeMode: string = 'full-access';
  @Prop interactionMode: string = 'default';
  @Prop disabled: boolean = false;
  @Prop saving: boolean = false;
  @Prop statusMessage: string = '';
  @Prop error: string = '';
  @Prop @Watch('requestModelPicker') modelPickerRequest: number = 0;
  onModel: (selection: ModelSelection) => void = () => {};
  onOptions: (selection: ModelSelection) => void = () => {};
  onMode: (kind: string, value: string) => void = () => {};
  @State sheetOpen: boolean = false;
  @State picker: string = 'model';
  @State query: string = '';
  @State activeProviderId: string = '';
  @State reasoningOpen: boolean = false;
  private permissions: PermissionItem[] = [
    { value: 'approval-required', label: '请求批准', detail: '受限操作执行前向你请求批准', icon: 'lock' },
    { value: 'auto-accept-edits', label: '自动接受编辑', detail: '自动接受文件编辑，其他受限操作仍需批准', icon: 'edit' },
    { value: 'auto', label: '自动判断', detail: '由支持的提供方判断哪些操作需要批准', icon: 'shield' },
    { value: 'full-access', label: '完全访问权限', detail: '允许执行命令和编辑文件，无需逐次批准', icon: 'shield-off' }
  ];
  private color(role: string): string { return ThemeRuntime.color(this.themeKey, role); }
  private font(size: number): number { return scaledFontSize(size, this.sizes.baseFontSize); }
  private model(): ModelChoice | undefined {
    return this.models.find((entry: ModelChoice) => entry.instanceId === this.selection?.instanceId && entry.model === this.selection?.model);
  }
  private selectedModel(entry: ModelChoice): boolean { return entry.instanceId === this.selection?.instanceId && entry.model === this.selection?.model; }
  private permission(): PermissionItem | undefined { return this.permissions.find((entry: PermissionItem) => entry.value === this.runtimeMode); }
  private permissionTint(normal: string = 'foreground-muted'): string { return this.color(this.runtimeMode === 'full-access' ? 'danger-foreground' : normal); }
  private descriptors(): ModelOptionDescriptor[] { return this.model()?.optionDescriptors ?? []; }
  private reasoning(): ModelOptionDescriptor | undefined { return reasoningOption(this.descriptors()); }
  private fastMode(): ModelOptionDescriptor | undefined { return fastModeOption(this.descriptors()); }
  private speedChoices(): ModelOptionChoice[] {
    const descriptor = this.fastMode();
    if (descriptor === undefined) return [];
    return descriptor.type === 'boolean' ? [{ id: 'false', label: '标准' }, { id: 'true', label: 'Fast' }] :
      modelOptionChoices(descriptor).map((choice: ModelOptionChoice): ModelOptionChoice => ({ id: choice.id, label: choice.id === 'priority' ? 'Fast' : '标准' }));
  }
  private speedValue(choice: ModelOptionChoice): string | boolean { return this.fastMode()?.type === 'boolean' ? choice.id === 'true' : choice.id; }
  private speedSelected(choice: ModelOptionChoice): boolean {
    const descriptor = this.fastMode();
    if (!descriptor || !this.selection) return false;
    const value = modelOptionValue(this.selection, descriptor);
    return (value === '' ? 'default' : value) === this.speedValue(choice);
  }
  private fastEnabled(): boolean {
    return fastModeEnabled(this.selection, this.descriptors());
  }
  private ultracode(): ModelOptionDescriptor | undefined { return ultracodeOption(this.descriptors()); }
  private workflowEnabled(): boolean { return ultracodeEnabled(this.selection, this.descriptors()); }
  private extraOptions(): ModelOptionDescriptor[] { return this.descriptors().filter((entry: ModelOptionDescriptor) => entry !== this.reasoning() && entry !== this.fastMode() && entry !== this.ultracode()); }
  private optionLabel(descriptor: ModelOptionDescriptor): string {
    if (this.selection === null) return '';
    const value = modelOptionValue(this.selection, descriptor), choice = modelOptionChoices(descriptor).find((entry: ModelOptionChoice) => entry.id === value);
    return choice ? choice.label : typeof value === 'boolean' ? value ? '开启' : '关闭' : value;
  }
  private quickOptionsLabel(): string {
    const effort = this.reasoning();
    return effort ? this.optionLabel(effort) || effort.label : this.fastEnabled() ? 'Fast' : '标准';
  }
  private providers(): ModelChoice[] {
    const result: ModelChoice[] = [];
    for (const entry of this.models) if (!result.some((provider: ModelChoice) => provider.instanceId === entry.instanceId)) result.push(entry);
    return result;
  }
  private matches(instanceId: string): ModelChoice[] {
    return this.models.filter((entry: ModelChoice) => entry.instanceId === instanceId &&
      `${entry.label} ${entry.model} ${entry.providerLabel ?? ''} ${entry.instanceId}`.toLowerCase().includes(this.query.trim().toLowerCase()));
  }
  private activeProvider(): string {
    if (this.models.some((entry: ModelChoice) => entry.instanceId === this.activeProviderId)) return this.activeProviderId;
    return this.models.find((entry: ModelChoice) => entry.instanceId === this.selection?.instanceId)?.instanceId ?? this.models[0]?.instanceId ?? '';
  }
  private browseProvider(instanceId: string): void {
    if (!this.models.some((entry: ModelChoice) => entry.instanceId === instanceId)) return;
    this.activeProviderId = instanceId; this.query = '';
  }
  private open(picker: string): void {
    this.reasoningOpen = false; this.picker = picker; this.query = '';
    this.activeProviderId = this.selection?.instanceId ?? ''; this.sheetOpen = true;
  }
  private requestModelPicker(): void { if (!this.disabled) this.open('model'); }
  private changeOption(descriptor: ModelOptionDescriptor | undefined, value: string | boolean | null): void {
    if (this.selection === null || descriptor === undefined || this.disabled) return;
    const next = withModelOption(this.selection, descriptor, value);
    if (next !== null) this.onOptions(next);
  }
  @Builder
  private speedPicker() {
    Row({ space: 2 }) {
      ForEach(this.speedChoices(), (choice: ModelOptionChoice) => {
        Button({ type: ButtonType.Normal }) {
          Row({ space: 5 }) {
            if (choice.id === 'true' || choice.id === 'priority') { AppIcon({ name: 'bolt', iconSize: 15, tint: this.color(this.speedSelected(choice) ? 'foreground' : 'foreground-muted') }) }
            Text(choice.label).fontSize(this.font(12)).fontWeight(this.speedSelected(choice) ? FontWeight.Medium : FontWeight.Regular).fontColor(this.color(this.speedSelected(choice) ? 'foreground' : 'foreground-secondary'))
            if (this.speedSelected(choice)) { AppIcon({ name: 'check', iconSize: 14, tint: this.color('foreground') }) }
          }
        }.height(36).padding({ left: 10, right: 10 }).borderRadius(9)
          .backgroundColor(this.speedSelected(choice) ? this.color('subtle-strong') : Color.Transparent)
          .enabled(!this.disabled).onClick(() => { this.changeOption(this.fastMode(), this.speedValue(choice)); })
          .accessibilityText(`运行速度 ${choice.label}${this.speedSelected(choice) ? '，已选择' : ''}`)
      }, (choice: ModelOptionChoice) => choice.id)
    }.padding(3).backgroundColor(this.color('input')).borderRadius(12).flexShrink(0)
  }
  @Builder
  private reasoningChoices(effort: ModelOptionDescriptor) {
    Row() {
      Text('推理强度').fontSize(this.font(13)).fontColor(this.color('foreground-muted')).layoutWeight(1)
      Text(this.model()?.label.split(' · ').slice(-1)[0] ?? '').fontSize(this.font(12)).fontColor(this.color('foreground-muted')).maxLines(1).constraintSize({ maxWidth: 140 }).textOverflow({ overflow: TextOverflow.Ellipsis })
    }.width('100%').padding({ left: 10, right: 10, top: 6, bottom: 10 })
    ForEach(modelOptionChoices(effort), (choice: ModelOptionChoice) => {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 8 }) {
          AppIcon({ name: 'thinking', iconSize: 16, tint: this.color('foreground-muted') })
          Text(choice.label).fontSize(this.font(15)).fontColor(this.color('foreground')).layoutWeight(1)
          if (choice.isDefault) { Text('默认').fontSize(this.font(11)).fontColor(this.color('foreground-muted')) }
          if (this.selection !== null && modelOptionValue(this.selection, effort) === choice.id) { AppIcon({ name: 'check', iconSize: 18, tint: this.color('primary') }) }
          else { Blank().width(18) }
        }.width('100%')
      }.width('100%').height(42).padding({ left: 10, right: 10 }).borderRadius(10)
        .backgroundColor(this.selection !== null && modelOptionValue(this.selection, effort) === choice.id ? this.color('subtle-strong') : Color.Transparent)
        .enabled(!this.disabled).accessibilityText(`推理强度 ${choice.label}`).onClick(() => { this.changeOption(effort, choice.id); this.reasoningOpen = false; })
    }, (choice: ModelOptionChoice) => choice.id)
    Button({ type: ButtonType.Normal }) {
      Row({ space: 6 }) {
        AppIcon({ name: 'refresh', iconSize: 14, tint: this.color('foreground-muted') })
        Text('恢复默认强度').fontSize(this.font(12)).fontColor(this.color('foreground-muted'))
      }
    }.backgroundColor(Color.Transparent).height(36).width('100%').accessibilityText('恢复默认强度')
      .enabled(!this.disabled).onClick(() => { this.changeOption(effort, null); this.reasoningOpen = false; })
  }
  @Builder
  private quickOptionsPopup() {
    Scroll() {
      Column({ space: 4 }) {
        if (this.fastMode() !== undefined) {
          Row({ space: 8 }) {
            Text('运行速度').fontSize(this.font(13)).fontColor(this.color('foreground-muted')).layoutWeight(1)
            this.speedPicker()
          }.width('100%').padding({ left: 10, right: 4 })
          if (this.reasoning() !== undefined) { Divider().color(this.color('border')) }
        }
        if (this.reasoning() !== undefined) { this.reasoningChoices(this.reasoning()!) }
      }.width('100%').padding(10)
    }.width(280).scrollBar(BarState.Auto)
  }
  @Builder
  private optionChoices(descriptor: ModelOptionDescriptor) {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(modelOptionChoices(descriptor), (choice: ModelOptionChoice) => {
        Button({ type: ButtonType.Normal }) {
          Row({ space: 5 }) {
            Text(choice.label).fontSize(this.font(13)).fontColor(this.selection !== null && modelOptionValue(this.selection, descriptor) === choice.id ? this.color('primary') : this.color('foreground-secondary'))
            if (choice.isDefault) { Text('默认').fontSize(this.font(10)).fontColor(this.color('foreground-muted')) }
            if (this.selection !== null && modelOptionValue(this.selection, descriptor) === choice.id) { AppIcon({ name: 'check', iconSize: 14, tint: this.color('primary') }) }
          }
        }.constraintSize({ minHeight: 38 }).padding({ left: 12, right: 12, top: 8, bottom: 8 }).borderRadius(10).margin({ right: 6, bottom: 6 })
          .backgroundColor(this.selection !== null && modelOptionValue(this.selection, descriptor) === choice.id ? this.color('subtle-strong') : this.color('input'))
          .enabled(!this.disabled).onClick(() => { this.changeOption(descriptor, choice.id); }).accessibilityText(`${descriptor.label} ${choice.label}`)
      }, (choice: ModelOptionChoice) => choice.id)
    }.width('100%')
  }
  @Builder
  private permissionsSheet() {
    List({ space: 4 }) {
      ListItem() { Text('选择代理执行操作时的批准方式').fontSize(this.font(13)).fontColor(this.color('foreground-muted')).padding({ left: 12, right: 12, bottom: 10 }).width('100%') }
      ForEach(this.permissions, (entry: PermissionItem) => {
        ListItem() {
          Button({ type: ButtonType.Normal }) {
            Row({ space: 14 }) {
              AppIcon({ name: entry.icon, iconSize: 22, tint: entry.value === 'full-access' ? this.color('danger-foreground') : this.color('foreground-secondary') })
              Column({ space: 5 }) {
                Text(entry.label).fontColor(entry.value === 'full-access' ? this.color('danger-foreground') : this.color('foreground')).fontSize(this.font(16)).fontWeight(FontWeight.Medium).width('100%')
                Text(entry.detail).fontColor(this.color('foreground-muted')).fontSize(this.font(12)).lineHeight(this.font(18)).width('100%')
              }.layoutWeight(1)
              if (this.runtimeMode === entry.value) { AppIcon({ name: 'check', iconSize: 20, tint: this.color('primary') }) }
              else { Blank().width(20) }
            }.width('100%').alignItems(VerticalAlign.Center)
          }.width('100%').padding(14).borderRadius(14).backgroundColor(this.runtimeMode === entry.value ? this.color('subtle-strong') : Color.Transparent)
            .enabled(!this.disabled).onClick(() => { this.sheetOpen = false; if (this.runtimeMode !== entry.value) this.onMode('runtime', entry.value); })
            .accessibilityText(`${entry.label}，${entry.detail}${this.runtimeMode === entry.value ? '，已选择' : ''}`)
        }
      }, (entry: PermissionItem) => entry.value)
    }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
  }
  @Builder
  private modelSheet() {
    Scroll() {
      Row({ space: 6 }) {
        ForEach(this.providers(), (provider: ModelChoice) => {
          Button({ type: ButtonType.Normal }) {
            Row({ space: 7 }) {
              ProviderIcon({ driver: provider.driver ?? '', label: provider.providerLabel ?? '', iconSize: 18 })
              Text(provider.providerLabel || provider.instanceId).fontSize(this.font(14))
                .fontWeight(this.activeProvider() === provider.instanceId ? FontWeight.Medium : FontWeight.Regular)
                .fontColor(this.color(this.activeProvider() === provider.instanceId ? 'primary' : 'foreground-muted'))
            }
          }.id(`model-provider-${provider.instanceId}`).height(40).padding({ left: 12, right: 12 }).borderRadius(12)
            .backgroundColor(this.activeProvider() === provider.instanceId ? this.color('subtle-strong') : Color.Transparent)
            .accessibilityText(`${provider.providerLabel || provider.instanceId} 标签${this.activeProvider() === provider.instanceId ? '，已选中' : ''}`)
            .onClick(() => { this.browseProvider(provider.instanceId); })
        }, (provider: ModelChoice) => provider.instanceId)
      }
    }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%').height(44).align(Alignment.Start)
    Search({ value: this.query, placeholder: '搜索当前提供方的模型' }).textFont({ size: this.font(16) })
      .fontColor(this.color('foreground')).backgroundColor(this.color('input')).onChange((value: string) => { this.query = value; })
    List({ space: 2 }) {
      ForEach(this.matches(this.activeProvider()), (entry: ModelChoice) => {
        ListItem() {
          Button({ type: ButtonType.Normal }) {
            Row({ space: 12 }) {
              ProviderIcon({ driver: entry.driver ?? '', label: entry.providerLabel ?? '', iconSize: 18 })
              Text(entry.label.split(' · ').slice(-1)[0]).fontSize(this.font(15)).fontColor(this.color('foreground')).layoutWeight(1).maxLines(2)
              if (this.selectedModel(entry)) { AppIcon({ name: 'check', iconSize: 19, tint: this.color('primary') }) }
              else { Blank().width(19) }
            }.width('100%')
          }.id(`model-choice-${entry.instanceId}-${entry.model}`).constraintSize({ minHeight: 46 }).padding({ left: 14, right: 14, top: 10, bottom: 10 }).width('100%').borderRadius(12)
            .backgroundColor(this.selectedModel(entry) ? this.color('subtle-strong') : Color.Transparent).enabled(!this.disabled)
            .onClick(() => { if (!this.selectedModel(entry)) this.onModel({ instanceId: entry.instanceId, model: entry.model }); })
            .accessibilityText(`${entry.label}${this.selectedModel(entry) ? '，已选择' : ''}`)
        }
      }, (entry: ModelChoice) => entry.instanceId + ':' + entry.model)
      if (this.matches(this.activeProvider()).length === 0) {
        ListItem() { Text(this.models.length === 0 ? '暂无可用模型，请恢复连接后重试' : '此提供方没有匹配的模型').fontSize(this.font(14)).fontColor(this.color('foreground-muted')).width('100%').textAlign(TextAlign.Center).padding(24) }
      }
    }.layoutWeight(1).width('100%').scrollBar(BarState.Auto).scrollBarWidth(2)
    if (!this.query) {
      Divider().color(this.color('border'))
      if (this.reasoning() !== undefined) {
        Row() {
          Text('推理强度').fontSize(this.font(12)).fontColor(this.color('foreground-muted')).layoutWeight(1)
          Text(this.model()?.label.split(' · ').slice(-1)[0] ?? '').fontSize(this.font(11)).fontColor(this.color('foreground-muted')).maxLines(1).constraintSize({ maxWidth: 130 }).textOverflow({ overflow: TextOverflow.Ellipsis })
          Button('恢复默认').fontSize(this.font(11)).fontColor(this.color('foreground-muted')).height(28).backgroundColor(Color.Transparent)
            .enabled(!this.disabled).onClick(() => { this.changeOption(this.reasoning()!, null); })
        }.width('100%')
        this.optionChoices(this.reasoning()!)
      }
      ForEach(this.extraOptions(), (descriptor: ModelOptionDescriptor) => {
        Button({ type: ButtonType.Normal }) {
          Row({ space: 10 }) {
            Text(descriptor.label).fontSize(this.font(14)).fontColor(this.color('foreground')).layoutWeight(1)
            Text(this.optionLabel(descriptor)).fontSize(this.font(13)).fontColor(this.color('foreground-muted')).maxLines(1)
            AppIcon({ name: 'chevron', iconSize: 13, tint: this.color('foreground-muted') })
          }.width('100%')
        }.height(40).padding({ left: 8, right: 8 }).width('100%').borderRadius(10).backgroundColor(Color.Transparent)
          .enabled(!this.disabled).onClick(() => { this.picker = descriptor.id; })
      }, (descriptor: ModelOptionDescriptor) => descriptor.id)
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
        if (this.fastMode() !== undefined) {
          Row() { this.speedPicker() }.margin({ right: 8, bottom: 6 }).flexShrink(0)
        }
        if (this.ultracode() !== undefined) {
          Button({ type: ButtonType.Normal }) {
            Row({ space: 6 }) {
              AppIcon({ name: 'workflow', iconSize: 16, tint: this.color(this.workflowEnabled() ? 'primary' : 'foreground-muted') })
              Text(this.ultracode()!.label).fontSize(this.font(12)).fontColor(this.color(this.workflowEnabled() ? 'primary' : 'foreground-secondary'))
              if (this.workflowEnabled()) { AppIcon({ name: 'check', iconSize: 14, tint: this.color('primary') }) }
            }
          }.height(40).padding({ left: 12, right: 12 }).borderRadius(12).flexShrink(0).margin({ right: 8, bottom: 6 })
            .backgroundColor(this.color(this.workflowEnabled() ? 'subtle-strong' : 'input')).enabled(!this.disabled)
            .accessibilityText(`${this.ultracode()!.label}，${this.workflowEnabled() ? '已开启，点击关闭' : '已关闭，点击开启'}`)
            .onClick(() => { this.changeOption(this.ultracode()!, !this.workflowEnabled()); })
        }
        Button({ type: ButtonType.Normal }) {
          Row({ space: 6 }) {
            AppIcon({ name: this.permission()?.icon ?? 'shield', iconSize: 16, tint: this.permissionTint() })
            Text(this.permission()?.label ?? '运行权限').fontSize(this.font(12)).fontColor(this.permissionTint())
            AppIcon({ name: 'down', iconSize: 10, tint: this.color('foreground-muted') })
          }
        }.height(40).padding({ left: 8, right: 8 }).borderRadius(12).flexShrink(0).margin({ bottom: 6 }).backgroundColor(Color.Transparent).enabled(!this.disabled).onClick(() => { this.picker = 'permission'; })
      }.width('100%')
    }
  }
  @Builder
  pickerSheet() {
    Column({ space: 10 }) {
      if (this.saving || this.statusMessage) {
        Row({ space: 8 }) {
          if (this.saving) { LoadingProgress().width(16).height(16).color(this.color('foreground-muted')) }
          Text(this.saving ? '正在保存模型设置…' : this.statusMessage).fontSize(this.font(12)).fontColor(this.color('foreground-muted')).layoutWeight(1)
        }.width('100%')
      }
      if (this.error) { Text(this.error).fontSize(this.font(12)).fontColor(this.color('danger-foreground')).width('100%') }
      if (this.picker === 'model') { this.modelSheet() }
      else if (this.picker === 'permission') { this.permissionsSheet() }
      else {
        Button({ type: ButtonType.Normal }) {
          Row({ space: 6 }) { AppIcon({ name: 'back', iconSize: 16, tint: this.color('foreground-muted') }); Text('模型与选项').fontColor(this.color('foreground-secondary')).fontSize(this.font(13)) }
        }.height(36).padding(8).backgroundColor(Color.Transparent).alignSelf(ItemAlign.Start).onClick(() => { this.picker = 'model'; })
        List({ space: 16 }) {
          ForEach(this.descriptors().filter((entry: ModelOptionDescriptor) => entry.id === this.picker), (descriptor: ModelOptionDescriptor) => {
            ListItem() {
              Column({ space: 12 }) {
                Text(descriptor.label).fontSize(this.font(17)).fontWeight(FontWeight.Medium).fontColor(this.color('foreground')).width('100%')
                if (descriptor.description) { Text(descriptor.description).fontSize(this.font(13)).fontColor(this.color('foreground-muted')).width('100%') }
                if (descriptor.type === 'select') { this.optionChoices(descriptor) }
                else if (descriptor.type === 'boolean') {
                  Toggle({ type: ToggleType.Switch, isOn: this.selection !== null && modelOptionValue(this.selection, descriptor) === true }).enabled(!this.disabled)
                    .onChange((value: boolean) => { this.changeOption(descriptor, value); })
                }
                Button('恢复默认').fontSize(this.font(13)).fontColor(this.color('foreground-muted')).backgroundColor(Color.Transparent)
                  .enabled(!this.disabled).onClick(() => { this.changeOption(descriptor, null); })
              }.width('100%')
            }
          }, (entry: ModelOptionDescriptor) => entry.id)
        }.layoutWeight(1).width('100%')
      }
    }.padding({ left: 16, right: 16, top: 12, bottom: 28 }).width('100%').height('100%')
  }
  build() {
    Row({ space: 2 }) {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 5 }) {
          AppIcon({ name: 'bulb', iconSize: 18, tint: this.interactionMode === 'plan' ? this.color('primary') : this.color('glass-label') })
          if (this.interactionMode === 'plan') { Text('计划').fontSize(this.font(13)).fontColor(this.color('primary')); AppIcon({ name: 'close', iconSize: 12, tint: this.color('primary') }) }
        }
      }.height(32).padding({ left: 8, right: 8 }).borderRadius(16).backgroundColor(this.interactionMode === 'plan' ? this.color('subtle-strong') : Color.Transparent).enabled(!this.disabled)
        .accessibilityText(this.interactionMode === 'plan' ? '关闭计划模式，切换为构建' : '开启计划模式').onClick(() => { this.onMode('interaction', this.interactionMode === 'plan' ? 'default' : 'plan'); })
      Button({ type: ButtonType.Circle }) { AppIcon({ name: this.permission()?.icon ?? 'shield', iconSize: 17, tint: this.permissionTint('glass-label') }) }
        .width(32).height(32).padding(0).backgroundColor(Color.Transparent).enabled(!this.disabled)
        .accessibilityText(`运行权限 ${this.permission()?.label ?? ''}`).onClick(() => { this.open('permission'); })
      Button({ type: ButtonType.Normal }) {
        ToolbarLabel({ maxLabelWidth: 135, provider: true, driver: this.model()?.driver ?? '', providerLabel: this.model()?.providerLabel ?? '',
          label: this.iconOnly ? '' : this.model()?.label.split(' · ').slice(-1)[0] ?? this.selection?.model ?? '模型' })
      }.height(32).padding({ left: 8, right: 4 }).borderRadius(16).backgroundColor(Color.Transparent).layoutWeight(1).enabled(!this.disabled)
        .onClick(() => { this.open('model'); }).accessibilityText(`模型与任务设置 ${this.model()?.label ?? ''}`)
        .bindSheet($$this.sheetOpen, this.pickerSheet(), { systemMaterial: immersiveMaterial('popup'), height: this.picker === 'permission' ? 460 : SheetSize.LARGE,
          title: { title: this.picker === 'model' ? '模型与推理' : this.picker === 'permission' ? '运行权限' : '模型选项' },
          dragBar: true, showClose: true })
      if (this.reasoning() !== undefined || this.fastMode() !== undefined) {
        Button({ type: ButtonType.Normal }) {
          Row({ space: 4 }) {
            Text(this.quickOptionsLabel()).fontSize(this.font(13)).fontColor(this.color('glass-label')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: 64 })
            if (this.fastEnabled()) { AppIcon({ name: 'bolt', iconSize: 14, tint: this.color('glass-label') }) }
            AppIcon({ name: 'down', iconSize: 10, tint: this.color('glass-label') })
          }.alignItems(VerticalAlign.Center)
        }.height(32).padding({ left: 6, right: 8 }).borderRadius(12).backgroundColor(Color.Transparent).enabled(!this.disabled)
          .accessibilityText(`${this.reasoning() ? '推理强度' : '运行速度'} ${this.quickOptionsLabel()}${this.reasoning() && this.fastMode() ? '，运行速度 ' + (this.fastEnabled() ? 'Fast' : '标准') : ''}`).onClick(() => { this.reasoningOpen = !this.reasoningOpen; })
          .bindPopup(this.reasoningOpen, { builder: this.quickOptionsPopup(), placement: Placement.Top, enableArrow: false, keyboardAvoidMode: KeyboardAvoidMode.DEFAULT,
            systemMaterial: immersiveMaterial('popup'), radius: 18,
            onStateChange: (event: PopupStateChangeParam) => { this.reasoningOpen = event.isVisible; } })
      }
      if (this.workflowEnabled()) {
        AppIcon({ name: 'workflow', iconSize: 14, tint: this.color('glass-label') }).margin({ right: 8 }).accessibilityText('Ultracode 已开启')
      }
    }.width('100%').height(34)
  }
}

@Component
struct ToolbarLabel {
  @Prop label: string = '';
  @Prop maxLabelWidth: number = 170;
  @Prop icon: string = '';
  @Prop provider: boolean = false;
  @Prop driver: string = '';
  @Prop providerLabel: string = '';
  @Prop chevron: boolean = true;
  @StorageLink('themeKey') themeKey: string = 't3-code-light';
  @StorageLink('textSizes') sizes: Typography = resolveTypography(16, null, null);
  build() {
    Row({ space: 4 }) {
      if (this.provider) { ProviderIcon({ driver: this.driver, label: this.providerLabel, iconSize: 16 }) }
      if (this.icon) { AppIcon({ name: this.icon, iconSize: 16, tint: ThemeRuntime.color(this.themeKey, 'glass-label') }) }
      if (this.label) { Text(this.label).fontSize(scaledFontSize(13, this.sizes.baseFontSize)).fontColor(ThemeRuntime.color(this.themeKey, 'glass-label'))
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: this.maxLabelWidth })
      }
      if (this.chevron) { AppIcon({ name: 'down', iconSize: 10, tint: ThemeRuntime.color(this.themeKey, 'glass-label') }) }
    }
  }
}
