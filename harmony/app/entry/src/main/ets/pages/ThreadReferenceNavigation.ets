import router from '@ohos.router';
import util from '@ohos.util';
import { ThreadNavigationTarget } from '../model/ThreadReferences';
import { EnvironmentSession } from '../connection/Environment';

export async function openThreadReference(reference: ThreadNavigationTarget, currentEnvironmentId: string, currentThreadId: string): Promise<void> {
  if (!reference.available) throw new Error('此会话引用缺少原始记录，暂时无法打开');
  if (EnvironmentSession.current?.descriptor.environmentId === reference.environmentId) {
    if (reference.environmentId === currentEnvironmentId && reference.threadId === currentThreadId) return;
    await router.pushUrl({ url: 'pages/Thread', params: { environmentId: reference.environmentId,
      threadId: reference.threadId, title: reference.title, cwd: reference.cwd, projectTitle: reference.projectTitle } });
    return;
  }
  // The home page owns restoring saved environments for incoming thread routes.
  AppStorage.setOrCreate('notificationRoute', JSON.stringify({ request: util.generateRandomUUID(true),
    environmentId: reference.environmentId, threadId: reference.threadId,
    title: reference.title, cwd: reference.cwd, projectTitle: reference.projectTitle }));
  router.back({ url: 'pages/Index' });
}
