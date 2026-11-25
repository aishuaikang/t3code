import { LatestTurn } from './Models';

export interface ThreadReadMark { revision: string; unread: boolean; }
export interface ThreadReadTarget { threadId: string; revision: string; }

export function threadReadKey(environmentId: string, threadId: string): string {
  return JSON.stringify([environmentId, threadId]);
}

export function threadReadRevision(turn: LatestTurn | null | undefined): string {
  if (turn === undefined || turn === null) return '';
  // Shells use four turn states; the detailed feed also includes run lifecycle states.
  const state = ['preparing', 'queued', 'starting', 'waiting'].includes(turn.state) ? 'running' :
    ['cancelled', 'stopped', 'rolled_back'].includes(turn.state) ? 'interrupted' : turn.state === 'failed' ? 'error' : turn.state;
  return JSON.stringify([turn.turnId, state, turn.completedAt ?? '']);
}

export function threadIsUnread(mark: ThreadReadMark | undefined, revision: string): boolean {
  return mark?.unread === true || (revision !== '' && mark?.revision !== revision);
}
