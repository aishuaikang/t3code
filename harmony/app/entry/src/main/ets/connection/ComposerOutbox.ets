import { DraftStore } from './DraftStore';
import { EnvironmentSession } from './Environment';
import { RpcClient, RpcRemoteError } from './Rpc';
import { ModelSelection, ShellState, WS } from '../model/Models';

export interface ComposerSettingCommand {
  type: string; commandId: string; threadId: string; createdAt?: string;
  runtimeMode?: string; interactionMode?: string; modelSelection?: ModelSelection; branch?: string; worktreePath?: string | null;
}
interface Choice { command: ComposerSettingCommand; stage: boolean; attempted: boolean; }
interface Confirmed { command: ComposerSettingCommand; sequence: number; }
export interface ModelDraft { store: DraftStore; value: ModelSelection | null; writes?: Promise<void>; }
interface Link { filesDir: string; environmentId: string; rpc: RpcClient; shell: ShellState; }
interface Receipt { sequence: number; }

function validModel(value: ModelSelection | null): boolean {
  return value !== null && typeof value?.instanceId === 'string' && !!value.instanceId && typeof value.model === 'string' && !!value.model &&
    (value.options === undefined || (Array.isArray(value.options) && value.options.every(option => !!option && typeof option.id === 'string' &&
      (typeof option.value === 'boolean' || typeof option.value === 'string'))));
}
function validChoice(row: Choice): boolean {
  const c = row?.command;
  if (!c || typeof c.commandId !== 'string' || !c.commandId || typeof c.threadId !== 'string' || !c.threadId ||
    typeof row.stage !== 'boolean' || typeof row.attempted !== 'boolean') return false;
  if (c.type === 'thread.model-selection.set') return validModel(c.modelSelection ?? null);
  if (c.type === 'thread.runtime-mode.set') return ['full-access', 'approval-required', 'auto-accept-edits', 'auto'].includes(c.runtimeMode ?? '');
  return c.type === 'thread.interaction-mode.set' && ['default', 'plan'].includes(c.interactionMode ?? '');
}

/** One journal per environment. The home socket can deliver work even after the chat that queued it is gone. */
export class ComposerOutbox {
  private static boxes: Map<string, Promise<ComposerOutbox>> = new Map();
  private static link: Link | null = null;
  private filesDir: string;
  private environmentId: string;
  private journal: DraftStore;
  private queue: Choice[];
  private recoveredJournal: boolean = false;
  private running: Map<string, Choice> = new Map();
  private receiptEpoch: number = 0;
  private confirmed: Map<string, Confirmed[]> = new Map();
  private drafts: Map<string, Promise<ModelDraft>> = new Map();
  private listeners: Map<string, Set<() => void>> = new Map();
  private errors: Map<string, string> = new Map();

  private constructor(filesDir: string, environmentId: string, journal: DraftStore, queue: Choice[]) {
    this.filesDir = filesDir; this.environmentId = environmentId; this.journal = journal; this.queue = queue;
  }
  static open(filesDir: string, environmentId: string): Promise<ComposerOutbox> {
    const key = JSON.stringify([filesDir, environmentId]);
    const existing = ComposerOutbox.boxes.get(key);
    if (existing !== undefined) return existing;
    const opening = ComposerOutbox.load(filesDir, environmentId);
    ComposerOutbox.boxes.set(key, opening);
    opening.then(box => box.resume(), () => { ComposerOutbox.boxes.delete(key); });
    return opening;
  }
  private static async load(filesDir: string, environmentId: string): Promise<ComposerOutbox> {
    const store = await DraftStore.open(filesDir, environmentId, 'composer-settings-v1');
    const raw = await store.load();
    let rows: Choice[] | null = [];
    if (raw) { try { rows = JSON.parse(raw) as Choice[]; } catch (_) { rows = null; } }
    const queue: Choice[] = Array.isArray(rows) ? rows.filter(validChoice) : [];
    const box = new ComposerOutbox(filesDir, environmentId, store, queue);
    if (!Array.isArray(rows) || rows.length !== queue.length) {
      await box.persist(); box.recoveredJournal = true;
    }
    return box;
  }
  static connected(filesDir: string, environmentId: string, rpc: RpcClient, shell: ShellState, replacedHistory: boolean = false): void {
    ComposerOutbox.link = { filesDir: filesDir, environmentId: environmentId, rpc: rpc, shell: shell };
    ComposerOutbox.open(filesDir, environmentId).then(box => {
      if (replacedHistory) {
        box.receiptEpoch++; const ids = Array.from(box.confirmed.keys()); box.confirmed.clear();
        for (const id of ids) box.changed(id);
      }
      box.resume();
    }).catch(() => {});
  }
  static disconnected(rpc: RpcClient): void {
    if (ComposerOutbox.link?.rpc === rpc) ComposerOutbox.link = null;
  }
  private currentLink(): Link | null {
    const link = ComposerOutbox.link, current = EnvironmentSession.current;
    return link !== null && link.filesDir === this.filesDir && link.environmentId === this.environmentId &&
      current?.descriptor.environmentId === this.environmentId && current.rpc === link.rpc ? link : null;
  }
  private resume(): void {
    for (const id of new Set(this.queue.map(row => row.command.threadId))) this.flush(id);
  }
  watch(id: string, change: () => void): () => void {
    const listeners = this.listeners.get(id) ?? new Set<() => void>();
    this.listeners.set(id, listeners);
    listeners.add(change);
    return () => { listeners.delete(change); if (listeners.size === 0) this.listeners.delete(id); };
  }
  private changed(id: string): void { this.listeners.get(id)?.forEach(change => change()); }
  error(id: string): string { return this.errors.get(id) ?? ''; }
  private persist(): Promise<void> { return this.journal.save(this.queue.length ? JSON.stringify(this.queue) : ''); }
  pending(id: string): ComposerSettingCommand[] { return this.queue.filter(row => row.command.threadId === id).map(row => row.command); }
  receipts(id: string, sequence: number): ComposerSettingCommand[] {
    return (this.confirmed.get(id) ?? []).filter(entry => entry.sequence > sequence).map(entry => entry.command);
  }

  draft(id: string): Promise<ModelDraft> {
    const previous = this.drafts.get(id);
    if (previous !== undefined) return previous;
    const loading = this.readDraft(id);
    this.drafts.set(id, loading);
    loading.catch(() => { this.drafts.delete(id); });
    return loading;
  }
  private async readDraft(id: string): Promise<ModelDraft> {
    const store = await DraftStore.open(this.filesDir, this.environmentId, `model:${id}`);
    const raw = await store.load(); // I/O errors are retryable; only reset known bad contents.
    if (this.recoveredJournal && !this.errors.has(id)) this.errors.set(id, '已跳过损坏的待同步设置，请核对当前选择。消息和附件已保留。');
    let value: ModelSelection | null = null;
    if (raw) {
      try { value = JSON.parse(raw) as ModelSelection; } catch (_) {}
      if (!validModel(value)) {
        await store.save(''); value = null;
        this.errors.set(id, '模型草稿已损坏，已恢复为会话模型。消息和附件已保留。');
      }
    }
    return { store: store, value: value };
  }
  private writeDraft(id: string, draft: ModelDraft, next: ModelSelection | null, expected?: ModelSelection): Promise<void> {
    const write = (draft.writes ?? Promise.resolve()).then(async () => {
      if (expected !== undefined && JSON.stringify(draft.value) !== JSON.stringify(expected)) return;
      await draft.store.save(next === null ? '' : JSON.stringify(next));
      draft.value = next;
      this.changed(id);
    });
    draft.writes = write.catch(() => {});
    return write;
  }
  async consume(id: string, expected: ModelSelection): Promise<void> {
    await this.writeDraft(id, await this.draft(id), null, expected);
  }

  async enqueue(command: ComposerSettingCommand, stage: boolean): Promise<void> {
    const id = command.threadId;
    this.queue = this.queue.filter(row => row.command.threadId !== id || row.command.type !== command.type ||
      row.attempted || row === this.running.get(id));
    this.queue.push({ command: command, stage: stage, attempted: false });
    this.errors.delete(id); this.changed(id);
    try { await this.persist(); }
    catch (error) { this.failed(id, error instanceof Error ? error.message : String(error)); return; }
    await this.flush(id);
  }
  private failed(id: string, message: string): void {
    this.errors.set(id, `设置尚未同步，点此重试：${message}`); this.changed(id);
  }
  async flush(id: string): Promise<void> {
    if (this.running.has(id)) return;
    let link = this.currentLink();
    try {
      while (true) {
        const row = this.queue.find(entry => entry.command.threadId === id);
        link = this.currentLink();
        if (row === undefined || (link === null && !row.stage)) return;
        this.running.set(id, row);
        const command = row.command, pick = command.modelSelection;
        try {
          const draft = pick === undefined ? null : await this.draft(id);
          if (!row.stage && this.currentLink() !== link) return;
          const canonical = link === null ? undefined : this.receipts(id, link.shell.cursor() ?? -1)
            .find(c => c.modelSelection !== undefined)?.modelSelection ?? link.shell.threads.find(t => t.id === id)?.modelSelection;
          if (pick !== undefined && draft !== null && (row.stage || (!row.attempted && canonical?.instanceId !== pick.instanceId))) {
            try { await this.writeDraft(id, draft, pick); }
            catch (error) { this.errors.set(id, `模型选择未保存：${error instanceof Error ? error.message : String(error)}`); }
          } else {
            if (link === null) return;
            const cancelDraft = draft !== null && draft.value !== null;
            if (row.attempted || !pick || pick.model !== canonical?.model ||
              (JSON.stringify(pick) !== JSON.stringify(canonical) && !(cancelDraft && pick.options === undefined))) {
              row.attempted = true;
              await this.persist(); // Persist the exact id before handing a command to the socket.
              if (this.currentLink() !== link) return;
              const epoch = this.receiptEpoch;
              const receipt = await link.rpc.call<Receipt>(WS.threadStartTurn, command);
              if (this.receiptEpoch === epoch) {
                const entries = (this.confirmed.get(id) ?? []).filter(entry => entry.command.type !== command.type);
                entries.push({ command: command, sequence: receipt.sequence }); this.confirmed.set(id, entries);
              }
            }
            if (draft !== null && cancelDraft) await this.writeDraft(id, draft, null);
          }
        } catch (error) {
          if (!(error instanceof RpcRemoteError) || !error.definitivelyRejected) {
            this.failed(id, error instanceof Error ? error.message : String(error)); return;
          }
          this.errors.set(id, `设置被拒绝：${error.message}`);
        }
        if (this.errors.get(id)?.startsWith('设置尚未同步')) this.errors.delete(id);
        this.queue = this.queue.filter(entry => entry !== row);
        try { await this.persist(); }
        catch (error) { this.queue.unshift(row); throw new Error(error instanceof Error ? error.message : String(error)); }
        this.changed(id);
      }
    } catch (error) { this.failed(id, error instanceof Error ? error.message : String(error)); }
    finally {
      this.running.delete(id);
      if (this.currentLink() !== link && this.currentLink() !== null) this.flush(id);
    }
  }
}
