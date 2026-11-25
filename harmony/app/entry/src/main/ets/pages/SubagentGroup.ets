import { ProviderInfo, SubagentSummary, WorkflowAgent, subagentActive, subagentElapsed, subagentTitle, subagentPreview } from '../model/Models';
import { statusColor, statusLabel } from '../model/StatusVisuals';
import { Typography, resolveTypography, scaledFontSize } from '../model/Typography';
import { ThemeRuntime } from '../connection/ThemeRuntime';
import { AppIcon } from './AppIcon';
import { immersiveMaterial } from './ChatGlass';
import { ProviderIcon } from './ProviderIcon';
import { subagentModelLabel } from '../model/ModelOptions';

@Component
export struct SubagentGroup {
  @Prop @Watch('updateClock') agents: SubagentSummary[] = [];
  @Prop providers: ProviderInfo[] = [];
  @Prop listOnly: boolean = false;
  @Prop groupId: string = '';
  @Prop expanded: boolean = false;
  @Prop disabled: boolean = false;
  @StorageLink('themeKey') themeKey: string = 't3-code-light';
  @StorageLink('textSizes') sizes: Typography = resolveTypography(16, null, null);
  @StorageLink('appForeground') @Watch('updateClock') foreground: boolean = true;
  @State now: number = Date.now();
  onToggle: () => void = () => {};
  onOpen: (agent: SubagentSummary) => void = () => {};
  private timer: number = -1;
  private mounted: boolean = false;
  private visible: boolean = true;

  aboutToAppear(): void { this.mounted = true; this.updateClock(); }
  aboutToDisappear(): void { this.mounted = false; this.stopClock(); }
  private stopClock(): void { if (this.timer !== -1) clearInterval(this.timer); this.timer = -1; }
  private updateClock(): void {
    this.stopClock(); this.now = Date.now();
    if (this.mounted && this.visible && this.foreground && this.liveCount() > 0) this.timer = setInterval(() => { this.now = Date.now(); }, 1000);
  }
  private color(role: string): string { return ThemeRuntime.color(this.themeKey, role); }
  private font(size: number): number { return scaledFontSize(size, this.sizes.baseFontSize); }
  private liveCount(): number { return this.agents.filter((agent: SubagentSummary) => subagentActive(agent.status)).length; }
  private summary(): string {
    const live = this.liveCount();
    const completed = this.agents.filter((agent: SubagentSummary) => agent.status === 'completed').length;
    const failed = this.agents.filter((agent: SubagentSummary) => agent.status === 'failed').length;
    const stopped = this.agents.filter((agent: SubagentSummary) => ['cancelled', 'interrupted'].includes(agent.status)).length;
    return [live > 0 ? `${live} 个进行中` : '', completed > 0 ? `${completed} 个已完成` : '',
      failed > 0 ? `${failed} 个异常` : '', stopped > 0 ? `${stopped} 个已停止` : ''].filter((part: string) => !!part).join(' · ') || '未开始';
  }

  private label(status: string): string {
    return status === 'pending' ? '等待开始' : status === 'cancelled' ? '已取消' : status === 'idle' ? '空闲' : status === 'failed' ? '失败' : statusLabel(status);
  }
  private tint(status: string): string { return statusColor(status === 'pending' ? 'running' : status, this.color('screen')); }

  private hasFailure(agent: SubagentSummary): boolean {
    return agent.status === 'failed' && !!(agent.result || agent.progress);
  }

  @Builder
  private agentRow(agent: SubagentSummary) {
    Column() {
      Button({ type: ButtonType.ROUNDED_RECTANGLE, stateEffect: !this.disabled && !!(agent.childThreadId || agent.remoteChild) }) {
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            Text(subagentTitle(agent)).fontSize(this.font(14)).fontWeight(FontWeight.Medium).fontColor(this.color('foreground'))
              .layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.label(agent.status)).fontSize(this.font(11)).fontColor(this.tint(agent.status)).maxLines(1)
            if (agent.childThreadId || agent.remoteChild) { AppIcon({ name: 'chevron', iconSize: 13, tint: this.color('foreground-muted') }) }
          }.width('100%')
          Row({ space: 5 }) {
            if (subagentModelLabel(agent, this.providers)) {
              ProviderIcon({ driver: agent.driver ?? '', label: agent.providerInstanceId ?? '', iconSize: 12 })
              Text(subagentModelLabel(agent, this.providers)).fontSize(this.font(11)).fontColor(this.color('foreground-secondary'))
                .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            Text(subagentElapsed([agent], this.now)).fontSize(this.font(11)).fontColor(this.color('foreground-muted')).maxLines(1)
          }.width('100%')
          if (!this.hasFailure(agent) && subagentPreview(agent)) {
            Text(subagentPreview(agent)).fontSize(this.font(13)).fontColor(this.color('foreground-secondary'))
              .maxLines(this.listOnly ? 3 : 2).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
      }.id(`subagent-child-${agent.id}`).width('100%').constraintSize({ minHeight: 48 })
        .padding({ left: 14, right: 14, top: 12, bottom: this.hasFailure(agent) ? 4 : 12 })
        .borderRadius(16).backgroundColor(Color.Transparent)
        .accessibilityText([subagentTitle(agent), this.label(agent.status), subagentModelLabel(agent, this.providers),
          this.hasFailure(agent) ? '' : subagentPreview(agent)].filter((text: string) => !!text).join('，'))
        .onClick(() => { if (!this.disabled && (agent.childThreadId || agent.remoteChild)) this.onOpen(agent); })
      if (this.hasFailure(agent)) {
        Button({ type: ButtonType.ROUNDED_RECTANGLE }) {
          Row({ space: 6 }) {
            Text(subagentPreview(agent)).fontSize(this.font(12)).fontColor(this.color('foreground-secondary')).layoutWeight(1)
              .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text('详情').fontSize(this.font(12)).fontColor(this.color('md-link'))
          }.width('100%')
        }.id(`subagent-error-${agent.id}`).width('100%').constraintSize({ minHeight: 40 })
          .padding({ left: 14, right: 14, top: 4, bottom: 8 }).borderRadius(16).backgroundColor(Color.Transparent).enabled(!this.disabled)
          .accessibilityText(`${subagentPreview(agent)}，查看错误详情`).onClick(() => {
            this.getUIContext().showAlertDialog({ title: '错误详情', message: agent.result || agent.progress || '',
              systemMaterial: immersiveMaterial('popup'), confirm: { value: '关闭', action: () => {} } });
          })
      }
      if (this.listOnly && agent.workflow) {
        Column({ space: 4 }) {
          Text(agent.workflow.phases.map(phase => phase.title).join(' · ') || '工作流').fontSize(this.font(12)).fontColor(this.color('foreground-muted'))
          ForEach(agent.workflow.agents, (child: WorkflowAgent) => {
            Text(`${child.label} · ${this.label(child.state)}`).fontSize(this.font(12)).fontColor(this.color('foreground-secondary'))
              .onClick(() => {
                if (!this.disabled && child.childThreadId) this.onOpen({ id: String(child.index), threadId: agent.threadId,
                  childThreadId: child.childThreadId, origin: 'provider_native', title: child.label, status: child.state, updatedAt: agent.updatedAt });
              })
          }, (child: WorkflowAgent) => JSON.stringify(child))
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 14, right: 14, bottom: 12 })
      }
    }.width('100%').backgroundColor(this.listOnly ? '#C8' + this.color('card').slice(1) : this.color('subtle'))
      .border({ width: 0.75, color: this.color('border'), radius: 16 }).clip(true)
  }

  build() {
    Column({ space: this.listOnly ? 10 : 6 }) {
      if (!this.listOnly && this.agents.length > 1) {
      Button({ type: ButtonType.ROUNDED_RECTANGLE }) {
        Row({ space: 8 }) {
          Row({ space: 2 }) {
            ForEach(this.agents.slice(0, 3), (agent: SubagentSummary) => {
              AppIcon({ name: 'robot', iconSize: 15, tint: statusColor(agent.status, this.color('screen')) })
            }, (agent: SubagentSummary) => `${agent.id}:${agent.status}`)
          }
          Column({ space: 3 }) {
            Text(`${this.agents.length} 个子代理`).fontSize(this.font(13)).fontWeight(FontWeight.Medium).fontColor(this.color('foreground'))
            Text(this.summary()).fontSize(this.font(11)).fontColor(this.liveCount() > 0 ? statusColor('running', this.color('screen')) : this.color('foreground-muted'))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Text(subagentElapsed(this.agents, this.now)).fontSize(this.font(12)).fontColor(this.color('foreground-muted')).maxLines(1)
          AppIcon({ name: this.expanded ? 'down' : 'chevron', iconSize: 13, tint: this.color('foreground-muted') })
        }.width('100%')
      }.id(`subagent-group-${this.groupId}`).width('100%').constraintSize({ minHeight: 44 }).padding(6)
        .backgroundColor(Color.Transparent).enabled(!this.disabled)
        .accessibilityText(`${this.agents.length} 个子代理，${this.summary()}，${this.expanded ? '收起' : '展开'}`)
        .onClick(() => { this.onToggle(); })
      }
      if (this.listOnly || this.agents.length === 1 || this.expanded) {
        ForEach(this.agents, (agent: SubagentSummary) => { this.agentRow(agent) }, (agent: SubagentSummary) => JSON.stringify(agent))
      }
    }.width('100%').padding({ bottom: 4 })
      .onVisibleAreaChange([0], (visible: boolean) => { this.visible = visible; this.updateClock(); })
  }
}
