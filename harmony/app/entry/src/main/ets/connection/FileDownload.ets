import fs from '@ohos.file.fs';
import http from '@ohos.net.http';
import util from '@ohos.util';
import { RpcClient } from './Rpc';

interface MediaResource { _tag: string; threadId: string; path: string; disposition: string; }
interface DraftWorkspaceResource { _tag: string; cwd: string; path: string; }
interface AttachmentResource { _tag: string; attachmentId: string; fileName: string; mimeType: string; }
export type DownloadResource = MediaResource | DraftWorkspaceResource | AttachmentResource;
interface AssetRequest { resource: DownloadResource; }
interface AssetUrl { relativeUrl: string; }

class FileHttpError extends Error {
  status: number;
  constructor(status: number) {
    super(status === 404 ? '文件不存在或已移动，请确认电脑上的原文件仍然存在。' :
      status === 401 || status === 403 ? '下载凭证已过期，请重新下载。' : `文件下载失败（HTTP ${status}），请重试。`);
    this.status = status;
  }
}

/** Stream original bytes into a temporary file; only a completed download can be saved. */
export class FileDownload {
  private client: http.HttpRequest | null = null;
  private abort: (() => void) | null = null;
  private cancelled: boolean = false;
  private path: string = '';

  cancel(): void {
    this.cancelled = true;
    this.abort?.();
    this.client?.destroy();
  }
  private requireActive(): void { if (this.cancelled) throw new Error('下载已取消'); }
  localFile(): string { this.requireActive(); return this.path; }

  async fetch(rpc: RpcClient, baseUrl: string, resource: DownloadResource, cacheDir: string,
    progress: (received: number, total: number) => void = () => {}): Promise<void> {
    this.path = `${cacheDir}/download-${util.generateRandomUUID(true)}.tmp`;
    try {
      for (let attempt = 0; attempt < 2; attempt++) {
        this.requireActive();
        const request: AssetRequest = { resource: resource };
        const result = await rpc.call<AssetUrl>('assets.createUrl', request);
        this.requireActive();
        if (!result.relativeUrl.startsWith('/') || result.relativeUrl.startsWith('//') || /[\\\r\n]/.test(result.relativeUrl)) throw new Error('文件下载地址无效，请重试');
        try {
          const name = resource._tag === 'attachment' ? (resource as AttachmentResource).fileName : (resource as MediaResource | DraftWorkspaceResource).path;
          await this.transfer(baseUrl.replace(/\/$/, '') + result.relativeUrl, /\.pdf$/i.test(name), progress);
          return;
        } catch (error) {
          // A URL can expire between minting and use, especially through a slow relay.
          if (attempt === 0 && !this.cancelled && error instanceof FileHttpError && (error.status === 401 || error.status === 403)) continue;
          throw error instanceof Error ? error : new Error(String(error));
        }
      }
    } catch (error) { await this.dispose(); throw error instanceof Error ? error : new Error(String(error)); }
  }

  private async transfer(url: string, pdf: boolean, progress: (received: number, total: number) => void): Promise<void> {
    let file: fs.File;
    try { file = await fs.open(this.path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC); }
    catch (_) { throw new Error('无法创建临时文件，请检查手机剩余空间后重试。'); }
    const client = http.createHttp();
    this.client = client;
    let writes: Promise<void> = Promise.resolve();
    let fail: (error: Error) => void = () => {};
    let received: number = 0;
    let prefix: string = '';
    let writeFailed: boolean = false;
    let lastProgress: number = 0;
    try {
      this.requireActive();
      const ended = new Promise<void>((resolve, reject) => {
        fail = reject;
        this.abort = () => { reject(new Error('下载已取消')); };
        client.on('dataEnd', () => { resolve(); });
      });
      client.on('dataReceive', (data: ArrayBuffer) => {
        writes = writes.then(async () => {
          this.requireActive();
          let offset = 0;
          while (offset < data.byteLength) {
            const count = await fs.write(file.fd, data.slice(offset));
            if (count <= 0) throw new Error('无法写入临时文件');
            offset += count;
          }
          if (pdf && prefix.length < 1024) {
            for (const byte of new Uint8Array(data.slice(0, 1024 - prefix.length))) prefix += String.fromCharCode(byte);
          }
          received += data.byteLength;
        });
        writes.catch(() => {
          if (writeFailed) return;
          writeFailed = true;
          fail(new Error(this.cancelled ? '下载已取消' : '无法保存临时文件，请检查手机剩余空间后重试。'));
          client.destroy();
        });
      });
      client.on('dataReceiveProgress', (info: http.DataReceiveProgressInfo) => {
        if (!this.cancelled && Date.now() - lastProgress >= 100) { lastProgress = Date.now(); progress(info.receiveSize, info.totalSize); }
      });
      const response = client.requestInStream(url, { method: http.RequestMethod.GET, usingCache: false, connectTimeout: 15000, readTimeout: 60000 })
        .catch(() => { throw new Error('文件下载中断，请检查网络后重试。'); })
        .then((status: number) => { if (status !== 200) throw new FileHttpError(status); });
      await Promise.all([response, ended]);
      await writes.catch(() => { throw new Error(this.cancelled ? '下载已取消' : '无法保存临时文件，请检查手机剩余空间后重试。'); });
      this.requireActive();
      if (pdf && !prefix.includes('%PDF-')) throw new Error('服务器未返回有效的 PDF 文件，请重新下载。');
      progress(received, received);
    } finally {
      this.abort = null;
      this.client = null;
      client.off('dataReceive');
      client.off('dataReceiveProgress');
      client.off('dataEnd');
      client.destroy();
      await writes.catch(() => {});
      await fs.close(file);
    }
  }

  async save(uri: string): Promise<void> {
    this.requireActive();
    try {
      const target = await fs.open(uri, fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try { this.requireActive(); await fs.copyFile(this.path, target.fd); }
      finally { await fs.close(target); }
    } catch (_) { throw new Error('保存失败，请重新选择保存位置并确认手机空间充足。'); }
  }

  async dispose(): Promise<void> {
    this.cancel();
    try { if (this.path && fs.accessSync(this.path)) await fs.unlink(this.path); } catch (_) {}
  }
}
