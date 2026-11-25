export interface SlashCommand { name: string; displayName?: string; description?: string; input?: CommandInput; kind?: string; insertion?: string; searchText?: string; icon?: string; }
interface CommandInput { hint: string; }
interface ProviderSkill { name: string; enabled: boolean; description?: string; shortDescription?: string; displayName?: string; userInvocable?: boolean; scope?: string; path?: string; }
interface WorkspaceCommands { cwd: string; slashCommands: SlashCommand[]; skills?: ProviderSkill[]; }
interface CommandProvider { instanceId: string; slashCommands?: SlashCommand[]; skills?: ProviderSkill[]; workspaceSnapshots?: WorkspaceCommands[]; }
export interface ProviderCommandCatalog { instanceId: string; commands: SlashCommand[]; workspaces: CommandWorkspace[]; }
interface CommandWorkspace { cwd: string; commands: SlashCommand[]; }
interface CommandTrigger { start: number; end: number; query: string; }
export interface CommandInsertion { text: string; cursor: number; }

export function insertComposerTrigger(text: string, start: number, end: number, trigger: string): CommandInsertion {
  const from = Math.max(0, Math.min(text.length, start));
  const to = Math.max(from, Math.min(text.length, end));
  const before = text.substring(0, from), after = text.substring(to);
  const inserted = (before && !/\s$/.test(before) ? ' ' : '') + trigger;
  return { text: before + inserted + (after && !/^\s/.test(after) ? ' ' : '') + after, cursor: before.length + inserted.length };
}

const CHINESE_COMMAND_TERMS: Record<string, string> = {
  'model': '模型 切换模型', 'compact': '压缩 精简上下文', 'clear': '清空 清除 重置 新上下文',
  'side': '旁支 分叉 支线', 'btw': '顺便 旁支', 'plan': '计划 规划', 'review': '审查 代码审查',
  'status': '状态 用量', 'context': '上下文', 'cost': '费用 成本', 'help': '帮助', 'init': '初始化',
  'skills': '技能', 'permissions': '权限 审批', 'new': '新建 新会话', 'resume': '恢复 继续',
  'rename': '重命名 改名', 'diff': '差异 改动', 'terminal': '终端 命令行'
};

function collectCommands(commands: SlashCommand[], skills: ProviderSkill[]): SlashCommand[] {
  const result: Map<string, SlashCommand> = new Map();
  for (const command of commands) {
    const name = command.name.replace(/^\//, '').trim();
    if (!name || /[\s/]/.test(name)) continue;
    result.set(name.toLocaleLowerCase(), { name: name, description: command.description, input: command.input, kind: 'provider' });
  }
  for (const skill of skills) {
    const name = skill.name.replace(/^\//, '').trim();
    if (!skill.enabled || skill.userInvocable === false || !name || /[\s/]/.test(name)) continue;
    result.delete(name.toLocaleLowerCase());
    if (!result.has(`skill:${name.toLocaleLowerCase()}`)) result.set(`skill:${name.toLocaleLowerCase()}`,
      { name: `skill:${name}`, displayName: skill.displayName || (name === 'review' ? '代码审查' : name),
        description: skill.shortDescription ?? skill.description, kind: 'skill', insertion: `$${name}`,
        searchText: `${skill.displayName ?? ''} ${skill.description ?? ''} ${skill.shortDescription ?? ''}`, icon: skillIcon(skill) });
  }
  return Array.from(result.values());
}

function skillIcon(skill: ProviderSkill): string {
  if (skill.path?.includes('/plugins/')) return 'sliders';
  if (['repo', 'repository', 'project', 'workspace', 'local'].includes(skill.scope ?? '')) return 'folder';
  if (['user', 'personal'].includes(skill.scope ?? '')) return 'person';
  return skill.scope === 'system' ? 'settings' : 'skill';
}

export function commandCatalog(providers: object[]): ProviderCommandCatalog[] {
  return (providers as CommandProvider[]).map((provider: CommandProvider): ProviderCommandCatalog => ({
    instanceId: provider.instanceId, commands: collectCommands(provider.slashCommands ?? [], provider.skills ?? []),
    workspaces: (provider.workspaceSnapshots ?? []).map((workspace: WorkspaceCommands): CommandWorkspace => ({
      cwd: workspace.cwd, commands: collectCommands(workspace.slashCommands, workspace.skills ?? [])
    }))
  }));
}

export function commandsFor(catalog: ProviderCommandCatalog[], instanceId: string, cwd: string, existingThread: boolean = true, allowSide: boolean = true): SlashCommand[] {
  const provider = catalog.find((entry: ProviderCommandCatalog) => entry.instanceId === instanceId);
  const commands: SlashCommand[] = [
    { name: 'model', description: '切换本次任务的回复模型', kind: 'model', icon: 'sliders' }
  ];
  if (existingThread) {
    if (allowSide) commands.push({ name: 'side', description: '基于当前上下文开启旁支对话', kind: 'side', icon: 'branch' },
      { name: 'btw', description: '与 /side 相同', kind: 'side', icon: 'chat' });
    commands.push({ name: 'clear', description: '使用全新上下文开始，保留已有聊天记录', kind: 'clear', icon: 'refresh', input: { hint: '接下来要发送的内容' } });
  }
  const merged: Map<string, SlashCommand> = new Map();
  const workspace = provider?.workspaces.find((entry: CommandWorkspace) => entry.cwd === cwd);
  for (const command of commands.concat(workspace?.commands ?? provider?.commands ?? [])) {
    const key = command.name.toLocaleLowerCase();
    if (!merged.has(key)) merged.set(key, command);
  }
  return Array.from(merged.values());
}

function commandTrigger(text: string, start: number, end: number): CommandTrigger | null {
  if (start !== end || start < 0 || start > text.length) return null;
  const match = /[/／]([^\s/／@＠，。！？；、()（）]*)$/.exec(text.substring(0, start));
  if (match === null) return null;
  const from = match.index;
  const prefix = text.substring(0, from).split(/\s/).pop() ?? '';
  if (/[/:\\]/.test(prefix) || /^\.{1,2}$/.test(prefix) || /[.\\]/.test(match[1])) return null;
  let to = start;
  while (to < text.length && !/[\s/／@＠，。！？；、()（）]/.test(text.charAt(to))) to++;
  return { start: from, end: to, query: match[1].toLocaleLowerCase() };
}

export function commandSuggestions(text: string, start: number, end: number, commands: SlashCommand[]): SlashCommand[] {
  const trigger = commandTrigger(text, start, end);
  if (trigger === null) return [];
  return commands.filter((command: SlashCommand) => commandScore(command, trigger.query) >= 0)
    .sort((a: SlashCommand, b: SlashCommand) => commandScore(a, trigger.query) - commandScore(b, trigger.query));
}

export function commandQuery(text: string, start: number, end: number): string | null { return commandTrigger(text, start, end)?.query ?? null; }

function commandScore(command: SlashCommand, query: string): number {
  const name = command.name.toLocaleLowerCase();
  const bare = name.replace(/^skill:/, '');
  const term = command.kind === 'skill' ? query.replace(/^skill(?::|$)/, '') : query;
  if (!term || name === term || bare === term) return 0;
  if (name.startsWith(term) || bare.startsWith(term)) return 1;
  if (name.includes(term)) return 2;
  const aliases = bare.split(/[:_-]/).map((word: string) => CHINESE_COMMAND_TERMS[word] ?? '').join(' ');
  return `${command.description ?? ''} ${command.searchText ?? ''} ${aliases}`.toLocaleLowerCase().includes(term) ? 3 : -1;
}

export function insertCommand(text: string, start: number, end: number, command: SlashCommand): CommandInsertion {
  const trigger = commandTrigger(text, start, end);
  if (trigger === null) return { text: text, cursor: end };
  const replacement = command.kind === 'model' ? '' : `${command.insertion ?? '/' + command.name} `;
  const suffix = text.substring(trigger.end).replace(/^ /, '');
  return { text: text.substring(0, trigger.start) + replacement + suffix, cursor: trigger.start + replacement.length };
}
