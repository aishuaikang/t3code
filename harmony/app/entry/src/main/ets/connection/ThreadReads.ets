import { DraftStore } from './DraftStore';
import { ThreadReadMark, ThreadReadTarget, threadReadKey, threadIsUnread } from '../model/ThreadReadState';

export class ThreadReads {
  private static store: DraftStore | null = null;
  private static marks: Record<string, ThreadReadMark> = {};
  private static pending: Promise<void> = Promise.resolve();
  private static version: number = 0;

  static async initialize(filesDir: string): Promise<void> {
    await ThreadReads.pending;
    const store = await DraftStore.open(filesDir, 'local', 'thread-read-marks');
    const raw = await store.load();
    const marks: Record<string, ThreadReadMark> = raw ? JSON.parse(raw) as Record<string, ThreadReadMark> : {};
    if (marks === null || typeof marks !== 'object' || Array.isArray(marks)) throw new Error('已读记录读取失败');
    for (const key of Object.keys(marks)) {
      const mark = marks[key];
      if (mark === null || typeof mark.revision !== 'string' || typeof mark.unread !== 'boolean') throw new Error('已读记录读取失败');
    }
    ThreadReads.store = store;
    ThreadReads.marks = marks;
    ThreadReads.publish();
  }

  static unread(environmentId: string, threadId: string, revision: string): boolean {
    return threadIsUnread(ThreadReads.marks[threadReadKey(environmentId, threadId)], revision);
  }

  static mark(environmentId: string, threadId: string, revision: string, unread: boolean = false): Promise<void> {
    return ThreadReads.update(environmentId, [{ threadId: threadId, revision: revision }], unread);
  }

  static markAll(environmentId: string, targets: ThreadReadTarget[]): Promise<void> {
    return ThreadReads.update(environmentId, targets, false);
  }

  private static update(environmentId: string, targets: ThreadReadTarget[], unread: boolean): Promise<void> {
    const next = ThreadReads.pending.then(async () => {
      if (ThreadReads.store === null) throw new Error('已读记录尚未就绪');
      const changed = targets.some((target: ThreadReadTarget) => {
        const mark = ThreadReads.marks[threadReadKey(environmentId, target.threadId)];
        return mark?.revision !== target.revision || mark?.unread !== unread;
      });
      if (!changed) return;
      const marks: Record<string, ThreadReadMark> = {};
      for (const existing of Object.keys(ThreadReads.marks)) marks[existing] = ThreadReads.marks[existing];
      for (const target of targets) {
        const key = threadReadKey(environmentId, target.threadId);
        marks[key] = { revision: target.revision, unread: unread };
      }
      await ThreadReads.store.save(JSON.stringify(marks));
      ThreadReads.marks = marks;
      ThreadReads.publish();
    });
    ThreadReads.pending = next.catch((error: Error) => { AppStorage.SetOrCreate('threadReadError', `已读状态保存失败：${error.message}`); });
    return next;
  }

  private static publish(): void {
    AppStorage.SetOrCreate('threadReadError', '');
    AppStorage.SetOrCreate('threadReadVersion', ++ThreadReads.version);
  }
}
