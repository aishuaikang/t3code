import { ChatAttachment } from './Models';

export interface AttachmentPart { text: string; attachmentId: string; }

export function attachmentFileRows(text: string, attachments: ChatAttachment[]): ChatAttachment[] {
  return attachments.filter((attachment: ChatAttachment) => attachment.type !== 'image' && (!attachment.name || !text.includes(attachment.name)));
}

export function attachmentFormat(attachment: ChatAttachment): string {
  const extension = attachment.name.match(/\.([a-z0-9]{1,8})$/i);
  return extension ? extension[1].toUpperCase() : attachment.mimeType === 'application/pdf' ? 'PDF' : '文件';
}

export function attachmentParts(text: string, attachments: ChatAttachment[]): AttachmentPart[] {
  const result: AttachmentPart[] = [];
  const reference = /!?\[([^\]]*)\]\(t3-context:\/\/v1\/(?:image|attachment)\/([^\s)]+)\)/g;
  let offset = 0;
  let match: RegExpExecArray | null;
  while ((match = reference.exec(text)) !== null) {
    result.push(...namedAttachmentParts(text.substring(offset, match.index), attachments));
    const name = match[1] || '图片';
    const attachment = attachments.find((entry: ChatAttachment) => entry.id === match![2] || entry.name === name);
    result.push({ text: attachment ? `${name} · ${attachmentSize(attachment.sizeBytes)}` : name, attachmentId: attachment?.id ?? '' });
    offset = match.index + match[0].length;
  }
  result.push(...namedAttachmentParts(text.substring(offset), attachments));
  return result;
}

function namedAttachmentParts(text: string, attachments: ChatAttachment[]): AttachmentPart[] {
  const result: AttachmentPart[] = [];
  let offset = 0;
  while (offset < text.length) {
    let next = text.length;
    let selected: ChatAttachment | undefined;
    for (const attachment of attachments) {
      const position = attachment.name ? text.indexOf(attachment.name, offset) : -1;
      if (position >= 0 && position < next) { next = position; selected = attachment; }
    }
    if (next > offset) result.push({ text: text.substring(offset, next), attachmentId: '' });
    if (!selected) break;
    result.push({ text: selected.name, attachmentId: selected.id });
    offset = next + selected.name.length;
  }
  return result;
}

export function attachmentSize(bytes: number): string {
  return bytes >= 1024 * 1024 ? `${(bytes / 1024 / 1024).toFixed(1)} MB` : `${Math.max(1, Math.round(bytes / 1024))} KB`;
}
