import { ChatGlass, immersiveMaterial } from './ChatGlass';
import { AppIcon } from './AppIcon';
import { DraftStore } from '../connection/DraftStore';
import { terminalExcerpt } from '../model/TerminalOutput';
import { Typography, resolveTypography, scaledFontSize } from '../model/Typography';
import { ThemeRuntime } from '../connection/ThemeRuntime';
import window from '@ohos.window';
import { TypographyRuntime } from '../connection/TypographyRuntime';
import { DEFAULT_TERMINAL_FONT_SIZE, terminalMetrics } from '../model/TerminalMetrics';
import pasteboard from '@ohos.pasteboard';
import { KeyCode } from '@ohos.multimodalInput.keyCode';
import { terminalTextKey, terminalControlKey } from '../model/TerminalTextKey';
import { TerminalInput } from '../connection/TerminalInput';
import { TerminalKeyboard } from '../connection/TerminalKeyboard';
import terminalNative, { TerminalFrame } from 'libt3terminal.so';
import { TerminalCanvas } from '../bridge/TerminalCanvas';
import router from '@ohos.router';
import { EnvironmentSession } from '../connection/Environment';
import { RpcClient } from '../connection/Rpc';
import { ReconnectingRpc } from '../connection/ReconnectingRpc';
import { TerminalState, TerminalEvent, terminalAttach, terminalWrite, terminalResize, terminalClose, terminalRestart, TerminalClosures } from '../model/TerminalState';

@Entry
@Component
struct TerminalPage {
  @State selecting: boolean = false;
  @State controlsOpen: boolean = false;
  @State lineEntry: boolean = false;
  @State outputOpen: boolean = false;
  @State outputLines: string[] = [];
  @State outputStart: number = 0;
  @State outputEnd: number = 0;
  @State outputAnchor: number = -1;
  @State outputError: string = '';
  @State attachingOutput: boolean = false;
  private anchorX: number = 0;
  private anchorY: number = 0;
  private selectionPoint(event: GestureEvent): number[] {
    const finger = event.fingerList[0];
    const metrics = terminalMetrics(this.fontSize);
    return [Math.max(0, Math.min(this.cols - 1, Math.floor(finger.localX / metrics.width))),
      Math.max(0, Math.min(this.rows - 1, Math.floor(finger.localY / metrics.height)))];
  }
  private clearSelection(): void {
    this.selecting = false;
    if (this.terminal !== null) {
      terminalNative.clearSelection(this.terminal);
      this.frame = terminalNative.snapshot(this.terminal);
    }
  }
  private selectWord(event: GestureEvent): void {
    if (this.terminal === null || !event.fingerList.length) return;
    const point = this.selectionPoint(event);
    try {
      terminalNative.selectWord(this.terminal, point[0], point[1]);
      this.selecting = true;
      this.frame = terminalNative.snapshot(this.terminal);
    } catch (_) { this.status = '此处没有可选择的文本'; }
  }
  private selectAll(): void {
    if (this.terminal === null) return;
    try {
      terminalNative.selectAll(this.terminal);
      this.selecting = true;
      this.frame = terminalNative.snapshot(this.terminal);
    } catch (_) { this.status = '没有可选择的文本'; }
  }
  private async copySelection(): Promise<void> {
    const handle = this.terminal;
    if (handle === null) return;
    try {
      const text = terminalNative.selectionText(handle);
      if (!text) { this.status = '未选中文本'; return; }
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text));
      if (this.active && this.terminal === handle) { this.clearSelection(); this.status = '已复制'; }
    } catch (_) { if (this.active) this.status = '复制失败，请重试'; }
  }
  private font(size: number): number { return scaledFontSize(size, this.sizes.baseFontSize); }
  @StorageLink('textSizes') @Watch('typographyChanged') sizes: Typography = resolveTypography(16, null, null);
  @StorageLink('themeKey') @Watch('themeChanged') themeKey: string = 't3-code-light';
  private color(role: string): string { return ThemeRuntime.color(this.themeKey, role); }
  @State frame: TerminalFrame = { cols: 1, rows: 1, cursorX: 0, cursorY: 0, cursorVisible: 0,
    cursorColor: 0xe2e8f0, background: 0x0f172a, cells: [] };
  private terminal: object | null = null;
  @State @Watch('fontChanged') fontSize: number = DEFAULT_TERMINAL_FONT_SIZE;
  @State appearanceError: string = '';
  private viewportWidth: number = 0;
  private viewportHeight: number = 0;
  @State inputLine: string = '';
  @State status: string = '正在连接…';
  @State ready: boolean = false;
  @State sending: boolean = false;
  @State directInput: boolean = false;
  @State keyboardInset: number = 0;
  private appWindow: window.Window | null = null;
  private active: boolean = false;
  private onKeyboardHeight: (height: number) => void = (height: number) => {
    this.keyboardInset = this.directInput ? px2vp(height) : 0;
  };
  private input: TerminalInput | null = null;
  private keyboard: TerminalKeyboard = new TerminalKeyboard((text: string) => { this.write(text); },
    (text: string) => {
      if (this.terminal !== null) this.write(terminalNative.encodePaste(this.terminal, text));
    });
  @State lifecycleBusy: boolean = false;
  private closedByUser: boolean = false;
  private rpc: RpcClient | null = null;
  private connection: ReconnectingRpc | null = null;
  private state: TerminalState = new TerminalState('', '');
  private environmentId: string = '';
  private threadId: string = '';
  private terminalId: string = 'term-1';
  private cwd: string = '';
  private panRows: number = 0;
  private cols: number = 80;
  private rows: number = 24;

  aboutToAppear(): void {
    this.active = true;
    this.fontSize = this.sizes.terminalFontSize;
    window.getLastWindow(getContext(this)).then((current: window.Window) => {
      if (!this.active) return;
      this.appWindow = current; current.on('keyboardHeightChange', this.onKeyboardHeight);
    }).catch(() => { this.status = '无法获取键盘布局'; });
    const params = router.getParams() as Record<string, string>;
    this.threadId = params['threadId'] ?? '';
    this.terminalId = params['terminalId'] ?? 'term-1';
    this.cwd = params['cwd'] ?? '';
    this.state = new TerminalState(this.threadId, this.terminalId);
    const environment = EnvironmentSession.current;
    if (environment === null || !this.threadId || !this.cwd) {
      this.status = '缺少终端连接或工作目录，请返回任务后重试';
      return;
    }
    this.environmentId = environment.descriptor.environmentId;
    this.closedByUser = TerminalClosures.has(this.environmentId, this.threadId, this.terminalId);
    try { this.terminal = terminalNative.create(this.cols, this.rows); this.resizeEngine(); this.applyTheme(); }
    catch (error) { this.status = `终端引擎无法启动：${String(error)}`; return; }
    this.connection = new ReconnectingRpc(() => environment.openRpc(), (rpc: RpcClient) => {
      this.rpc = rpc;
      this.input = new TerminalInput(async (data: string) => {
        await rpc.call('terminal.write', terminalWrite(this.threadId, this.terminalId, data));
      });
      return rpc.callStream('terminal.attach', terminalAttach(this.threadId, this.terminalId, this.cwd, this.cols, this.rows),
        (values: object[]) => {
          this.connection?.healthy();
          for (const value of values) {
            const event = value as TerminalEvent;
            const update = this.state.apply(event);
            if (update === null) continue;
            if (update.reset) {
              this.selecting = false;
              if (this.terminal !== null) terminalNative.destroy(this.terminal);
              this.terminal = terminalNative.create(this.cols, this.rows);
              this.resizeEngine();
              this.applyTheme();
            }
            if (this.terminal !== null) {
              const response = terminalNative.feed(this.terminal, update.data);
              // Do not replay query responses embedded in historical snapshots.
              if (response && !update.reset) rpc.call('terminal.write', terminalWrite(this.threadId, this.terminalId, response))
                .catch(() => { this.status = '终端响应发送失败'; });
            }
          }
          if (this.terminal !== null) this.frame = terminalNative.snapshot(this.terminal);
          const becameReady = !this.ready && this.state.status === 'running';
          this.ready = this.state.status === 'running';
          this.status = this.state.error || (this.ready ? '已连接' : `终端 ${this.state.status}`);
          // Font/layout changes can finish while attach is in flight.
          if (becameReady) rpc.call('terminal.resize', terminalResize(this.threadId, this.terminalId, this.cols, this.rows))
            .catch(() => { this.status = '终端尺寸同步失败'; });
        });
    }, () => {
      this.input?.close();
      this.rpc = null;
      this.ready = false;
      this.status = '正在连接终端…';
    });
    if (this.closedByUser) this.status = '终端已关闭';
    // onPageShow starts the subscription once the page is visible.
  }

  aboutToDisappear(): void {
    this.active = false;
    this.appWindow?.off('keyboardHeightChange', this.onKeyboardHeight);
    this.appWindow = null;
    this.input?.close();
    this.keyboard.close().catch(() => {});
    this.connection?.stop(); this.rpc = null;
    if (this.terminal !== null) terminalNative.destroy(this.terminal);
    this.terminal = null;
  }
  onPageHide(): void {
    this.input?.close();
    this.keyboard.close().catch(() => {});
    this.connection?.stop(); this.rpc = null; this.ready = false;
  }
  onPageShow(): void {
    this.loadAppearance();
    if (!this.closedByUser && !this.lifecycleBusy) this.connection?.start();
  }

  private applyTheme(): void {
    if (this.terminal === null) return;
    const theme = ThemeRuntime.palette(this.themeKey).terminal;
    terminalNative.setTheme(this.terminal, Number.parseInt(theme.foreground.slice(1), 16),
      Number.parseInt(theme.background.slice(1), 16), Number.parseInt(theme.cursorForeground.slice(1), 16),
      theme.palette.map((value: string) => Number.parseInt(value.slice(1), 16)));
    this.frame = terminalNative.snapshot(this.terminal);
  }
  private themeChanged(): void {
    try { this.applyTheme(); }
    catch (_) { this.appearanceError = '终端主题应用失败，请重新打开终端'; }
  }

  private async loadAppearance(): Promise<void> {
    try {
      await TypographyRuntime.reload();
      if (!this.active) return;
      this.fontSize = this.sizes.terminalFontSize;
      this.appearanceError = '';
    } catch (_) { if (this.active) this.appearanceError = '字号设置读取失败，正在使用当前字号'; }
  }
  private typographyChanged(): void { this.fontSize = this.sizes.terminalFontSize; }
  private fontChanged(): void {
    if (this.viewportWidth > 0 && this.viewportHeight > 0) this.resize(this.viewportWidth, this.viewportHeight);
  }

  private confirmClose(): void {
    AlertDialog.show({ title: '关闭终端？', message: '将结束此终端中的 shell 和子进程，保留终端历史。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '关闭终端', action: () => { this.changeTerminal(false); } }
    });
  }

  private async changeTerminal(reopen: boolean): Promise<void> {
    const environment = EnvironmentSession.current;
    if (environment === null || this.lifecycleBusy) return;
    this.lifecycleBusy = true;
    this.closedByUser = true;
    this.input?.close();
    this.keyboard.close().catch(() => {});
    TerminalClosures.set(this.environmentId, this.threadId, this.terminalId, true);
    this.connection?.stop();
    this.rpc = null;
    this.ready = false;
    this.status = reopen ? '正在打开终端…' : '正在关闭终端…';
    let control: RpcClient | null = null;
    try {
      control = await environment.openRpc();
      if (reopen) {
        await control.call('terminal.restart', terminalRestart(this.threadId, this.terminalId, this.cwd, this.cols, this.rows));
        this.closedByUser = false;
        TerminalClosures.set(this.environmentId, this.threadId, this.terminalId, false);
        this.connection?.start();
      } else {
        await control.call('terminal.close', terminalClose(this.threadId, this.terminalId));
        this.status = '终端已关闭';
      }
    } catch (error) {
      this.status = `${reopen ? '打开' : '关闭'}失败：${error instanceof Error ? error.message : String(error)}`;
    } finally { control?.close(); this.lifecycleBusy = false; }
  }

  private async write(data: string): Promise<boolean> {
    const input = this.input;
    if (input === null || !this.ready || !data) return false;
    this.clearSelection();
    this.latest();
    this.sending = true;
    try {
      await input.write(data);
      return true;
    } catch (error) {
      this.status = error instanceof Error ? error.message : '输入失败';
      return false;
    } finally { this.sending = false; }
  }

  private async pasteClipboard(): Promise<void> {
    const input = this.input;
    if (input === null || !this.ready || !this.directInput) return;
    try {
      this.latest();
      await input.paste(async (): Promise<string> => {
        const data = await pasteboard.getSystemPasteboard().getData();
        if (!this.active || !this.directInput || this.input !== input || this.terminal === null) return '';
        const text = data.getPrimaryText();
        return text ? terminalNative.encodePaste(this.terminal, text) : '';
      });
    } catch (_) { if (this.active) this.status = '粘贴失败，请重试或使用输入法剪贴板'; }
  }

  private async submit(): Promise<void> {
    if (this.sending) return;
    const text = this.inputLine;
    if (await this.write(`${text}\r`)) {
      if (this.inputLine === text) this.inputLine = '';

    }
  }

  private async showKeyboard(): Promise<void> {
    this.directInput = true;
    try {
      await this.keyboard.show();
      if (this.active && this.directInput) focusControl.requestFocus('terminal-key-input');
    }
    catch (error) { this.status = `键盘连接失败：${String(error)}`; }
  }

  private editingKey(event: KeyEvent): boolean {
    if (!this.directInput || !this.ready) return false;
    let data = '';
    if (event.getModifierKeyState?.(['ctrl']) && !event.getModifierKeyState?.(['alt'])) {
      data = terminalControlKey(event.keyText, event.getModifierKeyState?.(['shift']) ?? false);
    } else if (event.keyCode === KeyCode.KEYCODE_ENTER) data = '\r';
    else if (event.keyCode === KeyCode.KEYCODE_DEL) data = '\u007f';
    else if (event.keyCode === KeyCode.KEYCODE_FORWARD_DEL) data = '\u001b[3~';
    else if (event.keyCode === KeyCode.KEYCODE_TAB && event.getModifierKeyState?.(['shift'])) data = '\u001b[Z';
    if (!data) return false;
    if (event.type === KeyType.Down) this.write(data);
    return true;
  }

  private textKey(event: KeyEvent): boolean {
    if (!this.directInput || !this.ready || event.getModifierKeyState?.(['ctrl']) ||
      event.getModifierKeyState?.(['alt'])) return false;
    const data = terminalTextKey(event.keyText, event.unicode ?? 0,
      event.getModifierKeyState?.(['shift']) ?? false, event.isCapsLockOn ?? false);
    if (!data) return false;
    if (event.type === KeyType.Down) this.write(data);
    return true;
  }

  private async lineInput(): Promise<void> {
    await this.keyboard.close();
    this.directInput = false;
    this.keyboardInset = 0;
  }

  private scroll(rows: number): void {
    if (this.terminal === null) return;
    terminalNative.scroll(this.terminal, rows);
    this.frame = terminalNative.snapshot(this.terminal);
  }

  private latest(): void {
    if (this.terminal === null) return;
    terminalNative.scrollToBottom(this.terminal);
    this.frame = terminalNative.snapshot(this.terminal);
  }

  private resizeEngine(): void {
    if (this.terminal === null) return;
    const metrics = terminalMetrics(this.fontSize);
    terminalNative.resize(this.terminal, this.cols, this.rows,
      Math.max(1, Math.round(vp2px(metrics.width))), Math.max(1, Math.round(vp2px(metrics.height))));
  }
  private async resize(width: number, height: number): Promise<void> {
    this.viewportWidth = width;
    this.viewportHeight = height;
    const metrics = terminalMetrics(this.fontSize);
    const size = terminalResize(this.threadId, this.terminalId, Math.floor(width / metrics.width), Math.floor(height / metrics.height));
    const gridChanged = size.cols !== this.cols || size.rows !== this.rows;
    if (gridChanged && this.selecting) this.clearSelection();
    this.cols = size.cols;
    this.rows = size.rows;
    if (this.terminal !== null) {
      this.resizeEngine();
      this.frame = terminalNative.snapshot(this.terminal);
    }
    if (gridChanged && this.rpc !== null && this.ready) {
      try { await this.rpc.call('terminal.resize', size); }
      catch (_) { this.status = '终端尺寸同步失败'; }
    }
  }

  private async openOutput(): Promise<void> {
    if (this.terminal === null) return;
    try {
      await this.lineInput();
      if (!this.active || this.terminal === null) return;
      const lines: string[] = [];
      for (let y = 0; y < this.rows; y++) {
        terminalNative.selectRange(this.terminal, 0, y, this.cols - 1, y);
        lines.push(terminalNative.selectionText(this.terminal).replace(/\s+$/, ''));
      }
      while (lines.length > 1 && !lines[lines.length - 1]) lines.pop();
      this.outputLines = lines; this.outputStart = 0; this.outputEnd = lines.length - 1;
      this.outputAnchor = -1; this.outputError = ''; this.outputOpen = true;
    } catch (_) { this.status = '无法读取当前可见输出，请重试'; }
    finally { this.clearSelection(); }
  }
  private chooseOutputLine(index: number): void {
    if (this.outputAnchor < 0) { this.outputAnchor = index; this.outputStart = index; this.outputEnd = index; }
    else { this.outputStart = Math.min(index, this.outputAnchor); this.outputEnd = Math.max(index, this.outputAnchor); this.outputAnchor = -1; }
  }
  private outputText(): string | null { return terminalExcerpt(this.outputLines, this.outputStart, this.outputEnd, this.terminalId); }
  private async attachOutput(): Promise<void> {
    const excerpt = this.outputText();
    if (excerpt === null || this.attachingOutput || EnvironmentSession.current?.descriptor.environmentId !== this.environmentId) return;
    this.attachingOutput = true; this.outputError = '';
    try {
      const store = await DraftStore.open(getContext(this).filesDir, this.environmentId, this.threadId);
      const draft = await store.load();
      if (!this.active || EnvironmentSession.current?.descriptor.environmentId !== this.environmentId) return;
      await store.save(draft ? draft + '\n\n' + excerpt : excerpt);
      if (this.active) { this.outputOpen = false; router.back(); }
    } catch (_) { this.outputError = '保存到消息草稿失败，请重试'; }
    finally { this.attachingOutput = false; }
  }
  @Builder
  outputSheet() {
    Column({ space: 12 }) {
      Text('点击起始行和结束行选择范围').fontSize(this.font(13)).fontColor(this.color('foreground-muted')).width('100%')
      List() {
        ForEach(this.outputLines, (line: string, index: number) => {
          ListItem() {
            Row({ space: 12 }) {
              Text(String(index + 1)).fontFamily('monospace').fontSize(this.font(12)).fontColor(this.color('foreground-muted')).width(30)
              Text(line || ' ').fontFamily('monospace').fontSize(this.sizes.codeFontSize).fontColor(this.color('foreground')).layoutWeight(1)
            }.width('100%').padding({ top: 6, bottom: 6, left: 8, right: 8 })
              .backgroundColor(index >= this.outputStart && index <= this.outputEnd ? this.color('subtle-strong') : Color.Transparent)
              .onClick(() => { this.chooseOutputLine(index); }).accessibilityText(`第 ${index + 1} 行：${line}`)
          }
        }, (_line: string, index: number) => String(index))
      }.layoutWeight(1).width('100%')
      if (this.outputError) { Text(this.outputError).fontSize(this.font(12)).fontColor(this.color('danger-foreground')) }
      if (this.outputText() === null) { Text('请选择非空输出，最多 64,000 个字符').fontSize(this.font(12)).fontColor(this.color('foreground-muted')) }
      Button({ type: ButtonType.Normal }) {
        Row({ space: 8 }) {
          AppIcon({ name: 'attach', iconSize: 18, tint: this.color('foreground') })
          Text(`附加选中输出 · ${this.outputEnd - this.outputStart + 1} 行`).fontSize(this.font(15)).fontColor(this.color('foreground'))
        }.justifyContent(FlexAlign.Center).width('100%')
      }.width('100%').height(48).borderRadius(16).backgroundColor(this.color('card'))
        .enabled(this.outputText() !== null && !this.attachingOutput).onClick(() => { this.attachOutput(); })
    }.width('100%').height('100%').padding({ left: 16, right: 16, top: 8, bottom: 24 })
  }
  build() {
    Column({ space: 6 }) {
      ChatGlass() {
        Row({ space: 4 }) {
          Button({ type: ButtonType.Circle }) { AppIcon({ name: 'back', iconSize: 22, tint: this.color('foreground') }) }
            .width(38).height(38).padding(0).backgroundColor(Color.Transparent).accessibilityText('返回').onClick(() => { router.back(); })
          Column({ space: 3 }) {
            Text(this.terminalId).fontSize(this.font(16)).fontColor(this.color('foreground')).fontWeight(FontWeight.Medium).maxLines(1).width('100%')
            Text(this.cwd).fontSize(this.font(10)).fontColor(this.color('foreground-muted')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          }.layoutWeight(1)
          Button({ type: ButtonType.Circle }) { AppIcon({ name: 'latest', iconSize: 19, tint: this.color('foreground-secondary') }) }
            .width(36).height(36).padding(0).backgroundColor(Color.Transparent).accessibilityText('回到最新输出').onClick(() => { this.latest(); })
          Button({ type: ButtonType.Circle }) { AppIcon({ name: 'copy', iconSize: 19, tint: this.color('foreground-secondary') }) }
            .width(36).height(36).padding(0).backgroundColor(Color.Transparent).accessibilityText('选择文本').onClick(() => { this.selecting = true; })
          Button({ type: ButtonType.Circle }) { AppIcon({ name: 'settings', iconSize: 19, tint: this.color('foreground-secondary') }) }
            .width(36).height(36).padding(0).backgroundColor(Color.Transparent).accessibilityText('终端设置').onClick(() => { router.pushUrl({ url: 'pages/Settings' }); })
          Button({ type: ButtonType.Circle }) { AppIcon({ name: this.ready ? 'power' : 'refresh', iconSize: 19, tint: this.color('foreground-secondary') }) }
            .width(36).height(36).padding(0).backgroundColor(Color.Transparent).enabled(!this.lifecycleBusy)
            .accessibilityText(this.ready ? '关闭终端' : this.closedByUser || this.state.status === 'exited' || this.state.status === 'closed' ? '重新打开终端' : '重新连接')
            .onClick(() => { if (this.ready) this.confirmClose(); else if (this.closedByUser || this.state.status === 'exited' || this.state.status === 'closed') this.changeTerminal(true); else this.connection?.start(); })
        }.width('100%')
      }
      if (!this.ready || this.status !== '已连接') { Text(this.status).fontSize(this.font(12)).fontColor(this.color('foreground-muted')).width('100%') }
      if (this.appearanceError) { Text(this.appearanceError).fontSize(this.font(12)).fontColor(this.color('danger-foreground')) }
      if (this.selecting) {
        Row({ space: 8 }) {
          Text('拖动选择文本').fontSize(this.font(12)).fontColor(this.color('foreground-muted')).layoutWeight(1)
          Button({ type: ButtonType.Circle }) { AppIcon({ name: 'copy', iconSize: 18, tint: this.color('foreground') }) }
            .width(34).height(34).padding(0).backgroundColor(this.color('card')).accessibilityText('复制选中内容').onClick(() => { this.copySelection(); })
          Button('全选').fontSize(this.font(12)).height(34).fontColor(this.color('foreground')).backgroundColor(this.color('card')).onClick(() => { this.selectAll(); })
          Button({ type: ButtonType.Circle }) { AppIcon({ name: 'close', iconSize: 18, tint: this.color('foreground') }) }
            .width(34).height(34).padding(0).backgroundColor(Color.Transparent).accessibilityText('取消选择').onClick(() => { this.clearSelection(); })
        }.width('100%')
      }
      TerminalCanvas({ frame: this.frame, fontSize: this.fontSize }).layoutWeight(1).width('100%')
        .gesture(GestureGroup(GestureMode.Parallel,
          LongPressGesture({ repeat: false }).onAction((event: GestureEvent) => { this.selectWord(event); }),
          PanGesture({ direction: PanDirection.All })
          .onActionStart((event: GestureEvent) => {
            this.panRows = 0;
            if (this.selecting && event.fingerList.length) {
              const point = this.selectionPoint(event); this.anchorX = point[0]; this.anchorY = point[1];
            }
          })
          .onActionUpdate((event: GestureEvent) => {
            if (this.selecting && this.terminal !== null && event.fingerList.length) {
              const point = this.selectionPoint(event);
              try {
                terminalNative.selectRange(this.terminal, this.anchorX, this.anchorY, point[0], point[1]);
                this.frame = terminalNative.snapshot(this.terminal);
              } catch (_) { this.status = '选择失败，请重试'; }
            } else {
              const rows = Math.trunc(-event.offsetY / terminalMetrics(this.fontSize).height);
              if (rows !== this.panRows) { this.scroll(rows - this.panRows); this.panRows = rows; }
            }
          })))
        .onAreaChange((_old: Area, area: Area) => { this.resize(Number(area.width), Number(area.height)); })
      if (this.controlsOpen || this.directInput || this.lineEntry) {
        Scroll() {
          Row({ space: 6 }) {
            Button('Ctrl+C').fontSize(this.font(12)).height(32).fontColor(this.color('foreground')).backgroundColor(this.color('card')).onClick(() => { this.write('\u0003'); })
            Button('Tab').fontSize(this.font(12)).height(32).fontColor(this.color('foreground')).backgroundColor(this.color('card')).onClick(() => { this.write('\t'); }).keyboardShortcut(FunctionKey.TAB, [])
            Button('Esc').fontSize(this.font(12)).height(32).fontColor(this.color('foreground')).backgroundColor(this.color('card')).onClick(() => { this.write('\u001b'); }).keyboardShortcut(FunctionKey.ESC, [])
            Button('↵').fontSize(this.font(14)).height(32).fontColor(this.color('foreground')).backgroundColor(this.color('card')).accessibilityText('回车').onClick(() => { this.write('\r'); })
            Button('↑').fontSize(this.font(14)).height(32).fontColor(this.color('foreground')).backgroundColor(this.color('card')).onClick(() => { this.write('\u001b[A'); }).keyboardShortcut(FunctionKey.DPAD_UP, [])
            Button('↓').fontSize(this.font(14)).height(32).fontColor(this.color('foreground')).backgroundColor(this.color('card')).onClick(() => { this.write('\u001b[B'); }).keyboardShortcut(FunctionKey.DPAD_DOWN, [])
            Button('←').fontSize(this.font(14)).height(32).fontColor(this.color('foreground')).backgroundColor(this.color('card')).onClick(() => { this.write('\u001b[D'); }).keyboardShortcut(FunctionKey.DPAD_LEFT, [])
            Button('→').fontSize(this.font(14)).height(32).fontColor(this.color('foreground')).backgroundColor(this.color('card')).onClick(() => { this.write('\u001b[C'); }).keyboardShortcut(FunctionKey.DPAD_RIGHT, [])
            Button('Ctrl+A').fontSize(this.font(12)).height(32).fontColor(this.color('foreground')).backgroundColor(this.color('card')).onClick(() => { this.write('\u0001'); })
            Button('Ctrl+D').fontSize(this.font(12)).height(32).fontColor(this.color('foreground')).backgroundColor(this.color('card')).onClick(() => { this.write('\u0004'); })
            Button({ type: ButtonType.Circle }) { AppIcon({ name: 'copy', iconSize: 17, tint: this.color('foreground') }) }
              .width(32).height(32).padding(0).backgroundColor(this.color('card')).accessibilityText('粘贴到终端').onClick(() => { this.pasteClipboard(); })
          }.enabled(this.ready).keyboardShortcut('v', [ModifierKey.CTRL], () => { this.pasteClipboard(); })
        }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).height(36).width('100%')
      }
      if (this.lineEntry) {
        Row({ space: 8 }) {
          TextInput({ placeholder: '输入命令…', text: this.inputLine }).fontSize(this.font(15)).fontColor(this.color('foreground'))
            .backgroundColor(this.color('input')).placeholderColor(this.color('placeholder')).layoutWeight(1)
            .onChange((value: string) => { this.inputLine = value; }).onSubmit(() => { this.submit(); })
          Button({ type: ButtonType.Circle }) { AppIcon({ name: 'send', iconSize: 19, tint: this.color('primary-foreground') }) }
            .width(38).height(38).padding(0).backgroundColor(this.color('primary')).enabled(this.ready && !this.sending).accessibilityText('执行输入命令').onClick(() => { this.submit(); })
        }.width('100%')
      }
      Row({ space: 8 }) {
        Button({ type: ButtonType.Normal }) {
          Row({ space: 7 }) {
            AppIcon({ name: 'attach', iconSize: 18, tint: this.color('foreground-secondary') })
            Text('附加输出').fontSize(this.font(14)).fontColor(this.color('foreground-secondary'))
          }
        }.height(42).padding({ left: 10, right: 10 }).backgroundColor(Color.Transparent).enabled(this.terminal !== null)
          .onClick(() => { this.openOutput(); })
        Blank().layoutWeight(1)
        Button({ type: ButtonType.Circle }) { AppIcon({ name: 'sliders', iconSize: 19, tint: this.controlsOpen ? this.color('primary') : this.color('foreground-secondary') }) }
          .width(38).height(38).padding(0).backgroundColor(Color.Transparent).accessibilityText('终端快捷键').onClick(() => { this.controlsOpen = !this.controlsOpen; })
        Button({ type: ButtonType.Circle }) { AppIcon({ name: 'edit', iconSize: 19, tint: this.lineEntry ? this.color('primary') : this.color('foreground-secondary') }) }
          .width(38).height(38).padding(0).backgroundColor(Color.Transparent).enabled(this.ready).accessibilityText('整行输入')
          .onClick(() => { this.lineEntry = !this.lineEntry; this.lineInput(); })
        Button({ type: ButtonType.Circle }) { AppIcon({ name: 'keyboard', iconSize: 22, tint: this.directInput ? this.color('primary') : this.color('foreground-secondary') }) }
          .width(42).height(42).padding(0).backgroundColor(Color.Transparent).enabled(this.ready).accessibilityText(this.directInput ? '收起键盘' : '打开键盘')
          .onClick(() => { if (this.directInput) this.lineInput(); else { this.lineEntry = false; this.showKeyboard(); } })
      }.width('100%')
    }.id('terminal-key-input').focusable(true)
      .onKeyPreIme((event: KeyEvent): boolean => this.editingKey(event))
      .onKeyEvent((event: KeyEvent): boolean => this.textKey(event))
      .padding({ top: 8, left: 12, right: 12, bottom: 8 + this.keyboardInset })
      .width('100%').height('100%').backgroundColor(this.color('screen'))
      .bindSheet($$this.outputOpen, this.outputSheet(), { systemMaterial: immersiveMaterial('popup'), height: SheetSize.LARGE, title: { title: '可见终端输出' }, dragBar: true, showClose: true })
  }
}
