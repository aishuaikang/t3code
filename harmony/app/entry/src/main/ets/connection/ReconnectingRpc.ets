import { RpcClient } from './Rpc';

/** Reopens read subscriptions only. Commands are never replayed. */
export class ReconnectingRpc {
  private static foreground: boolean = true;
  private static sessions: Set<ReconnectingRpc> = new Set();
  private open: () => Promise<RpcClient>;
  private subscribe: (rpc: RpcClient) => Promise<void>;
  private status: (state: string) => void;
  private onSyncRecovery: () => void;
  private generation: number = 0;
  private attempt: number = 0;
  private syncFailures: number = 0;
  private timer: number = -1;
  private syncTimer: number = -1;
  private openTimer: number = -1;
  private rpc: RpcClient | null = null;
  private started: boolean = false;
  private opening: boolean = false;
  private syncing: boolean = false;

  static setForeground(foreground: boolean): void {
    if (ReconnectingRpc.foreground === foreground) return;
    ReconnectingRpc.foreground = foreground;
    for (const session of ReconnectingRpc.sessions) session.foregroundChanged();
  }

  constructor(open: () => Promise<RpcClient>, subscribe: (rpc: RpcClient) => Promise<void>,
    status: (state: string) => void, onSyncRecovery: () => void = () => {}) {
    this.open = open;
    this.subscribe = subscribe;
    this.status = status;
    this.onSyncRecovery = onSyncRecovery;
  }

  start(): void {
    this.stop();
    this.started = true;
    ReconnectingRpc.sessions.add(this);
    this.attempt = 0;
    if (ReconnectingRpc.foreground) this.connect(this.generation);
  }

  resume(): void {
    if (!this.started) { this.start(); return; }
    if (!ReconnectingRpc.foreground || this.opening) return;
    if (this.rpc !== null && this.rpc.probe()) return;
    if (this.rpc !== null) this.retry(this.generation);
    this.clearRetry();
    this.attempt = 0;
    this.connect(this.generation);
  }

  private foregroundChanged(): void {
    this.rpc?.setForeground(ReconnectingRpc.foreground);
    if (!ReconnectingRpc.foreground) {
      this.clearRetry();
      this.clearOpenDeadline();
      this.clearSyncDeadline();
      return;
    }
    // A dial started on the previous network may still be suspended when the window returns.
    if (this.opening) this.retry(this.generation);
    if (this.syncing) this.watchSync();
    this.resume();
  }

  healthy(): void {
    this.attempt = 0;
    this.syncFailures = 0;
    this.syncing = false;
    this.clearSyncDeadline();
  }

  progress(): void {
    if (this.syncing) this.watchSync();
  }

  private clearRetry(): void {
    if (this.timer !== -1) clearTimeout(this.timer);
    this.timer = -1;
  }

  private clearSyncDeadline(): void {
    if (this.syncTimer !== -1) clearTimeout(this.syncTimer);
    this.syncTimer = -1;
  }

  private clearOpenDeadline(): void {
    if (this.openTimer !== -1) clearTimeout(this.openTimer);
    this.openTimer = -1;
  }

  private watchOpen(): void {
    this.clearOpenDeadline();
    if (!ReconnectingRpc.foreground) return;
    const generation = this.generation;
    this.openTimer = setTimeout(() => this.retry(generation), 30000);
  }

  private watchSync(): void {
    this.clearSyncDeadline();
    if (!ReconnectingRpc.foreground) return;
    const generation = this.generation;
    this.syncTimer = setTimeout(() => this.retry(generation, true), 30000);
  }

  stop(): void {
    this.generation++;
    this.started = false;
    this.opening = false;
    this.syncing = false;
    ReconnectingRpc.sessions.delete(this);
    this.syncFailures = 0;
    this.clearRetry();
    this.clearSyncDeadline();
    this.clearOpenDeadline();
    this.rpc?.close();
    this.rpc = null;
  }

  private async connect(generation: number): Promise<void> {
    if (generation !== this.generation || !this.started || !ReconnectingRpc.foreground) return;
    this.opening = true;
    this.status(this.attempt === 0 ? 'connecting' : 'reconnecting');
    this.watchOpen();
    let rpc: RpcClient | null = null;
    try {
      rpc = await this.open();
      if (generation !== this.generation) { rpc.close(); return; }
      this.clearOpenDeadline();
      this.opening = false;
      this.rpc = rpc;
      if (!ReconnectingRpc.foreground) rpc.setForeground(false);
      this.syncing = true;
      this.watchSync();
      await this.subscribe(rpc);
    } catch (_) {
      // Reopen the subscription; its owner resumes from the last applied event cursor.
    }
    this.retry(generation);
  }

  private retry(generation: number, recover: boolean = false): void {
    if (generation !== this.generation) return;
    // Retire the attempt before closing it; pending setup work may finish much later.
    this.generation++;
    const incomplete = this.syncing;
    this.opening = false;
    this.syncing = false;
    this.clearSyncDeadline();
    this.clearOpenDeadline();
    this.rpc?.close();
    this.rpc = null;
    if (recover) {
      this.syncFailures = 0;
      this.onSyncRecovery();
    } else if (incomplete) {
      this.syncFailures++;
      if (this.syncFailures >= 3) {
        this.syncFailures = 0;
        this.onSyncRecovery();
      }
    }
    this.status('reconnecting');
    if (!ReconnectingRpc.foreground) return;
    const delay = Math.min(250 * Math.pow(2, this.attempt), 15000);
    this.attempt = Math.min(this.attempt + 1, 6);
    const next = this.generation;
    this.timer = setTimeout(() => {
      this.timer = -1;
      if (next === this.generation) this.connect(next);
    }, delay);
  }
}
