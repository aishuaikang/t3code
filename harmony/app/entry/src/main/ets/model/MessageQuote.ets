import { ChatAttachment, TimelineRow } from './Models';

export interface MessageQuote {
  environmentId: string;
  threadId: string;
  messageId: string;
  role: string;
  text: string;
  images?: ChatAttachment[];
}
interface QuoteSource { environmentId: string; threadId: string; messageId: string; role: string; images?: ChatAttachment[]; }
export interface QuotedMessage { text: string; quote: MessageQuote | null; }

function validQuoteImages(images: ChatAttachment[] | undefined): ChatAttachment[] {
  if (!Array.isArray(images)) return [];
  return images.filter((image: ChatAttachment) => image !== null && typeof image === 'object' && image.type === 'image' &&
    typeof image.id === 'string' && !!image.id && typeof image.name === 'string' && typeof image.mimeType === 'string' &&
    typeof image.sizeBytes === 'number' && Number.isFinite(image.sizeBytes) && image.sizeBytes >= 0);
}

export function messageQuoteImages(quote: MessageQuote | null, rows: TimelineRow[], environmentId: string, threadId: string): ChatAttachment[] {
  if (quote === null || quote.environmentId !== environmentId) return [];
  const images = validQuoteImages(quote.images);
  if (images.length > 0) return images;
  const original = rows.find((row: TimelineRow) => row.kind === 'message' && row.id === quote.messageId &&
    (row.sourceThreadId ?? threadId) === quote.threadId);
  return validQuoteImages(original?.attachments);
}

export function messageQuotePreview(quote: MessageQuote): string {
  return quote.text.replace(/!?\[([^\]]*)\]\(t3-context:\/\/v1\/(image|attachment)\/[^\s)]+\)/g,
    (_match: string, name: string, kind: string) => `[${kind === 'image' ? '图片' : '附件'}] ${name}`).replace(/\s+/g, ' ').trim();
}

export function canQuoteMessage(row: TimelineRow): boolean {
  return row.kind === 'message' && ['user', 'assistant'].includes(row.role) && !row.streaming &&
    (!!row.text.trim() || (row.attachments?.length ?? 0) > 0);
}

export function messageQuoteAuthor(quote: MessageQuote): string { return quote.role === 'user' ? '我' : 'AI'; }

export function quotedMessageText(text: string, quote: MessageQuote | null = null): string {
  if (!quote) return text;
  const source: QuoteSource = { environmentId: quote.environmentId, threadId: quote.threadId, messageId: quote.messageId, role: quote.role };
  const images = validQuoteImages(quote.images);
  if (images.length > 0) source.images = images;
  // The metadata is hidden in Markdown; the quoted words remain readable on every client and by the provider.
  const metadata = encodeURIComponent(JSON.stringify(source)).replace(/-/g, '%2D');
  return `<!-- t3-message-quote:v1 ${metadata} -->\n> ${messageQuoteAuthor(quote)}\n` +
    quote.text.replace(/\r\n?/g, '\n').split('\n').map((line: string) => '> ' + line).join('\n') + '\n\n' + text;
}

export function parseQuotedMessage(raw: string): QuotedMessage {
  const original: QuotedMessage = { text: raw, quote: null };
  const header = /^<!-- t3-message-quote:v1 ([^\s]+) -->\n> (我|AI)\n/.exec(raw);
  if (header === null) return original;
  try {
    const source = JSON.parse(decodeURIComponent(header[1])) as QuoteSource;
    if (typeof source.environmentId !== 'string' || !source.environmentId || typeof source.threadId !== 'string' || !source.threadId ||
      typeof source.messageId !== 'string' || !source.messageId || !['user', 'assistant'].includes(source.role) ||
      header[2] !== (source.role === 'user' ? '我' : 'AI')) return original;
    const remainder = raw.substring(header[0].length), separator = remainder.indexOf('\n\n');
    if (separator < 0) return original;
    const lines = remainder.substring(0, separator).split('\n');
    if (!lines.every((line: string) => line.startsWith('> '))) return original;
    const quote: MessageQuote = { environmentId: source.environmentId, threadId: source.threadId,
      messageId: source.messageId, role: source.role, text: lines.map((line: string) => line.substring(2)).join('\n') };
    const images = validQuoteImages(source.images);
    if (images.length > 0) quote.images = images;
    return { text: remainder.substring(separator + 2), quote: quote };
  } catch (_) { return original; }
}

export function createMessageQuote(row: TimelineRow, environmentId: string, threadId: string): MessageQuote | null {
  if (!canQuoteMessage(row)) return null;
  const body = parseQuotedMessage(row.text).text;
  const quote: MessageQuote = { environmentId: environmentId, threadId: row.sourceThreadId ?? threadId, messageId: row.id, role: row.role,
    text: body.trim() ? body : (row.attachments ?? []).map((attachment) => `[${attachment.type === 'image' ? '图片' : '附件'}] ${attachment.name}`).join('\n') };
  const images = validQuoteImages(row.attachments);
  if (images.length > 0) quote.images = images;
  return quote;
}

export function quoteMessageCopyText(raw: string): string {
  const message = parseQuotedMessage(raw);
  if (message.quote === null) return raw;
  return `> ${messageQuoteAuthor(message.quote)}\n` + message.quote.text.split('\n').map((line: string) => '> ' + line).join('\n') + '\n\n' + message.text;
}
