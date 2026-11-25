import { ThreadShell, ProjectShell, taskStatus } from './Models';

export interface TaskNotice {
  environmentId: string; threadId: string; title: string; text: string; state: string; cwd: string; projectTitle: string;
}
interface TaskNoticeState { state: string; runId: string; }

export class TaskNotificationTracker {
  private previous: Map<string, TaskNoticeState> = new Map();
  update(environmentId: string, threads: ThreadShell[], projects: ProjectShell[], baseline: boolean = false): TaskNotice[] {
    const notices: TaskNotice[] = [];
    for (const thread of threads) {
      const key = JSON.stringify([environmentId, thread.id]);
      const state = taskStatus(thread), runId = thread.activeRunId ?? thread.session?.activeTurnId ?? thread.latestRunId ?? thread.latestTurn?.turnId ?? '';
      const previous = this.previous.get(key);
      this.previous.set(key, { state: state, runId: runId });
      if (baseline || state === 'archived' || (previous?.state === state && previous.runId === runId)) continue;
      const finished = state === 'idle' && previous !== undefined && ['running', 'waiting', 'queued'].includes(previous.state);
      if (!finished && !['waiting', 'completed', 'failed', 'interrupted'].includes(state)) continue;
      const project = projects.find((entry: ProjectShell) => entry.id === thread.projectId);
      notices.push({ environmentId: environmentId, threadId: thread.id, title: thread.title || 'T3 任务',
        state: finished ? 'completed' : state, text: finished || state === 'completed' ? '回复已完成' :
          state === 'waiting' ? '任务需要你的回答或批准' : state === 'failed' ? '任务执行失败，点击查看详情' : '任务已停止',
        cwd: thread.worktreePath ?? project?.workspaceRoot ?? '', projectTitle: project?.title ?? '独立任务' });
    }
    return notices;
  }
}

export function taskNotificationId(environmentId: string, threadId: string): number {
  let hash = 2166136261;
  for (const value of JSON.stringify([environmentId, threadId])) hash = Math.imul(hash ^ value.charCodeAt(0), 16777619);
  return hash & 0x7fffffff;
}
