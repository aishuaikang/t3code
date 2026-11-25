import fs from '@ohos.file.fs';
import util from '@ohos.util';
import { DraftStore } from './DraftStore';
import { prepareImage } from './ImagePreparation';
import { UploadedImage } from './ImageAttachment';
import { attachmentMime, supportedImageFile, fileUploadLimit, MAX_FILE_BYTES } from '../model/FileAttachments';

export interface DraftImage { uri: string; name?: string; type?: string; mimeType?: string; sizeBytes?: number; uploaded?: UploadedImage; }
export class AttachmentDraftStore {
  private static opened: Map<string, WeakRef<AttachmentDraftStore>> = new Map();
  private static opening: Map<string, Promise<AttachmentDraftStore>> = new Map();
  images: DraftImage[] = [];
  private root: string;
  private metadata: DraftStore;
  private writes: Promise<void> = Promise.resolve();
  private constructor(root: string, metadata: DraftStore) { this.root = root; this.metadata = metadata; }
  static async open(filesDir: string, environmentId: string, threadId: string): Promise<AttachmentDraftStore> {
    const key = JSON.stringify([filesDir, environmentId, threadId]);
    const current = AttachmentDraftStore.opened.get(key)?.deref();
    if (current) return current;
    const pending = AttachmentDraftStore.opening.get(key);
    if (pending) return pending;
    AttachmentDraftStore.opened.forEach((ref, id) => { if (!ref.deref()) AttachmentDraftStore.opened.delete(id); });
    const load = AttachmentDraftStore.read(filesDir, environmentId, threadId);
    AttachmentDraftStore.opening.set(key, load);
    try {
      const store = await load;
      AttachmentDraftStore.opened.set(key, new WeakRef(store));
      return store;
    } finally { AttachmentDraftStore.opening.delete(key); }
  }
  private static async read(filesDir: string, environmentId: string, threadId: string): Promise<AttachmentDraftStore> {
    const root = `${filesDir}/draft-images`;
    if (!fs.accessSync(root)) fs.mkdirSync(root);
    const metadata = await DraftStore.open(filesDir, environmentId, `images:${threadId}`);
    const store = new AttachmentDraftStore(root, metadata);
    const raw = await metadata.load();
    if (raw) {
      const images = JSON.parse(raw) as DraftImage[];
      if (!Array.isArray(images) || images.length > 8) throw new Error('图片草稿格式无效');
      for (const image of images) {
        const name = image.uri?.substring(root.length + 1) ?? '';
        if (!image.uri?.startsWith(root + '/') || !/^[0-9a-f-]{36}\.(img|file)$/.test(name)) throw new Error('附件草稿路径无效');
        if (!fs.accessSync(image.uri)) throw new Error('图片草稿文件丢失，请重新选择');
      }
      store.images = images;
    }
    return store;
  }
  async add(sourceUri: string, name: string = '', replaceUri: string = ''): Promise<DraftImage> {
    if (replaceUri && !this.images.some((image: DraftImage) => image.uri === replaceUri)) throw new Error('待替换的图片已移除');
    if (!replaceUri && this.images.length >= 8) throw new Error('每条消息最多 8 张图片');
    const file = await fs.open(sourceUri, fs.OpenMode.READ_ONLY);
    const uri = `${this.root}/${util.generateRandomUUID(true)}.img`;
    let preparedName = name;
    try {
      const stat = await fs.stat(file.fd);
      if (stat.size < 1) throw new Error('图片不能为空');
      preparedName = await prepareImage(file.fd, uri, name);
      const prepared = await fs.stat(uri);
      if (prepared.size < 1 || prepared.size > 10 * 1024 * 1024) throw new Error('转换后图片须小于或等于 10 MB 且不能为空');
    } catch (error) {
      if (fs.accessSync(uri)) await fs.unlink(uri);
      throw new Error(error instanceof Error ? error.message : String(error));
    } finally { await fs.close(file); }
    const image: DraftImage = { uri: uri, name: preparedName };
    try { await this.change(() => {
      if (replaceUri) {
        if (!this.images.some((entry: DraftImage) => entry.uri === replaceUri)) throw new Error('待替换的图片已移除');
        return this.images.map((entry: DraftImage) => entry.uri === replaceUri ? image : entry);
      }
      if (this.images.length >= 8) throw new Error('每条消息最多 8 张图片');
      return this.images.concat([image]);
    }); }
    catch (error) { await fs.unlink(uri); throw new Error(error instanceof Error ? error.message : String(error)); }
    if (replaceUri && fs.accessSync(replaceUri)) await fs.unlink(replaceUri).catch(() => {});
    return image;
  }
  async setUploaded(uri: string, uploaded: UploadedImage | undefined): Promise<void> {
    await this.change(() => this.images.map((image: DraftImage): DraftImage => image.uri === uri ? {
      uri: uri, name: image.name, type: image.type, mimeType: image.mimeType, sizeBytes: image.sizeBytes, uploaded: uploaded } : image));
  }
  async addFile(sourceUri: string, name: string, maxBytes: number, keepFileType: boolean = false): Promise<DraftImage> {
    if (!keepFileType && supportedImageFile(name)) return this.add(sourceUri, name);
    // Local drafts do not require a connected server to advertise an upload limit.
    const limit = fileUploadLimit(maxBytes) || MAX_FILE_BYTES;
    if (!name.trim() || name.trim().length > 255) throw new Error('文件名须为 1–255 个字符');
    if (this.images.length >= 8) throw new Error('每条消息最多 8 个附件');
    const file = await fs.open(sourceUri, fs.OpenMode.READ_ONLY);
    const uri = `${this.root}/${util.generateRandomUUID(true)}.file`;
    let size = 0;
    try {
      size = (await fs.stat(file.fd)).size;
      if (size < 1 || size > limit) throw new Error(`文件不能为空且不能超过 ${Math.round(limit / 1024 / 1024 * 10) / 10} MB`);
      await fs.copyFile(file.fd, uri);
      if ((await fs.stat(uri)).size !== size) throw new Error('文件复制未完成，请重新选择');
    } catch (error) {
      if (fs.accessSync(uri)) await fs.unlink(uri);
      throw new Error(error instanceof Error ? error.message : String(error));
    } finally { await fs.close(file); }
    const attachment: DraftImage = { uri: uri, name: name.trim(), type: 'file', mimeType: attachmentMime(name), sizeBytes: size };
    try { await this.change(() => {
      if (this.images.length >= 8) throw new Error('每条消息最多 8 个附件');
      return this.images.concat([attachment]);
    }); } catch (error) { await fs.unlink(uri); throw new Error(error instanceof Error ? error.message : String(error)); }
    return attachment;
  }
  async remove(uri: string): Promise<void> {
    if (!this.images.some((image: DraftImage) => image.uri === uri)) return;
    await this.change(() => this.images.filter((image: DraftImage) => image.uri !== uri));
    if (fs.accessSync(uri)) await fs.unlink(uri);
  }
  async clear(): Promise<void> {
    let previous: DraftImage[] = [];
    await this.change(() => { previous = this.images; return []; });
    for (const image of previous) if (fs.accessSync(image.uri)) await fs.unlink(image.uri);
  }
  private change(update: () => DraftImage[]): Promise<void> {
    const write = this.writes.then(async () => {
      const images = update();
      await this.metadata.save(images.length > 0 ? JSON.stringify(images) : '');
      this.images = images;
    });
    this.writes = write.catch(() => {});
    return write;
  }
}
