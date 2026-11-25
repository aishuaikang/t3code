import notificationManager from '@ohos.notificationManager';
import wantAgent from '@ohos.app.ability.wantAgent';
import common from '@ohos.app.ability.common';
import preferences from '@ohos.data.preferences';
import { ShellSnapshot } from '../model/Models';
import { TaskNotice, TaskNotificationTracker, taskNotificationId } from '../model/TaskNotifications';

export class TaskNotifications {
  private static context: common.UIAbilityContext | null = null;
  private static store: preferences.Preferences | null = null;
  private static enabled: boolean = true;
  private static tracker: TaskNotificationTracker = new TaskNotificationTracker();
  private static environments: Set<string> = new Set();

  static async initialize(context: common.UIAbilityContext): Promise<void> {
    TaskNotifications.context = context;
    TaskNotifications.store = await preferences.getPreferences(context, { name: 'task-notifications' });
    TaskNotifications.enabled = await TaskNotifications.store.get('enabled', true) as boolean;
  }
  static async isEnabled(): Promise<boolean> {
    return TaskNotifications.enabled && await notificationManager.isNotificationEnabled();
  }
  static async setEnabled(enabled: boolean): Promise<void> {
    if (enabled && !await notificationManager.isNotificationEnabled()) {
      if (TaskNotifications.context === null) throw new Error('通知服务尚未就绪');
      await notificationManager.requestEnableNotification(TaskNotifications.context);
      if (!await notificationManager.isNotificationEnabled()) throw new Error('请在系统设置中允许 T3 发送通知');
    }
    if (TaskNotifications.store === null) throw new Error('通知设置尚未就绪');
    await TaskNotifications.store.put('enabled', enabled);
    await TaskNotifications.store.flush();
    TaskNotifications.enabled = enabled;
    AppStorage.setOrCreate('taskNotificationError', '');
  }
  static async requestOnce(): Promise<void> {
    const store = TaskNotifications.store;
    if (store === null || !TaskNotifications.enabled || await store.get('asked', false) === true) return;
    await store.put('asked', true); await store.flush();
    try { await TaskNotifications.setEnabled(true); } catch (_) { /* Permission remains under system control. */ }
  }
  static observe(environmentId: string, snapshot: ShellSnapshot): void {
    const notices = TaskNotifications.tracker.update(environmentId, snapshot.threads, snapshot.projects, !TaskNotifications.environments.has(environmentId));
    TaskNotifications.environments.add(environmentId);
    for (const notice of notices) TaskNotifications.publish(notice).catch(() => {
      AppStorage.setOrCreate('taskNotificationError', '系统任务通知发送失败，请检查通知权限');
    });
  }
  private static async publish(notice: TaskNotice): Promise<void> {
    if (!await TaskNotifications.isEnabled()) return;
    const id = taskNotificationId(notice.environmentId, notice.threadId);
    const agent = await wantAgent.getWantAgent({ wants: [{ bundleName: 'codes.t3.harmony', abilityName: 'EntryAbility',
      parameters: { notificationThreadId: notice.threadId, notificationEnvironmentId: notice.environmentId,
        notificationTitle: notice.title, notificationCwd: notice.cwd, notificationProject: notice.projectTitle } }],
      operationType: wantAgent.OperationType.START_ABILITY, requestCode: id, wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG] });
    await notificationManager.publish({ id: id, label: notice.threadId, groupName: notice.environmentId,
      notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION, tapDismissed: true, wantAgent: agent,
      content: { notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: { title: notice.title, text: notice.text, additionalText: notice.projectTitle } } });
  }
}
