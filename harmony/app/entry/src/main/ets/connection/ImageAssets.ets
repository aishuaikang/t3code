import { RpcClient } from './Rpc';
import { ChatAttachment } from '../model/Models';
import { ImageFileCache } from './ImageFileCache';

interface AttachmentResource { _tag: string; attachmentId: string; fileName: string; mimeType: string; }
interface MediaResource { _tag: string; threadId: string; path: string; }
interface WorkspaceImageResource { _tag: string; cwd: string; path: string; }
type ImageResource = AttachmentResource | MediaResource | WorkspaceImageResource;
interface AssetRequest { resource: ImageResource; }
interface AssetUrl { relativeUrl: string; expiresAt: number; }
interface CachedUrl { url: string; expiresAt: number; }

/** Share URL requests between inline images and the full-screen viewer, scoped to the environment and transport. */
export class ImageAssets {
  private static urls: Map<string, CachedUrl> = new Map();
  private static pending: Map<string, Promise<string>> = new Map();
  static cached(filesDir: string, environmentId: string, id: string): Promise<string> { return ImageFileCache.cached(filesDir, environmentId, id); }
  static async source(rpc: RpcClient, environmentId: string, baseUrl: string, attachment: ChatAttachment, refresh: boolean = false, filesDir: string = ''): Promise<string> {
    const resource: AttachmentResource = { _tag: 'attachment', attachmentId: attachment.id, fileName: attachment.name, mimeType: attachment.mimeType };
    return ImageAssets.sourceResource(rpc, environmentId, baseUrl, attachment.id, resource, refresh, filesDir);
  }
  static mediaId(threadId: string, path: string): string { return JSON.stringify(['media-file', threadId, path]); }
  static mediaSource(rpc: RpcClient, environmentId: string, baseUrl: string, threadId: string, path: string, refresh: boolean = false, filesDir: string = ''): Promise<string> {
    const resource: MediaResource = { _tag: 'media-file', threadId: threadId, path: path };
    return ImageAssets.sourceResource(rpc, environmentId, baseUrl, ImageAssets.mediaId(threadId, path), resource, refresh, filesDir);
  }
  static workspaceId(cwd: string, path: string): string { return JSON.stringify(['draft-workspace-file', cwd, path]); }
  static workspaceSource(rpc: RpcClient, environmentId: string, baseUrl: string, cwd: string, path: string, refresh: boolean = false, filesDir: string = ''): Promise<string> {
    const resource: WorkspaceImageResource = { _tag: 'draft-workspace-file', cwd: cwd, path: path };
    return ImageAssets.sourceResource(rpc, environmentId, baseUrl, ImageAssets.workspaceId(cwd, path), resource, refresh, filesDir);
  }
  private static async sourceResource(rpc: RpcClient, environmentId: string, baseUrl: string, id: string, resource: ImageResource, refresh: boolean, filesDir: string): Promise<string> {
    if (filesDir) return ImageFileCache.source(filesDir, environmentId, id,
      () => ImageAssets.sourceResource(rpc, environmentId, baseUrl, id, resource, refresh, ''), refresh, resource._tag !== 'attachment');
    const key = JSON.stringify([environmentId, baseUrl, id]);
    const cached = ImageAssets.urls.get(key);
    if (!refresh && cached !== undefined && cached.expiresAt > Date.now() + 30000) return cached.url;
    const pending = ImageAssets.pending.get(key);
    if (pending !== undefined) return pending;
    const request = ImageAssets.resolve(rpc, key, baseUrl, resource);
    ImageAssets.pending.set(key, request);
    try { return await request; }
    finally { ImageAssets.pending.delete(key); }
  }
  private static async resolve(rpc: RpcClient, key: string, baseUrl: string, resource: ImageResource): Promise<string> {
    const request: AssetRequest = { resource: resource };
    const result = await rpc.call<AssetUrl>('assets.createUrl', request);
    if (!result.relativeUrl.startsWith('/') || result.relativeUrl.startsWith('//') || /[\\\r\n]/.test(result.relativeUrl)) throw new Error('图片地址无效');
    const url = baseUrl.replace(/\/$/, '') + result.relativeUrl;
    ImageAssets.urls.delete(key);
    ImageAssets.urls.set(key, { url: url, expiresAt: result.expiresAt });
    while (ImageAssets.urls.size > 128) {
      const first = Array.from(ImageAssets.urls.keys())[0];
      ImageAssets.urls.delete(first);
    }
    return url;
  }
}
