export interface FileEntry {
  path: string;
  kind: string;
}

export function binaryFilePath(path: string): boolean {
  return /\.(pdf|docx?|xlsx?|pptx?|odt|ods|odp|zip|7z|rar|gz|bz2|xz|tar|tgz|png|jpe?g|gif|webp|avif|heic|heif|bmp|ico|icns|mp[34]|mov|mkv|webm|wav|ogg|m4a|flac|sqlite3?|db|woff2?|ttf|otf|eot|wasm|exe|dll|so|dylib|hap|apk)$/i.test(path);
}

export function binaryFileError(message: string): boolean { return /"failure"\s*:\s*"binary_file"/.test(message); }

export function downloadFileName(path: string): string {
  const name = (path.split(/[\\/]/).pop() ?? '').replace(/[\x00-\x1f\x7f:*?"<>|]/g, '_').trim();
  return !name || /^\.+$/.test(name) ? '文件' : name;
}

export function fileErrorText(message: string): string {
  if (binaryFileError(message)) return '此文件不是文本，无法在文本预览中打开。';
  if (/Asset(WorkspaceAsset|Attachment)NotFoundError|Workspace asset was not found|Attachment was not found/.test(message)) return '文件不存在或已移动，请确认电脑上的原文件仍然存在。';
  if (message.includes('AssetPreviewTypeValidationError')) return '当前服务器不支持下载此类型的文件，请更新电脑端后重试。';
  if (/AssetWorkspaceContext|AssetWorkspaceResolutionError/.test(message)) return '无法找到文件所在的会话目录，请返回原会话重试。';
  if (message.includes('ProjectReadFileError')) return '无法读取此文件，可尝试下载原文件；请确认电脑上的文件仍在原目录中。';
  if (message.includes('RPC connection') || message.includes('RPC is not connected')) return '连接已断开，请刷新重试。';
  if (message.startsWith('RPC ')) return '无法加载项目文件，请刷新重试。';
  return message;
}

function wordContainsAbbreviation(word: string, token: string): boolean {
  let index = 0;
  for (let offset = 0; offset < word.length; offset++) {
    if (word[offset] === token[index]) index++;
    if (index === token.length) return true;
  }
  return false;
}

function matchesPathSearch(path: string, query: string, tokens: string[]): boolean {
  if (path.toLowerCase().includes(query)) return true;
  const segments = path.toLowerCase().split('/');
  const words = path.replace(/([A-Z]+)([A-Z][a-z])/g, '$1 $2').replace(/([a-z0-9])([A-Z])/g, '$1 $2')
    .split(/[^A-Za-z0-9]+/).filter((word: string) => word.length > 0).map((word: string) => word.toLowerCase());
  return tokens.every((token: string) => segments.some((segment: string) => segment.includes(token)) ||
    words.some((word: string) => wordContainsAbbreviation(word, token)));
}

export function directoryEntries(entries: FileEntry[], directory: string, search: string): FileEntry[] {
  const result: Map<string, FileEntry> = new Map();
  const prefix = directory ? directory + '/' : '';
  const query = search.trim().toLowerCase();
  const tokens = query.split(/[\s/\\._-]+/).filter((token: string) => token.length > 0);
  for (const entry of entries) {
    if (entry.path.startsWith('/') || entry.path.split('/').some((part: string) => part === '..' || part === '')) continue;
    if (query && tokens.length > 0) {
      if (matchesPathSearch(entry.path, query, tokens)) result.set(entry.path, entry);
      continue;
    }
    if (!entry.path.startsWith(prefix)) continue;
    const remainder = entry.path.substring(prefix.length);
    const slash = remainder.indexOf('/');
    const row: FileEntry = slash < 0 ? entry : { path: prefix + remainder.substring(0, slash), kind: 'directory' };
    result.set(row.path, row);
  }
  const rows: FileEntry[] = [];
  result.forEach((entry: FileEntry) => { rows.push(entry); });
  return rows.sort((a: FileEntry, b: FileEntry) => {
    if (a.kind !== b.kind) return a.kind === 'directory' ? -1 : 1;
    return a.path.localeCompare(b.path);
  });
}
