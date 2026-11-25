import { MessageContext, ThreadShell, ProjectShell } from './Models';

export interface ThreadReferenceTarget { environmentId: string; threadId: string; title: string; }
export interface ThreadReferenceLink { href: string; label: string; }
export interface ThreadLinkMetadata { title: string; projectId: string | null; }
export interface ThreadNavigationTarget extends ThreadReferenceTarget { projectTitle: string; cwd: string; available: boolean; }
export interface ThreadReference extends ThreadNavigationTarget {
  href: string; iconText: string; iconColor: string;
}

const PROJECT_COLORS: string[] = ['gray', 'red', 'orange', 'amber', 'yellow', 'lime', 'green', 'emerald', 'teal', 'cyan', 'sky', 'blue', 'indigo', 'violet', 'purple', 'fuchsia', 'pink', 'rose'];

export function threadReferenceIconTint(color: string, dark: boolean): string {
  const colors: string[] = dark ?
    ['#9CA3AF', '#F87171', '#FB923C', '#FBBF24', '#FACC15', '#A3E635', '#4ADE80', '#34D399', '#2DD4BF', '#22D3EE', '#38BDF8', '#60A5FA', '#818CF8', '#A78BFA', '#C084FC', '#E879F9', '#F472B6', '#FB7185'] :
    ['#4B5563', '#DC2626', '#EA580C', '#D97706', '#CA8A04', '#65A30D', '#16A34A', '#059669', '#0D9488', '#0891B2', '#0284C7', '#2563EB', '#4F46E5', '#7C3AED', '#9333EA', '#C026D3', '#DB2777', '#E11D48'];
  return colors[PROJECT_COLORS.indexOf(color)] ?? colors[11];
}

function projectMonogram(title: string): string {
  const words = title.normalize('NFKC').trim().match(/[\p{L}\p{N}]+/gu) ?? [];
  const glyphs = Array.from(words[0] ?? 'PR');
  const second = glyphs.slice(1).find((glyph: string) => /\p{N}/u.test(glyph)) ??
    (words.length > 1 ? Array.from(words[words.length - 1])[0] : glyphs[glyphs.length - 1]) ?? glyphs[0];
  return Array.from((glyphs[0] + second).toUpperCase()).slice(0, 2).join('');
}

function projectColor(title: string): string {
  let index = 0;
  for (const glyph of Array.from(title.normalize('NFKC').trim().toLocaleLowerCase('en-US') || 'project')) {
    index = (index * 31 + (glyph.codePointAt(0) ?? 0)) % PROJECT_COLORS.length;
  }
  return PROJECT_COLORS[index];
}

export function threadReferenceTarget(href: string, environmentId: string, context?: MessageContext): ThreadReferenceTarget | null {
  const reference = /^t3-context:\/\/v1\/thread\/([a-z0-9_-]{1,128})$/i.exec(href);
  if (reference !== null) {
    const record = context?.records?.find((entry) => entry.kind === 'thread' && entry.contextId === reference[1]);
    // Context ids can be hashed producer keys. Only the attached record names the actual thread.
    return { environmentId: record?.environmentId ?? '', threadId: record?.threadId ?? '', title: record?.title ?? record?.label ?? '' };
  }
  const local = /^t3-thread:\/\/v1\/([^\s]+)$/.exec(href);
  if (local !== null) return { environmentId: environmentId, threadId: local[1], title: '' };
  const scoped = /^t3-thread:\/\/v2\/([^/\s]+)\/([^\s]+)$/.exec(href);
  if (scoped !== null) return { environmentId: scoped[1], threadId: scoped[2], title: '' };
  const hosted = /^https:\/\/app\.t3\.codes\/threads\/([^/?#\s]+)\/([^/?#\s]+)$/.exec(href);
  if (hosted !== null) {
    try { return { environmentId: decodeURIComponent(hosted[1]), threadId: decodeURIComponent(hosted[2]), title: '' }; }
    catch (_) { return null; }
  }
  return null;
}

export function threadReferenceIds(threadId: string): string[] {
  try {
    const decoded = decodeURIComponent(threadId);
    return decoded !== threadId && decoded.trim() ? [threadId, decoded] : [threadId];
  } catch (_) { return [threadId]; }
}

export function presentThreadReference(href: string, label: string, target: ThreadReferenceTarget,
  threads: ThreadShell[], projects: ProjectShell[], metadata: Record<string, ThreadLinkMetadata>): ThreadReference {
  const candidates = threadReferenceIds(target.threadId);
  const thread = candidates.map((id: string) => threads.find((entry: ThreadShell) => entry.id === id))
    .find((entry) => entry !== undefined);
  const id = thread?.id ?? candidates.find((id: string) => metadata[id] !== undefined) ?? target.threadId;
  const details = thread ?? metadata[id];
  const project = projects.find((entry: ProjectShell) => entry.id === details?.projectId);
  return { href: href, environmentId: target.environmentId, threadId: id,
    title: details?.title?.trim() || target.title || label || '会话', projectTitle: project?.title ?? '',
    cwd: thread?.worktreePath ?? project?.workspaceRoot ?? '', available: !!target.environmentId && !!id,
    iconText: project?.projectIcon?.kind === 'emoji' ? project.projectIcon.emoji ?? '' :
      project?.projectIcon?.kind === 'monogram' ? project.projectIcon.text ?? '' : project ? projectMonogram(project.title) : '',
    iconColor: project?.projectIcon?.color ?? projectColor(project?.title ?? '') };
}
