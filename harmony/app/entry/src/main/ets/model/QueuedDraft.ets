import { ChatAttachment, QueuedMessage } from './Models';

export interface QueuedDraft { base: string; text: string; attachments: ChatAttachment[]; }
export function queuedDraftBase(message: QueuedMessage): string { return JSON.stringify([message.runId, message.text, message.attachments]); }
export function queuedDraftText(message: QueuedMessage, text: string, attachments: ChatAttachment[]): string {
  const draft: QueuedDraft = { base: queuedDraftBase(message), text: text, attachments: attachments };
  return JSON.stringify(draft);
}
export function restoreQueuedDraft(message: QueuedMessage, raw: string): QueuedDraft | null {
  try {
    const value = JSON.parse(raw) as QueuedDraft;
    if (value.base === queuedDraftBase(message) && typeof value.text === 'string' && Array.isArray(value.attachments) &&
      value.attachments.every((attachment: ChatAttachment) => message.attachments.some((original: ChatAttachment) => JSON.stringify(original) === JSON.stringify(attachment)))) return value;
  } catch (_) {}
  return null;
}
