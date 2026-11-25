export interface ComposerPathTrigger { query: string; start: number; end: number; }
export interface ComposerPathInsertion { text: string; cursor: number; }
export interface ComposerPathEntry { path: string; kind: string; label?: string; threadId?: string; }
interface ComposerThread { id: string; title: string | null; updatedAt: string | null; archivedAt?: string | null; }

export function composerPathEntries(files: ComposerPathEntry[] | undefined, threads: ComposerThread[], query: string, currentId: string = ''): ComposerPathEntry[] {
  const term = query.trim().toLocaleLowerCase();
  const matches = threads.filter((thread: ComposerThread) => thread.id !== currentId && !thread.archivedAt &&
    !!thread.title && (!term || thread.title.toLocaleLowerCase().includes(term)))
    .sort((a: ComposerThread, b: ComposerThread) => (b.updatedAt ?? '').localeCompare(a.updatedAt ?? '')).slice(0, 5);
  return matches.map((thread: ComposerThread): ComposerPathEntry => ({ path: thread.id, kind: 'thread', threadId: thread.id,
    label: thread.title ?? '未命名任务' })).concat(files ?? []).slice(0, 20);
}

export function composerEntryLabel(entry: ComposerPathEntry): string {
  if (entry.label) return entry.label;
  return entry.path.substring(Math.max(entry.path.lastIndexOf('/'), entry.path.lastIndexOf('\\')) + 1) || entry.path;
}

export function composerEntryDescription(entry: ComposerPathEntry): string {
  if (entry.kind === 'thread') return '会话';
  const separator = Math.max(entry.path.lastIndexOf('/'), entry.path.lastIndexOf('\\'));
  return separator < 0 ? '' : entry.path.substring(0, separator);
}

export function composerPathTrigger(text: string, start: number, end: number): ComposerPathTrigger | null {
  if (start !== end) return null;
  const cursor = Number.isFinite(end) ? Math.max(0, Math.min(text.length, Math.floor(end))) : text.length;
  const match = /[@＠]([^\s@＠，。！？；、()（）]*)$/.exec(text.substring(0, cursor));
  if (match === null || /[a-zA-Z0-9_.+\-@＠/\\]/.test(text.charAt(match.index - 1))) return null;
  const prefix = text.substring(0, match.index).split(/\s/).pop() ?? '';
  if (prefix.includes('://')) return null;
  let to = cursor;
  while (to < text.length && !/[\s@＠，。！？；、()（）]/.test(text.charAt(to))) to++;
  return { query: match[1], start: match.index, end: to };
}

export function insertComposerPath(text: string, trigger: ComposerPathTrigger, path: string): ComposerPathInsertion {
  const separator = Math.max(path.lastIndexOf('/'), path.lastIndexOf('\\'));
  const label = path.substring(separator + 1).replace(/\\/g, '\\\\').replace(/\[/g, '\\[').replace(/\]/g, '\\]');
  const destination = encodeURI(path).replace(/\(/g, '%28').replace(/\)/g, '%29')
    .replace(/#/g, '%23').replace(/\?/g, '%3F').replace(/\\/g, '%5C');
  const replacement = `[${label}](${destination}) `;
  return { text: text.substring(0, trigger.start) + replacement + text.substring(trigger.end), cursor: trigger.start + replacement.length };
}

export function insertComposerEntry(text: string, trigger: ComposerPathTrigger, entry: ComposerPathEntry): ComposerPathInsertion {
  if (entry.kind !== 'thread' || !entry.threadId) return insertComposerPath(text, trigger, entry.path);
  const label = composerEntryLabel(entry).replace(/[\[\]\\\r\n]/g, ' ').replace(/\s+/g, ' ').trim();
  const replacement = `[${label}](t3-thread://v1/${encodeURIComponent(entry.threadId)}) `;
  return { text: text.substring(0, trigger.start) + replacement + text.substring(trigger.end), cursor: trigger.start + replacement.length };
}
