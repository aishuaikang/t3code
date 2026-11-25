export interface CodeToken { text: string; kind: string; }

// Small, conservative lexer: unsupported languages retain their original text.
export function highlightCode(text: string, language: string): CodeToken[] {
  const name = language.trim().toLowerCase().split(/\s/)[0];
  const shell = ['sh', 'bash', 'shell', 'zsh'].includes(name);
  const hashComment = shell || ['py', 'python', 'yaml', 'yml'].includes(name);
  if (text.length > 32768 || !['js', 'javascript', 'ts', 'typescript', 'jsx', 'tsx', 'ets', 'json', 'jsonc',
    'sh', 'bash', 'shell', 'zsh', 'py', 'python', 'go', 'rs', 'rust', 'c', 'cpp', 'java', 'kotlin', 'swift', 'yaml', 'yml'].includes(name)) {
    return [{ text: text, kind: 'plain' }];
  }
  const keywords = new Set(('async await break case catch class const continue def default do else enum export extends false finally fn for from func function if implements import in interface let match new nil none null package pass private public raise return static struct super switch this throw true try type typeof undefined val var void when while with yield').split(' '));
  const builtins = new Set(('cd echo export fi git node npm pnpm pwd then vp yarn').split(' '));
  const pattern = hashComment ? /#[^\r\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|\$\{[^}]*\}|\$[A-Za-z_]\w*|\b(?:0x[\da-fA-F]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\b|\b[A-Za-z_]\w*\b/g :
    /\/\/[^\r\n]*|\/\*[\s\S]*?\*\/|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`|\b(?:0x[\da-fA-F]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\b|\b[A-Za-z_]\w*\b/g;
  const result: CodeToken[] = [];
  let offset = 0;
  let match = pattern.exec(text);
  while (match !== null) {
    if (result.length > 4096) return [{ text: text, kind: 'plain' }];
    if (match.index > offset) result.push({ text: text.substring(offset, match.index), kind: 'plain' });
    const value = match[0];
    const kind = value.startsWith('//') || value.startsWith('/*') || (hashComment && value.startsWith('#')) ? 'comment' :
      /^["'`]/.test(value) ? 'string' : /^\d/.test(value) ? 'number' : value.startsWith('$') ? 'variable' :
      keywords.has(value) ? 'keyword' : shell && builtins.has(value) ? 'function' : 'plain';
    result.push({ text: value, kind: kind });
    offset = pattern.lastIndex;
    match = pattern.exec(text);
  }
  if (offset < text.length) result.push({ text: text.substring(offset), kind: 'plain' });
  return result;
}
