export interface BrowserNavigation { _tag: string; url?: string; title?: string; description?: string; }
export interface BrowserTab {
  threadId: string; tabId: string; runtime?: string; navStatus: BrowserNavigation;
  canGoBack: boolean; canGoForward: boolean; updatedAt: string;
}
export interface BrowserList { sessions: BrowserTab[]; serverEpoch: string; revision: number; }
export interface BrowserEvent {
  type: string; threadId: string; tabId: string; serverEpoch: string; revision: number;
  snapshot?: BrowserTab; url?: string; title?: string; description?: string;
}
export class BrowserSessions {
  private threadId: string;
  private sessions: BrowserTab[] = [];
  private epoch: string = '';
  private revision: number = 0;
  private initialized: boolean = false;
  private buffered: BrowserEvent[] = [];
  constructor(threadId: string) { this.threadId = threadId; }
  tabs(): BrowserTab[] { return this.sessions.filter((tab: BrowserTab): boolean => tab.threadId === this.threadId && tab.runtime === 'server'); }
  list(value: BrowserList): boolean {
    if (this.epoch && this.epoch !== value.serverEpoch) return false;
    if (this.initialized && value.revision < this.revision) return false;
    this.sessions = value.sessions.slice(); this.epoch = value.serverEpoch; this.revision = value.revision;
    for (const event of this.buffered) if (event.serverEpoch === value.serverEpoch && event.revision > value.revision) this.apply(event);
    this.buffered = []; this.initialized = true;
    return true;
  }
  event(value: BrowserEvent): void {
    if (this.epoch !== value.serverEpoch) {
      this.epoch = value.serverEpoch; this.revision = 0; this.sessions = []; this.buffered = []; this.initialized = false;
    }
    if (value.revision <= this.revision) return;
    if (!this.initialized) { this.buffered.push(value); if (this.buffered.length > 512) this.buffered.shift(); }
    this.apply(value);
  }
  private apply(value: BrowserEvent): void {
    this.revision = value.revision;
    if (value.threadId !== this.threadId) return;
    if (value.type === 'closed') this.sessions = this.sessions.filter((tab: BrowserTab): boolean => tab.tabId !== value.tabId);
    else if (value.snapshot) {
      const snapshot = value.snapshot, index = this.sessions.findIndex((tab: BrowserTab): boolean => tab.tabId === value.tabId);
      if (index >= 0) this.sessions[index] = snapshot; else this.sessions.push(snapshot);
    } else if (value.type === 'failed') {
      this.sessions = this.sessions.map((tab: BrowserTab): BrowserTab => tab.tabId !== value.tabId ? tab : {
        threadId: tab.threadId, tabId: tab.tabId, runtime: tab.runtime, updatedAt: tab.updatedAt,
        canGoBack: tab.canGoBack, canGoForward: tab.canGoForward, navStatus: { _tag: 'LoadFailed', url: value.url, title: value.title, description: value.description } });
    }
  }
}
export function browserTabTitle(tab: BrowserTab): string { return tab.navStatus.title?.trim() || tab.navStatus.url || '新标签页'; }
