import { ThreadPullRequestLink, ProjectScript, ProjectShell } from './Models';

export function pullRequestLink(input: string): ThreadPullRequestLink | null {
  const match = /^(https?):\/\/([^/\s?#@]+)\/(.+?)\/(pull|pulls|pull-requests|-\/merge_requests)\/(\d+)(?:[/?#].*)?$/i.exec(input.trim());
  if (match === null || !Number.isSafeInteger(Number(match[5])) || Number(match[5]) <= 0 ||
    match[3].split('/').length < 2 || match[3].split('/').some((part: string) => !part || part === '.' || part === '..')) return null;
  return { host: match[2].toLowerCase(), repository: match[3].toLowerCase(), number: Number(match[5]),
    url: `${match[1].toLowerCase()}://${match[2]}/${match[3]}/${match[4]}/${Number(match[5])}`, source: 'manual' };
}

export function validBranchName(input: string): boolean {
  return input.length > 0 && input.length <= 200 && input !== '@' && !input.startsWith('-') &&
    !input.endsWith('.') && !input.includes('..') && !input.includes('@{') &&
    !/[\x00-\x20\x7f~^:?*\[\\]/.test(input) &&
    input.split('/').every((part: string) => !!part && !part.startsWith('.') && !part.endsWith('.lock'));
}

export interface WorkspaceProjectSettings { defaultProjectScripts?: ProjectScript[]; }
export interface WorkspaceSettings {
  defaultProjectScripts?: ProjectScript[];
  projectSettingsFolded?: boolean;
  projectScriptOverrides?: Record<string, ProjectScript[] | null>;
  projectSettingsOverrides?: Record<string, WorkspaceProjectSettings>;
}
interface WorkspaceSettingsPatch {
  patch: WorkspaceSettings;
}

export function resolveProjectScripts(settings: WorkspaceSettings, project: ProjectShell): ProjectScript[] {
  const modern = settings.projectSettingsOverrides?.[project.id]?.defaultProjectScripts;
  if (modern !== undefined) return modern;
  const defaults = settings.defaultProjectScripts ?? [];
  if (settings.projectSettingsFolded) return defaults;
  const legacy = settings.projectScriptOverrides?.[project.id];
  if (legacy === null) return defaults;
  return legacy ?? (project.scripts?.length ? project.scripts : defaults);
}

export function projectScriptsPatch(settings: WorkspaceSettings, projectId: string, scripts: ProjectScript[], modern: boolean): WorkspaceSettingsPatch {
  if (!modern) {
    const overrides: Record<string, ProjectScript[] | null> = {};
    overrides[projectId] = scripts;
    return { patch: { projectScriptOverrides: overrides } };
  }
  // Retain settings that the phone does not edit, including newer server fields.
  const entry = JSON.parse(JSON.stringify(settings.projectSettingsOverrides?.[projectId] ?? {})) as WorkspaceProjectSettings;
  entry.defaultProjectScripts = scripts;
  const overrides: Record<string, WorkspaceProjectSettings> = {};
  overrides[projectId] = entry;
  return { patch: { projectSettingsOverrides: overrides } };
}

export function upsertProjectScript(scripts: ProjectScript[], script: ProjectScript): ProjectScript[] {
  const next = scripts.filter((entry: ProjectScript) => entry.id !== script.id).map((entry: ProjectScript): ProjectScript => {
    const copy = JSON.parse(JSON.stringify(entry)) as ProjectScript;
    if (script.runOnWorktreeCreate) copy.runOnWorktreeCreate = false;
    return copy;
  });
  const index = scripts.findIndex((entry: ProjectScript) => entry.id === script.id);
  next.splice(index < 0 ? next.length : index, 0, script);
  return next;
}

export interface WorkspaceGitStatus {
  isRepo: boolean; refName: string | null; hasPrimaryRemote: boolean; isDefaultRef: boolean;
  hasWorkingTreeChanges: boolean;
  workingTree: WorkspaceChanges;
  branchChanges?: WorkspaceChanges;
  aheadCount?: number; behindCount?: number;
  pr?: WorkspacePullRequest | null;
}
export interface WorkspaceChanges { insertions: number; deletions: number; baseRef?: string | null; }
export interface WorkspacePullRequest { number: number; url: string; title: string; state: string; }
export interface WorkspaceGitResult {
  branch: WorkspaceGitBranchResult;
  pr: WorkspaceGitPullResult;
}
interface WorkspaceGitBranchResult { status: string; name?: string; }
interface WorkspaceGitPullResult { status: string; url?: string; number?: number; }
export interface WorkspaceGitRequest {
  actionId: string; cwd: string; action: string; threadId: string; projectId: string;
  commitMessage?: string; featureBranch?: boolean;
}
export interface WorkspaceGitAction { id: string; label: string; icon: string; }
export function workspaceGitActions(): WorkspaceGitAction[] {
  return [
    { id: 'commit', label: '提交', icon: 'check' },
    { id: 'push', label: '推送', icon: 'send' },
    { id: 'create_pr', label: '创建变更请求', icon: 'pull-request' },
    { id: 'commit_push', label: '提交并推送', icon: 'send' },
    { id: 'commit_push_pr', label: '提交、推送并创建变更请求', icon: 'pull-request' }
  ];
}

export function workspaceGitRequest(action: string, actionId: string, cwd: string, threadId: string, projectId: string,
  message: string, featureBranch: boolean): WorkspaceGitRequest {
  const request: WorkspaceGitRequest = { actionId: actionId, cwd: cwd, action: action, threadId: threadId, projectId: projectId };
  if (message.trim()) request.commitMessage = message.trim();
  if (featureBranch) request.featureBranch = true;
  return request;
}

export function workspaceGitDisabled(status: WorkspaceGitStatus | null, action: string, featureBranch: boolean): string {
  if (status === null) return '正在读取仓库状态';
  if (!status.isRepo) return '当前目录不是 Git 仓库';
  if (!workspaceGitActions().some((entry: WorkspaceGitAction) => entry.id === action)) return '请选择 Git 操作';
  if (action === 'commit' && !status.hasWorkingTreeChanges) return '没有可提交的改动';
  if (action !== 'commit' && !status.hasPrimaryRemote) return '当前仓库没有远程地址';
  if (action !== 'commit' && status.isDefaultRef && !featureBranch) return '请先切换分支，或选择在新分支上发布';
  return '';
}
