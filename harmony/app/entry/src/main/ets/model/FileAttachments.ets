export const MAX_FILE_BYTES: number = 50 * 1024 * 1024;

export function fileUploadLimit(advertised: number | undefined): number {
  return advertised !== undefined && Number.isSafeInteger(advertised) && advertised > 0 ? Math.min(advertised, MAX_FILE_BYTES) : 0;
}

export function attachmentMime(name: string): string {
  const extension = name.toLowerCase().split('.').pop() ?? '';
  const types: Record<string, string> = {
    'pdf': 'application/pdf', 'txt': 'text/plain', 'md': 'text/markdown', 'csv': 'text/csv', 'json': 'application/json',
    'yaml': 'text/yaml', 'yml': 'text/yaml', 'xml': 'application/xml', 'html': 'text/html', 'css': 'text/css',
    'js': 'text/javascript', 'ts': 'text/plain', 'py': 'text/plain', 'java': 'text/plain', 'kt': 'text/plain',
    'c': 'text/plain', 'h': 'text/plain', 'cpp': 'text/plain', 'rs': 'text/plain', 'go': 'text/plain', 'sh': 'text/plain',
    'zip': 'application/zip', 'gz': 'application/gzip', 'tar': 'application/x-tar',
    'doc': 'application/msword', 'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel', 'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'gif': 'image/gif', 'webp': 'image/webp',
    'heic': 'image/heic', 'heif': 'image/heif', 'mp4': 'video/mp4', 'mov': 'video/quicktime', 'mp3': 'audio/mpeg', 'wav': 'audio/wav'
  };
  return types[extension] ?? 'application/octet-stream';
}

export function supportedImageFile(name: string): boolean {
  return ['image/png', 'image/jpeg', 'image/gif', 'image/webp', 'image/heic', 'image/heif'].includes(attachmentMime(name));
}
