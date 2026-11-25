import { MessageContext } from '../model/Models';
import { ThreadReference, ThreadReferenceLink, ThreadLinkMetadata, threadReferenceTarget, threadReferenceIds, presentThreadReference } from '../model/ThreadReferences';
import { ClientCache } from './ClientCache';
import { EnvironmentSession } from './Environment';

interface ThreadMetadataRequest { threadIds: string[]; }

export async function loadThreadReferences(filesDir: string, environmentId: string, links: ThreadReferenceLink[], context?: MessageContext): Promise<ThreadReference[]> {
  const result: ThreadReference[] = [];
  const connection = EnvironmentSession.current;
  const environments = new Set<string>();
  for (const link of links) {
    const target = threadReferenceTarget(link.href, environmentId, context);
    if (target !== null) environments.add(target.environmentId);
  }
  for (const targetEnvironment of environments) {
    const cache = targetEnvironment ? await ClientCache.open(filesDir, targetEnvironment) : null;
    const shell = cache?.shell();
    const targets = links.filter((link: ThreadReferenceLink) => threadReferenceTarget(link.href, environmentId, context)?.environmentId === targetEnvironment);
    const missing = new Set<string>();
    for (const link of targets) {
      const target = threadReferenceTarget(link.href, environmentId, context)!;
      const ids = threadReferenceIds(target.threadId).filter((id: string) => !!id);
      if (!ids.some((id: string) => shell?.threads.some((thread) => thread.id === id))) ids.forEach((id: string) => { missing.add(id); });
    }
    let metadata: Record<string, ThreadLinkMetadata> = {};
    if (missing.size > 0 && connection !== null && connection === EnvironmentSession.current && connection.descriptor.environmentId === targetEnvironment) {
      try {
        const request: ThreadMetadataRequest = { threadIds: Array.from(missing).slice(0, 100) };
        metadata = await connection.rpc.call<Record<string, ThreadLinkMetadata>>('orchestration.getThreadLinkMetadata', request);
      } catch (_) { /* Older servers and offline caches can still show the reference's saved title. */ }
    }
    for (const link of targets) result.push(presentThreadReference(link.href, link.label,
      threadReferenceTarget(link.href, environmentId, context)!, shell?.threads ?? [], shell?.projects ?? [], metadata));
  }
  return result;
}
