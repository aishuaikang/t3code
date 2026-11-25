export interface ImagePoint { x: number; y: number; }
export interface ImageStroke { color: string; width: number; points: ImagePoint[]; kind?: string; text?: string; fontSize?: number; textWidth?: number; }
export interface ImageRect { left: number; top: number; right: number; bottom: number; }
export interface ImageNote { x: number; y: number; text: string; }
export interface ImageSize { width: number; height: number; }
export interface ImageEditDocument {
  notes: ImageNote[]; width: number; height: number; strokes: ImageStroke[]; history: ImageStroke[][]; future: ImageStroke[][];
  masks: ImageStroke[]; maskHistory: ImageStroke[][]; maskFuture: ImageStroke[][];
}
export function emptyImageEdits(): ImageEditDocument { return { notes: [], width: 0, height: 0, strokes: [], history: [], future: [], masks: [], maskHistory: [], maskFuture: [] }; }
export function copyStrokes(strokes: ImageStroke[]): ImageStroke[] {
  return strokes.map((stroke: ImageStroke): ImageStroke => ({ color: stroke.color, width: stroke.width,
    points: stroke.points.map((point: ImagePoint): ImagePoint => ({ x: point.x, y: point.y })),
    kind: stroke.kind, text: stroke.text, fontSize: stroke.fontSize, textWidth: stroke.textWidth }));
}
export function imageShapePoints(kind: string, start: ImagePoint, end: ImagePoint): ImagePoint[] {
  if (kind === 'line') return [start, end];
  if (kind === 'arrow') {
    const angle = Math.atan2(end.y - start.y, end.x - start.x), length = Math.min(0.06, Math.hypot(end.x - start.x, end.y - start.y) * 0.3);
    return [start, end, { x: end.x - length * Math.cos(angle - 0.5), y: end.y - length * Math.sin(angle - 0.5) }, end,
      { x: end.x - length * Math.cos(angle + 0.5), y: end.y - length * Math.sin(angle + 0.5) }];
  }
  const left = Math.min(start.x, end.x), top = Math.min(start.y, end.y), width = Math.abs(end.x - start.x), height = Math.abs(end.y - start.y);
  let unit: ImagePoint[] = [];
  if (kind === 'rectangle') unit = [{ x: 0, y: 0 }, { x: 1, y: 0 }, { x: 1, y: 1 }, { x: 0, y: 1 }];
  else if (kind === 'triangle') unit = [{ x: 0.5, y: 0 }, { x: 1, y: 1 }, { x: 0, y: 1 }];
  else if (kind === 'diamond') unit = [{ x: 0.5, y: 0 }, { x: 1, y: 0.5 }, { x: 0.5, y: 1 }, { x: 0, y: 0.5 }];
  else {
    const count = kind === 'star' ? 10 : 64;
    for (let i = 0; i < count; i++) {
      const angle = i / count * Math.PI * 2;
      if (kind === 'heart') unit.push({ x: (16 * Math.pow(Math.sin(angle), 3) + 16) / 32,
        y: (12 - (13 * Math.cos(angle) - 5 * Math.cos(2 * angle) - 2 * Math.cos(3 * angle) - Math.cos(4 * angle))) / 29 });
      else { const radius = kind === 'star' && i % 2 ? 0.22 : 0.5; unit.push({ x: 0.5 + radius * Math.sin(angle), y: 0.5 - radius * Math.cos(angle) }); }
    }
  }
  const points = unit.map((point: ImagePoint): ImagePoint => ({ x: left + point.x * width, y: top + point.y * height }));
  if (points.length) points.push({ x: points[0].x, y: points[0].y });
  return points;
}
export function imageStrokeBounds(stroke: ImageStroke): ImageRect {
  const xs = stroke.points.map((point: ImagePoint): number => point.x), ys = stroke.points.map((point: ImagePoint): number => point.y);
  const left = Math.min(...xs), top = Math.min(...ys);
  return { left: left, top: top,
    right: stroke.kind === 'text' ? left + (stroke.textWidth ?? 0.1) : Math.max(...xs),
    bottom: stroke.kind === 'text' ? top + (stroke.fontSize ?? 0.05) * 1.2 * (stroke.text ?? '').split('\n').length : Math.max(...ys) };
}
function pointSegmentDistance(point: ImagePoint, start: ImagePoint, end: ImagePoint): number {
  const dx = end.x - start.x, dy = end.y - start.y, length = dx * dx + dy * dy;
  const t = length ? Math.max(0, Math.min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / length)) : 0;
  return Math.hypot(point.x - start.x - t * dx, point.y - start.y - t * dy);
}
export function imageStrokeAt(strokes: ImageStroke[], point: ImagePoint, tolerance: number): number {
  for (let i = strokes.length - 1; i >= 0; i--) {
    const stroke = strokes[i];
    if (!stroke.points.length) continue;
    if (stroke.kind === 'text') {
      const bounds = imageStrokeBounds(stroke);
      if (point.x >= bounds.left - tolerance && point.x <= bounds.right + tolerance && point.y >= bounds.top - tolerance && point.y <= bounds.bottom + tolerance) return i;
    } else {
      for (let n = 0; n < stroke.points.length; n++) {
        if (pointSegmentDistance(point, stroke.points[Math.max(0, n - 1)], stroke.points[n]) <= tolerance + stroke.width / 2) return i;
      }
    }
  }
  return -1;
}
export function moveImageStroke(stroke: ImageStroke, dx: number, dy: number): ImageStroke {
  const bounds = imageStrokeBounds(stroke), copy = copyStrokes([stroke])[0];
  dx = Math.max(-bounds.left, Math.min(1 - bounds.right, dx)); dy = Math.max(-bounds.top, Math.min(1 - bounds.bottom, dy));
  copy.points = copy.points.map((point: ImagePoint): ImagePoint => ({ x: point.x + dx, y: point.y + dy }));
  return copy;
}
export function resizeImageStroke(stroke: ImageStroke, rect: ImageRect): ImageStroke {
  const bounds = imageStrokeBounds(stroke), copy = copyStrokes([stroke])[0];
  const sx = (rect.right - rect.left) / Math.max(0.001, bounds.right - bounds.left), sy = (rect.bottom - rect.top) / Math.max(0.001, bounds.bottom - bounds.top);
  copy.points = copy.points.map((point: ImagePoint): ImagePoint => ({ x: rect.left + (point.x - bounds.left) * sx, y: rect.top + (point.y - bounds.top) * sy }));
  if (copy.kind === 'text') { const scale = Math.min(sx, sy); copy.fontSize = (copy.fontSize ?? 0.05) * scale; copy.textWidth = (copy.textWidth ?? 0.1) * scale; }
  return copy;
}
export interface ImageRatio { label: string; value: string; width: number; height: number; }
export function imageRatios(): ImageRatio[] {
  return [{ label: '正方形', value: '1:1', width: 18, height: 18 }, { label: '竖向', value: '3:4', width: 15, height: 20 },
    { label: '故事版式', value: '9:16', width: 13, height: 23 }, { label: '横向', value: '4:3', width: 20, height: 15 },
    { label: '宽屏', value: '16:9', width: 23, height: 13 }];
}
export function appendImageComment(draft: string, name: string, comment: string): string {
  return `${draft}${draft ? '\n\n' : ''}[图片评论：${name}]\n${comment.trim()}`;
}
export function imageNoteText(notes: ImageNote[]): string {
  return '图像 1：\n' + notes.map((note: ImageNote, index: number): string =>
    `${index + 1}.（x：${(note.x * 100).toFixed(1)}%，y：${(note.y * 100).toFixed(1)}%）${note.text}`).join('\n');
}
export interface ImageEditUpload { type: string; id: string; name: string; mimeType: string; sizeBytes: number; }
export interface ImageEditAttachment { uri: string; name?: string; type?: string; uploaded?: ImageEditUpload; }
export interface ImageCommentDraft { id: string; uri: string; name: string; text: string; action?: string; target?: string; maskUri?: string; extras?: ImageEditAttachment[]; attachmentDraftId?: string; }
export function parseImageComment(raw: string, filesDir: string): ImageCommentDraft | null {
  try {
    const value = JSON.parse(raw) as ImageCommentDraft;
    const root = filesDir + '/image-edits/';
    if (value?.extras !== undefined) {
      const attachments = filesDir + '/draft-images/';
      if (!Array.isArray(value.extras) || value.extras.length + 1 + (value.maskUri ? 1 : 0) > 8 ||
        typeof value.attachmentDraftId !== 'string' || !/^[0-9a-f-]{36}$/.test(value.attachmentDraftId)) return null;
      for (const extra of value.extras) {
        if (!extra || typeof extra.uri !== 'string' || !extra.uri.startsWith(attachments) || !/^[0-9a-f-]{36}\.(img|file)$/.test(extra.uri.slice(attachments.length)) ||
          typeof extra.name !== 'string' || !extra.uploaded || !['image', 'file'].includes(extra.uploaded.type) ||
          typeof extra.uploaded.id !== 'string' || !extra.uploaded.id || typeof extra.uploaded.name !== 'string' ||
          typeof extra.uploaded.mimeType !== 'string' || !Number.isSafeInteger(extra.uploaded.sizeBytes) || extra.uploaded.sizeBytes <= 0) return null;
      }
    }
    if (value?.maskUri !== undefined && (typeof value.maskUri !== 'string' || !value.maskUri.startsWith(root) || !/^[0-9a-f-]{36}\.png$/.test(value.maskUri.slice(root.length)))) return null;
    if (value && (value.action === undefined || ['comment', 'replace', 'send', 'draft'].includes(value.action)) && typeof value.id === 'string' && /^[0-9a-f-]{36}$/.test(value.id) &&
      typeof value.uri === 'string' && value.uri.startsWith(root) && /^[0-9a-f-]{36}\.png$/.test(value.uri.slice(root.length)) &&
      typeof value.name === 'string' && typeof value.text === 'string' &&
      (value.action === 'replace' ? typeof value.target === 'string' && !!value.target : !!value.text.trim())) return value;
  } catch (_) {}
  return null;
}
