/** Selection indices refer to a frozen viewport, never raw ANSI output or scrollback. */
export function terminalExcerpt(lines: string[], start: number, end: number, label: string): string | null {
  if (!Number.isInteger(start) || !Number.isInteger(end) || start < 0 || end < start || end >= lines.length) return null;
  const text = lines.slice(start, end + 1).join('\n');
  if (!text.trim() || text.length > 64000) return null;
  let fence = '```';
  for (const match of text.match(/`{3,}/g) ?? []) if (match.length >= fence.length) fence = '`'.repeat(match.length + 1);
  return `终端 ${label} · 可见行 ${start + 1}–${end + 1}\n\n${fence}text\n${text}\n${fence}`;
}
