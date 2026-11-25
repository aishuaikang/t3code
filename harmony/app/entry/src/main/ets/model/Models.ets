/**
 * 数据模型与 WS 方法名（与 packages/contracts WS_METHODS 对齐，按需扩充）。
 * strict ArkTS：方法名集合用显式类常量（无 "as const"）。
 */

export class WS {
  static readonly serverGetConfig: string = 'server.getConfig';
  static readonly serverProbe: string = 'server.probe';
  static readonly threadsList: string = 'orchestration.subscribeShell';
  static readonly threadStartTurn: string = 'orchestration.dispatchCommand';
  static readonly threadFeed: string = 'orchestration.subscribeThread';
  static readonly projectsListEntries: string = 'projects.listEntries';
  static readonly sourceControlLookupRepository: string = 'sourceControl.lookupRepository';
}

export interface ThreadShell {
  creationSource?: string;
  delegatedFrom?: RemoteAgentThread | null;
  lineage?: ThreadLineage;
  pinnedAt?: string | null;
  pinOrderKey?: string | null;
  activeOrderKey?: string | null;
  unsettledAt?: string | null;
  createdAt?: string;
  pullRequests?: ThreadPullRequestLink[];
  status?: string;
  activeRunId?: string | null;
  latestRunId?: string | null;
  latestRunRequestedAt?: string | null;
  latestRunStartedAt?: string | null;
  latestRunCompletedAt?: string | null;
  activityRunStartedAt?: string | null;
  activityRunStatus?: string | null;
  pendingRuntimeRequest?: PendingRuntimeSummary | null;
  settledOverride?: string | null;
  latestTurn?: LatestTurn | null;
  modelSelection?: ModelSelection;
  runtimeMode?: string;
  interactionMode?: string;
  id: string;
  title: string | null;
  state?: string;
  projectId: string;
  archivedAt?: string | null;
  settledAt?: string | null;
  session?: ThreadSession | null;
  worktreePath?: string | null;
  branch?: string | null;
  updatedAt: string | null;
}

interface PendingRuntimeSummary { kind: string; }

export interface EnvironmentInfo {
  environmentId: string;
  label: string;
  capabilities: EnvironmentCapabilities;
}
export interface AttachmentLimits { maxUploadBytes: number; }
export interface EnvironmentCapabilities { attachmentUploads?: boolean; fileAttachments?: AttachmentLimits; sideChats?: boolean; questionAttachments?: boolean; serverBrowser?: boolean; threadStop?: boolean; threadPinning?: boolean; threadPinReorder?: boolean; threadActiveReorder?: boolean; projectSettingsOverrides?: boolean; }

export interface ServerConfig {
  environment: EnvironmentInfo;
  providers: ProviderInfo[];
  threadResumeCompletionMarker?: boolean;
  threadSnapshotPagination?: boolean;
  shellResumeCompletionMarker?: boolean;
  reasoningMessages?: boolean;
}

export interface ProjectEntry {
  name: string;
  path: string;
}

export interface SavedSshEnvironment {
  alias: string;
  hostname: string;
  port: number;
  username: string;
  t3PackageSpec: string;
}

export interface ThreadSession {
  status: string;
  activeTurnId?: string | null;
}

export interface ChatAttachment {
  type: string; id: string; name: string; mimeType: string; sizeBytes: number;
}

export interface ChatMessage {
  context?: MessageContext;
  modelSwitch?: ModelSwitch;
  scheduledTaskId?: string;
  inputIntent?: string;
  itemOrdinal?: number;
  sourceThreadId?: string;
  visibleInTimeline?: boolean;
  queueAutomatic?: boolean;
  queueGuest?: boolean;
  timelinePosition?: number;
  turnId?: string | null;
  updatedAt?: string;
  attachments?: ChatAttachment[];
  id: string;
  role: string;
  text: string;
  streaming: boolean;
  createdAt?: string;
}

export interface MessageContextRecord {
  kind: string;
  contextId: string;
  label: string;
  environmentId?: string;
  threadId?: string;
  title?: string;
}
export interface MessageContext { version?: number; guest?: object; records?: MessageContextRecord[]; }

export interface ActivityData {
  command?: string;
  imagePath?: string;
}

export interface HtmlRenderReference { attachmentId: string; title: string; height: number; heights?: number[][]; }

interface RemoteAgentThread { environmentId: string; threadId: string; label?: string; }
interface WorkflowPhase { index: number; title: string; }
export interface WorkflowAgent { index: number; label: string; state: string; childThreadId?: string; }
interface AgentWorkflow { name?: string; phases: WorkflowPhase[]; agents: WorkflowAgent[]; }
interface SubagentMetadata {
  workflow?: AgentWorkflow | null;
  driver?: string; providerInstanceId?: string; model?: string | null; modelSelection?: ModelSelection; remoteChild?: RemoteAgentThread;
  promptOmitted?: boolean; resultOmitted?: boolean;
}
export interface SubagentSummary extends SubagentMetadata {
  id: string; threadId: string; runId?: string | null; providerTurnId?: string | null;
  childThreadId?: string | null; origin?: string; title?: string | null; status: string;
  prompt?: string; progress?: string; result?: string | null;
  startedAt?: string | null; completedAt?: string | null; updatedAt: string;
}

export interface ActivityPayload {
  htmlRender?: HtmlRenderReference;
  subagent?: SubagentSummary;
  updatedAt?: string;
  message?: string;
  changedFiles?: ChangedFile[];
  responseMode?: string;
  itemType?: string;
  itemId?: string;
  threadId?: string;
  files?: string[];
  detailOmitted?: boolean;
  requestId?: string;
  requestKind?: string;
  requestType?: string;
  appName?: string;
  options?: ApprovalOption[];
  questions?: InputQuestion[];
  questionAnswer?: QuestionAnswerPayload;
  questionTextById?: Record<string, string>;
  answers?: Record<string, string | string[] | NestedInputAnswer>;
  attachmentsByQuestionId?: Record<string, ChatAttachment[]>;
  viewedImagePath?: string;
  toolCallId?: string;
  status?: string;
  detail?: string;
  title?: string;
  data?: ActivityData;
}

export interface ThreadActivity {
  tone?: string;
  visibleInTimeline?: boolean;
  itemOrdinal?: number;
  timelinePosition?: number;
  id: string;
  kind: string;
  summary: string;
  turnId?: string | null;
  createdAt: string;
  payload?: ActivityPayload | null;
}

export interface ApprovalOption {
  decision: string;
  label: string;
  warning?: string;
}

export interface InputOption {
  label: string;
  description: string;
  value?: string;
}

export interface InputQuestion {
  id: string;
  header: string;
  question: string;
  options: InputOption[];
  multiSelect?: boolean;
  allowCustomAnswer?: boolean;
  initialAnswer?: string;
}

interface NestedInputAnswer { answers?: string | string[]; }
interface QuestionAnswerPayload {
  requestId: string;
  questionTextById?: Record<string, string>;
  answers: Record<string, string | string[] | NestedInputAnswer>;
  attachmentsByQuestionId: Record<string, ChatAttachment[]>;
}

export interface AnswerDraft {
  questionId: string;
  selected: string[];
  custom: string;
}

export interface PendingRequest {
  approvalKind?: string;
  dismissible?: boolean;
  requestId: string;
  kind: string;
  title: string;
  detail: string;
  options: ApprovalOption[];
  questions: InputQuestion[];
}

function approvalKindFromType(type: string): string {
  switch (type) {
    case 'command_execution_approval': case 'exec_command_approval': case 'dynamic_tool_call': return 'command';
    case 'file_read_approval': return 'file-read';
    case 'file_change_approval': case 'apply_patch_approval': return 'file-change';
    case 'mcp_elicitation_approval': return 'mcp-elicitation';
    case 'permission_approval': return 'permission';
    default: return type;
  }
}

function approvalTitle(kind: string): string {
  switch (kind) {
    case 'command': return '运行命令';
    case 'file-read': return '读取文件';
    case 'file-change': return '修改文件';
    case 'permission': return '请求权限';
    case 'mcp-elicitation': return '工具请求';
    default: return kind || '操作授权';
  }
}

export function pendingRequests(activities: ThreadActivity[]): PendingRequest[] {
  const pending: Map<string, PendingRequest> = new Map();
  const sorted = activities.slice().sort((a: ThreadActivity, b: ThreadActivity) => a.createdAt.localeCompare(b.createdAt));
  for (const activity of sorted) {
    const payload = activity.payload;
    const id = payload?.requestId;
    if (!id) continue;
    if (activity.kind === 'approval.resolved' || activity.kind === 'user-input.resolved') {
      pending.delete(id);
      continue;
    }
    if (activity.kind === 'provider.approval.respond.failed' || activity.kind === 'provider.user-input.respond.failed') {
      const detail = (payload?.detail ?? '').toLowerCase();
      if (detail.includes('unknown pending') || detail.includes('stale pending')) pending.delete(id);
      continue;
    }
    if (activity.kind !== 'approval.requested' && activity.kind !== 'user-input.requested') continue;
    const questions: InputQuestion[] = [];
    if (Array.isArray(payload?.questions)) {
      for (const question of payload?.questions ?? []) {
        if (question === null || typeof question.id !== 'string' || typeof question.header !== 'string' ||
          typeof question.question !== 'string' || !Array.isArray(question.options)) continue;
        const parsed: InputQuestion = {
          id: question.id, header: question.header, question: question.question, multiSelect: question.multiSelect === true,
          allowCustomAnswer: question.allowCustomAnswer, initialAnswer: question.initialAnswer,
          options: question.options.filter((option: InputOption) => option !== null &&
            typeof option.label === 'string' && typeof option.description === 'string')
        };
        questions.push(parsed);
      }
    }
    if (activity.kind === 'user-input.requested' && questions.length === 0) continue;
    const decisions: string[] = ['accept', 'acceptForSession', 'acceptAlways', 'decline', 'cancel'];
    const supplied = Array.isArray(payload?.options) ? (payload?.options ?? []).filter((option: ApprovalOption) =>
      option !== null && decisions.includes(option.decision) && typeof option.label === 'string' && option.label.length > 0) : [];
    const options: ApprovalOption[] = supplied.length > 0 ? supplied : [
      { decision: 'accept', label: '允许本次' },
      { decision: 'acceptForSession', label: '允许本会话' },
      { decision: 'decline', label: '拒绝' }
    ];
    const request: PendingRequest = {
      requestId: id, kind: activity.kind === 'approval.requested' ? 'approval' : 'input',
      title: payload?.appName ?? payload?.requestKind ?? payload?.requestType ?? '需要你的回答',
      detail: payload?.detail ?? '', options: options, questions: questions, dismissible: payload?.responseMode === 'message'
    };
    if (request.kind === 'approval') {
      request.approvalKind = approvalKindFromType(payload?.requestKind || payload?.requestType || '');
      request.title = payload?.appName?.trim() || approvalTitle(request.approvalKind);
    }
    pending.set(id, request);
  }
  const result: PendingRequest[] = [];
  pending.forEach((request: PendingRequest) => { result.push(request); });
  return result;
}

export function questionAnswers(questions: InputQuestion[], drafts: AnswerDraft[], attachments: Record<string, ChatAttachment[]> = {}): Record<string, string | string[]> | null {
  const answers: Record<string, string | string[]> = {};
  for (const question of questions) {
    const draft = drafts.find((entry: AnswerDraft) => entry.questionId === question.id);
    if (question.allowCustomAnswer !== false && draft?.custom.trim()) answers[question.id] = draft.custom.trim();
    else if (draft !== undefined && draft.selected.length > 0) {
      answers[question.id] = question.multiSelect ? draft.selected : draft.selected[0];
    } else if (question.allowCustomAnswer !== false && (attachments[question.id]?.length ?? 0) > 0) answers[question.id] = '';
    else return null;
  }
  return answers;
}

export interface ViewedImage { path: string; threadId: string; }

export interface TimelineRow {
  htmlRender?: HtmlRenderReference;
  originalImageHref?: string;
  subagents?: SubagentSummary[];
  context?: MessageContext;
  modelSwitch?: ModelSwitch;
  automationPreview?: string;
  tone?: string;
  answerPreview?: string;
  changedFiles?: ChangedFile[];
  checkpointTurnCount?: number;
  itemOrdinal?: number;
  icon?: string;
  delivery?: string;
  groupCount?: number;
  timelinePosition?: number;
  itemType?: string;
  viewedImagePath?: string;
  viewedImages?: ViewedImage[];
  itemId?: string;
  sourceThreadId?: string;
  files?: string[];
  detailOmitted?: boolean;
  turnId?: string | null;
  updatedAt?: string;
  streaming?: boolean;
  depth?: number;
  attachments?: ChatAttachment[];
  id: string;
  kind: string;
  role: string;
  text: string;
  detail: string;
  status: string;
  createdAt: string;
}

// Retain unchanged row objects so a resumed feed does not reset images or Markdown views.
export function reconcileTranscriptRows(previous: TimelineRow[], next: TimelineRow[]): TimelineRow[] {
  const existing: Map<string, TimelineRow> = new Map(previous.map((row: TimelineRow) => [row.id, row]));
  return next.map((row: TimelineRow) => {
    const old = existing.get(row.id);
    if (old === undefined || old.kind !== row.kind || old.role !== row.role || old.text !== row.text ||
      old.detail !== row.detail || old.status !== row.status || old.createdAt !== row.createdAt ||
      old.turnId !== row.turnId || old.updatedAt !== row.updatedAt || old.streaming !== row.streaming ||
      old.depth !== row.depth || old.delivery !== row.delivery || old.groupCount !== row.groupCount ||
      old.timelinePosition !== row.timelinePosition || old.itemType !== row.itemType || old.itemId !== row.itemId ||
      old.sourceThreadId !== row.sourceThreadId || old.detailOmitted !== row.detailOmitted ||
      old.icon !== row.icon || old.viewedImagePath !== row.viewedImagePath || old.itemOrdinal !== row.itemOrdinal ||
      old.answerPreview !== row.answerPreview || old.automationPreview !== row.automationPreview || old.tone !== row.tone ||
      old.originalImageHref !== row.originalImageHref) return row;
    if (old.checkpointTurnCount !== row.checkpointTurnCount || JSON.stringify(old.changedFiles) !== JSON.stringify(row.changedFiles)) return row;
    if (old.attachments !== row.attachments && JSON.stringify(old.attachments) !== JSON.stringify(row.attachments)) return row;
    if (old.context !== row.context && JSON.stringify(old.context) !== JSON.stringify(row.context)) return row;
    if (old.modelSwitch !== row.modelSwitch && JSON.stringify(old.modelSwitch) !== JSON.stringify(row.modelSwitch)) return row;
    if (old.viewedImages !== row.viewedImages && JSON.stringify(old.viewedImages) !== JSON.stringify(row.viewedImages)) return row;
    if (old.files !== row.files && JSON.stringify(old.files) !== JSON.stringify(row.files)) return row;
    if (old.htmlRender !== row.htmlRender && JSON.stringify(old.htmlRender) !== JSON.stringify(row.htmlRender)) return row;
    if (old.subagents !== row.subagents && JSON.stringify(old.subagents) !== JSON.stringify(row.subagents)) return row;
    return old;
  });
}

function inputAnswerText(value: string | string[] | NestedInputAnswer | undefined, options: InputOption[]): string {
  if (typeof value === 'string') return options.find((option: InputOption) => option.value === value)?.label ?? value;
  if (Array.isArray(value)) return value.map((entry: string) => inputAnswerText(entry, options)).join(', ');
  return value === undefined || value === null ? '' : inputAnswerText(value.answers, options);
}

function runtimeNoticeLabel(message: string): string {
  if (message === 'Cancelled because the server restarted before the provider work completed.') return '服务重启，任务执行已中断';
  if (message === 'T3 Code restarted and resumed this turn') return 'T3 Code 已重启并恢复此轮任务';
  if (message === 'Resumed thread') return '会话已恢复';
  const mcp = /^MCP client for `([^`]+)` failed to start:/.exec(message);
  return mcp === null ? message : `MCP「${mcp[1]}」启动失败`;
}

function automationMessageText(message: ChatMessage): string | undefined {
  if (message.role !== 'user' || message.queueGuest || message.context?.guest !== undefined) return undefined;
  if (message.scheduledTaskId) return message.text;
  if (!/^scheduled-task-message:.+:\d+:(?:scheduled|manual)$/.test(message.id)) return undefined;
  const prefix = /^\[Triggered by schedule task: [^\r\n]+\]\r?\n\r?\n/.exec(message.text);
  return prefix === null ? undefined : message.text.slice(prefix[0].length);
}

// The mobile transcript carries provider source IDs without a URL. Keep the stored message and Markdown code intact.
function assistantDisplayText(text: string): string {
  if (!text.includes('\uE200')) return text;
  const tokens = /^ {0,3}(`{3,}(?!`)(?=[^`\r\n]*\r?$)|~{3,})([^\r\n]*)|^(?: {4}|\t)[^\r\n]*|(`+)|\uE200(cite(?:\uE202turn\d+[a-z]+\d+)+\uE201|[a-z0-9\uE202]*(?![\s\S]))/gm;
  const codeEnd = /`+|\r?\n[ \t]*\r?\n/g;
  let fence = '', start = 0;
  const parts: string[] = [];
  let token = tokens.exec(text);
  while (token !== null) {
    if (token[1]) {
      if (fence) {
        if (token[1][0] === fence[0] && token[1].length >= fence.length && !token[2].trim()) fence = '';
      } else { fence = token[1]; }
    } else if (!fence && token[3] && text.charAt(token.index - 1) !== '\\') {
      // A lone backtick in prose does not start a code span.
      codeEnd.lastIndex = tokens.lastIndex;
      let close = codeEnd.exec(text);
      while (close !== null && close[0][0] === '`') {
        if (close[0] === token[3]) { tokens.lastIndex = codeEnd.lastIndex; break; }
        close = codeEnd.exec(text);
      }
    } else if (!fence && token[4] !== undefined && ('cite'.startsWith(token[4]) || token[4].startsWith('cite\uE202'))) {
      let end = token.index;
      const next = text.charAt(tokens.lastIndex);
      if (end > start && text[end - 1] === ' ' && (!next || /[\s.,;:!?，。；：！？、]/.test(next))) end--;
      parts.push(text.slice(start, end)); start = tokens.lastIndex;
    }
    token = tokens.exec(text);
  }
  return parts.length ? parts.join('') + text.slice(start) : text;
}

export function threadTimeline(messages: ChatMessage[], activities: ThreadActivity[], activeTurnId: string | null,
  liveSubagents: SubagentSummary[] = []): TimelineRow[] {
  const questions: Map<string, TimelineRow> = new Map();
  const foldedAnswers: Set<string> = new Set();
  const ordered = activities.filter((activity: ThreadActivity) => activity.visibleInTimeline !== false)
    .sort((a: ThreadActivity, b: ThreadActivity) => a.createdAt.localeCompare(b.createdAt));
  for (const activity of ordered) {
    const payload = activity.payload;
    if (!activity.kind.startsWith('user-input.') || !payload?.requestId) continue;
    const previous = questions.get(payload.requestId);
    const answer = payload.questionAnswer;
    const texts: Record<string, string> = answer?.questionTextById ?? payload.questionTextById ?? {};
    for (const question of payload.questions ?? []) texts[question.id] = question.question;
    const answers = answer?.answers ?? payload.answers ?? {};
    const attachmentsByQuestionId = answer?.attachmentsByQuestionId ?? payload.attachmentsByQuestionId ?? {};
    const attachments: ChatAttachment[] = [];
    for (const id of Object.keys(attachmentsByQuestionId)) attachments.push(...attachmentsByQuestionId[id]);
    const answered = Object.keys(answers).length > 0 || attachments.length > 0;
    if (answered) foldedAnswers.add(`async-answer:${payload.requestId}`);
    const answerTexts = Object.keys(answers).map((id: string) => inputAnswerText(answers[id],
      payload.questions?.find((question: InputQuestion) => question.id === id)?.options ?? [])).filter((text: string) => !!text);
    const answerPreview = (answerTexts.length > 0 ? answerTexts.join(' · ') :
      attachments.map((attachment: ChatAttachment) => attachment.name).join(', ')).replace(/\s+/g, ' ').trim();
    const detail = Object.keys(texts).map((id: string) => {
      const options = payload.questions?.find((question: InputQuestion) => question.id === id)?.options ?? [];
      return [texts[id], inputAnswerText(answers[id], options),
        ...(attachmentsByQuestionId[id] ?? []).map((attachment: ChatAttachment) => attachment.name)].filter((part: string) => !!part).join('\n');
    }).join('\n\n');
    if (!detail && previous === undefined) continue;
    questions.set(payload.requestId, { id: `question:${payload.requestId}`, kind: 'question', role: '', icon: 'chat',
      text: Object.keys(texts).map((id: string) => texts[id]).join(' · ') || previous?.text || activity.summary,
      answerPreview: answerPreview || previous?.answerPreview || '',
      detail: detail || previous?.detail || '', status: answered || previous?.status === '已回答' ? '已回答' : activity.kind === 'user-input.requested' ? '待回答' : '已关闭',
      createdAt: previous?.createdAt ?? activity.createdAt, timelinePosition: previous?.timelinePosition ?? activity.timelinePosition,
      itemOrdinal: previous?.itemOrdinal ?? activity.itemOrdinal, sourceThreadId: payload.threadId,
      turnId: activity.turnId, attachments: attachments.length > 0 ? attachments : previous?.attachments ?? [] });
  }
  const rows: TimelineRow[] = messages.filter((message: ChatMessage) => message.visibleInTimeline !== false && !foldedAnswers.has(message.id)).map((message: ChatMessage): TimelineRow => {
    const automationText = automationMessageText(message);
    return { id: message.id, kind: message.role === 'reasoning' ? 'thinking' : 'message', role: message.role,
      text: automationText ?? (message.role === 'assistant' ? assistantDisplayText(message.text) : message.text),
      automationPreview: automationText === undefined ? undefined : automationText.trim().split(/\r?\n/, 1)[0] || message.attachments?.[0]?.name || '',
      turnId: message.turnId, updatedAt: message.updatedAt, streaming: message.streaming, context: message.context,
      modelSwitch: message.role === 'user' ? message.modelSwitch : undefined, timelinePosition: message.timelinePosition,
      itemOrdinal: message.itemOrdinal, sourceThreadId: message.sourceThreadId,
      detail: '', status: '', createdAt: message.createdAt ?? '', attachments: message.attachments ?? [] };
  }).filter((row: TimelineRow) => !!row.text.trim() || (row.attachments?.length ?? 0) > 0);
  const tools: Map<string, TimelineRow> = new Map();
  const agents = new Map<string, SubagentSummary>(liveSubagents.map((agent: SubagentSummary) => [agent.id, agent]));
  for (const activity of ordered) {
    const runtime = ['runtime.warning', 'runtime.error', 'runtime.info'].includes(activity.kind);
    if (!activity.kind.startsWith('tool.') && !activity.kind.startsWith('timeline.') && !runtime) continue;
    if (activity.kind === 'runtime.warning' && activity.summary.endsWith('(no displayable text content)')) continue;
    const payload = activity.payload;
    const notice = runtime || ['system_notice', 'notification', 'error', 'run_interrupt_request', 'run_interrupt_result'].includes(payload?.itemType ?? '');
    const tone = notice ? activity.tone ?? (activity.kind === 'runtime.error' ? 'error' : activity.kind === 'runtime.info' ? 'info' : 'warning') : undefined;
    const id = `tool:${activity.turnId ?? ''}:${payload?.toolCallId ?? activity.id}`;
    const existing = tools.get(id);
    const status = payload?.status ?? activity.kind;
    const subagent = payload?.subagent;
    const row: TimelineRow = {
      id: id, kind: subagent ? 'subagents' : payload?.htmlRender ? 'html-render' : notice ? 'notice' : activity.kind.startsWith('tool.') ? 'tool' : 'activity', role: 'tool', turnId: activity.turnId,
      htmlRender: payload?.htmlRender,
      subagents: subagent ? [mergeSubagent(subagent, agents.get(subagent.id))] : undefined,
      tone: tone, icon: notice ? tone === 'success' ? 'check' : tone === 'info' ? 'info' : 'warning' : undefined,
      itemType: payload?.itemType, itemId: payload?.itemId, sourceThreadId: payload?.threadId,
      files: payload?.files, detailOmitted: payload?.detailOmitted,
      changedFiles: payload?.changedFiles,
      viewedImagePath: payload?.viewedImagePath ?? payload?.data?.imagePath,
      timelinePosition: activity.timelinePosition,
      itemOrdinal: activity.itemOrdinal,
      text: notice ? payload?.title ?? runtimeNoticeLabel(payload?.message ?? payload?.detail ?? activity.summary) :
        payload?.data?.command ?? existing?.text ?? payload?.title ?? activity.summary,
      detail: payload?.detail ?? payload?.message ?? existing?.detail ?? (notice ? activity.summary : ''),
      status: activity.turnId !== activeTurnId && status === 'inProgress' ? '未收到完成状态' : status,
      createdAt: existing?.createdAt ?? activity.createdAt
    };
    tools.set(id, row);
  }
  tools.forEach((row: TimelineRow) => { rows.push(row); });
  questions.forEach((row: TimelineRow) => { rows.push(row); });
  rows.sort((left: TimelineRow, right: TimelineRow) => {
    if (left.sourceThreadId && left.sourceThreadId === right.sourceThreadId && left.itemOrdinal !== undefined && right.itemOrdinal !== undefined) {
      return left.itemOrdinal - right.itemOrdinal;
    }
    return left.timelinePosition !== undefined && right.timelinePosition !== undefined ?
      left.timelinePosition - right.timelinePosition : left.createdAt.localeCompare(right.createdAt);
  });
  const grouped: TimelineRow[] = [];
  for (const row of rows) {
    const previous = grouped[grouped.length - 1];
    const agent = row.subagents?.[0];
    if (agent && previous?.subagents && previous.turnId === row.turnId && previous.sourceThreadId === row.sourceThreadId &&
      previous.subagents[0].providerTurnId === agent.providerTurnId) {
      if (!previous.subagents.some((entry: SubagentSummary) => entry.id === agent.id)) previous.subagents.push(agent);
    } else grouped.push(row);
  }
  return grouped;
}

function compactSubagent(agent: SubagentSummary): SubagentSummary {
  const w = agent.workflow;
  const progress = agent.progress?.trim(), result = agent.result?.trim();
  const workflow: AgentWorkflow | null = w ? { name: w.name, phases: (w.phases ?? []).map((p: WorkflowPhase): WorkflowPhase => ({ index: p.index, title: p.title })),
    agents: (w.agents ?? []).map((a: WorkflowAgent): WorkflowAgent => ({ index: a.index, label: a.label, state: a.state, childThreadId: a.childThreadId })) } : null;
  return { workflow: workflow, id: agent.id, threadId: agent.threadId, runId: agent.runId, providerTurnId: agent.providerTurnId,
    childThreadId: agent.childThreadId, remoteChild: agent.remoteChild, origin: agent.origin, title: agent.title?.slice(0, 160), status: agent.status,
    driver: agent.driver, providerInstanceId: agent.providerInstanceId, model: agent.model ?? null, modelSelection: agent.modelSelection,
    prompt: agent.promptOmitted ? undefined : agent.prompt?.trim().slice(0, 260), progress: agent.status === 'failed' && !result ? progress : progress?.slice(0, 260),
    result: agent.resultOmitted ? undefined : agent.result === null ? null : agent.status === 'failed' ? result : result?.slice(0, 260),
    startedAt: agent.startedAt, completedAt: agent.completedAt, updatedAt: agent.updatedAt };
}

function mergeSubagent(item: SubagentSummary, live: SubagentSummary | undefined): SubagentSummary {
  if (!live || live.threadId !== item.threadId) return item;
  const latest = Date.parse(live.updatedAt) < Date.parse(item.updatedAt) ? item : live;
  const other = latest === item ? live : item;
  return { workflow: latest.workflow ?? other.workflow ?? null, id: latest.id, threadId: latest.threadId, runId: latest.runId ?? other.runId, providerTurnId: latest.providerTurnId ?? other.providerTurnId,
    childThreadId: latest.childThreadId ?? other.childThreadId, remoteChild: latest.remoteChild ?? other.remoteChild, origin: latest.origin ?? other.origin,
    title: latest.title || other.title, driver: latest.driver ?? other.driver, providerInstanceId: latest.providerInstanceId ?? other.providerInstanceId,
    model: latest.model ?? other.model ?? null, modelSelection: latest.modelSelection ?? other.modelSelection,
    status: latest.status, prompt: latest.prompt || other.prompt, progress: latest.progress ?? other.progress, result: latest.result === undefined ? other.result : latest.result,
    startedAt: latest.startedAt ?? other.startedAt, completedAt: latest.completedAt ?? other.completedAt, updatedAt: latest.updatedAt };
}

export function subagentPreview(agent: SubagentSummary): string {
  const detail = subagentActive(agent.status) || agent.status === 'idle' ? agent.progress || agent.result : agent.result || agent.progress;
  if (agent.status === 'failed' && /^(?:unexpected status\s+|HTTP(?:\/[\d.]+)?\s+)?503\s+Service Unavailable\b/i.test(detail?.trim() ?? '')) return '服务暂时不可用（503）';
  return assistantDisplayText((detail ?? '').slice(0, 260)).replace(/\s+/g, ' ').trim();
}

export function subagentTitle(agent: SubagentSummary): string {
  return subagentDisplayTitle(agent.title || agent.workflow?.name || agent.prompt || '子代理');
}

export function subagentDisplayTitle(value: string, taskTitle: string = ''): string {
  const title = value.replace(/^Subagent:\s*/i, '');
  const path = /^\/root\/(?:[^/]+\/)*([^/]+)\/?$/.exec(title);
  return path ? (taskTitle && !taskTitle.startsWith('/root/') ? taskTitle : path[1].replace(/_/g, ' ')) : title;
}

export function turnSubagents(thread: ThreadDetail | null, activities: ThreadActivity[]): SubagentSummary[] {
  if (!thread) return [];
  const agents = new Map<string, SubagentSummary>();
  for (const activity of activities) {
    const agent = activity.payload?.subagent;
    if (agent?.threadId === thread.id && activity.visibleInTimeline !== false) agents.set(agent.id, mergeSubagent(agent, agents.get(agent.id)));
  }
  for (const agent of thread.subagents ?? []) {
    if (agent.threadId === thread.id) agents.set(agent.id, mergeSubagent(agents.get(agent.id) ?? agent, agent));
  }
  if (!agents.size) return [];
  const turns = thread.turns ?? [], rolledBack = new Set(turns.filter(turn => turn.state === 'rolled_back').map(turn => turn.turnId));
  const eligible = Array.from(agents.values()).filter(agent => !rolledBack.has(agent.runId ?? ''));
  if (!eligible.length) return [];
  const last = turns.filter(turn => turn.startedAt && !rolledBack.has(turn.turnId)).sort((a, b) => (b.ordinal ?? 0) - (a.ordinal ?? 0))[0];
  const latest = last?.turnId ?? (thread.latestTurn?.state === 'queued' ? null : thread.latestTurn?.turnId);
  const runId = thread.session?.activeTurnId ?? latest ?? eligible.reduce((a, b) => Date.parse(a.updatedAt) >= Date.parse(b.updatedAt) ? a : b).runId;
  return eligible.filter(agent => agent.runId === runId || subagentActive(agent.status) || agent.workflow != null).sort((a, b) =>
    Date.parse(a.startedAt ?? a.updatedAt) - Date.parse(b.startedAt ?? b.updatedAt) || a.id.localeCompare(b.id));
}

export function subagentPillLabel(agents: SubagentSummary[]): string {
  const live = agents.filter(agent => subagentActive(agent.status)).length;
  if (live) return `${live}/${agents.length}`;
  const ended = agents.filter(agent => ['completed', 'failed', 'cancelled', 'interrupted'].includes(agent.status)).length;
  return ended === agents.length ? `${ended} 个已结束` : `${agents.length} 个代理`;
}

export interface Checkpoint {
  checkpointTurnCount: number;
  status: string;
}

export interface RewindCheckpoint {
  id: string; scopeId: string; appRunOrdinal: number | null; ordinalWithinScope: number; status: string;
}
export interface RewindProviderThread {
  id: string; appThreadId: string | null; ownerNodeId: string | null; providerInstanceId: string; lastRunOrdinal: number | null;
  status?: string; firstRunOrdinal?: number | null; nativeThreadRef?: object | null; providerSessionId?: string | null;
}
interface RollbackFailure { requestId: string; message: string; }

function rewindCheckpoint(checkpoint: RewindCheckpoint): RewindCheckpoint {
  return { id: checkpoint.id, scopeId: checkpoint.scopeId, appRunOrdinal: checkpoint.appRunOrdinal,
    ordinalWithinScope: checkpoint.ordinalWithinScope, status: checkpoint.status };
}

export interface LatestTurn {
  turnId: string;
  state: string;
  userMessageId?: string;
  ordinal?: number;
  queuePosition?: number | null;
  queueHeld?: boolean;
  freshContext?: boolean;
  requestedAt?: string;
  startedAt?: string | null;
  completedAt?: string | null;
  assistantMessageId?: string | null;
}

function durationLabel(from: string, to: string): string | null {
  const seconds = Math.max(0, Math.round((Date.parse(to) - Date.parse(from)) / 1000));
  if (!Number.isFinite(seconds)) return null;
  return seconds < 60 ? `${seconds}s` : seconds < 3600 ? `${Math.floor(seconds / 60)}m ${seconds % 60}s` :
    `${Math.floor(seconds / 3600)}h ${Math.floor(seconds % 3600 / 60)}m ${seconds % 60}s`;
}

export function workDuration(turn: LatestTurn | null, now: string): string {
  if (turn === null) return '';
  const duration = durationLabel(turn.startedAt ?? turn.requestedAt ?? '', turn.completedAt ?? now);
  if (duration === null) return '';
  const prefix = turn.state === 'interrupted' || turn.state === 'cancelled' ? '已中断 · ' :
    turn.state === 'error' || turn.state === 'failed' ? '异常 · ' : '';
  return `${prefix}工作了 ${duration}`;
}

export function subagentActive(status: string): boolean { return ['running', 'pending', 'waiting'].includes(status); }

export function subagentElapsed(agents: SubagentSummary[], now: number): string {
  let start = Number.MAX_VALUE, end = 0;
  for (const agent of agents) {
    const from = Date.parse(agent.startedAt ?? '');
    const to = subagentActive(agent.status) ? now : Date.parse(agent.completedAt ?? agent.updatedAt);
    if (Number.isFinite(from) && Number.isFinite(to)) { start = Math.min(start, from); end = Math.max(end, to); }
  }
  return start === Number.MAX_VALUE ? '' : durationLabel(new Date(start).toISOString(), new Date(end).toISOString()) ?? '';
}

function toolImages(rows: TimelineRow[]): ViewedImage[] {
  const images: ViewedImage[] = [];
  const seen: Set<string> = new Set();
  for (const row of rows) {
    const read = row.itemType === 'image_view' || (row.itemType === 'dynamic_tool' && row.text.trim().toLowerCase() === 'read file');
    const path = (row.viewedImagePath ?? (read ? row.detail : '')).trim();
    if (!path || /[\r\n\0]/.test(path) || !/\.(png|jpe?g|gif|webp|avif|bmp|heic|heif|tiff?|svg|ico)$/i.test(path) ||
      (/^[a-z][a-z0-9+.-]*:/i.test(path) && !/^[a-z]:[\\/]/i.test(path)) || path.startsWith('//')) continue;
    const threadId = row.sourceThreadId ?? '';
    const key = JSON.stringify([threadId, path]);
    if (!seen.has(key)) { seen.add(key); images.push({ path: path, threadId: threadId }); }
  }
  return images;
}

function toolGroupLabel(rows: TimelineRow[]): string {
  if (!rows.some((row: TimelineRow) => row.itemType !== undefined)) return `${rows.length} 次工具调用`;
  const files: Set<string> = new Set();
  let commands = 0;
  let reads = 0;
  let other = 0;
  for (const row of rows) {
    if (row.itemType === 'file_change') for (const path of row.files ?? []) files.add(path);
    else if (row.itemType === 'command_execution') commands++;
    else if (row.viewedImagePath || row.itemType === 'image_view' ||
      (row.itemType === 'dynamic_tool' && row.text.trim().toLowerCase() === 'read file')) reads++;
    else other++;
  }
  const parts: string[] = [];
  if (files.size > 0) parts.push(`修改了 ${files.size} 个文件`);
  if (commands > 0) parts.push(`运行了 ${commands} 条命令`);
  if (reads > 0) parts.push(`读取了 ${reads} 个文件`);
  if (other > 0) parts.push(`${other} 次工具调用`);
  return parts.join('，') || `${rows.length} 次工具调用`;
}

// Use user-message boundaries for legacy servers whose messages have no turn ID.
// Never hide an unfinished/error run or discard its output; expansion is a view only.
export function transcriptRows(messages: ChatMessage[], activities: ThreadActivity[], session: ThreadSession | null,
  latest: LatestTurn | null, expanded: string[], turns: LatestTurn[] = [], subagents: SubagentSummary[] = []): TimelineRow[] {
  const pending = new Set(turns.filter((turn: LatestTurn) => turn.state === 'queued' ||
    (turn.state === 'cancelled' && !turn.startedAt)).map((turn: LatestTurn) => turn.turnId));
  const rewound = new Set(turns.filter((turn: LatestTurn) => turn.state === 'rolled_back').map((turn: LatestTurn) => turn.turnId));
  const timeline = threadTimeline(messages.filter((message: ChatMessage) => !pending.has(message.turnId ?? '') && !rewound.has(message.turnId ?? '')),
    rewound.size > 0 ? activities.filter((activity: ThreadActivity) => !rewound.has(activity.turnId ?? '')) : activities,
    session?.activeTurnId ?? null, subagents);
  const result: TimelineRow[] = [];
  let start = 0;
  while (start < timeline.length) {
    let end = start + 1;
    while (end < timeline.length && timeline[end].role !== 'user') end++;
    const checkpoints = timeline.slice(start, end).filter((row: TimelineRow) => row.itemType === 'checkpoint');
    const section = timeline.slice(start, end).filter((row: TimelineRow) => row.itemType !== 'checkpoint');
    // Bounded history can start with a checkpoint and no message in this section.
    const user = section[0]?.role === 'user' ? section.shift() : undefined;
    if (user !== undefined) {
      const run = turns.find((turn: LatestTurn) => turn.turnId === user.turnId);
      if (run?.userMessageId && run.userMessageId !== user.id) user.delivery = 'steer';
      result.push(user);
    }
    const assistant = section.filter((row: TimelineRow) => row.role === 'assistant');
    const last = assistant[assistant.length - 1];
    const turnId = last?.turnId ?? section.find((row: TimelineRow) => !!row.turnId)?.turnId ?? user?.id ?? section[0]?.id ?? '';
    const turn = turns.find((entry: LatestTurn) => entry.turnId === turnId) ?? (latest?.turnId === turnId ? latest : null);
    if (user !== undefined && turns.some((entry: LatestTurn) => entry.turnId === user.turnId && entry.state === 'queued')) user.status = 'queued';
    const final = assistant.find((row: TimelineRow) => row.id === turn?.assistantMessageId) ?? last;
    if (final?.turnId && !final.streaming) {
      const original = /^\[查看原图\]\((<[^>\r\n]+>|[^\s<>()]+)\)$/.exec(final.text.trim());
      if (original !== null) {
        const previews = section.filter((row: TimelineRow) => row.htmlRender !== undefined && row.turnId === final.turnId && row.sourceThreadId === final.sourceThreadId);
        if (previews.length === 1) previews[0].originalImageHref = original[1];
      }
    }
    const active = turn?.state === 'running' || session?.activeTurnId === turnId || (end === timeline.length &&
      (session?.status === 'running' || session?.status === 'starting'));
    const failed = turn?.state === 'error' || turn?.state === 'interrupted' ||
      (end === timeline.length && (session?.status === 'error' || session?.status === 'interrupted'));
    // Diagnostics remain in timeline order even after a run completes.
    const settled = final !== undefined && section.some((row: TimelineRow) => row.id !== final.id && row.kind !== 'html-render') &&
      !section.some((row: TimelineRow) => row.streaming === true || row.kind === 'notice') && !active && !failed;
    // Steered messages create separate sections within the same run.
    const sectionId = user?.id ?? section[0]?.id ?? turnId;
    const foldId = `turn:${turnId}:${sectionId}`;
    if (settled) {
      const duration = durationLabel(turn?.startedAt ?? turn?.requestedAt ?? user?.createdAt ?? section[0].createdAt,
        turn?.completedAt ?? final.updatedAt ?? final.createdAt);
      result.push({ id: foldId, kind: 'turn', role: '', text: duration === null ? '运行过程' :
        turns.length > 0 && turn !== null ? workDuration(turn, final.updatedAt ?? final.createdAt) : `运行了 ${duration}`,
        detail: '', status: '', createdAt: section[0].createdAt });
    }
    if (!settled || expanded.includes(foldId)) {
      const process = settled ? section.filter((row: TimelineRow) => row.id !== final.id) : section;
      let index = 0;
      while (index < process.length) {
        const row = process[index];
        if (row.kind !== 'tool' && row.kind !== 'thinking') { result.push(row); index++; continue; }
        let tail = index + 1;
        while (tail < process.length && (process[tail].kind === 'tool' || process[tail].kind === 'thinking') &&
          process[tail].turnId === row.turnId) tail++;
        const tools = process.slice(index, tail).filter((entry: TimelineRow) => entry.kind === 'tool');
        if (tools.length > 0) {
          const groupId = `tools:${tools[0].id}`;
          const thinking = active && end === timeline.length && tail === process.length && process[tail - 1].kind === 'thinking';
          result.push({ id: groupId, kind: 'tools', role: '', text: thinking ? '思考中…' : toolGroupLabel(tools),
            icon: thinking ? 'thinking' : 'terminal', streaming: thinking,
            viewedImages: toolImages(tools),
            detail: '', status: '', createdAt: row.createdAt });
          if (expanded.includes(groupId)) {
            let n = index;
            while (n < tail) {
              const detail = process[n];
              if (detail.kind !== 'thinking' || detail.streaming) { detail.depth = 1; result.push(detail); n++; continue; }
              let next = n + 1;
              while (next < tail && process[next].kind === 'thinking' && !process[next].streaming) next++;
              result.push({ id: next === n + 1 ? detail.id : `thoughts:${detail.id}`, kind: 'thinking', role: 'reasoning', depth: 1,
                text: process.slice(n, next).map((entry: TimelineRow) => entry.text).join('\n\n'), groupCount: next - n,
                detail: '', status: detail.status, createdAt: detail.createdAt, turnId: detail.turnId, streaming: false });
              n = next;
            }
          }
          index = tail;
        } else {
          const completed = process.slice(index, tail).filter((entry: TimelineRow) => !entry.streaming);
          if (completed.length === 1) result.push(completed[0]);
          else if (completed.length > 1) result.push({ id: `thoughts:${completed[0].id}`, kind: 'thinking', role: 'reasoning',
            text: completed.map((entry: TimelineRow) => entry.text).join('\n\n'), groupCount: completed.length,
            detail: '', status: '', streaming: false, createdAt: row.createdAt });
          for (let n = index; n < tail; n++) if (process[n].streaming) result.push(process[n]);
          index = tail;
        }
      }
    } else {
      for (const row of section) if (row.kind === 'question' || row.kind === 'html-render' || row.kind === 'subagents') result.push(row);
    }
    if (settled) result.push(final);
    if (!settled && turn?.completedAt && turns.length > 0) {
      const label = workDuration(turn, turn.completedAt);
      if (label) result.push({ id: `duration:${turnId}:${sectionId}`, kind: 'duration', role: '', text: label,
        detail: '', status: turn.state, createdAt: turn.completedAt });
    }
    const checkpoint = checkpoints[checkpoints.length - 1];
    if (checkpoint !== undefined) {
      const files = checkpoint.changedFiles ?? checkpoint.detail.split('\n').map((line: string): ChangedFile => {
        const match = /^(.*?)\s+\+(\d+)\s+[−-](\d+)$/.exec(line);
        return { path: match?.[1] ?? '', additions: Number(match?.[2] ?? 0), deletions: Number(match?.[3] ?? 0) };
      }).filter((file: ChangedFile) => !!file.path);
      if (files.length > 0) result.push({ id: `changes:${checkpoint.id}`, kind: 'changes', role: '',
        text: `修改了 ${files.length} 个文件`, detail: '', status: checkpoint.status, createdAt: checkpoint.createdAt,
        turnId: checkpoint.turnId, sourceThreadId: checkpoint.sourceThreadId,
        checkpointTurnCount: turn?.ordinal, changedFiles: files });
    }
    start = end;
  }
  return result;
}

interface ThreadMetadata {
  pullRequests?: ThreadPullRequestLink[];
  lineage?: ThreadLineage;
  creationSource?: string;
  activeProviderThreadId?: string | null;
  rollbackFailure?: RollbackFailure | null;
  latestTurn?: LatestTurn | null;
  branch?: string | null;
  modelSelection?: ModelSelection;
  id: string;
  title: string;
  projectId: string;
  runtimeMode: string;
  interactionMode: string;
  worktreePath?: string | null;
  session?: ThreadSession | null;
}
export interface ThreadPullRequestLink {
  host: string;
  repository: string;
  number: number;
  url: string;
  source: string;
}
interface ThreadLineage { sideChat?: boolean; relationshipToParent?: string | null; parentThreadId?: string | null; }

export interface ThreadDetail extends ThreadMetadata {
  historyCursor?: string | null;
  hasMoreHistory?: boolean;
  canonicalTimeline?: boolean;
  transcriptVersion?: number;
  syncSequence?: number;
  turns?: LatestTurn[];
  messages: ChatMessage[];
  activities?: ThreadActivity[];
  checkpoints?: Checkpoint[];
  rewindCheckpoints?: RewindCheckpoint[];
  providerThreads?: RewindProviderThread[];
  subagents?: SubagentSummary[];
}

export interface RepositoryIdentity {
  canonicalKey: string;
  rootPath?: string;
  name?: string;
  displayName?: string;
}

export interface ProjectScript {
  id: string; name: string; command: string; icon: string; runOnWorktreeCreate: boolean;
  runOnSettle?: boolean; stopOnSettle?: boolean; async?: boolean; previewUrl?: string; autoOpenPreview?: boolean;
}

export interface ProjectShell {
  projectIcon?: ProjectIconDescriptor | null;
  scripts?: ProjectScript[];
  faviconPath?: string | null;
  repositoryIdentity?: RepositoryIdentity | null;
  updatedAt?: string;
  createdAt?: string;
  id: string;
  title: string;
  workspaceRoot: string;
  defaultModelSelection?: ModelSelection | null;
}
export interface ProjectIconDescriptor { kind: string; text?: string; color?: string; emoji?: string; name?: string; }

export interface ShellSnapshot {
  snapshotSequence: number;
  threads: ThreadShell[];
  projects: ProjectShell[];
  archivedThreads?: ThreadShell[];
}

export interface ShellItem {
  kind: string;
  location?: string;
  resolvedRepositoryIdentityRoots?: string[];
  sequence?: number;
  snapshot?: ShellSnapshot;
  thread?: ThreadShell;
  threadId?: string;
  project?: ProjectShell;
  projectId?: string;
}

export class ShellState {
  threads: ThreadShell[] = [];
  projects: ProjectShell[] = [];
  private sequence: number = -1;
  cursor(): number | null { return this.sequence < 0 ? null : this.sequence; }

  requireSnapshot(): void { this.sequence = -1; }

  snapshot(): ShellSnapshot {
    const snapshot: ShellSnapshot = { snapshotSequence: Math.max(0, this.sequence), threads: this.threads, projects: this.projects };
    return snapshot;
  }

  apply(item: ShellItem): void {
    if (item.kind === 'snapshot' && item.snapshot !== undefined) {
      if (item.resolvedRepositoryIdentityRoots !== undefined && item.snapshot.threads.length === 0 &&
        (item.snapshot.archivedThreads?.length ?? 0) === 0) {
        // Enrichment snapshots carry repository identities, not a replacement task list.
        this.projects = this.projects.map((project: ProjectShell) => {
          const enriched = item.snapshot?.projects.find((entry: ProjectShell) =>
            entry.id === project.id && entry.workspaceRoot === project.workspaceRoot);
          if (enriched !== undefined) project.repositoryIdentity = enriched.repositoryIdentity;
          return project;
        });
        return;
      }
      if (item.snapshot.snapshotSequence < this.sequence) return;
      this.sequence = item.snapshot.snapshotSequence;
      this.threads = item.snapshot.threads;
      this.projects = item.snapshot.projects;
      return;
    }
    if (item.location === 'archive') return;
    if (item.sequence === undefined || item.sequence <= this.sequence) return;
    this.sequence = item.sequence;
    if ((item.kind === 'thread-upserted' || item.kind === 'thread.updated') && item.thread !== undefined) {
      const thread = item.thread;
      this.threads = this.threads.filter((entry: ThreadShell) => entry.id !== thread.id).concat([thread]);
    } else if (item.kind === 'thread-removed' || item.kind === 'thread.removed') {
      this.threads = this.threads.filter((entry: ThreadShell) => entry.id !== item.threadId);
    } else if ((item.kind === 'project-upserted' || item.kind === 'project.updated') && item.project !== undefined) {
      const project = item.project;
      this.projects = this.projects.filter((entry: ProjectShell) => entry.id !== project.id).concat([project]);
    } else if (item.kind === 'project-removed' || item.kind === 'project.removed') {
      this.projects = this.projects.filter((entry: ProjectShell) => entry.id !== item.projectId);
    }
  }
}

export interface ThreadSnapshot {
  snapshotSequence: number;
  thread: ThreadDetail;
}

export interface ThreadSnapshotResponse {
  snapshotSequence: number;
  thread?: ThreadDetail;
  projection?: ThreadProjection;
  hasMoreHistory?: boolean;
  historyCursor?: string | null;
}

export interface ThreadHistoryPage {
  snapshotSequence: number;
  items: VisibleTurnItem[];
  nextCursor: string | null;
  hasMoreHistory: boolean;
}

interface MessagePayload {
  context?: MessageContext;
  scheduledTaskId?: string;
  turnId?: string | null;
  modelSelection?: ModelSelection;
  runtimeMode?: string;
  interactionMode?: string;
  attachments?: ChatAttachment[];
  activity?: ThreadActivity;
  checkpointTurnCount?: number;
  status?: string;
  threadId: string;
  messageId?: string;
  role?: string;
  text?: string;
  streaming?: boolean;
  session?: ThreadSession;
}

interface ThreadEvent {
  sequence?: number;
  threadId?: string;
  occurredAt?: string;
  type: string;
  payload: object;
}

interface ConversationMessage extends ChatMessage {
  threadId?: string;
  runId?: string | null;
  delegatedCompletion?: object;
  notification?: object;
}
interface ThreadRun {
  id: string;
  userMessageId?: string;
  queuePosition?: number | null;
  queueHeld?: boolean;
  freshContext?: boolean;
  ordinal: number;
  status: string;
  requestedAt: string;
  startedAt?: string | null;
  completedAt?: string | null;
}

interface PlanStep { text: string; status: string; }
export interface ChangedFile { path: string; additions?: number; deletions?: number; }
interface TurnItemFailure { message: string; class?: string; }
interface ProviderRetry { attempt: number; maxAttempts: number | null; retryDelayMs: number | null; }
export interface CurrentTurnItem extends SubagentMetadata {
  context?: MessageContext;
  modelSwitch?: ModelSwitch;
  scheduledTaskId?: string;
  inputIntent?: string;
  subagentId?: string;
  providerTurnId?: string | null;
  childThreadId?: string | null;
  origin?: string;
  level?: string;
  retry?: ProviderRetry;
  outcome?: string;
  detail?: string;
  questionAnswer?: QuestionAnswerPayload;
  viewedImagePath?: string;
  responseMode?: string;
  id: string;
  threadId: string;
  runId: string | null;
  type: string;
  ordinal: number;
  status: string;
  title?: string | null;
  startedAt?: string | null;
  completedAt?: string | null;
  updatedAt: string;
  messageId?: string;
  text?: string;
  textOmitted?: boolean;
  streaming?: boolean;
  attachments?: ChatAttachment[];
  input?: object | string;
  output?: object | string;
  outputOmitted?: boolean;
  fileName?: string;
  additions?: number;
  deletions?: number;
  changes?: ChangedFile[];
  files?: ChangedFile[];
  diffStr?: string;
  oldStr?: string;
  newStr?: string;
  steps?: PlanStep[];
  explanation?: string;
  markdown?: string;
  summary?: string;
  message?: string;
  pattern?: string;
  patterns?: string[];
  results?: object[];
  toolName?: string | null;
  prompt?: string;
  progress?: string;
  result?: string | null;
  failure?: TurnItemFailure;
  reason?: string;
  label?: string;
  requestId?: string;
  requestKind?: string;
  appName?: string;
  options?: ApprovalOption[];
  questions?: InputQuestion[];
}
interface VisibleTurnItem { position: number; sourceThreadId: string; sourceItemId: string; item: CurrentTurnItem; }
interface ThreadProjection {
  thread: ThreadMetadata;
  messages: ConversationMessage[];
  runs: ThreadRun[];
  checkpoints?: RewindCheckpoint[];
  providerThreads?: RewindProviderThread[];
  subagents?: SubagentSummary[];
  turnItems?: CurrentTurnItem[];
  visibleTurnItems?: VisibleTurnItem[];
}

interface HtmlRenderOutput { htmlRender?: HtmlRenderReference; isError?: boolean; structuredContent?: HtmlRenderOutput; }

function htmlRenderFromItem(item: CurrentTurnItem): HtmlRenderReference | undefined {
  if (item.type !== 'dynamic_tool' || item.status !== 'completed' ||
    !/^(?:execute|(?:mcp__)?t3[-_ ]?code(?:[-_]direct)?(?:__|[-_.:/ ])html_render|html_render)$/i.test(item.toolName ?? '') ||
    item.output === null || typeof item.output !== 'object') return undefined;
  const output = item.output as HtmlRenderOutput;
  const render = output.htmlRender ?? output.structuredContent?.htmlRender;
  if (output.isError || output.structuredContent?.isError || !render || typeof render.attachmentId !== 'string' ||
    !render.attachmentId || render.attachmentId.length > 256 || typeof render.title !== 'string' || !Number.isFinite(render.height)) return undefined;
  const height = Math.min(2000, Math.max(80, Math.round(render.height)));
  const heights = Array.isArray(render.heights) && render.heights.length <= 16 ? render.heights.filter((pair: number[]) =>
    Array.isArray(pair) && pair.length === 2 && Number.isInteger(pair[0]) && pair[0] > 0 && Number.isFinite(pair[1])) : undefined;
  return { attachmentId: render.attachmentId, title: render.title.trim().slice(0, 200) || 'HTML', height: height, heights: heights };
}

function detailText(value: object | string | undefined): string {
  if (value === undefined || value === null) return '';
  return typeof value === 'string' ? value : JSON.stringify(value, null, 2);
}

function itemActivity(item: CurrentTurnItem): ThreadActivity | null {
  if (['user_message', 'assistant_message', 'reasoning'].includes(item.type)) return null;
  let title = item.title ?? '';
  let detail = '';
  let tool = false;
  let tone: string | undefined;
  const files: string[] = [];
  if (item.type === 'command_execution') {
    title = detailText(item.input) || title || '运行命令';
    detail = detailText(item.output);
    tool = true;
  } else if (item.type === 'file_change') {
    if (item.fileName) files.push(item.fileName);
    for (const change of item.changes ?? []) if (!files.includes(change.path)) files.push(change.path);
    for (const change of item.files ?? []) if (!files.includes(change.path)) files.push(change.path);
    title = `修改文件 · ${files.join('，')}`;
    const counts = item.additions !== undefined || item.deletions !== undefined ? `+${item.additions ?? 0} −${item.deletions ?? 0}\n` : '';
    detail = counts + (item.diffStr ?? (item.oldStr !== undefined || item.newStr !== undefined ?
      `修改前\n${item.oldStr ?? ''}\n修改后\n${item.newStr ?? ''}` : files.join('\n')));
    tool = true;
  } else if (item.type === 'image_view') {
    title = title || '读取图片'; detail = item.viewedImagePath ?? ''; tool = true;
  } else if (item.type === 'dynamic_tool') {
    title = title || item.toolName || '工具调用';
    detail = [detailText(item.input), detailText(item.output), item.viewedImagePath ?? ''].filter((part: string) => part.length > 0).join('\n\n');
    tool = true;
  } else if (item.type === 'file_search' || item.type === 'web_search') {
    title = title || `${item.type === 'file_search' ? '搜索文件' : '搜索网页'} · ${item.pattern ?? item.patterns?.join('，') ?? ''}`;
    detail = detailText(item.results);
    tool = true;
  } else if (item.type === 'todo_list') {
    title = title || '任务计划';
    detail = [item.explanation ?? '', ...(item.steps ?? []).map((step: PlanStep) =>
      `${step.status === 'completed' ? '✓' : step.status === 'running' ? '→' : '○'} ${step.text}`)].filter((part: string) => !!part).join('\n');
  } else if (item.type === 'proposed_plan') {
    title = title || '建议计划'; detail = item.markdown ?? '';
  } else if (item.type === 'compaction') {
    title = item.status === 'running' ? '正在压缩上下文' : '上下文已压缩'; detail = item.summary ?? '';
  } else if (item.type === 'system_notice') {
    detail = item.message ?? title;
    title = runtimeNoticeLabel(detail);
    tone = item.level === 'info' ? 'info' : item.level === 'error' ? 'error' : 'warning';
  } else if (item.type === 'notification') {
    title = runtimeNoticeLabel(item.summary ?? title);
    detail = [item.summary ?? '', item.detail ?? ''].filter((part: string) => !!part).join('\n\n');
    tone = item.outcome === 'failed' ? 'error' : 'info';
  } else if (item.type === 'run_interrupt_request' || item.type === 'run_interrupt_result') {
    title = item.type === 'run_interrupt_request' ? '正在停止任务' : '任务已停止';
    detail = item.message ?? '';
    tone = 'info';
  } else if (item.type === 'error') {
    detail = item.failure?.message ?? item.message ?? '';
    const limit = item.failure?.class === 'usage_limit';
    const retry = item.retry;
    tone = retry !== undefined && item.status === 'completed' ? 'success' : limit || (retry !== undefined && item.status !== 'failed') ? 'warning' : 'error';
    title = limit ? '已达到使用额度上限' : runtimeNoticeLabel(detail) || title || '执行出错';
    if (retry !== undefined) {
      const progress = `${retry.attempt}${retry.maxAttempts === null ? '' : '/' + retry.maxAttempts}`;
      title = item.status === 'running' ? `正在重试（${progress}）` : item.status === 'completed' ? `服务已恢复（重试 ${progress} 次）` :
        `${limit ? '已达到使用额度上限' : '执行失败'}（重试 ${progress} 次）`;
      if (item.status === 'running' && retry.retryDelayMs !== null && retry.retryDelayMs > 0) {
        detail += `\n${retry.retryDelayMs < 1000 ? retry.retryDelayMs + 'ms' : retry.retryDelayMs / 1000 + 's'} 后重试`;
      }
    }
  } else if (item.type === 'checkpoint') {
    title = title || `改动摘要 · ${item.files?.length ?? 0} 个文件`;
    detail = (item.files ?? []).map((file: ChangedFile) => `${file.path}  +${file.additions ?? 0} −${file.deletions ?? 0}`).join('\n');
  } else if (item.type === 'subagent') {
    title = title || item.prompt?.slice(0, 80) || '子代理';
    return { id: item.id, kind: 'timeline.updated', summary: title, turnId: item.runId, createdAt: item.startedAt ?? item.updatedAt,
      payload: { itemType: item.type, threadId: item.threadId, toolCallId: item.id, status: item.status,
        subagent: compactSubagent({ id: item.subagentId ?? item.id, title: item.title, threadId: item.threadId, runId: item.runId,
          providerTurnId: item.providerTurnId, childThreadId: item.childThreadId, origin: item.origin, workflow: item.workflow,
          driver: item.driver, providerInstanceId: item.providerInstanceId, model: item.model, modelSelection: item.modelSelection, remoteChild: item.remoteChild,
          status: item.status, prompt: item.prompt, progress: item.progress, result: item.result, promptOmitted: item.promptOmitted, resultOmitted: item.resultOmitted,
          startedAt: item.startedAt, completedAt: item.completedAt, updatedAt: item.updatedAt }) } };
  } else if (item.type === 'approval_request' || item.type === 'user_input_request') {
    const pending = ['pending', 'running', 'waiting'].includes(item.status);
    const activity: ThreadActivity = {
      id: item.id, kind: `${item.type === 'approval_request' ? 'approval' : 'user-input'}.${pending ? 'requested' : 'resolved'}`,
      summary: title || (item.type === 'approval_request' ? '审批请求' : '用户回答'), turnId: item.runId,
      createdAt: item.startedAt ?? item.updatedAt,
      payload: { requestId: item.requestId, requestKind: item.requestKind, appName: item.appName,
        threadId: item.threadId,
        detail: item.prompt ?? item.reason ?? '', options: item.options, questions: item.questions, responseMode: item.responseMode,
        questionAnswer: item.questionAnswer }
    };
    return activity;
  } else {
    // Keep notices and future item types visible even when this client has no specialized card.
    title = title || item.message || item.label || item.type;
    detail = item.summary ?? item.reason ?? '';
  }
  const activity: ThreadActivity = {
    id: item.id, kind: tool ? 'tool.updated' : 'timeline.updated', summary: title, tone: tone,
    turnId: item.runId, createdAt: item.startedAt ?? item.updatedAt,
    payload: { itemType: item.type, itemId: item.id, threadId: item.threadId, toolCallId: item.id, updatedAt: item.updatedAt,
      status: item.status, title: title, detail: detail, files: files, changedFiles: item.type === 'checkpoint' ? item.files : undefined,
      viewedImagePath: item.viewedImagePath, htmlRender: htmlRenderFromItem(item),
      detailOmitted: item.outputOmitted === true || (item.type === 'file_change' && item.diffStr === undefined && item.oldStr === undefined && item.newStr === undefined) }
  };
  return activity;
}

function projectedMessage(message: ConversationMessage): ChatMessage {
  const projected: ChatMessage = {
    id: message.id, role: message.role, text: message.text, streaming: message.streaming,
    createdAt: message.createdAt, updatedAt: message.updatedAt, attachments: message.attachments ?? [],
    turnId: message.runId, inputIntent: message.inputIntent, modelSwitch: message.modelSwitch, scheduledTaskId: message.scheduledTaskId,
    sourceThreadId: message.threadId,
    queueAutomatic: message.delegatedCompletion !== undefined || message.notification !== undefined,
    queueGuest: message.context?.guest !== undefined,
    context: message.context
  };
  return projected;
}

export interface ThreadItem {
  kind: string;
  sequence?: number;
  snapshotSequence?: number;
  historyCursor?: string | null;
  hasMoreHistory?: boolean;
  projection?: ThreadProjection;
  snapshot?: ThreadSnapshot;
  event?: ThreadEvent;
}

const TRANSCRIPT_CACHE_VERSION = 6;

export class ThreadState {
  private historyEpoch: number = 0;
  private canonicalTimeline: boolean = false;
  checkpointCount: number = 0;
  thread: ThreadDetail | null = null;
  messages: ChatMessage[] = [];
  activities: ThreadActivity[] = [];
  private sequence: number = -1;
  private resumable: boolean = false;
  private nextPosition: number = 0;
  private metadataSequence: number = -1;
  private shellSequence: number = -1;
  private shellThread: ThreadShell | null = null;
  private runs: ThreadRun[] = [];
  private itemDetails: Map<string, CurrentTurnItem> = new Map();
  private itemPositions: Map<string, number> = new Map();

  cursor(): number | null { return this.resumable && this.sequence >= 0 ? this.sequence : null; }
  historyVersion(): number { return this.historyEpoch; }

  requireSnapshot(): void {
    // Keep the visible transcript until the replacement snapshot establishes a new baseline.
    this.resumable = false;
    this.sequence = -1;
    this.metadataSequence = -1;
    this.shellSequence = -1;
    this.shellThread = null;
    this.historyEpoch++;
  }

  mergeHistory(page: ThreadHistoryPage, cursor: string, epoch: number): boolean {
    if (this.thread === null || this.historyEpoch !== epoch || this.thread.historyCursor !== cursor || page.snapshotSequence > this.sequence) return false;
    const unseen = page.items.slice().sort((left: VisibleTurnItem, right: VisibleTurnItem) => left.position - right.position)
      .filter((row: VisibleTurnItem) => this.activities.some((activity: ThreadActivity) => activity.id === row.item.id && activity.visibleInTimeline === false) ||
        (!this.itemPositions.has(row.item.id) &&
        !this.messages.some((message: ChatMessage) => message.visibleInTimeline !== false && message.id === (row.item.messageId ?? row.item.id)) &&
        !this.activities.some((activity: ThreadActivity) => activity.id === row.item.id)));
    let position = Math.min(0, ...this.messages.map((message: ChatMessage) => message.timelinePosition ?? 0),
      ...this.activities.map((activity: ThreadActivity) => activity.timelinePosition ?? 0)) - unseen.length;
    for (const row of unseen) {
      this.itemPositions.set(row.item.id, position++);
      this.applyTurnItem(row.item, true);
    }
    this.thread.historyCursor = page.nextCursor;
    this.thread.hasMoreHistory = page.hasMoreHistory && page.nextCursor !== null;
    return true;
  }
  restoreCached(thread: ThreadDetail): void {
    const version = thread.transcriptVersion;
    this.apply({ kind: 'snapshot', snapshot: { snapshotSequence: thread.syncSequence ?? 0, thread: thread } });
    // Older caches did not retain inline render references. Keep the transcript visible while resyncing.
    const missingNotices = this.activities.some((activity: ThreadActivity) => activity.tone === undefined &&
      ['system_notice', 'notification', 'error', 'run_interrupt_request', 'run_interrupt_result'].includes(activity.payload?.itemType ?? ''));
    const missingReferences = this.messages.some((message: ChatMessage) => message.text.includes('](t3-context://v1/thread/') && message.context?.records === undefined);
    // Null markers distinguish complete compact records from older caches that lost these fields.
    const missingAgentMetadata = thread.subagents?.some(agent => agent.model === undefined || agent.workflow === undefined) ||
      this.activities.some(activity => activity.payload?.subagent !== undefined && (activity.payload.subagent.model === undefined || activity.payload.subagent.workflow === undefined));
    if (version !== TRANSCRIPT_CACHE_VERSION || missingNotices || missingReferences || missingAgentMetadata || thread.syncSequence === undefined ||
      !Number.isSafeInteger(thread.syncSequence) || thread.syncSequence < 0) this.requireSnapshot();
  }

  private applyTurnItem(item: CurrentTurnItem, visible?: boolean): void {
    let position = this.itemPositions.get(item.id);
    if (position === undefined) {
      position = this.messages.find((message: ChatMessage) => message.id === (item.messageId ?? item.id))?.timelinePosition ??
        this.activities.find((activity: ThreadActivity) => activity.id === item.id)?.timelinePosition ?? this.nextPosition;
      this.nextPosition = Math.max(this.nextPosition, position + 1);
      this.itemPositions.set(item.id, position);
    }
    const detail = this.itemDetails.get(item.id);
    let resolved = item;
    if (detail !== undefined && detail.updatedAt === item.updatedAt) {
      resolved = JSON.parse(JSON.stringify(item)) as CurrentTurnItem;
      resolved.output = item.outputOmitted ? detail.output : item.output;
      resolved.outputOmitted = item.outputOmitted && detail.output === undefined;
      resolved.diffStr = item.diffStr ?? detail.diffStr;
      resolved.oldStr = item.oldStr ?? detail.oldStr;
      resolved.newStr = item.newStr ?? detail.newStr;
    }
    if (['user_message', 'assistant_message', 'reasoning'].includes(item.type)) {
      const id = item.messageId ?? item.id;
      const existing = this.messages.find((message: ChatMessage) => message.id === id);
      // The message record is authoritative; visible rows additionally contain inherited history.
      if (existing !== undefined && item.type !== 'reasoning') {
        existing.timelinePosition = position; existing.itemOrdinal = item.ordinal;
        existing.sourceThreadId = item.threadId; existing.visibleInTimeline = true;
        existing.inputIntent = item.inputIntent ?? existing.inputIntent;
        existing.modelSwitch = item.modelSwitch ?? existing.modelSwitch;
        existing.scheduledTaskId = item.scheduledTaskId ?? existing.scheduledTaskId;
        return;
      }
      const message: ChatMessage = { id: id, role: item.type === 'user_message' ? 'user' : item.type === 'reasoning' ? 'reasoning' : 'assistant',
        text: item.textOmitted ? existing?.text ?? '' : item.text ?? '', streaming: item.streaming ?? false,
        createdAt: item.startedAt ?? item.updatedAt, updatedAt: item.updatedAt, turnId: item.runId, attachments: item.attachments ?? [], context: item.context,
        inputIntent: item.inputIntent, modelSwitch: item.modelSwitch, scheduledTaskId: item.scheduledTaskId,
        timelinePosition: position, itemOrdinal: item.ordinal, sourceThreadId: item.threadId, visibleInTimeline: true };
      this.messages = this.messages.filter((entry: ChatMessage) => entry.id !== id).concat([message]);
      return;
    }
    const activity = itemActivity(resolved);
    if (activity !== null) {
      activity.visibleInTimeline = visible ?? this.activities.find((entry: ThreadActivity) => entry.id === item.id)?.visibleInTimeline;
      activity.timelinePosition = position;
      activity.itemOrdinal = item.ordinal;
      this.activities = this.activities.filter((entry: ThreadActivity) => entry.id !== activity.id).concat([activity]);
    }
  }

  applyTurnItemDetail(item: CurrentTurnItem): void {
    const existing = this.activities.find((activity: ThreadActivity) => activity.id === item.id);
    const cached = this.itemDetails.get(item.id);
    // Both the visible output and its cached detail must keep their newest version.
    if (Date.parse(existing?.payload?.updatedAt ?? '') > Date.parse(item.updatedAt) ||
      Date.parse(cached?.updatedAt ?? '') > Date.parse(item.updatedAt)) return;
    this.itemDetails.set(item.id, item);
    const activity = itemActivity(item);
    if (existing === undefined || activity?.payload === undefined) return;
    this.activities = this.activities.map((entry: ThreadActivity) => {
      if (entry.id === item.id && entry.payload !== undefined && entry.payload !== null) {
        entry.payload.detail = activity.payload?.detail;
        entry.payload.detailOmitted = false;
      }
      return entry;
    });
  }

  // Shell metadata may arrive before the detail snapshot.
  composerMetadataSequence(): number { return Math.max(this.metadataSequence, this.shellSequence); }

  applyShell(item: ShellItem, threadId: string): boolean {
    if (item.resolvedRepositoryIdentityRoots !== undefined || item.location === 'archive') return false;
    const sequence = item.kind === 'snapshot' ? item.snapshot?.snapshotSequence : item.sequence;
    if (sequence === undefined || sequence <= this.shellSequence) return false;
    const thread = item.kind === 'snapshot' ? item.snapshot?.threads.find((entry: ThreadShell) => entry.id === threadId) :
      (item.kind === 'thread-upserted' || item.kind === 'thread.updated' ? item.thread : undefined);
    if (thread === undefined || thread.id !== threadId) return false;
    this.shellSequence = sequence;
    this.shellThread = thread;
    this.applyShellMetadata();
    return true;
  }

  private applyShellMetadata(): void {
    const shell = this.shellThread;
    if (this.thread === null || shell === null || shell.id !== this.thread.id || this.shellSequence < this.metadataSequence) return;
    if (shell.latestTurn !== undefined) this.thread.latestTurn = shell.latestTurn;
    if (shell.title !== undefined) this.thread.title = shell.title ?? '';
    if (shell.branch !== undefined) this.thread.branch = shell.branch;
    if (shell.worktreePath !== undefined) this.thread.worktreePath = shell.worktreePath;
    if (shell.modelSelection !== undefined) this.thread.modelSelection = shell.modelSelection;
    if (shell.runtimeMode !== undefined) this.thread.runtimeMode = shell.runtimeMode;
    if (shell.interactionMode !== undefined) this.thread.interactionMode = shell.interactionMode;
    if (shell.pullRequests !== undefined) this.thread.pullRequests = shell.pullRequests;
  }

  apply(item: ThreadItem): void {
    if (item.kind === 'snapshot' && item.projection !== undefined && item.snapshotSequence !== undefined) {
      if (item.snapshotSequence < this.sequence) return;
      this.historyEpoch++;
      this.sequence = item.snapshotSequence;
      this.resumable = true;
      this.metadataSequence = item.snapshotSequence;
      this.messages = item.projection.messages.map(projectedMessage);
      this.activities = [];
      const visible = item.projection.visibleTurnItems;
      this.canonicalTimeline = visible !== undefined;
      const items = visible === undefined ? item.projection.turnItems ?? [] :
        visible.slice().sort((left: VisibleTurnItem, right: VisibleTurnItem) => left.position - right.position).map((row: VisibleTurnItem) => row.item);
      if (visible !== undefined) {
        const visibleMessages: Set<string> = new Set(items.filter((entry: CurrentTurnItem) =>
          entry.type === 'user_message' || entry.type === 'assistant_message').map((entry: CurrentTurnItem) => entry.messageId ?? entry.id));
        for (const run of item.projection.runs) if (run.status === 'queued' && run.userMessageId) visibleMessages.add(run.userMessageId);
        this.messages = this.messages.filter((message: ChatMessage) => visibleMessages.has(message.id));
      }
      this.itemPositions.clear();
      this.nextPosition = 0;
      for (const turnItem of items) this.applyTurnItem(turnItem);
      if (visible !== undefined) {
        const visibleIds = new Set(items.map((entry: CurrentTurnItem) => entry.id));
        for (const dependency of item.projection.turnItems ?? []) {
          if (!visibleIds.has(dependency.id) && (dependency.type === 'user_input_request' || dependency.type === 'approval_request')) this.applyTurnItem(dependency, false);
        }
      }
      this.checkpointCount = 0;
      this.setMetadata(item.projection.thread);
      if (this.thread !== null) {
        this.thread.transcriptVersion = TRANSCRIPT_CACHE_VERSION; this.thread.canonicalTimeline = this.canonicalTimeline;
        this.thread.rewindCheckpoints = item.projection.checkpoints?.map(rewindCheckpoint);
        this.thread.providerThreads = item.projection.providerThreads;
        this.thread.subagents = item.projection.subagents?.map(compactSubagent);
        this.thread.historyCursor = item.historyCursor;
        this.thread.hasMoreHistory = item.hasMoreHistory === true && typeof item.historyCursor === 'string';
      }
      this.runs = item.projection.runs;
      this.applyRunState();
      this.applyShellMetadata();
      return;
    }
    if (item.kind === 'snapshot' && item.snapshot !== undefined) {
      if (item.snapshot.snapshotSequence < this.sequence) return;
      this.historyEpoch++;
      this.sequence = item.snapshot.snapshotSequence;
      this.resumable = true;
      this.metadataSequence = item.snapshot.snapshotSequence;
      this.thread = item.snapshot.thread;
      this.thread.transcriptVersion = TRANSCRIPT_CACHE_VERSION;
      this.canonicalTimeline = this.thread.canonicalTimeline === true;
      this.applyShellMetadata();
      this.messages = item.snapshot.thread.messages;
      this.activities = item.snapshot.thread.activities ?? [];
      this.runs = (this.thread.turns ?? []).map((turn: LatestTurn, index: number): ThreadRun => ({
        id: turn.turnId, ordinal: turn.ordinal ?? (this.thread?.turns?.length ?? 0) - index,
        status: turn.state === 'error' ? 'failed' : turn.state, userMessageId: turn.userMessageId,
        queuePosition: turn.queuePosition, queueHeld: turn.queueHeld, freshContext: turn.freshContext,
        requestedAt: turn.requestedAt ?? '', startedAt: turn.startedAt, completedAt: turn.completedAt }));
      this.itemPositions.clear(); this.nextPosition = 0;
      for (const message of this.messages) this.nextPosition = Math.max(this.nextPosition, (message.timelinePosition ?? -1) + 1);
      for (const activity of this.activities) this.nextPosition = Math.max(this.nextPosition, (activity.timelinePosition ?? -1) + 1);
      this.checkpointCount = 0;
      for (const checkpoint of item.snapshot.thread.checkpoints ?? []) {
        if (checkpoint.status === 'ready') this.checkpointCount = Math.max(this.checkpointCount, checkpoint.checkpointTurnCount);
      }
      return;
    }
    const event = item.event;
    const sequence = item.sequence ?? event?.sequence;
    if (event === undefined || sequence === undefined || sequence <= this.sequence || this.thread === null) return;
    const payload = event.payload as MessagePayload;
    if ((event.threadId ?? payload.threadId) !== this.thread.id) return;
    this.sequence = sequence;
    if (event.type === 'message.updated') {
      const message = projectedMessage(event.payload as ConversationMessage);
      const existing = this.messages.find((entry: ChatMessage) => entry.id === message.id);
      message.timelinePosition = existing?.timelinePosition;
      message.itemOrdinal = existing?.itemOrdinal;
      message.sourceThreadId = existing?.sourceThreadId ?? message.sourceThreadId;
      message.visibleInTimeline = existing?.visibleInTimeline ?? (this.canonicalTimeline ? false : undefined);
      message.modelSwitch = message.modelSwitch ?? existing?.modelSwitch;
      message.scheduledTaskId = message.scheduledTaskId ?? existing?.scheduledTaskId;
      this.messages = existing !== undefined ? this.messages.map((entry: ChatMessage) => entry.id === message.id ? message : entry) :
        this.messages.concat([message]);
      return;
    }
    if (event.type === 'run.created' || event.type === 'run.updated') {
      const run = event.payload as ThreadRun;
      if (run.status === 'rolled_back' && !this.runs.some((previous: ThreadRun) => previous.id === run.id && previous.status === run.status)) this.historyEpoch++;
      this.runs = this.runs.filter((entry: ThreadRun) => entry.id !== run.id).concat([run]);
      this.applyRunState();
      return;
    }
    if (event.type === 'checkpoint.captured') {
      const checkpoint = rewindCheckpoint(event.payload as RewindCheckpoint);
      this.thread.rewindCheckpoints = (this.thread.rewindCheckpoints ?? []).filter((entry: RewindCheckpoint) => entry.id !== checkpoint.id).concat([checkpoint]);
      return;
    }
    if (event.type === 'provider-thread.updated') {
      const providerThread = event.payload as RewindProviderThread;
      this.thread.providerThreads = (this.thread.providerThreads ?? []).filter((entry: RewindProviderThread) => entry.id !== providerThread.id).concat([providerThread]);
      const queued = providerThread.status === 'not_loaded' && providerThread.firstRunOrdinal === null &&
        providerThread.nativeThreadRef === null && providerThread.providerSessionId === null;
      if (providerThread.appThreadId === this.thread.id && !queued) this.thread.activeProviderThreadId = providerThread.id;
      return;
    }
    if (event.type === 'subagent.updated') {
      const agent = compactSubagent(event.payload as SubagentSummary);
      const agents = this.thread.subagents ?? [], index = agents.findIndex(entry => entry.id === agent.id);
      if (index < 0) this.thread.subagents = agents.concat([agent]);
      else this.thread.subagents = agents.map((entry, i) => i === index ? mergeSubagent(entry, agent) : entry);
      return;
    }
    if (event.type === 'turn-item.updated') {
      this.applyTurnItem(event.payload as CurrentTurnItem);
      return;
    }
    if (event.type === 'thread.pull-request-link-updated') {
      this.metadataSequence = sequence;
      const link = event.payload as ThreadPullRequestLink;
      this.thread.pullRequests = (this.thread.pullRequests ?? []).filter((entry: ThreadPullRequestLink) =>
        entry.host !== link.host || entry.repository !== link.repository || entry.number !== link.number).concat([link]);
      return;
    }
    if (['thread.created', 'thread.metadata-updated', 'thread.pull-request-synced', 'thread.runtime-mode-updated',
      'thread.interaction-mode-updated', 'thread.model-selection-updated', 'thread.provider-switched'].includes(event.type)) {
      this.metadataSequence = sequence;
      this.setMetadata(event.payload as ThreadMetadata);
      this.applyShellMetadata();
      return;
    }
    if (event.type === 'thread.activity-appended' && payload.activity !== undefined) {
      const activity = payload.activity;
      this.activities = this.activities.filter((entry: ThreadActivity) => entry.id !== activity.id).concat([activity]);
    }
    if (event.type === 'thread.turn-diff-completed' && payload.status === 'ready') {
      this.checkpointCount = Math.max(this.checkpointCount, payload.checkpointTurnCount ?? 0);
    }
    if (event.type === 'thread.meta-updated' && payload.modelSelection !== undefined) {
      this.thread.modelSelection = payload.modelSelection;
    }
    if (event.type === 'thread.runtime-mode-set' && payload.runtimeMode !== undefined) {
      this.thread.runtimeMode = payload.runtimeMode;
    }
    if (event.type === 'thread.interaction-mode-set' && payload.interactionMode !== undefined) {
      this.thread.interactionMode = payload.interactionMode;
    }
    if (event.type === 'thread.session-set') {
      this.thread.session = payload.session;
    }
    if (event.type !== 'thread.message-sent' || payload.messageId === undefined) return;
    const existing = this.messages.find((message: ChatMessage) => message.id === payload.messageId);
    const text = payload.text ?? '';
    const message: ChatMessage = {
      id: payload.messageId ?? '', role: payload.role ?? existing?.role ?? 'assistant',
      turnId: payload.turnId ?? existing?.turnId, updatedAt: event.occurredAt ?? existing?.updatedAt,
      text: existing === undefined ? text : (payload.streaming ? existing.text + text : (text || existing.text)),
      streaming: payload.streaming ?? false,
      attachments: payload.attachments ?? existing?.attachments ?? [],
      context: payload.context ?? existing?.context,
      modelSwitch: existing?.modelSwitch,
      scheduledTaskId: payload.scheduledTaskId ?? existing?.scheduledTaskId,
      createdAt: existing?.createdAt ?? event.occurredAt ?? ''
    };
    if (existing === undefined) this.messages = this.messages.concat([message]);
    else this.messages = this.messages.map((entry: ChatMessage) => entry.id === message.id ? message : entry);
  }

  private setMetadata(metadata: ThreadMetadata): void {
    const detail: ThreadDetail = {
      id: metadata.id, projectId: metadata.projectId, title: metadata.title,
      modelSelection: metadata.modelSelection, runtimeMode: metadata.runtimeMode, interactionMode: metadata.interactionMode,
      branch: metadata.branch, worktreePath: metadata.worktreePath,
      lineage: metadata.lineage, creationSource: metadata.creationSource,
      activeProviderThreadId: metadata.activeProviderThreadId, rollbackFailure: metadata.rollbackFailure,
      rewindCheckpoints: this.thread?.rewindCheckpoints, providerThreads: this.thread?.providerThreads, subagents: this.thread?.subagents,
      transcriptVersion: this.thread?.transcriptVersion,
      canonicalTimeline: this.canonicalTimeline,
      historyCursor: this.thread?.historyCursor, hasMoreHistory: this.thread?.hasMoreHistory,
      pullRequests: metadata.pullRequests ?? this.thread?.pullRequests,
      messages: this.messages, activities: this.activities,
      session: this.thread?.session, latestTurn: this.thread?.latestTurn, turns: this.thread?.turns
    };
    this.thread = detail;
  }

  private applyRunState(): void {
    if (this.thread === null) return;
    const ordered = this.runs.slice().sort((left: ThreadRun, right: ThreadRun) => right.ordinal - left.ordinal);
    const latest = ordered.find((run: ThreadRun) => run.status !== 'rolled_back');
    this.thread.turns = ordered.map((run: ThreadRun): LatestTurn => ({ turnId: run.id,
      state: run.status === 'failed' ? 'error' : run.status, requestedAt: run.requestedAt,
      startedAt: run.startedAt, completedAt: run.completedAt, userMessageId: run.userMessageId,
      ordinal: run.ordinal, queuePosition: run.queuePosition, queueHeld: run.queueHeld, freshContext: run.freshContext }));
    const active = ordered.find((run: ThreadRun) =>
      ['preparing', 'starting', 'running', 'waiting'].includes(run.status));
    this.thread.session = {
      status: active === undefined ? 'ready' :
        (active.status === 'preparing' || active.status === 'starting' ? 'starting' : 'running'),
      activeTurnId: active?.id ?? null
    };
    this.thread.latestTurn = latest === undefined ? null : {
      turnId: latest.id, state: latest.status === 'failed' ? 'error' : latest.status,
      requestedAt: latest.requestedAt, startedAt: latest.startedAt, completedAt: latest.completedAt
    };
  }
}

export interface QueuedMessage {
  runId: string;
  messageId: string;
  text: string;
  attachments: ChatAttachment[];
  held: boolean;
  freshContext: boolean;
  automatic: boolean;
  canEdit: boolean;
}

export function queuedMessages(thread: ThreadDetail | null, messages: ChatMessage[]): QueuedMessage[] {
  if (thread === null) return [];
  const queued = (thread.turns ?? []).filter((turn: LatestTurn) => turn.state === 'queued').slice()
    .sort((left: LatestTurn, right: LatestTurn) => (left.queuePosition ?? left.ordinal ?? 0) -
      (right.queuePosition ?? right.ordinal ?? 0) || (left.ordinal ?? 0) - (right.ordinal ?? 0));
  const result: QueuedMessage[] = [];
  for (const turn of queued) {
    const message = messages.find((entry: ChatMessage) => entry.role === 'user' &&
      (turn.userMessageId ? entry.id === turn.userMessageId : entry.turnId === turn.turnId));
    if (message === undefined) continue;
    result.push({ runId: turn.turnId, messageId: message.id, text: message.text, attachments: message.attachments ?? [],
      held: turn.queueHeld === true, freshContext: turn.freshContext === true, automatic: message.queueAutomatic === true,
      canEdit: message.queueAutomatic !== true && message.queueGuest !== true });
  }
  return result;
}

export interface QueuedMessageCommand {
  type: string;
  commandId: string;
  threadId: string;
  runId?: string;
  queuedRunId?: string;
  targetRunId?: string;
  text?: string;
  attachments?: ChatAttachment[];
}

export function queuedMessageCommand(thread: ThreadDetail, messages: ChatMessage[], runId: string,
  action: string, commandId: string, text: string = '', attachments?: ChatAttachment[]): QueuedMessageCommand | null {
  const queued = queuedMessages(thread, messages).find((entry: QueuedMessage) => entry.runId === runId);
  if (queued === undefined) return null;
  const command: QueuedMessageCommand = { type: '', commandId: commandId, threadId: thread.id, runId: runId };
  if (action === 'delete') command.type = 'queued-run.cancel';
  else if (action === 'edit' && queued.canEdit &&
    (text.trim().length > 0 || (attachments ?? queued.attachments).length > 0)) {
    if (attachments !== undefined && attachments.length > 8) return null;
    command.type = 'queued-run.edit'; command.text = text;
    if (attachments !== undefined) command.attachments = attachments;
  }
  else if (action === 'send' && !queued.automatic) {
    const target = thread.session?.activeTurnId;
    if (target) {
      if (queued.freshContext) return null;
      return { type: 'queued-message.promote-to-steer', commandId: commandId, threadId: thread.id,
        queuedRunId: runId, targetRunId: target };
    }
    if (['starting', 'running'].includes(thread.session?.status ?? '')) return null;
    command.type = 'queued-run.start';
  }
  return command.type ? command : null;
}

interface TurnMessage {
  messageId: string;
  role: string;
  text: string;
  attachments: object[];
}

export interface InterruptTurnCommand {
  type: string;
  commandId: string;
  threadId: string;
  runId?: string;
  holdQueue?: boolean;
}

export function interruptTurnCommand(thread: ThreadDetail, commandId: string, supportsThreadStop: boolean): InterruptTurnCommand | null {
  const session = thread.session;
  if (session?.status !== 'running' && session?.status !== 'starting') return null;
  if (session.activeTurnId) return { type: 'run.interrupt', commandId: commandId, threadId: thread.id, runId: session.activeTurnId, holdQueue: true };
  if (supportsThreadStop) return { type: 'thread.stop', commandId: commandId, threadId: thread.id };
  return null;
}

export interface StartTurnCommand {
  modelSelection?: ModelSelection;
  dispatchMode?: MessageDispatchMode;
  composerText?: string;
  freshContext?: boolean;
  sideThreadId?: string;
  sideForkCommandId?: string;
  type: string;
  commandId: string;
  threadId: string;
  message: TurnMessage;
  runtimeMode: string;
  interactionMode: string;
  createdAt: string;
}
export interface MessageDispatchMode { type: string; targetRunId?: string; }

export function initialTurnCommand(thread: ThreadDetail, text: string, commandId: string, messageId: string, createdAt: string): StartTurnCommand {
  return { type: 'thread.turn.start', commandId: commandId, threadId: thread.id,
    message: { messageId: messageId, role: 'user', text: text, attachments: [] },
    runtimeMode: thread.runtimeMode, interactionMode: thread.interactionMode ?? 'default', createdAt: createdAt };
}

export function startTurnCommand(thread: ThreadDetail, text: string, commandId: string,
  messageId: string, createdAt: string, delivery: string = 'queue', modelSelection: ModelSelection | null = null, composerCommands: boolean = true): StartTurnCommand {
  const command = initialTurnCommand(thread, text, commandId, messageId, createdAt);
  if (modelSelection !== null) command.modelSelection = modelSelection;
  const localCommand = /^\s*\/(clear|side|btw)(?:\s+|$)/.exec(text);
  if (composerCommands && localCommand !== null) {
    command.composerText = text;
    command.message.text = text.substring(localCommand[0].length);
    if (localCommand[1] === 'clear') command.freshContext = true;
    else { command.sideThreadId = `side:${messageId}`; command.sideForkCommandId = `fork:${commandId}`; }
  }
  if (!command.sideThreadId && (thread.session?.activeTurnId ||
    ['running', 'starting'].includes(thread.session?.status ?? '') || thread.turns?.some((turn: LatestTurn) => turn.state === 'queued'))) {
    command.dispatchMode = { type: 'queue_after_active' };
    if (delivery === 'steer' && thread.session?.activeTurnId && !command.freshContext && modelSelection === null) {
      command.dispatchMode = { type: 'steer_active', targetRunId: thread.session.activeTurnId };
    }
  }
  return command;
}

export interface ModelOptionSelection { id: string; value: string | boolean; }
export interface ModelOptionChoice { id: string; label: string; isDefault?: boolean; }
export interface ModelOptionDescriptor {
  id: string; label: string; type: string; description?: string; role?: string;
  currentValue?: string | boolean; options?: ModelOptionChoice[]; promptInjectedValues?: string[];
}
export interface ModelCapabilities { optionDescriptors?: ModelOptionDescriptor[]; }

export interface ModelSelection {
  options?: ModelOptionSelection[];
  instanceId: string;
  model: string;
}

export interface ModelSwitch { from: ModelSelection; to: ModelSelection; }

export interface ProviderModel {
  capabilities?: ModelCapabilities;
  slug: string;
  name: string;
  shortName?: string;
}

export interface ProviderInfo {
  driver?: string;
  instanceId: string;
  displayName?: string;
  enabled: boolean;
  installed: boolean;
  availability?: string;
  supportsConversationRollback?: boolean;
  models: ProviderModel[];
}

export interface ModelChoice {
  driver?: string;
  providerLabel?: string;
  optionDescriptors?: ModelOptionDescriptor[];
  instanceId: string;
  model: string;
  label: string;
}

export function availableModels(providers: ProviderInfo[]): ModelChoice[] {
  const choices: ModelChoice[] = [];
  for (const provider of providers) {
    if (!provider.enabled || !provider.installed || provider.availability === 'unavailable') continue;
    for (const model of provider.models) {
      choices.push({ instanceId: provider.instanceId, model: model.slug, driver: provider.driver, providerLabel: provider.displayName ?? provider.instanceId,
        label: `${provider.displayName ?? provider.instanceId} · ${model.name}`, optionDescriptors: model.capabilities?.optionDescriptors });
    }
  }
  return choices;
}

export function preferredModelIndex(choices: ModelChoice[], preferred: ModelSelection | null): number {
  if (choices.length === 0) return -1;
  const index = choices.findIndex((choice: ModelChoice) =>
    choice.instanceId === preferred?.instanceId && choice.model === preferred?.model);
  return index < 0 ? 0 : index;
}

export function taskStatus(thread: ThreadShell): string {
  if (thread.archivedAt) return 'archived';
  if (thread.pendingRuntimeRequest) return 'waiting';
  const status = thread.activityRunStatus ?? thread.status ?? thread.session?.status ?? 'idle';
  if (status === 'waiting') return 'waiting';
  if (['preparing', 'starting', 'running'].includes(status) || thread.activeRunId || thread.session?.activeTurnId) return 'running';
  if (status === 'queued') return 'queued';
  if (status === 'failed' || status === 'error') return 'failed';
  if (['interrupted', 'cancelled', 'rolled_back', 'stopped'].includes(status)) return 'interrupted';
  if (thread.settledAt || (status === 'completed' && thread.settledOverride !== 'active')) return 'completed';
  return 'idle';
}

export function shownUnderParent(thread: ThreadShell, parentListed?: (env: string, id: string) => boolean): boolean {
  const parent = thread.delegatedFrom;
  return thread.lineage?.relationshipToParent === 'subagent' || thread.lineage?.sideChat === true ||
    (!!parent && parentListed?.(parent.environmentId, parent.threadId) === true);
}

export function visibleThreads(threads: ThreadShell[], projectId: string, filter: string,
  search: string, archiveOrder: string = 'newest', parentListed?: (env: string, id: string) => boolean): ThreadShell[] {
  const query = search.trim().toLocaleLowerCase();
  return threads.filter((thread: ThreadShell) => {
    if (shownUnderParent(thread, parentListed)) return false;
    if (projectId.length > 0 && thread.projectId !== projectId) return false;
    if (query.length > 0 && !(thread.title ?? '').toLocaleLowerCase().includes(query)) return false;
    if (filter === 'archived') return Boolean(thread.archivedAt);
    if (thread.archivedAt) return false;
    const settled = taskStatus(thread) === 'completed';
    if (filter === 'active') return !settled;
    if (filter === 'settled') return settled;
    if (['running', 'waiting', 'queued', 'failed', 'interrupted', 'idle'].includes(filter)) return taskStatus(thread) === filter;
    return true;
  }).sort((a: ThreadShell, b: ThreadShell) => {
    if (filter !== 'archived') return (b.updatedAt ?? '').localeCompare(a.updatedAt ?? '');
    const aTime = Date.parse(a.archivedAt ?? a.updatedAt ?? '');
    const bTime = Date.parse(b.archivedAt ?? b.updatedAt ?? '');
    const delta = (Number.isFinite(aTime) ? aTime : 0) - (Number.isFinite(bTime) ? bTime : 0);
    if (delta !== 0) return archiveOrder === 'oldest' ? delta : -delta;
    const aTitle = a.title ?? '', bTitle = b.title ?? '';
    if (aTitle !== bTitle) return aTitle < bTitle ? -1 : 1;
    return a.id < b.id ? -1 : a.id === b.id ? 0 : 1;
  });
}


export function searchArchivedThreads(snapshot: ShellSnapshot, query: string, environmentLabel: string,
  parentListed?: (env: string, id: string) => boolean): ThreadShell[] {
  const search = query.trim().toLocaleLowerCase();
  const projects = new Map<string, ProjectShell>();
  for (const project of snapshot.projects) projects.set(project.id, project);
  return snapshot.threads.filter((thread: ThreadShell) => {
    const project = projects.get(thread.projectId);
    if (shownUnderParent(thread, parentListed) || !thread.archivedAt || !project) return false;
    return [project.title, project.workspaceRoot, environmentLabel, thread.title ?? '', thread.branch ?? '']
      .some((value: string) => value.toLocaleLowerCase().includes(search));
  });
}
