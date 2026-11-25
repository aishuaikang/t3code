import { ChatAttachment, ViewedImage } from './Models';

export interface PreviewImage {
  name: string;
  attachmentId?: string;
  mimeType?: string;
  mediaPath?: string;
  mediaThreadId?: string;
  localUri?: string;
  draftTarget?: string;
}
export interface ImageGalleryState { images: PreviewImage[]; index: number; }

export function attachmentGallery(images: ChatAttachment[]): PreviewImage[] {
  return images.filter((image: ChatAttachment) => image.type === 'image').map((image: ChatAttachment): PreviewImage =>
    ({ attachmentId: image.id, name: image.name, mimeType: image.mimeType }));
}
export function viewedImageGallery(images: ViewedImage[], threadId: string): PreviewImage[] {
  return images.map((image: ViewedImage): PreviewImage => ({ name: image.path.split(/[\\/]/).pop() || '图片',
    mediaPath: image.path, mediaThreadId: image.threadId || threadId }));
}
export function previewGallery(params: Record<string, string>): ImageGalleryState {
  let images: PreviewImage[] = [];
  try {
    const supplied = JSON.parse(params['gallery'] ?? '[]') as PreviewImage[];
    if (Array.isArray(supplied)) images = supplied.filter((image: PreviewImage) => image !== null && typeof image.name === 'string' &&
      ((typeof image.attachmentId === 'string' && !!image.attachmentId) ||
        (typeof image.mediaPath === 'string' && !!image.mediaPath && typeof image.mediaThreadId === 'string') ||
        (typeof image.localUri === 'string' && !!image.localUri)));
  } catch (_) {}
  if (images.length === 0) images = [{ name: params['name'] ?? '图片', attachmentId: params['attachmentId'],
    mimeType: params['mimeType'], mediaPath: params['mediaPath'], mediaThreadId: params['mediaThreadId'], localUri: params['localUri'] }];
  const index = Number(params['imageIndex']) || 0;
  return { images: images, index: Math.max(0, Math.min(images.length - 1, Math.trunc(index))) };
}
export function imageStep(index: number, count: number, delta: number): number {
  return Math.max(0, Math.min(count - 1, index + delta));
}

export interface AttachmentTileLayout { width: number; aspect: number; right: number; bottom: number; }
export function attachmentTileLayout(count: number, index: number, width: number): AttachmentTileLayout {
  if (count <= 1) return { width: width, aspect: 0, right: 0, bottom: 0 };
  const half = (width - 2) / 2;
  const wide = count > 3 && count % 2 === 1 && index === count - 1;
  const tileWidth = wide ? width : half;
  return { width: tileWidth, aspect: tileWidth / (half / 1.6), right: !wide && index % 2 === 0 ? 2 : 0,
    bottom: index < count - (count % 2 === 1 ? 1 : 2) ? 2 : 0 };
}
