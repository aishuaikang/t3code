import { ChatAttachment, ProjectShell, StartTurnCommand, ThreadDetail, ThreadShell, TimelineRow } from './Models';
import { quoteMessageCopyText } from './MessageQuote';

export interface ForwardContent { text: string; attachments: ChatAttachment[]; count: number; }
function copyAttachment(attachment: ChatAttachment): ChatAttachment {
  return { id: attachment.id, type: attachment.type, name: attachment.name, mimeType: attachment.mimeType, sizeBytes: attachment.sizeBytes };
}

export function canForwardMessage(row: TimelineRow): boolean {
  return row.kind === 'message' && ['user', 'assistant'].includes(row.role) && !row.streaming &&
    (!!row.text.trim() || (row.attachments?.length ?? 0) > 0);
}

export function forwardContent(rows: TimelineRow[], ids: string[], title: string): ForwardContent {
  const selected = new Set(ids);
  const messages = rows.filter((row: TimelineRow) => selected.has(row.id) && canForwardMessage(row));
  if (selected.size === 0 || messages.length !== selected.size) throw new Error('请选择完整的消息，内容已变化的消息需重新选择');
  const attachments: Map<string, ChatAttachment> = new Map();
  const parts: string[] = [];
  for (const row of messages) {
    for (const attachment of row.attachments ?? []) attachments.set(attachment.id, copyAttachment(attachment));
    const text = quoteMessageCopyText(row.text) || (row.attachments ?? []).map((attachment: ChatAttachment) => attachment.name).join('、');
    parts.push(`${row.role === 'user' ? '用户' : '助手'}：\n${text.split('\n').map((line: string) => '> ' + line).join('\n')}`);
  }
  if (attachments.size > 8) throw new Error('一次转发最多包含 8 个附件，请减少所选消息');
  return { text: `转发自「${title.trim().replace(/[\r\n]+/g, ' ') || '对话'}」\n\n${parts.join('\n\n')}`,
    attachments: Array.from(attachments.values()), count: messages.length };
}

function readOnlyRecipient(thread: ThreadShell | ThreadDetail): boolean {
  return thread.lineage?.relationshipToParent === 'subagent' && thread.creationSource === 'provider';
}

export function forwardTargets(threads: ThreadShell[], projects: ProjectShell[], sourceThreadId: string, query: string): ThreadShell[] {
  const keyword = query.trim().toLocaleLowerCase();
  return threads.filter((thread: ThreadShell) => thread.id !== sourceThreadId && !thread.archivedAt && !readOnlyRecipient(thread) &&
    `${thread.title ?? ''} ${thread.branch ?? ''} ${projects.find((project: ProjectShell) => project.id === thread.projectId)?.title ?? ''}`
      .toLocaleLowerCase().includes(keyword)).sort((left: ThreadShell, right: ThreadShell) =>
        (Date.parse(right.updatedAt ?? '') || 0) - (Date.parse(left.updatedAt ?? '') || 0));
}

export function forwardCommand(thread: ThreadDetail, content: ForwardContent, commandId: string,
  messageId: string, createdAt: string): StartTurnCommand {
  if (readOnlyRecipient(thread)) throw new Error('此子会话只读，请选择其他会话');
  if (!content.count || !content.text.trim() || content.attachments.length > 8) throw new Error('转发内容无效，请重新选择消息');
  // A forward is quoted content, never a local slash command, and never interrupts its recipient.
  return { type: 'thread.turn.start', commandId: commandId, threadId: thread.id,
    message: { messageId: messageId, role: 'user', text: content.text, attachments: content.attachments.map(copyAttachment) },
    runtimeMode: thread.runtimeMode, interactionMode: thread.interactionMode ?? 'default', createdAt: createdAt,
    dispatchMode: { type: 'queue_after_active' } };
}
