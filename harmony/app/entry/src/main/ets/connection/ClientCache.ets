import { DraftStore } from './DraftStore';
import { ChatMessage, ThreadActivity, ThreadDetail, ThreadShell, ShellSnapshot, ServerConfig, ModelChoice, availableModels } from '../model/Models';
import { ProviderCommandCatalog, commandCatalog } from '../model/ComposerCommands';

interface CachedEnvironment {
  version: number;
  environmentId: string;
  shell: ShellSnapshot | null;
  threadIds: string[];
  models: ModelChoice[];
  commands: ProviderCommandCatalog[];
}
interface LegacyCache extends CachedEnvironment { threads: ThreadDetail[]; }
interface CacheWrite { id: string; text: string; }

/** Read-only UI snapshots. They never restore a send queue or authorize an action. */
export class ClientCache {
  private static instances: Map<string, Promise<ClientCache>> = new Map();
  private store: DraftStore;
  private filesDir: string;
  private data: CachedEnvironment;
  private listedIds: Set<string> | null = null;
  private threads: Map<string, ThreadDetail> = new Map();
  private threadEpochs: Map<string, number> = new Map();
  private replacementPending: Set<string> = new Set();
  private dirty: Set<string> = new Set();
  private volatile: Set<string> = new Set();
  private persisted: Set<string> = new Set();
  private removed: Set<string> = new Set();
  private metadataDirty: boolean = false;
  private timer: number = -1;
  private volatileTimer: number = -1;
  private writing: Promise<void> | null = null;

  private constructor(store: DraftStore, filesDir: string, environmentId: string) {
    this.store = store; this.filesDir = filesDir;
    this.data = { version: 2, environmentId: environmentId, shell: null, threadIds: [], models: [], commands: [] };
  }

  static open(filesDir: string, environmentId: string): Promise<ClientCache> {
    const key = JSON.stringify([filesDir, environmentId]);
    const existing = ClientCache.instances.get(key);
    if (existing !== undefined) return existing;
    const opening = ClientCache.load(filesDir, environmentId);
    ClientCache.instances.set(key, opening);
    opening.catch(() => { ClientCache.instances.delete(key); });
    return opening;
  }

  private static validThread(thread: ThreadDetail): boolean {
    return typeof thread?.id === 'string' && Array.isArray(thread.messages);
  }
  private static async load(filesDir: string, environmentId: string): Promise<ClientCache> {
    const cache = new ClientCache(await DraftStore.open(filesDir, environmentId, 'read-cache-v1'), filesDir, environmentId);
    try {
      const raw = await cache.store.load();
      if (raw && raw.length <= 8 * 1024 * 1024) {
        const data = JSON.parse(raw) as LegacyCache;
        if (data.environmentId !== environmentId || !Array.isArray(data.models) || !Array.isArray(data.commands) ||
          !(data.shell === null || (Array.isArray(data.shell?.threads) && Array.isArray(data.shell?.projects)))) return cache;
        if (data.version === 2 && Array.isArray(data.threadIds) && data.threadIds.every((id: string) => typeof id === 'string')) {
          cache.data = { version: 2, environmentId: environmentId, shell: data.shell, models: data.models,
            commands: data.commands, threadIds: data.threadIds.slice(-8) };
          cache.persisted = new Set(cache.data.threadIds);
        } else if (data.version === 1 && Array.isArray(data.threads) && data.threads.every(ClientCache.validThread)) {
          cache.data.shell = data.shell; cache.data.models = data.models; cache.data.commands = data.commands;
          for (const thread of data.threads.slice(-8)) {
            cache.threads.set(thread.id, thread); cache.data.threadIds.push(thread.id); cache.dirty.add(thread.id);
          }
          cache.schedule();
        }
      }
    } catch (_) { /* A disposable read cache must not prevent a live connection. */ }
    return cache;
  }

  shell(): ShellSnapshot | null {
    return this.data.shell === null ? null : JSON.parse(JSON.stringify(this.data.shell)) as ShellSnapshot;
  }
  sideChats(parentId: string): ThreadShell[] {
    return (this.data.shell?.threads ?? []).filter(thread => !thread.archivedAt && thread.lineage?.sideChat === true &&
      thread.lineage.parentThreadId === parentId).sort((a, b) => (b.updatedAt ?? '').localeCompare(a.updatedAt ?? ''));
  }
  listsThread(id: string): boolean {
    if (!this.listedIds) this.listedIds = new Set((this.data.shell?.threads ?? []).filter(thread => !thread.archivedAt).map(thread => thread.id));
    return this.listedIds.has(id);
  }
  shellSequence(): number | undefined { return this.data.shell?.snapshotSequence; }
  async thread(threadId: string): Promise<ThreadDetail | null> {
    if (!this.data.threadIds.includes(threadId)) return null;
    let thread = this.threads.get(threadId);
    if (thread === undefined) {
      try {
        const store = await DraftStore.open(this.filesDir, this.data.environmentId, `read-thread-v2:${threadId}`);
        const raw = await store.load();
        if (raw && raw.length <= 8 * 1024 * 1024) {
          const loaded = JSON.parse(raw) as ThreadDetail;
          if (loaded.id === threadId && ClientCache.validThread(loaded) && this.data.threadIds.includes(threadId) && !this.threads.has(threadId)) this.threads.set(threadId, loaded);
        }
      } catch (_) {}
      thread = this.threads.get(threadId);
    }
    return thread === undefined ? null : JSON.parse(JSON.stringify(thread)) as ThreadDetail;
  }
  models(): ModelChoice[] { return this.data.models; }
  commands(): ProviderCommandCatalog[] { return this.data.commands; }

  setShell(snapshot: ShellSnapshot): void { this.data.shell = snapshot; this.listedIds = null; this.schedule(); }
  setCatalog(config: ServerConfig): void {
    this.data.models = availableModels(config.providers);
    this.data.commands = commandCatalog(config.providers);
    this.schedule();
  }
  threadEpoch(id: string): number { return this.threadEpochs.get(id) ?? 0; }
  threadSequence(id: string): number | null { return this.threads.get(id)?.syncSequence ?? null; }
  threadSnapshotEpoch(id: string, epoch: number, previous: number | null, sequence: number): number | null {
    const current = this.threadEpoch(id);
    if (epoch !== current) return null;
    if (previous === null || sequence >= previous) return current;
    // A server restored from backup has a new timeline. Outstanding pages belong to the old one.
    this.threadEpochs.set(id, current + 1); this.replacementPending.add(id);
    return current + 1;
  }
  setThread(thread: ThreadDetail, messages: ChatMessage[], activities: ThreadActivity[], checkpointCount: number,
    sequence: number | null = null, persist: boolean = true, epoch: number = 0): void {
    if (epoch !== this.threadEpoch(thread.id)) return;
    if (!this.replacementPending.has(thread.id) && (this.threads.get(thread.id)?.syncSequence ?? -1) > (sequence ?? -1)) return;
    this.replacementPending.delete(thread.id);
    const snapshot: ThreadDetail = {
      id: thread.id, title: thread.title, projectId: thread.projectId,
      runtimeMode: thread.runtimeMode, interactionMode: thread.interactionMode, modelSelection: thread.modelSelection,
      branch: thread.branch, worktreePath: thread.worktreePath, session: thread.session, latestTurn: thread.latestTurn,
      turns: thread.turns, syncSequence: sequence ?? undefined, lineage: thread.lineage, pullRequests: thread.pullRequests,
      creationSource: thread.creationSource, activeProviderThreadId: thread.activeProviderThreadId, rollbackFailure: thread.rollbackFailure,
      rewindCheckpoints: thread.rewindCheckpoints, providerThreads: thread.providerThreads, subagents: thread.subagents,
      transcriptVersion: thread.transcriptVersion,
      canonicalTimeline: thread.canonicalTimeline,
      historyCursor: thread.historyCursor, hasMoreHistory: thread.hasMoreHistory,
      messages: messages.slice(), activities: activities.slice(),
      checkpoints: checkpointCount > 0 ? [{ status: 'ready', checkpointTurnCount: checkpointCount }] : []
    };
    this.threads.set(thread.id, snapshot); this.removed.delete(thread.id);
    this.data.threadIds = this.data.threadIds.filter((id: string) => id !== thread.id).concat([thread.id]);
    while (this.data.threadIds.length > 8) {
      const id = this.data.threadIds.shift()!;
      this.threads.delete(id); this.dirty.delete(id); this.volatile.delete(id); this.removed.add(id);
    }
    if (persist) { this.dirty.add(thread.id); this.volatile.delete(thread.id); this.schedule(); }
    else {
      this.volatile.add(thread.id); this.dirty.delete(thread.id);
      if (this.volatileTimer === -1) this.volatileTimer = setTimeout(() => {
        this.volatileTimer = -1; this.flush();
      }, 5000);
    }
  }
  private schedule(): void {
    this.metadataDirty = true;
    if (this.timer !== -1) clearTimeout(this.timer);
    this.timer = setTimeout(() => { this.timer = -1; this.flush(false); }, 500);
  }
  async flush(force: boolean = true): Promise<void> {
    if (this.timer !== -1) clearTimeout(this.timer);
    this.timer = -1;
    if (force) {
      if (this.volatileTimer !== -1) clearTimeout(this.volatileTimer);
      this.volatileTimer = -1;
      this.volatile.forEach((id: string) => { this.dirty.add(id); }); this.volatile.clear();
    }
    const previous = this.writing ?? Promise.resolve();
    const operation = previous.catch(() => {}).then(async () => {
      if (this.metadataDirty || this.dirty.size > 0 || this.removed.size > 0) await this.writePending();
    });
    this.writing = operation;
    try { await operation; } catch (_) { /* Drafts and the send journal are independent. */ }
    finally { if (this.writing === operation) this.writing = null; }
  }
  private async writePending(): Promise<void> {
    const writes: CacheWrite[] = [];
    this.dirty.forEach((id: string) => {
      const thread = this.threads.get(id);
      if (thread === undefined) return;
      const text = JSON.stringify(thread);
      // Never truncate history while retaining its resume cursor.
      if (text.length > 8 * 1024 * 1024) { this.data.threadIds = this.data.threadIds.filter((entry: string) => entry !== id); this.threads.delete(id); writes.push({ id: id, text: '' }); }
      else writes.push({ id: id, text: text });
    });
    this.removed.forEach((id: string) => { writes.push({ id: id, text: '' }); });
    const metadata: CachedEnvironment = { version: 2, environmentId: this.data.environmentId, shell: this.data.shell,
      models: this.data.models, commands: this.data.commands,
      threadIds: this.data.threadIds.filter((id: string) => !this.volatile.has(id) || this.persisted.has(id)) };
    const manifest = JSON.stringify(metadata);
    this.dirty.clear(); this.removed.clear(); this.metadataDirty = false;
    try {
      for (const write of writes) {
        const store = await DraftStore.open(this.filesDir, this.data.environmentId, `read-thread-v2:${write.id}`);
        await store.save(write.text);
        if (write.text) this.persisted.add(write.id); else this.persisted.delete(write.id);
      }
      if (manifest.length <= 8 * 1024 * 1024) await this.store.save(manifest);
    } catch (error) {
      for (const write of writes) { if (this.threads.has(write.id)) this.dirty.add(write.id); else this.removed.add(write.id); }
      this.metadataDirty = true;
      throw new Error(String(error));
    }
  }
}
