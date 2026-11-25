import fs from '@ohos.file.fs';
import http from '@ohos.net.http';
import cryptoFramework from '@ohos.security.cryptoFramework';
import util from '@ohos.util';

interface ImageVersion { hash: string; etag?: string; modified?: string; }
interface ImageFile { path: string; bytes: number; time: number; }

/** Persist image bytes, never their signed URLs. Environment identity is part of every key. */
export class ImageFileCache {
  private static pending: Map<string, Promise<string>> = new Map();
  private static paths: Map<string, Promise<string>> = new Map();
  private static async path(filesDir: string, environmentId: string, id: string): Promise<string> {
    const identity = JSON.stringify([filesDir, environmentId, id]);
    const existing = ImageFileCache.paths.get(identity);
    if (existing !== undefined) return existing;
    const path = ImageFileCache.createPath(filesDir, environmentId, id);
    ImageFileCache.paths.set(identity, path);
    path.catch(() => { ImageFileCache.paths.delete(identity); });
    if (ImageFileCache.paths.size > 128) ImageFileCache.paths.delete(Array.from(ImageFileCache.paths.keys())[0]);
    return path;
  }
  private static async createPath(filesDir: string, environmentId: string, id: string): Promise<string> {
    const root = `${filesDir}/image-cache`;
    if (!fs.accessSync(root)) fs.mkdirSync(root);
    const key = await ImageFileCache.digest(new util.TextEncoder().encodeInto(JSON.stringify([environmentId, id])));
    return `${root}/${key}.img`;
  }
  private static async digest(data: Uint8Array): Promise<string> {
    const digest = cryptoFramework.createMd('SHA256');
    await digest.update({ data: data });
    let key = '';
    for (const byte of (await digest.digest()).data) key += byte.toString(16).padStart(2, '0');
    return key;
  }
  private static version(path: string): ImageVersion | null {
    try {
      if (!fs.accessSync(path + '.json')) return null;
      const version = JSON.parse(fs.readTextSync(path + '.json')) as ImageVersion;
      if (/^[a-f0-9]{64}$/.test(version.hash) && fs.accessSync(`${path}.${version.hash}`)) return version;
    } catch (_) {}
    return null;
  }
  private static localSource(path: string): string {
    try {
      if (!fs.accessSync(path)) return '';
      const stat = fs.statSync(path);
      if (stat.size <= 0) return '';
      if (Date.now() - stat.mtime * 1000 > 60000) {
        try { fs.utimes(path, Date.now()); } catch (_) { /* The file is still readable. */ }
      }
      return `file://${path}`;
    } catch (_) { return ''; }
  }
  static async cached(filesDir: string, environmentId: string, id: string): Promise<string> {
    try {
      const base = await ImageFileCache.path(filesDir, environmentId, id);
      const version = ImageFileCache.version(base);
      return ImageFileCache.localSource(version ? `${base}.${version.hash}` : base);
    } catch (_) { return ''; }
  }
  static async source(filesDir: string, environmentId: string, id: string, resolveUrl: () => Promise<string>, refresh: boolean = false, mutable: boolean = false): Promise<string> {
    if (!refresh && !mutable) {
      const cached = await ImageFileCache.cached(filesDir, environmentId, id);
      if (cached) return cached;
    }
    let path: string;
    try { path = await ImageFileCache.path(filesDir, environmentId, id); }
    catch (_) { return resolveUrl(); }
    const existing = ImageFileCache.pending.get(path);
    if (existing !== undefined) return existing;
    const request = ImageFileCache.download(path, resolveUrl, mutable, refresh).finally(() => { ImageFileCache.pending.delete(path); });
    ImageFileCache.pending.set(path, request);
    return request;
  }
  private static async write(path: string, bytes: ArrayBuffer): Promise<void> {
    const temporary = `${path}.tmp`;
    try {
      const file = await fs.open(temporary, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        let offset = 0;
        while (offset < bytes.byteLength) {
          const count = await fs.write(file.fd, offset === 0 ? bytes : bytes.slice(offset));
          if (count <= 0) throw new Error('图片缓存写入失败');
          offset += count;
        }
      } finally { await fs.close(file); }
      await fs.rename(temporary, path);
    } finally { try { if (fs.accessSync(temporary)) await fs.unlink(temporary); } catch (_) {} }
  }
  private static async download(path: string, resolveUrl: () => Promise<string>, mutable: boolean, refresh: boolean): Promise<string> {
    const client = http.createHttp();
    try {
      const url = await resolveUrl();
      const previous = mutable ? ImageFileCache.version(path) : null;
      const headers: Record<string, string> = {};
      if (previous && !refresh) {
        if (previous.etag) headers['If-None-Match'] = previous.etag;
        else if (previous.modified) headers['If-Modified-Since'] = previous.modified;
      }
      const options: http.HttpRequestOptions = { method: http.RequestMethod.GET, expectDataType: http.HttpDataType.ARRAY_BUFFER,
        header: headers, usingCache: !mutable && !refresh, connectTimeout: 15000, readTimeout: 60000, maxLimit: 20 * 1024 * 1024 };
      let response = await client.request(url, options);
      if (response.responseCode === 304 && previous) {
        const local = ImageFileCache.localSource(`${path}.${previous.hash}`);
        if (local) return local;
        options.header = {};
        response = await client.request(url, options);
      }
      if (response.responseCode !== 200 || !(response.result instanceof ArrayBuffer) || response.result.byteLength === 0 ||
        response.result.byteLength > 20 * 1024 * 1024) throw new Error('图片下载失败，请重试');
      let target = path;
      try {
        if (mutable) {
          const hash = await ImageFileCache.digest(new Uint8Array(response.result));
          target = `${path}.${hash}`; // A new URI also invalidates ArkUI's decoded bitmap.
          if (!fs.accessSync(target)) await ImageFileCache.write(target, response.result);
          const h = (response.header ?? {}) as Record<string, string>;
          const version: ImageVersion = { hash: hash, etag: h['etag'] ?? h['ETag'], modified: h['last-modified'] ?? h['Last-Modified'] };
          await ImageFileCache.write(path + '.json', new util.TextEncoder().encodeInto(JSON.stringify(version)).buffer as ArrayBuffer);
          // Retire the old unversioned copy only after the new bytes and their manifest are durable.
          if (fs.accessSync(path)) await fs.unlink(path).catch(() => {});
        } else await ImageFileCache.write(target, response.result);
      } catch (_) { return url; }
      ImageFileCache.prune(path.substring(0, path.lastIndexOf('/')), target).catch(() => {});
      return `file://${target}`;
    } finally { client.destroy(); }
  }
  private static async prune(root: string, keep: string): Promise<void> {
    const files: ImageFile[] = [];
    for (const name of await fs.listFile(root)) {
      if (!/^[a-f0-9]{64}\.img(?:\.[a-f0-9]{64})?$/.test(name)) continue;
      const path = `${root}/${name}`;
      try {
        const stat = fs.statSync(path);
        files.push({ path: path, bytes: stat.size, time: stat.mtime });
      } catch (_) { /* Another eviction may have finished. */ }
    }
    let bytes = files.reduce((sum: number, file: ImageFile) => sum + file.bytes, 0);
    for (const file of files.sort((left: ImageFile, right: ImageFile) => left.time - right.time)) {
      if (bytes <= 80 * 1024 * 1024) break;
      const base = file.path.slice(0, file.path.lastIndexOf('.img') + 4);
      if (file.path === keep || ImageFileCache.pending.has(base)) continue;
      try {
        const current = base !== file.path ? ImageFileCache.version(base) : null;
        if (current && file.path === `${base}.${current.hash}`) fs.unlinkSync(base + '.json');
        await fs.unlink(file.path); bytes -= file.bytes;
      } catch (_) { /* Already removed. */ }
    }
  }
}
