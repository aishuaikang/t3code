import { ProjectShell } from '../model/Models';
import { ProjectGroup, groupProjects, projectWorkspaces, projectGroupMatches } from '../model/ProjectGrouping';
import { ThemeRuntime } from '../connection/ThemeRuntime';
import { Typography, resolveTypography, scaledFontSize } from '../model/Typography';
import { ProjectIcon } from './ProjectIcon';
import { AppIcon } from './AppIcon';

@Component
export struct ProjectPicker {
  @Prop projects: ProjectShell[] = [];
  @Prop selectedId: string = '';
  @Prop environmentId: string = '';
  @Prop groupingMode: string = 'repository';
  @Prop allowAll: boolean = false;
  @Prop selectWorkspace: boolean = false;
  @Prop canAdd: boolean = false;
  onSelect: (id: string) => void = () => {};
  onAdd: () => void = () => {};
  @StorageLink('themeKey') themeKey: string = 't3-code-light';
  @StorageLink('textSizes') sizes: Typography = resolveTypography(16, null, null);
  @State query: string = '';
  @State workspaceGroup: string = '';
  private color(role: string): string { return ThemeRuntime.color(this.themeKey, role); }
  private font(size: number): number { return scaledFontSize(size, this.sizes.baseFontSize); }
  private groups(): ProjectGroup[] { return groupProjects(this.projects, this.environmentId, this.groupingMode); }
  private matchingGroups(): ProjectGroup[] { return this.groups().filter((group: ProjectGroup) => projectGroupMatches(this.projects, group, this.query)); }
  private project(group: ProjectGroup): ProjectShell | undefined { return this.projects.find((entry: ProjectShell) => entry.id === group.representativeId); }
  private workspaces(group: ProjectGroup): ProjectShell[] { return projectWorkspaces(this.projects, group); }
  private visibleWorkspaces(): ProjectShell[] {
    const group = this.groups().find((entry: ProjectGroup) => entry.key === this.workspaceGroup);
    return group === undefined ? [] : this.workspaces(group).filter((project: ProjectShell) => `${project.title} ${project.workspaceRoot}`.toLocaleLowerCase().includes(this.query.trim().toLocaleLowerCase()));
  }
  private choose(group: ProjectGroup): void {
    if (this.selectWorkspace && this.workspaces(group).length > 1) { this.workspaceGroup = group.key; this.query = ''; }
    else this.onSelect(group.representativeId);
  }
  build() {
    Column({ space: 12 }) {
      if (this.workspaceGroup) {
        Row({ space: 8 }) {
          Button({ type: ButtonType.Circle }) { AppIcon({ name: 'back', iconSize: 20, tint: this.color('foreground') }) }
            .width(36).height(36).padding(0).backgroundColor(Color.Transparent).accessibilityText('返回项目列表')
            .onClick(() => { this.workspaceGroup = ''; this.query = ''; })
          Text(this.groups().find((group: ProjectGroup) => group.key === this.workspaceGroup)?.label ?? '选择工作区')
            .fontSize(this.font(16)).fontWeight(FontWeight.Medium).fontColor(this.color('foreground')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        }.width('100%')
      }
      Row({ space: 8 }) {
        Search({ value: this.query, placeholder: this.workspaceGroup ? '搜索工作区' : '搜索项目' }).height(42).borderRadius(14)
          .textFont({ size: this.font(15) }).fontColor(this.color('foreground')).backgroundColor(this.color('input')).layoutWeight(1)
          .onChange((value: string) => { this.query = value; })
        if (!this.workspaceGroup && this.canAdd) {
          Button({ type: ButtonType.Circle }) { AppIcon({ name: 'plus', iconSize: 21, tint: this.color('foreground') }) }
            .width(40).height(40).padding(0).backgroundColor(Color.Transparent).accessibilityText('添加项目').onClick(() => { this.onAdd(); })
        }
      }.width('100%')
      List() {
        if (this.workspaceGroup) {
          ForEach(this.visibleWorkspaces(), (project: ProjectShell) => {
            ListItem() {
              Button({ type: ButtonType.Normal }) {
                Row({ space: 12 }) {
                  AppIcon({ name: 'folder', iconSize: 22, tint: this.color('foreground-muted') })
                  Column({ space: 4 }) {
                    Text(project.title === 'No project' ? '独立任务' : project.title).fontSize(this.font(16)).fontColor(this.color('foreground')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                    Text(project.workspaceRoot).fontSize(this.font(12)).fontColor(this.color('foreground-muted')).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                  }.layoutWeight(1)
                  if (project.id === this.selectedId) { AppIcon({ name: 'check', iconSize: 20, tint: this.color('primary') }) }
                }.width('100%')
              }.width('100%').height(76).borderRadius(0).padding({ left: 16, right: 16 }).backgroundColor(Color.Transparent)
                .onClick(() => { this.onSelect(project.id); }).accessibilityText(`选择工作区 ${project.workspaceRoot}`)
            }
          }, (project: ProjectShell) => project.id)
        } else {
          if (this.allowAll && !this.query) {
            ListItem() {
              Button({ type: ButtonType.Normal }) {
                Row({ space: 12 }) {
                  AppIcon({ name: 'folder', iconSize: 23, tint: this.color('foreground-muted') })
                  Text('全部项目').fontSize(this.font(16)).fontColor(this.color('foreground')).layoutWeight(1)
                  if (!this.selectedId) { AppIcon({ name: 'check', iconSize: 20, tint: this.color('primary') }) }
                }.width('100%')
              }.width('100%').height(60).borderRadius(0).padding({ left: 16, right: 16 }).backgroundColor(Color.Transparent).onClick(() => { this.onSelect(''); })
            }
          }
          ForEach(this.matchingGroups(), (group: ProjectGroup) => {
            ListItem() {
              Button({ type: ButtonType.Normal }) {
                Row({ space: 12 }) {
                  ProjectIcon({ cwd: this.project(group)?.workspaceRoot ?? '', faviconPath: this.project(group)?.faviconPath ?? '', label: group.label, iconSize: 26 })
                  Column({ space: 4 }) {
                    Text(group.label === 'No project' ? '独立任务' : group.label).fontSize(this.font(16)).fontWeight(FontWeight.Medium)
                      .fontColor(this.color('foreground')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                    Text(this.workspaces(group).length > 1 ? `${this.workspaces(group).length} 个工作区` : this.project(group)?.workspaceRoot ?? '')
                      .fontSize(this.font(12)).fontColor(this.color('foreground-muted')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                  }.layoutWeight(1)
                  if (group.projectIds.includes(this.selectedId)) { AppIcon({ name: 'check', iconSize: 20, tint: this.color('primary') }) }
                  if (this.selectWorkspace && this.workspaces(group).length > 1) { AppIcon({ name: 'chevron', iconSize: 15, tint: this.color('foreground-muted') }) }
                }.width('100%')
              }.width('100%').height(72).borderRadius(0).padding({ left: 16, right: 16 }).backgroundColor(Color.Transparent)
                .onClick(() => { this.choose(group); }).accessibilityText(`选择项目 ${group.label}`)
            }
          }, (group: ProjectGroup) => group.key)
        }
        if (this.workspaceGroup ? this.visibleWorkspaces().length === 0 : this.matchingGroups().length === 0) {
          ListItem() { Text('没有匹配的项目或工作区').fontSize(this.font(14)).fontColor(this.color('foreground-muted')).width('100%').textAlign(TextAlign.Center).padding(24) }
        }
      }.layoutWeight(1).width('100%').borderRadius(20).backgroundColor('#B3' + this.color('card').slice(1)).clip(true)
    }.padding({ left: 16, right: 16, top: 8, bottom: 24 }).width('100%').height('100%')
  }
}
