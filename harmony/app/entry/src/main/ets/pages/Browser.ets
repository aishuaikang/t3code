import { ChatGlass, immersiveMaterial } from './ChatGlass';
import router from '@ohos.router';
import webview from '@ohos.web.webview';
import pasteboard from '@ohos.pasteboard';
import picker from '@ohos.file.picker';
import fileUri from '@ohos.file.fileuri';
import fs from '@ohos.file.fs';
import http from '@ohos.net.http';
import { EnvironmentSession } from '../connection/Environment';
import { RpcClient, EmptyPayload } from '../connection/Rpc';
import { ReconnectingRpc } from '../connection/ReconnectingRpc';
import { BrowserTab, BrowserList, BrowserEvent, BrowserSessions, browserTabTitle } from '../model/BrowserSessions';
import { attachmentMime } from '../model/FileAttachments';
import { ThemeRuntime } from '../connection/ThemeRuntime';
import { Typography, resolveTypography, scaledFontSize } from '../model/Typography';
import { AppIcon } from './AppIcon';

interface BrowserTarget { threadId: string; tabId?: string; }
interface BrowserOpen { threadId: string; runtime: string; url?: string; }
interface BrowserDialog { type: string; message: string; defaultValue: string; }
interface BrowserChooser { multiple: boolean; accept: string; uploadUrl: string; }
interface BrowserMessage {
  type: string; viewerId: number; controller?: string; canOperate?: boolean; status?: string; detail?: string;
  dialog?: BrowserDialog | null; text?: string; command?: string; url?: string; fileName?: string; chooser?: BrowserChooser | null;
}
class BrowserBridge {
  private receive: (value: string) => void;
  constructor(receive: (value: string) => void) { this.receive = receive; }
  postMessage(value: string): void { this.receive(value); }
}

@Entry
@Component
struct BrowserPage {
  @StorageLink('themeKey') themeKey: string = 't3-code-light';
  @StorageLink('textSizes') sizes: Typography = resolveTypography(16, null, null);
  @State tabs: BrowserTab[] = [];
  @State tabId: string = '';
  @State address: string = '';
  @State editingAddress: boolean = false;
  @State tabsOpen: boolean = false;
  @State connected: boolean = false;
  @State controller: string = '';
  @State canOperate: boolean = false;
  @State status: string = '正在连接…';
  @State error: string = '';
  @State busy: boolean = false;
  @State dialogOpen: boolean = false;
  @State dialog: BrowserDialog | null = null;
  @State promptText: string = '';
  private web: webview.WebviewController = new webview.WebviewController();
  private bridge: BrowserBridge = new BrowserBridge((value: string) => { this.receive(value); });
  private webReady: boolean = false;
  private threadId: string = '';
  private environmentId: string = '';
  private active: boolean = false;
  private visible: boolean = false;
  private rpc: RpcClient | null = null;
  private connection: ReconnectingRpc | null = null;
  private streamVersion: number = 0;
  private interactive: boolean = false;
  private pendingTakeControl: boolean = false;
  private streamBase: string = '';
  private authRetry: number = -1;
  private authFailures: number = 0;
  private streamDeadline: number = -1;
  private color(role: string): string { return ThemeRuntime.color(this.themeKey, role); }
  private font(size: number): number { return scaledFontSize(size, this.sizes.baseFontSize); }

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string>;
    this.environmentId = params['environmentId'] ?? ''; this.threadId = params['threadId'] ?? ''; this.tabId = params['tabId'] ?? '';
    this.active = true;
    this.connection = new ReconnectingRpc(async (): Promise<RpcClient> => {
      const environment = EnvironmentSession.current;
      if (!environment || environment.descriptor.environmentId !== this.environmentId) throw new Error('请先连接会话所在的环境');
      return await environment.openRpc();
    }, (rpc: RpcClient) => this.subscribe(rpc), () => { this.rpc = null; });
  }
  onPageShow(): void { this.visible = true; this.connection?.start(); if (this.webReady && this.tabId) this.startStream(); }
  onPageHide(): void { this.visible = false; this.connection?.stop(); this.stopStream(); }
  aboutToDisappear(): void { this.active = false; this.connection?.stop(); this.stopStream(); }
  private async subscribe(rpc: RpcClient): Promise<void> {
    this.rpc = rpc;
    const sessions = new BrowserSessions(this.threadId);
    const events = rpc.callStream('subscribePreviewEvents', new EmptyPayload(), (values: object[]) => {
      if (!this.active || !this.visible || this.rpc !== rpc) return;
      for (const value of values) sessions.event(value as BrowserEvent);
      this.updateTabs(sessions.tabs());
    });
    events.catch(() => {});
    try {
      const target: BrowserTarget = { threadId: this.threadId };
      const result = await rpc.call<BrowserList>('preview.list', target);
      if (this.active && this.rpc === rpc) {
        sessions.list(result); this.updateTabs(sessions.tabs()); this.connection?.healthy();
      }
      await events;
    } finally { if (this.rpc === rpc) this.rpc = null; }
  }
  private updateTabs(tabs: BrowserTab[]): void {
    this.tabs = tabs;
    if (!tabs.some((tab: BrowserTab) => tab.tabId === this.tabId)) {
      const latest = tabs.reduce<BrowserTab | null>((value: BrowserTab | null, tab: BrowserTab): BrowserTab => !value || tab.updatedAt > value.updatedAt ? tab : value, null);
      this.selectTab(latest?.tabId ?? '');
    }
    if (!this.editingAddress) this.address = this.selected()?.navStatus.url ?? '';
  }
  private selected(): BrowserTab | undefined { return this.tabs.find((tab: BrowserTab): boolean => tab.tabId === this.tabId); }
  private selectTab(id: string): void {
    if (id === this.tabId) return;
    this.stopStream(); this.tabId = id; this.interactive = false; this.pendingTakeControl = false; this.authFailures = 0;
    this.address = this.selected()?.navStatus.url ?? ''; this.tabsOpen = false; this.error = '';
    if (id) this.startStream();
  }
  private stopStream(): void {
    this.streamVersion++; this.connected = false; this.controller = ''; this.canOperate = false; this.dialogOpen = false;
    if (this.authRetry !== -1) clearTimeout(this.authRetry); this.authRetry = -1;
    if (this.streamDeadline !== -1) clearTimeout(this.streamDeadline); this.streamDeadline = -1;
    if (this.webReady) this.web.runJavaScript('T3PreviewStream.stop();').catch(() => {});
  }
  private async startStream(): Promise<void> {
    if (!this.webReady || !this.active || !this.visible || !this.tabId) return;
    this.stopStream(); const version = this.streamVersion, tabId = this.tabId;
    this.status = '正在连接…'; this.error = '';
    this.streamDeadline = setTimeout(() => { this.error = '浏览器画面暂未加载，请重试'; this.stopStream(); }, 15000);
    try {
      const environment = EnvironmentSession.current;
      if (!environment || environment.descriptor.environmentId !== this.environmentId) throw new Error('请先连接会话所在的环境');
      const access = await environment.openPreviewAccess();
      if (!this.active || !this.visible || version !== this.streamVersion || tabId !== this.tabId) return;
      this.streamBase = access.httpBase;
      const config = JSON.stringify({ access: access, threadId: this.threadId, tabId: tabId, interactive: this.interactive, background: this.color('screen') });
      await this.web.runJavaScript(`window.ReactNativeWebView={postMessage:function(raw){var value=JSON.parse(raw);value.viewerId=${version};HarmonyBrowser.postMessage(JSON.stringify(value));}};T3PreviewStream.start(${config});`);
    } catch (error) { if (version === this.streamVersion && this.active) this.error = error instanceof Error ? error.message : String(error); }
  }
  private receive(raw: string): void {
    let value: BrowserMessage;
    try { value = JSON.parse(raw) as BrowserMessage; } catch (_) { return; }
    if (!this.active || !this.visible || value.viewerId !== this.streamVersion) return;
    if (value.type === 'control') {
      this.controller = value.controller ?? ''; this.canOperate = value.canOperate === true;
      const next = value.dialog ?? null;
      if (JSON.stringify(next) !== JSON.stringify(this.dialog)) this.promptText = next?.defaultValue ?? '';
      this.dialog = next; this.dialogOpen = this.controller === 'you' && this.dialog !== null;
      if (this.pendingTakeControl && this.canOperate) { this.pendingTakeControl = false; this.send('{"type":"takeControl"}'); }
      else if (this.pendingTakeControl && !this.canOperate) { this.pendingTakeControl = false; this.error = '当前连接没有浏览器操作权限'; }
    } else if (value.type === 'status') {
      this.connected = value.status === 'streaming';
      this.status = this.connected ? '' : value.status === 'error' ? '页面连接失败' : '正在连接…';
      if (value.status !== 'connecting' && this.streamDeadline !== -1) { clearTimeout(this.streamDeadline); this.streamDeadline = -1; }
      if (value.status === 'error') this.error = '浏览器画面连接失败，请重试';
      if (this.connected) { this.authFailures = 0; this.error = ''; }
      else { this.controller = ''; this.canOperate = false; this.dialogOpen = false; }
    } else if (value.type === 'unauthorized') {
      if (this.authFailures++ >= 3) { this.error = '浏览器连接失败，请重试'; return; }
      this.authRetry = setTimeout(() => { this.authRetry = -1; this.startStream(); }, 1000 * this.authFailures);
    } else if (value.type === 'gone') { this.error = '这个标签页已关闭'; this.stopStream(); }
    else if (value.type === 'hostSetup') this.error = '服务器浏览器尚未就绪，请在服务器执行：' + (value.command ?? 'npx t3 browser setup');
    else if (value.type === 'clipboard' && typeof value.text === 'string') pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, value.text)).catch(() => {});
    else if (value.type === 'download' && value.url) this.download(value.url, value.fileName ?? '下载文件');
    else if (value.type === 'fileChooser' && value.chooser) this.upload(value.chooser);
  }
  private send(command: string): void { if (this.webReady) this.web.runJavaScript(`T3PreviewStream.command(${command});`).catch(() => { this.error = '操作未发送，请重新连接'; }); }
  private takeControl(): void {
    if (this.controller === 'you') {
      this.send('{"type":"releaseControl"}'); this.interactive = false; this.pendingTakeControl = false; this.startStream();
    } else { this.interactive = true; this.pendingTakeControl = true; this.startStream(); }
  }
  private async openTab(): Promise<void> {
    if (!this.rpc || this.busy) return;
    this.busy = true; this.error = '';
    try {
      const input: BrowserOpen = { threadId: this.threadId, runtime: 'server' };
      const tab = await this.rpc.call<BrowserTab>('preview.open', input);
      this.tabs = this.tabs.filter((entry: BrowserTab): boolean => entry.tabId !== tab.tabId).concat([tab]); this.selectTab(tab.tabId);
    } catch (error) { this.error = error instanceof Error ? error.message : String(error); }
    finally { this.busy = false; }
  }
  private async closeTab(id: string): Promise<void> {
    if (!this.rpc || this.busy) return;
    this.busy = true;
    try { const target: BrowserTarget = { threadId: this.threadId, tabId: id }; await this.rpc.call('preview.close', target); }
    catch (error) { this.error = error instanceof Error ? error.message : String(error); }
    finally { this.busy = false; }
  }
  private navigate(): void {
    if (this.controller !== 'you' || !this.address.trim()) return;
    const input = this.address.trim(), url = /^[a-z][a-z0-9+.-]*:/i.test(input) && !/^[^/]+:\d+(\/|$)/.test(input) ? input : 'http://' + input;
    if (!/^https?:\/\//i.test(url)) { this.error = '请输入 http 或 https 地址'; return; }
    this.editingAddress = false; this.send(JSON.stringify({ type: 'navigate', url: url }));
  }
  private answerDialog(accept: boolean): void {
    this.send(JSON.stringify({ type: 'dialog', accept: accept, promptText: this.promptText })); this.dialogOpen = false;
  }
  private async download(url: string, name: string): Promise<void> {
    if (this.busy || !url.startsWith(this.streamBase + '/download?')) return;
    this.busy = true; const client = http.createHttp();
    try {
      const uris = await new picker.DocumentViewPicker().save({ newFileNames: [name.replace(/[\/\\]/g, '_')] });
      if (!uris[0]) return;
      const response = await client.request(url, { expectDataType: http.HttpDataType.ARRAY_BUFFER, connectTimeout: 15000, readTimeout: 60000, maxLimit: 50 * 1024 * 1024 });
      if (response.responseCode !== 200 || !(response.result instanceof ArrayBuffer)) throw new Error('文件下载失败，请重试');
      const file = await fs.open(uris[0], fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try { let offset = 0; while (offset < response.result.byteLength) { const count = await fs.write(file.fd, response.result.slice(offset)); if (count <= 0) throw new Error('文件保存未完成'); offset += count; } }
      finally { await fs.close(file); }
    } catch (_) { this.error = '文件下载失败，请重试'; }
    finally { client.destroy(); this.busy = false; }
  }
  private async upload(chooser: BrowserChooser): Promise<void> {
    if (this.busy || this.controller !== 'you' || !chooser.uploadUrl.startsWith(this.streamBase + '/upload?')) return;
    this.busy = true; const client = http.createHttp(), version = this.streamVersion;
    try {
      const uris = await new picker.DocumentViewPicker().select({ maxSelectNumber: chooser.multiple ? 8 : 1 });
      if (!this.active || version !== this.streamVersion || this.controller !== 'you') return;
      const form: http.MultiFormData[] = [];
      for (const uri of uris) {
        const name = new fileUri.FileUri(uri).name, file = await fs.open(uri, fs.OpenMode.READ_ONLY);
        try {
          const size = (await fs.stat(file.fd)).size;
          if (size > 50 * 1024 * 1024) throw new Error('单个文件不能超过 50 MB');
          const bytes = new ArrayBuffer(size); let offset = 0;
          while (offset < size) {
            const chunk = new ArrayBuffer(Math.min(64 * 1024, size - offset));
            const count = await fs.read(file.fd, chunk, { offset: offset, length: chunk.byteLength });
            if (count <= 0) throw new Error('文件读取未完成'); new Uint8Array(bytes).set(new Uint8Array(chunk, 0, count), offset); offset += count;
          }
          form.push({ name: 'file', contentType: attachmentMime(name), remoteFileName: name, data: bytes });
        } finally { await fs.close(file); }
      }
      const response = await client.request(chooser.uploadUrl, { method: http.RequestMethod.POST, multiFormDataList: form, connectTimeout: 15000, readTimeout: 60000 });
      if (response.responseCode < 200 || response.responseCode >= 300) throw new Error('文件上传失败');
    } catch (error) { this.error = error instanceof Error ? error.message : '文件上传失败，请重试'; }
    finally { client.destroy(); this.busy = false; }
  }
  @Builder
  private icon(name: string, label: string, action: () => void, enabled: boolean = true) {
    Button({ type: ButtonType.Circle }) { AppIcon({ name: name, iconSize: 20, tint: this.color('foreground-secondary') }) }
      .id('browser-action-' + label).width(40).height(40).padding(0).backgroundColor(Color.Transparent).enabled(enabled).accessibilityText(label).onClick(action)
  }
  @Builder
  private tabSheet() {
    Column({ space: 6 }) {
      Row() { Text('浏览器标签页').fontSize(this.font(18)).fontWeight(FontWeight.Bold).fontColor(this.color('foreground')).layoutWeight(1); this.icon('plus', '新建浏览器标签页', () => { this.openTab(); }, !this.busy); this.icon('close', '关闭标签列表', () => { this.tabsOpen = false; }) }.width('100%')
      Scroll() {
        Column({ space: 6 }) {
          ForEach(this.tabs, (tab: BrowserTab) => {
            Row({ space: 8 }) {
              Button({ type: ButtonType.Normal }) {
                Row({ space: 10 }) {
                  AppIcon({ name: 'globe', iconSize: 20, tint: this.color('foreground-muted') })
                  Column({ space: 4 }) {
                    Text(browserTabTitle(tab)).fontSize(this.font(14)).fontColor(this.color('foreground')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                    Text(tab.navStatus.url ?? '新标签页').fontSize(this.font(11)).fontColor(this.color('foreground-muted')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  if (tab.tabId === this.tabId) { AppIcon({ name: 'check', iconSize: 17, tint: this.color('primary') }) }
                }.width('100%')
              }.layoutWeight(1).height(64).padding(12).borderRadius(16).backgroundColor(tab.tabId === this.tabId ? this.color('subtle') : Color.Transparent).onClick(() => { this.selectTab(tab.tabId); this.tabsOpen = false; })
              this.icon('close', '关闭标签页 ' + browserTabTitle(tab), () => { this.closeTab(tab.tabId); }, !this.busy)
            }.width('100%')
          }, (tab: BrowserTab) => tab.tabId)
        }.width('100%')
      }.layoutWeight(1).scrollBar(BarState.Off)
    }.padding(16).height('100%')
  }
  @Builder
  private dialogSheet() {
    Column({ space: 14 }) {
      Text(this.dialog?.message ?? '').fontSize(this.font(16)).fontColor(this.color('foreground')).width('100%')
      if (this.dialog?.type === 'prompt') { TextInput({ text: this.promptText }).onChange((text: string) => { this.promptText = text; }) }
      Row({ space: 12 }) { Button('取消').onClick(() => { this.answerDialog(false); }); Button('确定').onClick(() => { this.answerDialog(true); }) }.justifyContent(FlexAlign.End).width('100%')
    }.padding(20).width('100%')
  }
  build() {
    Column({ space: 0 }) {
      ChatGlass() {
        Row({ space: 4 }) {
          this.icon('back', '返回会话', () => { router.back(); })
          Text(this.selected() ? browserTabTitle(this.selected()!) : '浏览器').fontSize(this.font(16)).fontWeight(FontWeight.Medium).fontColor(this.color('foreground')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          Button({ type: ButtonType.Normal }) { Row({ space: 5 }) { AppIcon({ name: 'globe', iconSize: 18, tint: this.color('foreground-secondary') }); Text(String(this.tabs.length)).fontSize(this.font(13)).fontColor(this.color('foreground-secondary')) } }
            .height(38).padding(10).backgroundColor(Color.Transparent).accessibilityText('浏览器标签列表').onClick(() => { this.tabsOpen = true; })
            .bindSheet($$this.tabsOpen, this.tabSheet(), { systemMaterial: immersiveMaterial('popup'), height: SheetSize.LARGE, dragBar: true, showClose: false })
        }.width('100%').padding({ left: 6, right: 10, top: 4, bottom: 4 })
      }
      if (this.tabId) {
        Row({ space: 2 }) {
          this.icon('back', '网页后退', () => { this.send('{"type":"history","delta":-1}'); }, this.controller === 'you' && this.selected()?.canGoBack === true)
          this.icon('chevron', '网页前进', () => { this.send('{"type":"history","delta":1}'); }, this.controller === 'you' && this.selected()?.canGoForward === true)
          TextInput({ text: this.address, placeholder: '输入网页地址' }).layoutWeight(1).height(40).fontSize(this.font(13)).fontColor(this.color('foreground')).backgroundColor(this.color('input'))
            .enabled(this.controller === 'you').enterKeyType(EnterKeyType.Go).onFocus(() => { this.editingAddress = true; }).onBlur(() => { this.editingAddress = false; })
            .onChange((value: string) => { this.address = value; }).onSubmit(() => { this.navigate(); })
          this.icon('refresh', '刷新网页', () => { this.send('{"type":"reload"}'); }, this.controller === 'you')
        }.width('100%').padding({ left: 4, right: 4, bottom: 8 })
        Row({ space: 8 }) {
          Text(this.controller === 'you' ? '由你控制' : this.controller === 'agent' ? '智能体正在控制' : this.controller === 'another-viewer' ? '其他设备正在控制' : '正在观看')
            .fontSize(this.font(12)).fontColor(this.color('foreground-muted')).layoutWeight(1)
          Button(this.controller === 'you' ? '交还控制' : '接管').height(32).fontSize(this.font(12)).fontColor(this.color('foreground')).backgroundColor(this.color('subtle')).enabled(!this.busy && this.connected && this.controller !== 'another-viewer').onClick(() => { this.takeControl(); })
        }.width('100%').padding({ left: 14, right: 12, bottom: 8 })
        Stack() {
          Web({ src: $rawfile('preview-stream.html'), controller: this.web }).width('100%').height('100%').javaScriptAccess(true).domStorageAccess(false).fileAccess(false).mixedMode(MixedMode.All)
            .javaScriptProxy({ object: this.bridge, name: 'HarmonyBrowser', methodList: ['postMessage'], controller: this.web })
            .onPageEnd(() => { this.webReady = true; this.startStream(); })
            .onErrorReceive(() => { this.error = '浏览器查看器加载失败，请重试'; })
          if (!this.connected && !this.error) { Text(this.status).fontSize(this.font(14)).fontColor(this.color('foreground-muted')).padding(14).backgroundColor(this.color('card')).borderRadius(16).hitTestBehavior(HitTestMode.Block) }
        }.width('100%').layoutWeight(1)
      } else {
        Column({ space: 16 }) {
          AppIcon({ name: 'globe', iconSize: 42, tint: this.color('foreground-muted') })
          Text('此会话还没有浏览器标签页').fontSize(this.font(15)).fontColor(this.color('foreground-muted'))
          Button('新建标签页').enabled(this.rpc !== null && !this.busy).onClick(() => { this.openTab(); })
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      }
      if (this.error) { Row({ space: 8 }) { Text(this.error).fontSize(this.font(12)).fontColor(this.color('danger')).layoutWeight(1); this.icon('refresh', '重新连接浏览器', () => { this.authFailures = 0; this.startStream(); }); }.padding(12).width('100%') }
    }.width('100%').height('100%').backgroundColor(this.color('screen'))
      .bindSheet($$this.dialogOpen, this.dialogSheet(), { systemMaterial: immersiveMaterial('popup'), height: SheetSize.FIT_CONTENT, showClose: false, dragBar: false, shouldDismiss: () => { this.answerDialog(false); } })
  }
}
