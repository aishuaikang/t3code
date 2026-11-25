import { EnvironmentSession } from './Environment';
import { ImageAssets } from './ImageAssets';
import { ImageFileCache } from './ImageFileCache';
import { markdownFileLink, markdownImageFileLink } from '../model/MarkdownLink';

export async function loadMarkdownImage(filesDir: string, environmentId: string, threadId: string,
  cwd: string, baseDir: string, href: string, refresh: boolean = false, online: boolean = true): Promise<string> {
  const value = href.startsWith('//') ? 'https:' + href : href;
  if (/^https?:\/\/[^\s/?#]+(?:[/?#][^\s]*)?$/i.test(value)) {
    return ImageFileCache.source(filesDir, environmentId, JSON.stringify(['markdown-image', value]), async () => value, refresh);
  }
  const image = markdownImageFileLink(value, cwd, baseDir);
  if (image === null) throw new Error('图片地址无效');
  const relative = markdownFileLink(image.path, cwd);
  if (!threadId && relative === null) throw new Error('图片不在当前项目内');
  const id = threadId ? ImageAssets.mediaId(threadId, image.path) : ImageAssets.workspaceId(cwd, relative!.path);
  const environment = EnvironmentSession.current;
  if (!online || environment === null || environment.descriptor.environmentId !== environmentId) {
    const cached = await ImageAssets.cached(filesDir, environmentId, id);
    if (cached) return cached;
    throw new Error('请连接图片所在的环境');
  }
  const source = threadId ? await ImageAssets.mediaSource(environment.rpc, environmentId, environment.httpBaseUrl,
    threadId, image.path, refresh, filesDir) : await ImageAssets.workspaceSource(environment.rpc, environmentId,
    environment.httpBaseUrl, cwd, relative!.path, refresh, filesDir);
  if (EnvironmentSession.current !== environment) throw new Error('图片所在环境已切换');
  return source;
}
