import { ChatPageHeader, immersiveMaterial } from './ChatGlass';
import { Typography, resolveTypography, scaledFontSize } from '../model/Typography';
import { ThemeRuntime } from '../connection/ThemeRuntime';
import measure from '@ohos.measure';
import router from '@ohos.router';
import { FrameCallback } from '@ohos.arkui.UIContext';
import { EnvironmentSession } from '../connection/Environment';
import { RpcClient } from '../connection/Rpc';
import { DiffProjection, DiffScope, diffScopes, checkpointRequest, projectionCheckpoints } from '../model/DiffScope';
import { DraftStore } from '../connection/DraftStore';
import { ReviewLine, formatLineComment, appendComment } from '../model/ReviewComment';
import { DiffRow, parseDiffRows } from '../model/DiffRows';
import { DiffDisplayRow, diffDisplayRows, diffAnchorIndex, diffLineText } from '../model/DiffPresentation';
import { DiffDataSource } from './DiffDataSource';
import { AppIcon } from './AppIcon';

interface ThreadRequest { threadId: string; }
interface DiffResult { diff: string; }
interface PreviewRequest { cwd: string; ignoreWhitespace: boolean; sourceKind?: string; }
interface PreviewSource { kind: string; diff: string; truncated: boolean; }
interface PreviewResult { sources: PreviewSource[]; }

class DiffScrollFrame extends FrameCallback {
  private action: () => void;
  constructor(action: () => void) { super(); this.action = action; }
  onFrame(): void { this.action(); }
}

@Entry
@Component
struct DiffPage {
  private font(size: number): number { return scaledFontSize(size, this.sizes.baseFontSize); }
  @StorageLink('textSizes') @Watch('viewChanged') sizes: Typography = resolveTypography(16, null, null);
  @StorageLink('themeKey') @Watch('viewChanged') themeKey: string = 't3-code-light';
  private color(role: string): string { return ThemeRuntime.color(this.themeKey, role); }
  private diffColor(role: string): string { return ThemeRuntime.palette(this.themeKey).diff[role]; }
  @State ready: boolean = false;
  @State errorText: string = '';
  private rpc: RpcClient | null = null;
  private active: boolean = false;
  private dataSource: DiffDataSource = new DiffDataSource();
  private scroller: Scroller = new Scroller();
  private horizontalScroller: Scroller = new Scroller();
  private visibleIndex: number = 0;
  private scrollRevision: number = 0;
  @State viewportWidth: number = 360;
  @State contentWidth: number = 360;
  @State horizontalOffset: number = 0;
  @State scopes: DiffScope[] = [];
  @State selectedId: string = 'all';
  @State loading: boolean = false;
  @State notice: string = '';
  @State collapsedFiles: string[] = [];
  @State viewedFiles: string[] = [];
  @State files: DiffRow[] = [];
  @State split: boolean = false;
  @State wrap: boolean = true;
  @State whitespace: boolean = false;
  @State ignoreWhitespace: boolean = false;
  @State scopeOpen: boolean = false;
  @State filesOpen: boolean = false;
  @State fileQuery: string = '';
  private rows: DiffRow[] = [];
  private initialScope: boolean = true;
  @State commentRow: DiffRow | null = null;
  @State commentText: string = '';
  @State commentPath: string = '';
  @State savingComment: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    this.load();
  }

  private async load(): Promise<void> {
    if (this.loading) return;
    this.loading = true;
    this.errorText = '';
    this.notice = '';
    this.ready = false;
    this.rpc?.close();
    this.rpc = null;
    try {
      const params = router.getParams() as Record<string, string>;
      const environment = EnvironmentSession.current;
      if (environment === null) throw new Error('连接已关闭，请返回重新连接');
      const rpc = await environment.openRpc();
      if (!this.active) { rpc.close(); return; }
      this.rpc = rpc;
      const threadId = params['threadId'] ?? '';
      const subscription: ThreadRequest = { threadId: threadId };
      const projection = await rpc.call<DiffProjection>('orchestration.getThreadProjection', subscription);
      if (!this.active) return;
      this.scopes = diffScopes(projectionCheckpoints(projection));
      if (this.initialScope) {
        const workspaceScope = params['scope'] === 'branch' || params['scope'] === 'workspace' ? params['scope'] : '';
        if (workspaceScope) this.selectedId = workspaceScope;
        const ordinal = workspaceScope ? 0 : Number(params['toTurnCount']) || projection.checkpoints?.find((entry) =>
          entry.runId === params['runId'] && entry.status === 'ready' && entry.appRunOrdinal !== null)?.appRunOrdinal;
        if (ordinal) this.selectedId = `turn:${ordinal}`;
        if ((params['runId'] && !ordinal) || (ordinal && !this.scopes.some((item: DiffScope) => item.id === this.selectedId))) {
          throw new Error('本轮文件快照尚未就绪，可刷新重试或选择其他变更范围');
        }
        if (!ordinal && !params['runId'] && this.selectedId === 'all' && !this.scopes.some((item: DiffScope) => item.id === 'all')) {
          this.selectedId = 'workspace';
        }
      }
      const scope = this.scopes.find((item: DiffScope) => item.id === this.selectedId);
      if (scope === undefined) throw new Error('所选范围的文件快照尚未就绪，请刷新重试');
      this.initialScope = false;
      this.selectedId = scope.id;
      let diff = '';
      if (scope.id === 'workspace' || scope.id === 'branch') {
        const request: PreviewRequest = { cwd: params['cwd'] ?? '', ignoreWhitespace: this.ignoreWhitespace };
        if (scope.id === 'branch') request.sourceKind = 'branch-range';
        const preview = await rpc.call<PreviewResult>('review.getDiffPreview', request);
        const source = preview.sources.find((item: PreviewSource) => item.kind === (scope.id === 'branch' ? 'branch-range' : 'working-tree'));
        diff = source?.diff ?? '';
        if (source?.truncated) this.notice = '变更内容过长，当前显示已截断';
      } else {
        const query = checkpointRequest(threadId, scope.turnCount, scope.id === 'all', this.ignoreWhitespace);
        const result = await rpc.call<DiffResult>(query.method, query.payload);
        diff = result.diff;
      }
      if (!this.active) return;
      const rows = parseDiffRows(diff);
      this.rows = rows;
      this.files = rows.filter((row: DiffRow) => row.kind === 'file');
      this.collapsedFiles = [];
      this.viewedFiles = [];
      this.rebuildRows(true);
      if (rows.length === 0) { this.notice = '此范围没有文件变更'; return; }
      this.ready = true;
    } catch (error) {
      if (this.active) this.errorText = error instanceof Error ? error.message : String(error);
    } finally {
      if (this.active) this.loading = false;
    }
  }

  private async addComment(): Promise<void> {
    const row = this.commentRow;
    const environment = EnvironmentSession.current;
    if (row === null || environment === null || !this.commentText.trim() || this.savingComment) return;
    this.savingComment = true;
    try {
      const params = router.getParams() as Record<string, string>;
      const store = await DraftStore.open(getContext(this).filesDir, environment.descriptor.environmentId, params['threadId']);
      const existing = await store.load();
      const index = this.rows.filter((entry: DiffRow) => entry.fileId === row.fileId && entry.kind === 'line')
        .findIndex((entry: DiffRow) => entry.id === row.id);
      const section = this.scopes.find((item: DiffScope) => item.id === this.selectedId);
      const line: ReviewLine = { change: row.change, content: row.content, oldLineNumber: row.oldLineNumber, newLineNumber: row.newLineNumber };
      const comment = formatLineComment(this.selectedId === 'workspace' ? 'working-tree' : this.selectedId === 'branch' ? 'branch-range' : this.selectedId,
        section?.value ?? 'Diff', this.commentPath, index, line, this.commentText);
      await store.save(appendComment(existing, comment));
      if (this.active) router.back();
    } catch (error) {
      this.errorText = error instanceof Error ? error.message : String(error);
    } finally { this.savingComment = false; }
  }

  aboutToDisappear(): void {
    this.active = false;
    this.rpc?.close();
  }

  private scrollTo(index: number): void {
    const revision = ++this.scrollRevision;
    this.getUIContext().postFrameCallback(new DiffScrollFrame(() => {
      if (!this.active || revision !== this.scrollRevision || !this.ready || this.commentRow !== null) return;
      this.horizontalScroller.scrollTo({ xOffset: 0, yOffset: 0 });
      this.scroller.scrollToIndex(index, false, ScrollAlign.START);
    }));
  }
  private rebuildRows(reset: boolean = false): void {
    const anchor = this.dataSource.getData(this.visibleIndex);
    const rows = diffDisplayRows(this.rows, this.collapsedFiles, this.split);
    let width = this.viewportWidth;
    if (!this.wrap) {
      let codeWidth = 0;
      for (const row of this.rows) {
        if (row.kind !== 'line') continue;
        codeWidth = Math.max(codeWidth, this.getUIContext().px2vp(measure.measureText({
          textContent: diffLineText(row.content, this.whitespace).replace(/\t/g, '    '),
          fontSize: this.sizes.codeFontSize, fontFamily: 'monospace'
        })));
      }
      width = Math.max(width, this.split ? (codeWidth + 58) * 2 : codeWidth + 96);
    }
    this.contentWidth = width;
    this.dataSource.update(rows);
    this.horizontalOffset = 0;
    this.scrollTo(reset || anchor === undefined ? 0 : diffAnchorIndex(rows, anchor.source.id, anchor.fileId));
  }
  private viewChanged(): void { if (this.active) this.rebuildRows(); }
  private toggleFile(id: string): void {
    this.collapsedFiles = this.collapsedFiles.includes(id) ? this.collapsedFiles.filter((entry: string) => entry !== id) : this.collapsedFiles.concat([id]);
    this.rebuildRows();
  }
  private showFile(file: DiffRow): void {
    this.filesOpen = false;
    this.collapsedFiles = this.collapsedFiles.filter((id: string) => id !== file.id);
    this.rebuildRows();
    this.scrollTo(diffAnchorIndex(diffDisplayRows(this.rows, this.collapsedFiles, this.split), file.id, file.id));
  }
  private startComment(row: DiffRow): void {
    this.commentPath = this.files.find((file: DiffRow) => file.id === row.fileId)?.filePath ?? '';
    this.commentRow = row; this.commentText = '';
  }
  private lineBackground(row: DiffRow | undefined): string {
    return this.diffColor(row?.change === 'add' ? 'addBackground' : row?.change === 'delete' ? 'deleteBackground' : 'background');
  }
  private lineColor(row: DiffRow | undefined): string {
    return this.diffColor(row?.change === 'add' ? 'addText' : row?.change === 'delete' ? 'deleteText' : 'mutedText');
  }
  @Builder
  private action(icon: string, label: () => string, selected: () => boolean, callback: () => void) {
    Button({ type: ButtonType.Normal }) { AppIcon({ name: icon, iconSize: 18, tint: this.color(selected() ? 'primary' : 'foreground-muted') }) }
      .id('diff-tool-' + icon).width(40).height(40).padding(0).borderRadius(10).backgroundColor(selected() ? this.color('subtle-strong') : Color.Transparent)
      .enabled(!this.loading && this.commentRow === null).accessibilityText(label()).accessibilitySelected(selected()).onClick(callback)
  }
  @Builder
  private scopePicker() {
    Column() {
      List() {
        ForEach(this.scopes, (scope: DiffScope) => {
          ListItem() {
            Button({ type: ButtonType.Normal }) {
              Row({ space: 10 }) {
                AppIcon({ name: scope.id === 'workspace' ? 'folder' : scope.id === 'branch' ? 'branch' : scope.id === 'all' ? 'diff' : 'clock',
                  iconSize: 17, tint: this.color('foreground-muted') })
                Text(scope.value).fontSize(this.font(14)).fontColor(this.color('foreground')).layoutWeight(1).maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis }).textAlign(TextAlign.Start)
                if (scope.id === this.selectedId) { AppIcon({ name: 'check', iconSize: 16, tint: this.color('primary') }) }
              }.width('100%')
            }.width('100%').height(44).padding({ left: 8, right: 10 }).borderRadius(10).backgroundColor(Color.Transparent).onClick(() => {
              this.scopeOpen = false;
              if (scope.id !== this.selectedId) { this.selectedId = scope.id; this.initialScope = false; this.load(); }
            })
          }
        }, (scope: DiffScope) => scope.id)
      }.id('diff-scope-list').width('100%').height(Math.min(this.scopes.length, 7) * 44)
        .scrollBar(this.scopes.length > 7 ? BarState.Auto : BarState.Off).scrollBarWidth(2)
        .scrollBarColor('#55' + this.color('foreground-muted').slice(1))
    }.width(Math.min(264, this.viewportWidth - 32)).padding(8)
  }
  @Builder
  private filesSheet() {
    Column({ space: 12 }) {
      Search({ value: this.fileQuery, placeholder: '搜索变更文件' }).textFont({ size: this.font(16) })
        .fontColor(this.color('foreground')).backgroundColor(this.color('input')).onChange((value: string) => { this.fileQuery = value; })
      List({ space: 2 }) {
        ForEach(this.files.filter((file: DiffRow) => (file.filePath ?? '').toLowerCase().includes(this.fileQuery.toLowerCase())), (file: DiffRow) => {
          ListItem() {
            Button({ type: ButtonType.Normal }) {
              Row({ space: 10 }) {
                AppIcon({ name: 'file', iconSize: 18, tint: this.color('foreground-muted') })
                Text(file.filePath ?? '').fontSize(this.font(14)).fontColor(this.color('foreground')).layoutWeight(1).maxLines(2).textAlign(TextAlign.Start)
                Text(`+${file.additions ?? 0}`).fontSize(this.font(12)).fontColor(this.diffColor('addText'))
                Text(`−${file.deletions ?? 0}`).fontSize(this.font(12)).fontColor(this.diffColor('deleteText'))
              }.width('100%')
            }.width('100%').constraintSize({ minHeight: 52 }).padding(12).backgroundColor(Color.Transparent).onClick(() => { this.showFile(file); })
          }
        }, (file: DiffRow) => file.id)
      }.layoutWeight(1).width('100%').scrollBar(BarState.Auto).scrollBarWidth(2)
    }.padding(16).height('100%').width('100%')
  }
  @Builder
  private fileHeader(file: DiffRow) {
    Row({ space: 4 }) {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 8 }) {
          AppIcon({ name: this.collapsedFiles.includes(file.id) ? 'chevron' : 'down', iconSize: 14, tint: this.diffColor('mutedText') })
          AppIcon({ name: 'file', iconSize: 16, tint: this.color('primary') })
          Text(file.filePath ?? '').fontSize(this.font(13)).fontColor(this.diffColor('text')).layoutWeight(1).maxLines(2).textAlign(TextAlign.Start)
        }.width('100%')
      }.layoutWeight(1).constraintSize({ minHeight: 44 }).padding({ left: 10, right: 4 }).backgroundColor(Color.Transparent)
        .accessibilityText(`${this.collapsedFiles.includes(file.id) ? '展开' : '折叠'} ${file.filePath ?? ''}`).onClick(() => { this.toggleFile(file.id); })
      Text(`+${file.additions ?? 0}`).fontSize(this.font(11)).fontColor(this.diffColor('addText'))
      Text(`−${file.deletions ?? 0}`).fontSize(this.font(11)).fontColor(this.diffColor('deleteText'))
      Button({ type: ButtonType.Circle }) {
        AppIcon({ name: this.viewedFiles.includes(file.id) ? 'check-all' : 'check', iconSize: 17,
          tint: this.color(this.viewedFiles.includes(file.id) ? 'primary' : 'foreground-muted') })
      }.width(40).height(44).padding(0).backgroundColor(Color.Transparent).accessibilityText(`${this.viewedFiles.includes(file.id) ? '取消已查看' : '标记已查看'} ${file.filePath ?? ''}`)
        .onClick(() => { this.viewedFiles = this.viewedFiles.includes(file.id) ? this.viewedFiles.filter((id: string) => id !== file.id) : this.viewedFiles.concat([file.id]); this.rebuildRows(); })
    }.width(this.viewportWidth).backgroundColor(this.diffColor('headerBackground')).border({ width: { bottom: 0.5 }, color: this.diffColor('border') })
      .translate({ x: this.horizontalOffset })
  }
  @Builder
  private codeCell(row: DiffRow | undefined, side: string) {
    Row({ space: 0 }) {
      Text(row === undefined ? '' : `${side === 'right' ? row.newLineNumber ?? '' : row.oldLineNumber ?? ''}`)
        .fontFamily('monospace').fontSize(Math.max(8, this.sizes.codeFontSize - 1)).fontColor(this.lineColor(row))
        .width(34).textAlign(TextAlign.End).padding({ right: 5, top: 3 })
      if (!this.split) {
        Text(row?.newLineNumber === undefined ? '' : `${row.newLineNumber}`).fontFamily('monospace')
          .fontSize(Math.max(8, this.sizes.codeFontSize - 1)).fontColor(this.lineColor(row)).width(34).textAlign(TextAlign.End).padding({ right: 5, top: 3 })
      }
      Text(row?.change === 'add' ? '+' : row?.change === 'delete' ? '−' : ' ').fontFamily('monospace')
        .fontSize(this.sizes.codeFontSize).fontColor(this.lineColor(row)).width(14).padding({ top: 2 })
      Text(diffLineText(row?.content, this.whitespace).replace(/\t/g, '    ') || ' ')
        .fontFamily('monospace').fontSize(this.sizes.codeFontSize).lineHeight(this.sizes.codeFontSize + 7)
        .fontColor(this.diffColor('text')).wordBreak(WordBreak.BREAK_ALL).layoutWeight(1).padding({ top: 2, bottom: 2, right: 6 })
    }.width(this.split ? this.contentWidth / 2 : this.contentWidth).alignItems(VerticalAlign.Top)
      .backgroundColor(this.lineBackground(row)).border({ width: { left: 2 }, color: row?.change === 'add' ? this.diffColor('addBar') : row?.change === 'delete' ? this.diffColor('deleteBar') : Color.Transparent })
      .gesture(LongPressGesture().onAction(() => { if (row !== undefined) this.startComment(row); }))
  }
  @Builder
  private diffList() {
    Scroll(this.horizontalScroller) {
      List({ scroller: this.scroller }) {
        LazyForEach(this.dataSource, (row: DiffDisplayRow) => {
          ListItem() {
            if (row.kind === 'file') { this.fileHeader(row.source) }
            else if (row.kind === 'line') {
              if (this.split) {
                Flex({ direction: FlexDirection.Row, alignItems: ItemAlign.Stretch }) { this.codeCell(row.left, 'left'); this.codeCell(row.right, 'right') }
                  .width(this.contentWidth)
              } else { this.codeCell(row.source, 'left') }
            } else {
              Text(row.source.text ?? '').fontFamily('monospace').fontSize(Math.max(10, this.sizes.codeFontSize - 1))
                .fontColor(this.diffColor('hunkText')).padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .width(this.viewportWidth).backgroundColor(this.diffColor('hunkBackground')).translate({ x: this.horizontalOffset })
            }
          }
        }, (row: DiffDisplayRow) => this.dataSource.key(row))
      }.width(this.contentWidth).height('100%').cachedCount(8).scrollBar(BarState.Auto).scrollBarWidth(2)
        .scrollBarColor('#66' + this.color('foreground-muted').slice(1)).onScrollIndex((index: number) => { this.visibleIndex = index; })
    }.scrollable(ScrollDirection.Horizontal).width('100%').layoutWeight(1).align(Alignment.TopStart)
      .scrollBar(BarState.Auto).scrollBarWidth(2).onScroll((offset: number) => { this.horizontalOffset = offset; })
      .onAreaChange((_old: Area, area: Area) => { const width = Number(area.width); if (width > 0 && Math.abs(width - this.viewportWidth) > 1) { this.viewportWidth = width; this.rebuildRows(); } })
  }

  build() {
    Column({ space: 0 }) {
      ChatPageHeader() {
        Column({ space: 2 }) {
          Row({ space: 6 }) {
            Button({ type: ButtonType.Circle }) { AppIcon({ name: 'back', iconSize: 21, tint: this.color('glass-label') }) }
              .width(38).height(38).padding(0).backgroundColor(Color.Transparent).accessibilityText('返回聊天').onClick(() => { router.back(); })
            Text('文件变更').fontColor(this.color('foreground')).fontSize(this.font(17)).fontWeight(FontWeight.Medium).layoutWeight(1)
            Button({ type: ButtonType.Circle }) { AppIcon({ name: 'refresh', iconSize: 19, tint: this.color('glass-label') }) }
              .width(38).height(38).padding(0).backgroundColor(Color.Transparent).enabled(!this.loading && this.commentRow === null)
              .accessibilityText('刷新文件变更').onClick(() => { this.load(); })
          }.width('100%').padding({ left: 6, right: 6 })
          Row({ space: 6 }) {
            Button({ type: ButtonType.Normal }) {
              Row({ space: 4 }) {
                Text(this.scopes.find((scope: DiffScope) => scope.id === this.selectedId)?.value ?? '选择变更范围')
                  .fontSize(this.font(13)).fontColor(this.color('foreground')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).flexShrink(1)
                AppIcon({ name: 'down', iconSize: 11, tint: this.color('glass-label') })
              }
            }.id('diff-scope').height(32).padding({ left: 10, right: 8 }).borderRadius(10).backgroundColor(this.color('subtle')).flexShrink(1)
              .enabled(!this.loading && this.commentRow === null).accessibilityText('选择变更轮次').onClick(() => { this.scopeOpen = true; })
              .bindPopup(this.scopeOpen, { builder: this.scopePicker(), placement: Placement.BottomLeft, enableArrow: false,
                systemMaterial: immersiveMaterial('popup'), radius: 16,
                onStateChange: (event: PopupStateChangeParam) => { this.scopeOpen = event.isVisible; } })
            Blank().layoutWeight(1)
            if (this.ready) {
              Text(`+${this.files.reduce((sum: number, file: DiffRow) => sum + (file.additions ?? 0), 0)}`).fontSize(this.font(12)).fontColor(this.diffColor('addText')).maxLines(1)
              Text(`−${this.files.reduce((sum: number, file: DiffRow) => sum + (file.deletions ?? 0), 0)}`).fontSize(this.font(12)).fontColor(this.diffColor('deleteText')).maxLines(1)
            }
            Button({ type: ButtonType.Normal }) {
              Row({ space: 4 }) {
                AppIcon({ name: 'folder', iconSize: 15, tint: this.color('glass-label') })
                Text(`${this.ready ? this.files.length : 0}`).fontSize(this.font(12)).fontColor(this.color('glass-label')).maxLines(1)
              }
            }.id('diff-files').height(32).padding({ left: 6, right: 6 }).borderRadius(9).backgroundColor(Color.Transparent)
              .enabled(!this.loading && this.ready && this.commentRow === null).accessibilityText('浏览和定位变更文件')
              .onClick(() => { this.fileQuery = ''; this.filesOpen = true; })
              .bindSheet($$this.filesOpen, this.filesSheet(), { systemMaterial: immersiveMaterial('popup'), height: SheetSize.LARGE,
                title: { title: '变更文件' }, dragBar: true, showClose: true })
          }.width('100%').padding({ left: 12, right: 10 })
        }.width('100%').padding({ top: 3, bottom: 6 })
      }
      Row({ space: 3 }) {
        this.action('unified', () => '统一对比', () => !this.split, () => { this.split = false; this.rebuildRows(); })
        this.action('split', () => '左右对比', () => this.split, () => { this.split = true; this.rebuildRows(); })
        Divider().vertical(true).height(20).color(this.color('border')).margin({ left: 3, right: 3 })
        this.action('wrap', () => this.wrap ? '关闭自动换行' : '开启自动换行', () => this.wrap, () => { this.wrap = !this.wrap; this.rebuildRows(); })
        this.action('paragraph', () => this.whitespace ? '隐藏空白字符' : '显示空白字符', () => this.whitespace, () => { this.whitespace = !this.whitespace; this.rebuildRows(); })
        this.action('ignore-space', () => this.ignoreWhitespace ? '包含空白差异' : '忽略空白差异', () => this.ignoreWhitespace, () => { this.ignoreWhitespace = !this.ignoreWhitespace; this.load(); })
        Blank()
        this.action('fold', () => this.files.length > 0 && this.collapsedFiles.length === this.files.length ? '展开全部文件' : '折叠全部文件', () => this.collapsedFiles.length > 0,
          () => { this.collapsedFiles = this.collapsedFiles.length === this.files.length ? [] : this.files.map((file: DiffRow) => file.id); this.rebuildRows(); })
      }.width('100%').padding({ left: 16, right: 16, top: 6, bottom: 6 }).border({ width: { bottom: 0.5 }, color: this.color('border') })
      if (this.commentRow !== null) {
        Column({ space: 12 }) {
        Text(`${this.commentPath} · ${this.commentRow.newLineNumber ?? this.commentRow.oldLineNumber}`)
          .fontColor(this.color('foreground')).fontSize(this.font(14))
        Text(this.commentRow.content ?? '').fontColor(this.color('foreground-muted')).fontFamily('monospace').maxLines(4)
        TextArea({ text: this.commentText, placeholder: '输入对此行的评论' }).fontSize(this.font(16)).fontColor(this.color('foreground')).backgroundColor(this.color('input')).placeholderColor(this.color('placeholder'))
          .onChange((value: string) => { this.commentText = value; }).height(140)
        Row({ space: 12 }) {
          Button('取消评论').fontSize(this.font(16)).fontColor(this.color('primary-foreground')).backgroundColor(this.color('primary')).enabled(!this.savingComment).onClick(() => { this.commentRow = null; this.commentText = ''; this.rebuildRows(); })
          Button('加入任务草稿').fontSize(this.font(16)).fontColor(this.color('primary-foreground')).backgroundColor(this.color('primary')).enabled(!this.savingComment && this.commentText.trim().length > 0)
            .onClick(() => { this.addComment(); })
        }
        }.width('100%').padding(16)
      }
      if (this.loading) { Text('正在加载变更…').fontColor(this.color('foreground-muted')).fontSize(this.font(13)).padding(24) }
      if (this.notice.length > 0) { Text(this.notice).fontColor(this.color('foreground-muted')).fontSize(this.font(13)).padding(16) }
      if (this.errorText.length > 0) {
        Text(this.errorText).fontSize(this.font(13)).fontColor(this.color('danger-foreground')).padding(16)
      } else if (this.ready && this.commentRow === null) {
        this.diffList()
        Text('长按代码行添加评论').fontSize(this.font(10)).fontColor(this.color('foreground-muted')).padding(5)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.color('screen'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
