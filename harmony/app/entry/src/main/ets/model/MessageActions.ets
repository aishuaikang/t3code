import { ChatMessage, LatestTurn, MessageContextRecord, RewindCheckpoint, RewindProviderThread, ThreadDetail, TimelineRow } from './Models';

export interface MessageForkPoint { type: string; runId: string; }
export interface MessageForkCommand {
  type: string; commandId: string; sourceThreadId: string; targetThreadId: string;
  sourcePoint: MessageForkPoint; title: string; createdBy: string; creationSource: string;
}

export function assistantActionIds(rows: TimelineRow[], activeRunId: string | null): string[] {
  const last: Map<string, TimelineRow> = new Map();
  for (const row of rows) {
    if (row.kind === 'message' && row.role === 'assistant' && (row.text.trim() || (row.attachments?.length ?? 0) > 0)) {
      last.set(row.turnId ?? row.id, row);
    }
  }
  return Array.from(last.values()).filter((row: TimelineRow) => !row.streaming && (!activeRunId || row.turnId !== activeRunId))
    .map((row: TimelineRow) => row.id);
}

export function forkFromMessage(sourceThreadId: string, row: TimelineRow, commandId: string,
  targetThreadId: string, title: string): MessageForkCommand {
  if (row.role !== 'assistant' || row.streaming || !row.turnId) throw new Error('请等待这条回复完成后再分叉');
  return { type: 'thread.fork', commandId: commandId, sourceThreadId: sourceThreadId, targetThreadId: targetThreadId,
    sourcePoint: { type: 'run', runId: row.turnId }, title: (title.trim() || '对话').slice(0, 72) + ' · 分支',
    createdBy: 'user', creationSource: 'mobile' };
}

export function messageTimeValue(row: TimelineRow): string {
  return row.role === 'assistant' ? row.updatedAt || row.createdAt : row.createdAt;
}

export interface HistoryEditTarget {
  turnCount: number; checkpoint: RewindCheckpoint; witnessRunId: string; providerThreadId: string;
  providerInstanceId: string; existingProviderThreads: string[]; canRestoreFiles: boolean;
}

interface EditableRun { messageId?: string | null; target: HistoryEditTarget; }

export class HistoryEditIndex {
  private threadId: string;
  private turns?: LatestTurn[];
  private checkpoints?: RewindCheckpoint[];
  private providers?: RewindProviderThread[];
  private providerId?: string | null;
  private latestId?: string;
  private worktree?: string | null;
  private editable: Map<string, EditableRun> = new Map();

  constructor(thread: ThreadDetail) {
    this.threadId = thread.id; this.turns = thread.turns; this.checkpoints = thread.rewindCheckpoints;
    this.providers = thread.providerThreads; this.providerId = thread.activeProviderThreadId;
    this.latestId = thread.latestTurn?.turnId; this.worktree = thread.worktreePath;
    const provider = this.providers?.find(value => value.id === this.providerId);
    if (!provider || !this.checkpoints?.length || !this.turns?.length ||
      (this.latestId && !this.turns.some(turn => turn.turnId === this.latestId))) return;
    const checkpoints = new Map<number, RewindCheckpoint>();
    for (const checkpoint of this.checkpoints) {
      if (checkpoint.status !== 'ready' && checkpoint.status !== 'missing') continue;
      if (checkpoint.appRunOrdinal === null && checkpoint.ordinalWithinScope === 0) checkpoints.set(0, checkpoint);
      else if (checkpoint.appRunOrdinal && checkpoint.appRunOrdinal > 0) checkpoints.set(checkpoint.appRunOrdinal, checkpoint);
    }
    const turns = this.turns.slice().sort((a, b) => (a.ordinal ?? 0) - (b.ordinal ?? 0));
    const settled = (turn: LatestTurn): boolean => ['completed', 'interrupted', 'error', 'failed'].includes(turn.state) ||
      (turn.state === 'cancelled' && !!turn.startedAt);
    const witness = turns.slice().reverse().find(settled);
    if (!witness) return;
    const providerIds = (this.providers ?? []).map(entry => entry.id);
    let previous = 0, covered = 0;
    for (const turn of turns) {
      const ordinal = turn.ordinal ?? 0;
      if (ordinal < 1) continue;
      if (!settled(turn)) {
        if (ordinal === covered + 1 && (turn.state === 'rolled_back' || (turn.state === 'cancelled' && !turn.startedAt))) covered = ordinal;
        continue;
      }
      const checkpoint = checkpoints.get(previous);
      // A gap can hide an earlier settled run; never rewind across an unknown predecessor.
      if (ordinal === covered + 1 && checkpoint) this.editable.set(turn.turnId, { messageId: turn.userMessageId,
        target: { turnCount: previous, checkpoint: checkpoint, witnessRunId: witness.turnId, providerThreadId: provider.id,
          providerInstanceId: provider.providerInstanceId, existingProviderThreads: providerIds, canRestoreFiles: !!this.worktree && checkpoint.status === 'ready' } });
      previous = covered = ordinal;
    }
  }

  matches(thread: ThreadDetail): boolean {
    return this.threadId === thread.id && this.turns === thread.turns && this.checkpoints === thread.rewindCheckpoints &&
      this.providers === thread.providerThreads && this.providerId === thread.activeProviderThreadId &&
      this.latestId === thread.latestTurn?.turnId && this.worktree === thread.worktreePath;
  }

  target(message: ChatMessage | undefined): HistoryEditTarget | null {
    if (!message || message.role !== 'user' || message.sourceThreadId !== this.threadId || !message.turnId ||
      message.streaming || message.queueAutomatic || message.queueGuest) return null;
    const run = this.editable.get(message.turnId);
    if (!run || (message.inputIntent ? !['turn_start', 'queued_turn'].includes(message.inputIntent) : run.messageId !== message.id)) return null;
    return run.target;
  }
}

export function historyEditTarget(thread: ThreadDetail | null, message: ChatMessage | undefined): HistoryEditTarget | null {
  return thread ? new HistoryEditIndex(thread).target(message) : null;
}

export function historyEditCompleted(thread: ThreadDetail | null, target: HistoryEditTarget): boolean {
  if (thread === null || !thread.turns?.some((turn: LatestTurn) => turn.turnId === target.witnessRunId && turn.state === 'rolled_back')) return false;
  return thread.providerThreads?.some((provider: RewindProviderThread) =>
    provider.lastRunOrdinal === (target.turnCount === 0 ? null : target.turnCount) &&
    (provider.id === target.providerThreadId || (target.turnCount === 0 && provider.ownerNodeId === null && provider.appThreadId === thread.id &&
      provider.providerInstanceId === target.providerInstanceId && !target.existingProviderThreads.includes(provider.id)))) === true;
}

export function recalledHistoryText(message: ChatMessage): string {
  if (message.text.trim().replace(/^Ultrathink:\s*/i, '') === '[User attached one or more files without additional text. Respond using the conversation context and the attached files.]') return '';
  return message.text.replace(/(\]\()t3-context:\/\/v1\/thread\/([a-z0-9_-]+)(?=\))/gi,
    (match: string, link: string, id: string): string => {
      const record = message.context?.records?.find((entry: MessageContextRecord) => entry.kind === 'thread' && entry.contextId === id);
      return record?.environmentId && record.threadId ? `${link}t3-thread://v2/${encodeURIComponent(record.environmentId)}/${encodeURIComponent(record.threadId)}` : match;
    });
}
