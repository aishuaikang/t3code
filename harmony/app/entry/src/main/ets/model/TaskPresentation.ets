import { ThreadShell, LatestTurn, taskStatus } from './Models';

export function taskLatestTurn(thread: ThreadShell): LatestTurn | null {
  if (thread.latestTurn) return thread.latestTurn;
  if (!thread.latestRunId) return null;
  return { turnId: thread.latestRunId, state: thread.status ?? thread.activityRunStatus ?? 'idle',
    requestedAt: thread.latestRunRequestedAt ?? undefined, startedAt: thread.latestRunStartedAt,
    completedAt: thread.latestRunCompletedAt };
}

export function taskWorkTurn(thread: ThreadShell): LatestTurn | null {
  if (!['running', 'waiting'].includes(taskStatus(thread))) return null;
  if (thread.activeRunId && thread.activityRunStartedAt) {
    return { turnId: thread.activeRunId, state: 'running', startedAt: thread.activityRunStartedAt };
  }
  const turn = taskLatestTurn(thread);
  return turn?.completedAt ? null : turn;
}

export function relativeTaskTime(updatedAt: string | null, now: number): string {
  const elapsed = Math.max(0, now - Date.parse(updatedAt ?? ''));
  if (!Number.isFinite(elapsed)) return '';
  const minutes = Math.floor(elapsed / 60000);
  return minutes < 1 ? '刚刚' : minutes < 60 ? `${minutes}m` : minutes < 1440 ? `${Math.floor(minutes / 60)}h` : `${Math.floor(minutes / 1440)}d`;
}
export function taskSection(state: string, pinned: boolean = false): number {
  if (pinned) return -1;
  return ['running', 'waiting', 'queued'].includes(state) ? 0 : state === 'completed' ? 2 : 1;
}

export function sortPinnedThreads(threads: ThreadShell[]): ThreadShell[] {
  return threads.slice().sort((left: ThreadShell, right: ThreadShell) => {
    if (!!left.pinnedAt !== !!right.pinnedAt) return left.pinnedAt ? -1 : 1;
    if (!left.pinnedAt) return 0;
    // Match Android's server order, retaining the existing order of unpinned tasks.
    const a = left.pinOrderKey, b = right.pinOrderKey;
    if (a != null && b == null) return -1;
    if (a == null && b != null) return 1;
    if (a != null && b != null) return a < b ? -1 : a > b ? 1 : left.id.localeCompare(right.id);
    return ((Date.parse(right.createdAt ?? '') || 0) - (Date.parse(left.createdAt ?? '') || 0)) || left.id.localeCompare(right.id);
  });
}
export function projectInitials(title: string): string {
  const words = title.trim().split(/[\s_/-]+/).filter((word: string) => !!word);
  return words.length > 1 ? (words[0][0] + words[1][0]).toUpperCase() : (words[0] ?? '').substring(0, 2).toUpperCase();
}
export function projectTint(title: string): string {
  const colors: string[] = ['#0D9488', '#A16207', '#7C3AED', '#BE185D', '#2563EB'];
  let hash = 0;
  for (let index = 0; index < title.length; index++) hash = (hash * 31 + title.charCodeAt(index)) >>> 0;
  return colors[hash % colors.length];
}
