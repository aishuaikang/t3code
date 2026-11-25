import { DraftStore } from './DraftStore';
import { StartTurnCommand } from '../model/Models';

export class ForwardJournal {
  pending: StartTurnCommand | null = null;
  private busy: boolean = false;
  private store: DraftStore;
  private sourceThreadId: string;
  private constructor(store: DraftStore, sourceThreadId: string) { this.store = store; this.sourceThreadId = sourceThreadId; }

  static async open(filesDir: string, environmentId: string, sourceThreadId: string): Promise<ForwardJournal> {
    const store = await DraftStore.open(filesDir, environmentId, `forward:${sourceThreadId}`);
    const journal = new ForwardJournal(store, sourceThreadId);
    const raw = await store.load();
    if (raw) {
      const command = JSON.parse(raw) as StartTurnCommand;
      journal.validate(command);
      journal.pending = command;
    }
    return journal;
  }

  private validate(command: StartTurnCommand): void {
    if (command.type !== 'thread.turn.start' || !command.threadId || command.threadId === this.sourceThreadId ||
      !command.commandId || !command.message?.messageId || command.message.role !== 'user' ||
      typeof command.message.text !== 'string' || !command.message.text.trim() || !Array.isArray(command.message.attachments) ||
      command.message.attachments.length > 8 || typeof command.runtimeMode !== 'string' ||
      command.dispatchMode?.type !== 'queue_after_active' || command.freshContext || command.sideThreadId) {
      throw new Error('转发记录无效，请保留当前记录');
    }
  }

  async submit(prepare: () => Promise<StartTurnCommand>, dispatch: (command: StartTurnCommand) => Promise<void>): Promise<void> {
    if (this.busy) throw new Error('正在转发，请稍候');
    this.busy = true;
    try {
      if (this.pending === null) {
        const command = await prepare();
        this.validate(command);
        await this.store.save(JSON.stringify(command));
        this.pending = command;
      }
      await dispatch(this.pending);
      await this.clear();
    } finally { this.busy = false; }
  }

  async clear(): Promise<void> { await this.store.save(''); this.pending = null; }
}
