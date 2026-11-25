export interface ComposerSkill { insertion: string; label: string; icon: string; }
export interface ComposerSpan { raw: string; kind: string; label: string; icon: string; href?: string; }

function plain(raw: string): ComposerSpan { return { raw: raw, kind: 'text', label: '', icon: '' }; }
function length(span: ComposerSpan): number { return span.kind === 'text' ? span.raw.length : 1; }

// Each native builder span occupies one UTF-16 position, while the saved draft keeps its full reference.
export function composerSpans(text: string, skills: ComposerSkill[]): ComposerSpan[] {
  const result: ComposerSpan[] = [];
  const pattern = /\[((?:\\.|[^\]\\])*)\]\(([^)\s]+)\)|\$([^\s$\[\](){},，。！？；、]+)/g;
  let offset = 0;
  let match: RegExpExecArray | null;
  while ((match = pattern.exec(text)) !== null) {
    let token: ComposerSpan | null = null;
    const thread = /^(?:t3-thread:\/\/v[12]\/|t3-context:\/\/v1\/thread\/|https:\/\/app\.t3\.codes\/threads\/)/.test(match[2] ?? '');
    if (match[2] && (!/^[a-z][a-z0-9+.-]*:/i.test(match[2]) || thread || /^[a-z]:[%/\\]/i.test(match[2]))) {
      const kind = thread ? 'thread' : 'file';
      token = { raw: match[0], label: match[1].replace(/\\([\\\[\]])/g, '$1'), kind: kind, icon: kind === 'thread' ? 'chat' : 'file', href: match[2] };
    } else if (match[3] && !/[a-zA-Z0-9_$]/.test(text.charAt(match.index - 1))) {
      const skill = skills.find((entry: ComposerSkill) => entry.insertion === match![0]);
      if (skill) token = { raw: match[0], kind: 'skill', label: skill.label, icon: skill.icon };
    }
    if (token === null) continue;
    if (match.index > offset) result.push(plain(text.substring(offset, match.index)));
    result.push(token);
    offset = match.index + match[0].length;
  }
  if (offset < text.length) result.push(plain(text.substring(offset)));
  return result;
}

export function composerRawText(spans: ComposerSpan[]): string { return spans.map((span: ComposerSpan) => span.raw).join(''); }

export function messageSkillSpans(text: string, skills: ComposerSkill[], literal: boolean = false): ComposerSpan[] {
  return literal ? [plain(text)] : composerSpans(text, skills).map((span: ComposerSpan): ComposerSpan => span.kind === 'skill' ? span : plain(span.raw));
}

export function messageReferenceSpans(text: string, skills: ComposerSkill[], literal: boolean = false): ComposerSpan[] {
  if (literal) return [plain(text)];
  const result: ComposerSpan[] = [];
  const append = (value: string): void => { result.push(...composerSpans(value, skills).map((span: ComposerSpan): ComposerSpan =>
    span.kind === 'skill' || span.kind === 'thread' ? span : plain(span.raw))); };
  const code = /(`{3,}|~{3,})[\s\S]*?(?:\1|$)|(`+)[^\n]*?\2/g;
  let offset = 0, match: RegExpExecArray | null;
  while ((match = code.exec(text)) !== null) {
    append(text.substring(offset, match.index)); result.push(plain(match[0])); offset = match.index + match[0].length;
  }
  append(text.substring(offset));
  return result;
}

export function composerRawOffset(spans: ComposerSpan[], viewOffset: number): number {
  let remaining = Math.max(0, viewOffset), raw = 0;
  for (const span of spans) {
    const size = length(span);
    if (remaining < size) return raw + (span.kind === 'text' ? remaining : 0);
    raw += span.raw.length; remaining -= size;
  }
  return raw;
}

export function composerViewOffset(spans: ComposerSpan[], rawOffset: number): number {
  let remaining = Math.max(0, rawOffset), view = 0;
  for (const span of spans) {
    if (remaining < span.raw.length) return view + (span.kind === 'text' ? remaining : remaining === 0 ? 0 : 1);
    remaining -= span.raw.length; view += length(span);
  }
  return view;
}

function sliceSpans(spans: ComposerSpan[], from: number, to: number): ComposerSpan[] {
  const result: ComposerSpan[] = [];
  let offset = 0;
  for (const span of spans) {
    const end = offset + length(span);
    if (from < end && to > offset) result.push(span.kind === 'text' ? plain(span.raw.substring(Math.max(0, from - offset), Math.min(length(span), to - offset))) : span);
    offset = end;
  }
  return result;
}

export function editComposerSpans(spans: ComposerSpan[], from: number, to: number, inserted: string): ComposerSpan[] {
  const result = sliceSpans(spans, 0, from);
  if (inserted) result.push(plain(inserted));
  return result.concat(sliceSpans(spans, to, Number.MAX_SAFE_INTEGER));
}
