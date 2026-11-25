import { menuIcon, menuModalMode } from './MenuIcon';
import { ChatPageHeader, immersiveMaterial } from './ChatGlass';
import { Typography, resolveTypography, scaledFontSize } from '../model/Typography';
import { ThemeRuntime } from '../connection/ThemeRuntime';
import router from '@ohos.router';
import pasteboard from '@ohos.pasteboard';
import promptAction from '@ohos.promptAction';
import picker from '@ohos.file.picker';
import { MarkdownText } from './MarkdownText';
import { AppIcon } from './AppIcon';
import { SourceFileText } from './SourceFileText';
import { EnvironmentSession, PreparedConnection } from '../connection/Environment';
import { RpcClient } from '../connection/Rpc';
import { FileDownload, DownloadResource } from '../connection/FileDownload';
import { FileEntry, directoryEntries, fileErrorText, binaryFilePath, binaryFileError, downloadFileName } from '../model/FileEntries';
import { attachmentSize } from '../model/AttachmentLabels';

interface EntriesRequest { cwd: string; }
interface EntriesResult { entries: FileEntry[]; truncated: boolean; }
interface ReadRequest { cwd: string; relativePath: string; }
interface ReadResult { relativePath: string; contents: string; byteLength: number; truncated: boolean; }

@Entry
@Component
struct FilesPage {
  private font(size: number): number { return scaledFontSize(size, this.sizes.baseFontSize); }
  @StorageLink('textSizes') sizes: Typography = resolveTypography(16, null, null);
  @StorageLink('themeKey') themeKey: string = 't3-code-light';
  private color(role: string): string { return ThemeRuntime.color(this.themeKey, role); }
  @State rows: FileEntry[] = [];
  @State directory: string = '';
  @State locationOpen: boolean = false;
  @State query: string = '';
  @State searching: boolean = false;
  @State selectedPath: string = '';
  @State preview: boolean = true;
  @State initialLine: number = 0;
  @State file: ReadResult | null = null;
  @State truncated: boolean = false;
  @State loading: boolean = false;
  @State error: string = '';
  @State downloadOnly: boolean = false;
  @State saving: boolean = false;
  @State received: number = 0;
  @State total: number = 0;
  private entries: FileEntry[] = [];
  private cwd: string = '';
  private environmentId: string = '';
  private threadId: string = '';
  private attachmentId: string = '';
  private attachmentName: string = '';
  private mimeType: string = '';
  private fromLink: boolean = false;
  private rpc: RpcClient | null = null;
  private environment: PreparedConnection | null = null;
  private download: FileDownload | null = null;
  private active: boolean = false;
  private revision: number = 0;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string>;
    this.cwd = params['cwd'] ?? '';
    this.selectedPath = params['path'] ?? '';
    this.environmentId = params['environmentId'] ?? EnvironmentSession.current?.descriptor.environmentId ?? '';
    this.threadId = params['threadId'] ?? '';
    this.attachmentId = params['attachmentId'] ?? '';
    this.attachmentName = params['name'] ?? '';
    this.mimeType = params['mimeType'] ?? 'application/octet-stream';
    const line = Number(params['line']);
    this.initialLine = Number.isInteger(line) && line > 0 ? line : 0;
    if (this.initialLine > 0) this.preview = false;
    this.fromLink = this.hasFile();
    this.active = true;
    this.reload();
  }

  aboutToDisappear(): void {
    this.active = false;
    ++this.revision;
    this.download?.cancel();
    this.rpc?.close();
  }

  onBackPress(): boolean {
    if (this.searching) { this.searching = false; this.query = ''; this.refreshRows(); return true; }
    if (this.fromLink) return false;
    if (!this.selectedPath && !this.directory) return false;
    this.back();
    return true;
  }

  private refreshRows(): void { this.rows = directoryEntries(this.entries, this.directory, this.query); }
  private hasFile(): boolean { return !!this.selectedPath || !!this.attachmentId; }
  private fileName(): string { return downloadFileName(this.attachmentId ? this.attachmentName : this.selectedPath); }
  private async connection(): Promise<PreparedConnection> {
    const environment = EnvironmentSession.current;
    if (environment === null) throw new Error('连接已关闭，请返回重新连接');
    if (this.environmentId && environment.descriptor.environmentId !== this.environmentId) throw new Error('请切回文件所在的环境后重试');
    if (this.environment !== environment) { this.rpc?.close(); this.rpc = null; }
    if (this.rpc === null) {
      const revision = this.revision;
      const rpc = await environment.openRpc();
      if (!this.active || revision !== this.revision) { rpc.close(); throw new Error('页面已切换'); }
      this.rpc = rpc;
      this.environment = environment;
    }
    return environment;
  }

  private async reload(): Promise<void> {
    if (this.loading || this.saving) return;
    const revision = ++this.revision;
    this.loading = true;
    this.error = '';
    try {
      if (this.attachmentId || binaryFilePath(this.selectedPath)) { this.downloadOnly = true; this.file = null; return; }
      this.downloadOnly = false;
      if (!this.cwd) throw new Error('任务缺少项目目录');
      await this.connection();
      const rpc = this.rpc;
      if (rpc === null) throw new Error('连接已关闭，请刷新重试');
      if (this.selectedPath) {
        const request: ReadRequest = { cwd: this.cwd, relativePath: this.selectedPath };
        const file = await rpc.call<ReadResult>('projects.readFile', request);
        if (this.active && revision === this.revision) this.file = file;
      } else {
        const request: EntriesRequest = { cwd: this.cwd };
        const result = await rpc.call<EntriesResult>('projects.listEntries', request);
        if (!this.active || revision !== this.revision) return;
        this.entries = result.entries;
        this.truncated = result.truncated;
        this.refreshRows();
      }
    } catch (error) {
      if (this.active && revision === this.revision) {
        const message = error instanceof Error ? error.message : String(error);
        if (this.selectedPath && binaryFileError(message)) { this.downloadOnly = true; this.file = null; }
        else this.error = fileErrorText(message);
        this.rpc?.close();
        this.rpc = null;
      }
    } finally {
      if (revision === this.revision) this.loading = false;
    }
  }

  private open(entry: FileEntry): void {
    if (this.loading || this.saving) return;
    this.error = '';
    if (entry.kind === 'directory') {
      this.directory = entry.path;
      this.query = '';
      this.refreshRows();
    } else {
      this.selectedPath = entry.path;
      this.initialLine = 0;
      this.preview = true;
      this.file = null;
      this.reload();
    }
  }

  private back(): void {
    this.download?.cancel();
    this.saving = false;
    ++this.revision;
    if (this.fromLink) { router.back(); return; }
    this.loading = false;
    this.error = '';
    if (this.selectedPath) {
      this.selectedPath = '';
      this.file = null;
      this.downloadOnly = false;
    } else if (this.directory) {
      const slash = this.directory.lastIndexOf('/');
      this.directory = slash < 0 ? '' : this.directory.substring(0, slash);
      this.query = '';
      this.refreshRows();
    } else router.back();
  }

  private async saveFile(): Promise<void> {
    if (!this.hasFile() || this.loading || this.saving) return;
    const revision = this.revision;
    const download = new FileDownload();
    this.download = download;
    this.saving = true; this.error = ''; this.received = 0; this.total = 0;
    try {
      const environment = await this.connection();
      const rpc = this.rpc;
      if (rpc === null) throw new Error('连接已关闭，请刷新重试');
      let resource: DownloadResource;
      if (this.attachmentId) resource = { _tag: 'attachment', attachmentId: this.attachmentId, fileName: this.fileName(), mimeType: this.mimeType };
      else if (this.threadId) resource = { _tag: 'media-file', threadId: this.threadId,
        path: this.cwd ? this.cwd.replace(/\/$/, '') + '/' + this.selectedPath : this.selectedPath, disposition: 'attachment' };
      else resource = { _tag: 'draft-workspace-file', cwd: this.cwd, path: this.selectedPath };
      await download.fetch(rpc, environment.httpBaseUrl, resource, getContext(this).cacheDir, (received: number, total: number) => {
        if (this.active && revision === this.revision) { this.received = received; this.total = total; }
      });
      if (!this.active || revision !== this.revision) return;
      const uris = await new picker.DocumentViewPicker().save({ newFileNames: [this.fileName()] });
      if (!uris[0] || !this.active || revision !== this.revision) return;
      await download.save(uris[0]);
      if (this.active && revision === this.revision) promptAction.showToast({ message: '文件已保存' });
    } catch (error) {
      if (this.active && revision === this.revision) {
        this.error = fileErrorText(error instanceof Error ? error.message : String(error));
        this.rpc?.close(); this.rpc = null;
      }
    } finally {
      await download.dispose();
      if (this.download === download) this.download = null;
      if (this.active && revision === this.revision) this.saving = false;
    }
  }

  private downloadStatus(): string {
    return this.received > 0 ? `正在下载 ${attachmentSize(this.received)}${this.total > 0 ? ' / ' + attachmentSize(this.total) : ''}` : '正在准备下载…';
  }

  private async copyText(text: string): Promise<void> {
    try {
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text));
      promptAction.showToast({ message: '已复制' });
    } catch (_) { promptAction.showToast({ message: '复制失败，请重试' }); }
  }

  private pathName(path: string): string { return path.replace(/[\\/]$/, '').split(/[\\/]/).pop() || path || '项目目录'; }
  private fullPath(relative: string): string {
    if (!relative || !this.cwd) return relative || this.cwd;
    const windows = this.cwd.includes('\\') && !this.cwd.includes('/');
    return this.cwd.replace(/[\\/]$/, '') + (windows ? '\\' + relative.replace(/\//g, '\\') : '/' + relative);
  }
  private location(): string { return this.attachmentId ? this.fileName() : this.fullPath(this.selectedPath || this.directory); }
  private toggleSearch(): void { this.searching = !this.searching; if (!this.searching) { this.query = ''; this.refreshRows(); } }
  @Builder
  private locationSheet() {
    Column({ space: 12 }) {
      Scroll() {
        Text(this.location()).width('100%').fontSize(this.font(15)).fontColor(this.color('foreground'))
          .wordBreak(WordBreak.BREAK_ALL).copyOption(CopyOptions.LocalDevice)
      }.width('100%').layoutWeight(1).align(Alignment.TopStart)
      Row({ space: 8 }) {
        if (!this.attachmentId && (this.selectedPath || this.directory) && this.cwd) {
          Button('复制相对路径').height(44).layoutWeight(1).fontSize(this.font(14)).fontColor(this.color('foreground'))
            .backgroundColor(this.color('subtle')).onClick(() => { this.copyText(this.selectedPath || this.directory); })
        }
        Button(this.attachmentId ? '复制文件名' : '复制完整路径').height(44).layoutWeight(1).fontSize(this.font(14))
          .fontColor(this.color('primary-foreground')).backgroundColor(this.color('primary')).onClick(() => { this.copyText(this.location()); })
      }.width('100%')
    }.width('100%').height('100%').padding({ left: 20, right: 20, top: 8, bottom: 20 })
  }
  @Builder
  fileMenu(entry: FileEntry) {
    Menu() {
      MenuItem({ content: '复制相对路径', symbolStartIcon: menuIcon($r('sys.symbol.doc_text_on_doc_text')) }).onClick(() => { this.copyText(entry.path); })
      MenuItem({ content: '复制完整路径', symbolStartIcon: menuIcon($r('sys.symbol.link')) }).onClick(() => { this.copyText(this.fullPath(entry.path)); })
    }
  }
  build() {
    Column({ space: 6 }) {
      ChatPageHeader() {
        Row({ space: 6 }) {
          Button({ type: ButtonType.Circle }) { AppIcon({ name: 'back', iconSize: 22, tint: this.color('foreground') }) }
            .width(40).height(40).padding(0).backgroundColor(Color.Transparent).accessibilityText('返回').onClick(() => { this.back(); })
          Button({ type: ButtonType.Normal }) {
            Column({ space: 2 }) {
              Text(this.hasFile() ? this.fileName() : '项目文件').width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .fontSize(this.font(16)).fontWeight(FontWeight.Medium).fontColor(this.color('foreground')).textAlign(TextAlign.Start)
              Row({ space: 4 }) {
                if (!this.hasFile()) { AppIcon({ name: 'folder', iconSize: 12, tint: this.color('glass-label') }) }
                Text(this.saving ? this.downloadStatus() : this.hasFile() ? this.file ? `${this.file.byteLength} 字节${this.file.truncated ? ' · 部分内容' : ''}` : '文件' : this.pathName(this.directory || this.cwd))
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).flexShrink(1).fontSize(this.font(12)).fontColor(this.color('glass-label'))
                AppIcon({ name: 'down', iconSize: 10, tint: this.color('glass-label') })
              }.width('100%')
            }.width('100%').alignItems(HorizontalAlign.Start)
          }.id('file-location').layoutWeight(1).constraintSize({ minHeight: 44 }).padding({ top: 4, bottom: 4 }).borderRadius(10)
            .backgroundColor(Color.Transparent).accessibilityText(`查看当前位置：${this.location()}`).onClick(() => { this.locationOpen = true; })
            .bindSheet($$this.locationOpen, this.locationSheet(), { height: SheetSize.MEDIUM, title: { title: this.attachmentId ? '文件名' : '当前位置' },
              systemMaterial: immersiveMaterial('popup'), dragBar: true, showClose: true })
          if (!this.hasFile()) {
            Button({ type: ButtonType.Circle }) { AppIcon({ name: this.searching ? 'close' : 'search', iconSize: 20, tint: this.color('glass-label') }) }
              .width(38).height(38).padding(0).backgroundColor(Color.Transparent).accessibilityText(this.searching ? '关闭搜索' : '搜索文件').onClick(() => { this.toggleSearch(); })
          } else {
            Button({ type: ButtonType.Circle }) {
              if (this.saving) { LoadingProgress().width(20).height(20) }
              else { AppIcon({ name: 'download', iconSize: 20, tint: this.color('glass-label') }) }
            }.width(38).height(38).padding(0).backgroundColor(Color.Transparent).enabled(!this.loading && !this.saving)
              .accessibilityText('下载原文件').onClick(() => { this.saveFile(); })
            if (this.file !== null) {
              Button({ type: ButtonType.Circle }) { AppIcon({ name: 'copy', iconSize: 20, tint: this.color('glass-label') }) }
                .width(38).height(38).padding(0).backgroundColor(Color.Transparent).enabled(!this.loading)
                .accessibilityText(this.file?.truncated ? '复制已显示文本' : '复制文件内容').onClick(() => { if (this.file !== null) this.copyText(this.file.contents); })
            }
            if (/\.(md|markdown)$/i.test(this.selectedPath)) {
              Button({ type: ButtonType.Circle }) { AppIcon({ name: this.preview ? 'terminal' : 'file', iconSize: 20, tint: this.color('glass-label') }) }
                .width(38).height(38).padding(0).backgroundColor(Color.Transparent).accessibilityText(this.preview ? '查看源码' : '预览 Markdown').onClick(() => { this.preview = !this.preview; })
            }
          }
          Button({ type: ButtonType.Circle }) {
            if (this.loading) { LoadingProgress().width(22).height(22) }
            else { AppIcon({ name: 'refresh', iconSize: 20, tint: this.color('glass-label') }) }
          }.width(38).height(38).padding(0).backgroundColor(Color.Transparent).enabled(!this.loading && !this.saving).accessibilityText('刷新').onClick(() => { this.reload(); })
        }.width('100%').padding({ left: 6, right: 8 })
      }
      if (this.error) { Text(this.error).fontColor(this.color('danger-foreground')).fontSize(this.font(13)).padding(16).width('100%') }
      if (this.hasFile()) {
        if (this.downloadOnly) {
          Column({ space: 16 }) {
            AppIcon({ name: 'file', iconSize: 46, tint: this.color('foreground-muted') })
            Text(this.fileName()).fontSize(this.font(17)).fontColor(this.color('foreground')).textAlign(TextAlign.Center).maxLines(3)
            Text('保存原文件到手机后，可使用支持此格式的应用打开。').fontSize(this.font(13)).fontColor(this.color('foreground-muted')).textAlign(TextAlign.Center)
            Button(this.saving ? this.downloadStatus() : this.error ? '重新下载' : '下载文件')
              .fontSize(this.font(14)).fontColor(this.color('primary-foreground')).backgroundColor(this.color('primary'))
              .enabled(!this.loading && !this.saving).onClick(() => { this.saveFile(); })
          }.padding(28).layoutWeight(1).width('100%').justifyContent(FlexAlign.Center)
        } else if (this.file !== null) {
          if (this.preview && /\.(md|markdown)$/i.test(this.selectedPath) && this.file.contents) {
            Scroll() {
              MarkdownText({ content: this.file.contents, cwd: this.cwd, environmentId: this.environmentId, threadId: this.threadId,
                baseDir: this.selectedPath.includes('/') ? this.selectedPath.substring(0, this.selectedPath.lastIndexOf('/')) : '' })
            }.layoutWeight(1).width('100%').align(Alignment.TopStart).padding({ left: 16, right: 16 })
              .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
          } else {
            SourceFileText({ contents: this.file.contents, fontSize: this.sizes.codeFontSize, initialLine: this.initialLine,
              wrap: this.sizes.codeWordBreak, foreground: this.color('foreground'), muted: this.color('foreground-muted') })
              .layoutWeight(1).width('100%')
          }
        } else { Blank().layoutWeight(1) }
      } else {
        if (this.searching) {
          Search({ value: this.query, placeholder: '搜索项目文件' }).textFont({ size: this.font(15) }).fontColor(this.color('foreground'))
            .backgroundColor(this.color('input')).placeholderColor(this.color('placeholder')).margin({ left: 16, right: 16, bottom: 8 })
            .onChange((value: string) => { this.query = value; this.refreshRows(); })
        }
        if (this.truncated) { Text('文件列表不完整，部分文件未返回').fontColor(this.color('danger-foreground')).fontSize(this.font(12)).padding(12) }
        if (!this.loading && this.rows.length === 0 && !this.error) {
          Column({ space: 12 }) {
            AppIcon({ name: 'folder', iconSize: 36, tint: this.color('foreground-muted') })
            Text('没有匹配的文件').fontSize(this.font(14)).fontColor(this.color('foreground-muted'))
          }.layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          List() {
            ForEach(this.rows, (entry: FileEntry) => {
              ListItem() {
                Row({ space: 12 }) {
                  AppIcon({ name: entry.kind === 'directory' ? 'folder' : 'file', iconSize: 21,
                    tint: entry.kind === 'directory' ? this.color('primary') : this.color('foreground-muted') })
                  Text(this.query ? entry.path : this.pathName(entry.path)).fontSize(this.font(15)).fontColor(this.color('foreground'))
                    .maxLines(this.query ? 2 : 1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                  if (entry.kind === 'directory') { AppIcon({ name: 'chevron', iconSize: 14, tint: this.color('foreground-muted') }) }
                }.constraintSize({ minHeight: 50 }).padding({ left: 20, right: 20, top: 10, bottom: 10 }).width('100%')
                  .onClick(() => { this.open(entry); }).bindContextMenu(this.fileMenu(entry), ResponseType.LongPress, { modalMode: menuModalMode() })
              }
            }, (entry: FileEntry) => entry.path + ':' + entry.kind)
          }.layoutWeight(1).width('100%')
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        }
      }
    }.width('100%').height('100%').backgroundColor(this.color('screen'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
