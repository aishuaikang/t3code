import type { ModelSelection } from '../model/Models';
/** Effect layerJson transport. Keep envelopes aligned with RpcMessage.ts. */
import webSocket from '@ohos.net.webSocket';
import util from '@ohos.util';

export interface RpcExit {
  _tag: string;
  value?: object;
  cause?: object;
}

interface RemoteFailure {
  _tag: string;
  message?: string;
  detail?: string;
  cause?: RemoteFailureCause;
}
interface RemoteFailureCause { name?: string; _tag?: string; }
interface RpcFailureReason { _tag: string; error?: RemoteFailure; }

export class RpcRemoteError extends Error {
  remoteTag: string = '';
  definitivelyRejected: boolean = false;
  constructor(method: string, exit: RpcExit) {
    super(method === 'vcs.switchRef' ? '未能确认切换结果，请核对工作区当前分支。' : `RPC ${method}: ${JSON.stringify(exit.cause ?? exit)}`);
    if (!Array.isArray(exit.cause) || exit.cause.length !== 1) return;
    const reason = exit.cause[0] as RpcFailureReason;
    if (reason._tag !== 'Fail' || reason.error === undefined) return;
    const failure = reason.error;
    this.remoteTag = failure._tag;
    if (method === 'vcs.switchRef') {
      const detail = [failure.message ?? '', failure.detail ?? ''].map(value => value.trim().replace(/\s+/g, ' '))
        .find(value => value.length > 0 && !/^git checkout failed[.!]?$/i.test(value));
      if (detail) this.message = detail.length > 160 ? detail.slice(0, 159) + '…' : detail;
      else if (failure._tag === 'GitCommandError') this.message = 'Git 未能切换分支，请检查本地改动和目标分支。';
    } else if (failure.message) this.message = `${failure._tag}: ${failure.message}`;
    const rejectedV2 = ['OrchestratorCommandRejectedError', 'OrchestratorCommandPreviouslyRejectedError', 'OrchestratorProviderSelectionBusyError',
      'OrchestratorThreadAboveModeLimitError', 'OrchestratorRuntimeModeAboveCeilingError', 'OrchestratorSubagentThreadReadOnlyError',
      'OrchestratorThreadAlreadyExistsError', 'OrchestratorCommandIdConflictError'];
    const names = [failure.cause?.name ?? '', failure.cause?._tag ?? ''];
    // Normalizer rejects these before dispatch and exposes only a message on the wire.
    const message = failure.message ?? '';
    const rejectedAttachment = message.startsWith("Attachment '") &&
      (message.endsWith("' cannot be sent: attachment not found.") ||
        message.endsWith("' cannot be sent: attachment not found (removed or expired).") ||
        message.endsWith("' cannot be sent: stored size does not match.") ||
        message.endsWith("' cannot be sent: attachment type does not match the upload."));
    // Workspace validation runs before dispatch; legacy servers expose only its message.
    const rejectedWorkspace = message.startsWith('Workspace root does not exist: ') ||
      message.startsWith('Workspace root is not a directory: ') ||
      message.startsWith('Failed to create workspace root: ') ||
      /^Failed to stat workspace root '.+' during '(validate-existing|verify-created)'\.$/.test(message);
    const legacy = failure._tag === 'OrchestrationDispatchCommandError', v2 = failure._tag === 'OrchestrationV2DispatchCommandError';
    this.definitivelyRejected = failure._tag === 'EnvironmentAuthorizationError' ||
      ((legacy || v2) && (rejectedAttachment || rejectedWorkspace)) ||
      (v2 && names.some(name => rejectedV2.includes(name))) ||
      (legacy && names.some(name => name === 'OrchestrationCommandInvariantError' || name === 'OrchestrationCommandPreviouslyRejectedError'));
  }
}

export interface RpcMessage {
  _tag: string;
  requestId?: number;
  exit?: RpcExit;
  values?: object[];
}

interface RpcRequest {
  _tag: string;
  id: number;
  tag: string;
  payload: object;
  headers: string[][];
}

interface RpcControl {
  _tag: string;
  requestId?: number;
}

interface LocalCommand {
  type: string;
  commandId: string;
  threadId: string;
  createdBy?: string;
  creationSource?: string;
}

interface JournaledTurn extends LocalCommand {
  modelSelection?: ModelSelection;
  message: JournaledMessage;
  freshContext?: boolean;
  sideThreadId?: string;
  dispatchMode?: DispatchMode;
}
interface JournaledMessage { messageId: string; text: string; attachments: object[]; }
interface MessageDispatch extends LocalCommand {
  modelSelection?: ModelSelection;
  freshContext?: boolean;
  messageId: string;
  text: string;
  attachments: object[];
  dispatchMode: DispatchMode;
}
interface DispatchMode { type: string; targetRunId?: string; }

// Drafts and the send journal retain their original IDs and local format on retries.
function commandForWire(method: string, payload: object): object {
  if (method !== 'orchestration.dispatchCommand') return payload;
  const command = payload as LocalCommand;
  if (command.type === 'thread.create') {
    const create = JSON.parse(JSON.stringify(payload)) as LocalCommand;
    create.createdBy = 'user';
    create.creationSource = 'mobile';
    return create;
  }
  if (command.type === 'thread.turn.start') {
    const turn = payload as JournaledTurn;
    const dispatch: MessageDispatch = {
      type: 'message.dispatch', createdBy: 'user', creationSource: 'mobile',
      commandId: turn.commandId, threadId: turn.sideThreadId ?? turn.threadId,
      messageId: turn.message.messageId, text: turn.message.text,
      attachments: turn.message.attachments, dispatchMode: turn.dispatchMode ?? { type: 'start_immediately' }
    };
    if (turn.freshContext) dispatch.freshContext = true;
    if (turn.modelSelection !== undefined) dispatch.modelSelection = turn.modelSelection;
    return dispatch;
  }
  if (command.type === 'thread.approval.respond' || command.type === 'thread.user-input.respond') {
    const response = JSON.parse(JSON.stringify(payload)) as LocalCommand;
    response.type = 'runtime-request.respond';
    return response;
  }
  return payload;
}

export class EmptyPayload {}

// After a long suspension a live WebSocket does not prove its read subscriptions survived.
const RESUBSCRIBE_AFTER_SILENCE_MS: number = 5 * 60 * 1000;

export class RpcClient {
  private socket: webSocket.WebSocket | null = null;
  private connected: boolean = false;
  private nextRequestId: number = 0;
  private owner: RpcClient | null = null;
  private scopes: Set<RpcClient> = new Set();
  private pending: Map<number, (exit: RpcExit) => void> = new Map();
  private failures: Map<number, (error: Error) => void> = new Map();
  private streamHandlers: Map<number, (values: object[]) => void> = new Map();
  private pingTimer: number = -1;
  private probeTimer: number = -1;
  private foreground: boolean = true;
  private lastReceivedAt: number = 0;
  private connectTimer: number = -1;
  private rejectConnect: ((error: Error) => void) | null = null;

  isOpen(): boolean { return this.connected; }

  // Pages own their requests, while the environment owns the socket and heartbeat.
  openScope(): RpcClient | null {
    if (!this.connected || !this.foreground || this.owner !== null) return null;
    const scope = new RpcClient();
    scope.owner = this; scope.connected = true;
    this.scopes.add(scope);
    return scope;
  }

  async connect(socketUrl: string): Promise<void> {
    this.close();
    const socket = webSocket.createWebSocket();
    this.socket = socket;
    return new Promise<void>((resolve, reject) => {
      this.rejectConnect = reject;
      this.connectTimer = setTimeout(() => { if (this.socket === socket) this.close(); }, 10000);
      socket.on('open', () => {
        if (this.socket !== socket) return;
        clearTimeout(this.connectTimer);
        this.connectTimer = -1;
        this.rejectConnect = null;
        this.connected = true;
        this.startPinger();
        resolve();
      });
      socket.on('error', () => {
        if (this.socket !== socket) return;
        const error = new Error('RPC connection failed');
        this.close();
        reject(error);
      });
      socket.on('message', (_error, value) => {
        if (this.socket !== socket) return;
        if (typeof value === 'string') this.handleFrame(value);
        else this.handleFrame(util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(value)));
      });
      socket.on('close', () => {
        if (this.socket !== socket) return;
        this.close();
        reject(new Error('RPC connection closed'));
      });
      socket.connect(socketUrl, (error) => {
        if (this.socket !== socket) return;
        if (error) {
          this.close();
          reject(new Error('RPC connection failed'));
        }
      });
    });
  }

  setForeground(foreground: boolean): void {
    if (this.foreground === foreground) return;
    this.foreground = foreground;
    if (this.owner !== null) return;
    this.stopPinger();
    this.clearProbe();
    if (foreground && this.probe()) this.startPinger();
  }

  /** Probe the existing transport without replaying requests or replacing its streams. */
  probe(): boolean {
    if (!this.connected || !this.foreground) return false;
    if (this.owner !== null) return this.owner.probe();
    if (Date.now() - this.lastReceivedAt >= RESUBSCRIBE_AFTER_SILENCE_MS) {
      console.info('[T3Connection] Resuming subscriptions on a fresh socket after inactivity');
      this.close();
      return false;
    }
    if (this.probeTimer !== -1) return true;
    const socket = this.socket;
    this.lastReceivedAt = Date.now();
    this.probeTimer = setTimeout(() => { if (this.socket === socket) this.close(); }, 10000);
    try { this.send({ _tag: 'Ping' } as RpcControl); }
    catch (_) { this.close(); }
    return this.connected;
  }

  private clearProbe(): void {
    if (this.probeTimer !== -1) clearTimeout(this.probeTimer);
    this.probeTimer = -1;
  }

  private stopPinger(): void {
    if (this.pingTimer !== -1) clearInterval(this.pingTimer);
    this.pingTimer = -1;
  }

  private startPinger(): void {
    this.stopPinger();
    if (!this.foreground) return;
    const socket = this.socket;
    this.lastReceivedAt = Date.now();
    this.pingTimer = setInterval(() => {
      if (this.socket !== socket) return;
      if (Date.now() - this.lastReceivedAt >= 30000) {
        this.close();
        return;
      }
      const ping: RpcControl = { _tag: 'Ping' };
      this.send(ping);
    }, 5000);
  }

  private send(message: object): void {
    if (this.owner !== null) { this.owner.send(message); return; }
    const socket = this.socket;
    if (socket === null || !this.connected) {
      throw new Error('RPC is not connected');
    }
    socket.send(JSON.stringify(message)).then((sent: boolean) => {
      if (!sent && this.socket === socket) this.close();
    }).catch(() => { if (this.socket === socket) this.close(); });
  }

  private handleFrame(text: string): void {
    try {
      const decoded: object = JSON.parse(text);
      this.lastReceivedAt = Date.now();
      this.clearProbe();
      const messages = Array.isArray(decoded) ? decoded as object[] : [decoded];
      for (const message of messages) this.handleMessage(message as RpcMessage);
    } catch (_) {
      this.close();
    }
  }

  private handleMessage(message: RpcMessage): void {
    if (message._tag === 'Pong') {
      return;
    }
    const requestId = message.requestId;
    if (requestId === undefined) return;
    if (!this.pending.has(requestId)) {
      for (const scope of this.scopes) {
        if (!scope.pending.has(requestId)) continue;
        try { scope.handleMessage(message); } catch (_) { scope.close(); }
        break;
      }
      return;
    }
    if (message._tag === 'Exit' && message.exit !== undefined) {
      const resolver = this.pending.get(requestId);
      this.pending.delete(requestId);
      this.failures.delete(requestId);
      this.streamHandlers.delete(requestId);
      if (resolver !== undefined) resolver(message.exit);
    } else if (message._tag === 'Chunk') {
      const stream = this.streamHandlers.get(requestId);
      if (stream !== undefined) {
        stream(message.values ?? []);
        const ack: RpcControl = { _tag: 'Ack', requestId: requestId };
        if (this.streamHandlers.has(requestId)) this.send(ack);
      }
    }
  }

  call<T extends object>(method: string, payload: object): Promise<T> {
    return this.request<T>(method, payload, null);
  }

  async callStream(method: string, payload: object,
    onChunk: (values: object[]) => void): Promise<void> {
    await this.request<object>(method, payload, onChunk);
  }

  private request<T extends object>(method: string, payload: object,
    onChunk: ((values: object[]) => void) | null): Promise<T> {
    return new Promise<T>((resolve, reject) => {
      if (!this.connected) {
        reject(new Error('RPC is not connected'));
        return;
      }
      const requestId = this.owner !== null ? this.owner.nextRequestId++ : this.nextRequestId++;
      this.pending.set(requestId, (exit: RpcExit) => {
        if (exit._tag === 'Success') resolve(exit.value as T);
        else reject(new RpcRemoteError(method, exit));
      });
      this.failures.set(requestId, reject);
      if (onChunk !== null) this.streamHandlers.set(requestId, onChunk);
      const request: RpcRequest = {
        _tag: 'Request', id: requestId, tag: method, payload: commandForWire(method, payload), headers: []
      };
      try {
        this.send(request);
      } catch (_) {
        this.close();
      }
    });
  }

  close(): void {
    if (this.connectTimer !== -1) clearTimeout(this.connectTimer);
    this.connectTimer = -1;
    const rejectConnect = this.rejectConnect;
    this.rejectConnect = null;
    if (rejectConnect !== null) rejectConnect(new Error('RPC connection closed'));
    this.connected = false;
    if (this.owner !== null) {
      const owner = this.owner;
      this.owner = null; owner.scopes.delete(this);
      if (owner.connected) {
        try { for (const requestId of this.streamHandlers.keys()) owner.send({ _tag: 'Interrupt', requestId: requestId } as RpcControl); }
        catch (_) { owner.close(); }
      }
    }
    for (const scope of this.scopes) scope.close();
    this.stopPinger();
    this.clearProbe();
    for (const reject of this.failures.values()) reject(new Error('RPC connection closed'));
    this.failures.clear();
    this.pending.clear();
    this.streamHandlers.clear();
    const socket = this.socket;
    this.socket = null;
    if (socket !== null) {
      socket.off('message');
      socket.off('open');
      socket.off('error');
      socket.off('close');
      socket.close();
    }
  }
}
