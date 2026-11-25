import { ChatGlass, immersiveMaterial } from './ChatGlass';
import { Typography, resolveTypography, scaledFontSize } from '../model/Typography';
import { ThemeRuntime } from '../connection/ThemeRuntime';
import router from '@ohos.router';
import { KeyboardAvoidMode } from '@ohos.arkui.UIContext';
import picker from '@ohos.file.picker';
import util from '@ohos.util';
import fs from '@ohos.file.fs';
import photoAccessHelper from '@ohos.file.photoAccessHelper';
import fileUri from '@ohos.file.fileuri';
import { EnvironmentSession } from '../connection/Environment';
import { RpcClient, EmptyPayload, RpcRemoteError } from '../connection/Rpc';
import { ChatAttachment, ServerConfig, WS } from '../model/Models';
import { fileUploadLimit } from '../model/FileAttachments';
import { AttachmentDraftStore, DraftImage } from '../connection/AttachmentDraftStore';
import { uploadImage, deleteImageUpload } from '../connection/ImageAttachment';
import { PreviewImage, previewGallery, imageStep } from '../model/ImageGallery';
import { ImageEditDocument, ImageStroke, ImagePoint, ImageRect, emptyImageEdits, copyStrokes, ImageCommentDraft, ImageRatio, imageRatios, ImageNote, imageNoteText, imageShapePoints, imageStrokeAt, imageStrokeBounds, moveImageStroke, resizeImageStroke } from '../model/ImageEdits';
import { ImageAssets } from '../connection/ImageAssets';
import { ImageEditor } from '../connection/ImageEditor';
import { AppIcon } from './AppIcon';
import { ComposerEditor } from './ComposerEditor';
import { ComposerActions } from './ComposerActions';
import { DraftImages, DraftImageProgress } from './DraftImages';

const TOOLBAR_INSET = 5;
const COMPACT_TOOL_HEIGHT = 44;
const PREVIEW_TOOL_HEIGHT = 54;
const PREVIEW_BAR_GAP = 12;

interface ImageComposerDraft { id: string; explanation: string; store: AttachmentDraftStore | null; images: DraftImageProgress[]; }
interface ImageToolChoice { name: string; label: string; }

@Entry
@Component
struct ImagePreviewPage {
  private font(size: number): number { return scaledFontSize(size, this.sizes.baseFontSize); }
  @StorageLink('textSizes') sizes: Typography = resolveTypography(16, null, null);
  @State gallery: PreviewImage[] = [];
  @State gallerySources: string[] = [];
  @State imageIndex: number = 0;
  @State name: string = '';
  @State source: string = '';
  @State error: string = '';
  @State loading: boolean = false;
  @State busy: boolean = false;
  @State zoom: number = 1;
  @State offsetX: number = 0;
  @State offsetY: number = 0;
  @State viewportWidth: number = 1;
  @State viewportHeight: number = 1;
  @State aspect: number = 1;
  @State annotating: boolean = false;
  @State erasing: boolean = false;
  @State penColor: string = '#EF4444';
  @State penWidth: number = 3;
  @State eraseWidth: number = 28;
  @State markEraserWidth: number = 18;
  @State markTool: string = 'pen';
  @State toolMenu: string = '';
  @State selectedMark: number = -1;
  @State textSize: number = 24;
  private textIndex: number = -1;
  private gestureStart: ImagePoint | null = null;
  private selectionSource: ImageStroke | null = null;
  private resizeCorner: number = -1;
  private gestureChanged: boolean = false;
  @State editRevision: number = 0;
  @State panel: string = '';
  @State comment: string = '';
  @State commenting: boolean = false;
  @State noteIndex: number = -1;
  @State explanation: string = '';
  @State extraImages: DraftImageProgress[] = [];
  @State extrasBusy: boolean = false;
  @State maxFileBytes: number = 0;
  @StorageLink('themeKey') themeKey: string = 't3-code-light';
  private extraStore: AttachmentDraftStore | null = null;
  private extraDraftId: string = '';
  private imageDrafts: Map<number, ImageComposerDraft> = new Map();
  private extraRpc: RpcClient | null = null;
  private extraConnection: Promise<RpcClient> | null = null;
  private handedOff: boolean = false;
  @State headerY: number = 0;
  private headerStartY: number = 0;
  private toolbarRoom: number = 0;
  @State controlsX: number = 0;
  @State controlsY: number = 0;
  private controlsWidth: number = 0;
  private controlsStartX: number = 0;
  private controlsStartY: number = 0;
  private noteX: number = 0;
  private noteY: number = 0;
  @State imageReady: boolean = false;
  private swiper: SwiperController = new SwiperController();
  private startZoom: number = 1;
  private startX: number = 0;
  private startY: number = 0;
  private panningZoomed: boolean = false;
  private documents: Map<string, ImageEditDocument> = new Map();
  private stroke: ImageStroke | null = null;
  private canvas: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private active: boolean = false;
  private revision: number = 0;
  private commentThreadId: string = '';
  private environmentId: string = '';
  private draftScope: string = '';
  private previousKeyboardAvoidMode: KeyboardAvoidMode | null = null;

  aboutToAppear(): void {
    this.active = true;
    const params = router.getParams() as Record<string, string>, selection = previewGallery(params);
    this.gallery = selection.images; this.imageIndex = selection.index;
    this.gallerySources = selection.images.map((): string => '');
    this.commentThreadId = params['commentThreadId'] ?? ''; this.environmentId = params['environmentId'] ?? '';
    this.draftScope = params['draftScope'] ?? '';
    this.extraDraftId = util.generateRandomUUID(true);
    this.reload();
  }
  onPageShow(): void {
    if (this.previousKeyboardAvoidMode === null) this.previousKeyboardAvoidMode = this.getUIContext().getKeyboardAvoidMode();
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    ThemeRuntime.setImagePreview(true);
  }
  onPageHide(): void { this.restoreKeyboardAvoidMode(); ThemeRuntime.setImagePreview(false); }
  aboutToDisappear(): void {
    this.restoreKeyboardAvoidMode(); this.active = false; this.revision++;
    if (!this.handedOff) this.discardExtras(this.extraStore).catch(() => {});
    this.imageDrafts.forEach((draft: ImageComposerDraft) => { this.discardExtras(draft.store).catch(() => {}); });
    this.imageDrafts.clear();
  }
  private restoreKeyboardAvoidMode(): void {
    if (this.previousKeyboardAvoidMode === null) return;
    this.getUIContext().setKeyboardAvoidMode(this.previousKeyboardAvoidMode);
    this.previousKeyboardAvoidMode = null;
  }
  onBackPress(): boolean {
    if (this.busy || this.extrasBusy) return true;
    if (this.panel) { this.panel = ''; return true; }
    if (this.annotating) { this.finishAnnotation(); return true; }
    if (this.commenting) { this.commenting = false; return true; }
    return false;
  }
  private edits(): ImageEditDocument {
    const key = JSON.stringify(this.gallery[this.imageIndex]);
    let value = this.documents.get(key);
    if (!value) { value = emptyImageEdits(); this.documents.set(key, value); }
    return value;
  }
  private async reload(refresh: boolean = false): Promise<void> {
    const revision = ++this.revision, index = this.imageIndex;
    this.loading = true; this.error = ''; this.source = ''; this.imageReady = false; this.aspect = 1; this.resetZoom(); this.stroke = null;
    try {
      const selected = this.gallery[index];
      this.name = selected.name;
      const filesDir = getContext(this).filesDir;
      let source = '';
      if (selected.localUri) {
        if (!selected.localUri.startsWith(filesDir + '/draft-images/') || selected.localUri.includes('/../')) throw new Error('本地图片路径无效');
        source = `file://${selected.localUri}`;
      } else {
        const id = selected.mediaPath ? ImageAssets.mediaId(selected.mediaThreadId ?? '', selected.mediaPath) : selected.attachmentId ?? '';
        if (!refresh) source = await ImageAssets.cached(filesDir, this.environmentId, id);
        if (!source) {
          if (!this.active || revision !== this.revision) return;
          const environment = EnvironmentSession.current;
          if (environment === null) throw new Error('连接已关闭，请重新连接');
          if (this.environmentId && this.environmentId !== environment.descriptor.environmentId) throw new Error('请切回图片所在的环境');
          const rpc = environment.rpc;
          const attachment: ChatAttachment = { type: 'image', id: selected.attachmentId ?? '', name: selected.name, mimeType: selected.mimeType ?? 'image/jpeg', sizeBytes: 0 };
          source = selected.mediaPath ? await ImageAssets.mediaSource(rpc, environment.descriptor.environmentId, environment.httpBaseUrl,
            selected.mediaThreadId ?? '', selected.mediaPath, refresh, filesDir) :
            await ImageAssets.source(rpc, environment.descriptor.environmentId, environment.httpBaseUrl, attachment, refresh, filesDir);
          if (EnvironmentSession.current !== environment) throw new Error('图片所在环境已切换');
        }
      }
      if (this.active && revision === this.revision) {
        const doc = this.edits();
        if (doc.width && doc.height) this.aspect = doc.width / doc.height;
        this.source = source;
        const sources = this.gallerySources.slice(); sources[index] = source; this.gallerySources = sources;
        this.warmNeighbors(index).catch(() => {});
      }
    } catch (error) { if (this.active && revision === this.revision) this.error = error instanceof Error ? error.message : String(error); }
    finally { if (this.active && revision === this.revision) this.loading = false; }
  }
  private async warmNeighbors(index: number): Promise<void> {
    for (const neighbor of [index - 1, index + 1]) {
      const image = this.gallery[neighbor];
      if (!image || this.gallerySources[neighbor]) continue;
      const source = image.localUri ? `file://${image.localUri}` : await ImageAssets.cached(getContext(this).filesDir, this.environmentId,
        image.mediaPath ? ImageAssets.mediaId(image.mediaThreadId ?? '', image.mediaPath) : image.attachmentId ?? '');
      if (!this.active) return;
      if (source) { const sources = this.gallerySources.slice(); sources[neighbor] = source; this.gallerySources = sources; }
    }
  }
  private moveImage(delta: number): void {
    if (this.busy || this.extrasBusy || this.panel || this.annotating) return;
    const next = imageStep(this.imageIndex, this.gallery.length, delta);
    if (next !== this.imageIndex) this.swiper.changeIndex(next, true);
  }
  private selectImage(index: number): void {
    if (!this.active || index === this.imageIndex) return;
    if (this.busy || this.extrasBusy) { this.swiper.changeIndex(this.imageIndex, false); return; }
    this.imageDrafts.set(this.imageIndex, { id: this.extraDraftId, explanation: this.explanation, store: this.extraStore, images: this.extraImages });
    const draft = this.imageDrafts.get(index);
    this.imageDrafts.delete(index);
    this.extraDraftId = draft?.id ?? util.generateRandomUUID(true);
    this.explanation = draft?.explanation ?? ''; this.extraStore = draft?.store ?? null; this.extraImages = draft?.images ?? [];
    this.imageIndex = index; this.reload();
  }
  private resetZoom(): void { this.zoom = 1; this.offsetX = 0; this.offsetY = 0; }
  private toolbarTravel(): number {
    return Math.max(0, this.toolbarRoom - PREVIEW_BAR_GAP);
  }
  private moveHeader(y: number): void {
    this.headerY = Math.max(0, Math.min(y, this.toolbarTravel() + this.controlsY));
  }
  private moveControls(x: number, y: number): void {
    const maxX = Math.max(0, (this.viewportWidth - this.controlsWidth) / 2 - 12);
    const minY = Math.min(0, this.headerY - this.toolbarTravel());
    this.controlsX = Math.max(-maxX, Math.min(maxX, x));
    this.controlsY = Math.max(minY, Math.min(0, y));
  }
  private fitToolbars(): void {
    this.moveHeader(this.headerY);
    this.moveControls(this.controlsX, this.controlsY);
  }
  private imageWidth(): number { return Math.min(this.viewportWidth, this.viewportHeight * this.aspect); }
  private imageHeight(): number { return this.imageWidth() / this.aspect; }
  private pan(x: number, y: number): void {
    const maxX = Math.max(0, (this.imageWidth() * this.zoom - this.viewportWidth) / 2), maxY = Math.max(0, (this.imageHeight() * this.zoom - this.viewportHeight) / 2);
    this.offsetX = Math.max(-maxX, Math.min(maxX, x)); this.offsetY = Math.max(-maxY, Math.min(maxY, y));
  }
  private paint(): void {
    this.canvas.clearRect(0, 0, this.canvas.width, this.canvas.height);
    this.paintStrokes(this.edits().strokes);
    if (this.erasing && this.annotating) this.paintStrokes(this.edits().masks);
    const selected = this.edits().strokes[this.selectedMark];
    if (selected && this.annotating && !this.erasing && this.markTool === 'select') {
      const rect = imageStrokeBounds(selected), x = rect.left * this.canvas.width, y = rect.top * this.canvas.height;
      this.canvas.strokeStyle = '#60A5FA'; this.canvas.lineWidth = 1; this.canvas.setLineDash([4, 3]);
      this.canvas.strokeRect(x, y, (rect.right - rect.left) * this.canvas.width, (rect.bottom - rect.top) * this.canvas.height); this.canvas.setLineDash([]);
      this.canvas.fillStyle = '#FFFFFF';
      for (const corner of this.corners(rect)) this.canvas.fillRect(corner.x * this.canvas.width - 4, corner.y * this.canvas.height - 4, 8, 8);
    }
  }
  private paintStrokes(strokes: ImageStroke[]): void {
    for (const stroke of strokes) {
      if (stroke.points.length === 0) continue;
      if (stroke.kind === 'text') {
        const size = (stroke.fontSize ?? 0.05) * this.canvas.height;
        this.canvas.font = `${size}px sans-serif`; this.canvas.fillStyle = stroke.color;
        const lines = (stroke.text ?? '').split('\n');
        for (let n = 0; n < lines.length; n++) this.canvas.fillText(lines[n], stroke.points[0].x * this.canvas.width, stroke.points[0].y * this.canvas.height + size * (1 + n * 1.2));
        continue;
      }
      this.canvas.strokeStyle = stroke.color; this.canvas.lineCap = 'round'; this.canvas.lineJoin = 'round';
      this.canvas.lineWidth = stroke.width * Math.min(this.canvas.width, this.canvas.height);
      this.canvas.beginPath(); this.canvas.moveTo(stroke.points[0].x * this.canvas.width, stroke.points[0].y * this.canvas.height);
      if (stroke.points.length === 1) this.canvas.lineTo(stroke.points[0].x * this.canvas.width + 0.01, stroke.points[0].y * this.canvas.height + 0.01);
      for (let n = 1; n < stroke.points.length; n++) this.canvas.lineTo(stroke.points[n].x * this.canvas.width, stroke.points[n].y * this.canvas.height);
      this.canvas.stroke();
    }
  }
  private draw(event: TouchEvent): void {
    if (this.commenting && !this.busy && !this.panel && event.type === TouchType.Down) {
      const touch = event.touches[0];
      if (touch) { event.stopPropagation(); this.beginNote(Math.max(0, Math.min(1, touch.x / this.imageWidth())), Math.max(0, Math.min(1, touch.y / this.imageHeight()))); }
      return;
    }
    if (!this.annotating || this.busy || this.panel) return;
    event.stopPropagation();
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.stroke = null; this.gestureStart = null; this.selectionSource = null; return; }
    const touch = event.touches[0]; if (!touch) return;
    const point: ImagePoint = { x: Math.max(0, Math.min(1, touch.x / this.imageWidth())), y: Math.max(0, Math.min(1, touch.y / this.imageHeight())) };
    const doc = this.edits();
    if (event.type === TouchType.Down) {
      this.gestureChanged = false; this.gestureStart = point;
      if (!this.erasing && this.markTool === 'select') { this.selectMark(point); return; }
      if (!this.erasing && this.markTool === 'text') {
        const index = imageStrokeAt(doc.strokes, point, 0.02);
        this.textIndex = index >= 0 && doc.strokes[index].kind === 'text' ? index : -1;
        this.noteX = point.x; this.noteY = point.y; this.comment = this.textIndex >= 0 ? doc.strokes[this.textIndex].text ?? '' : ''; this.panel = 'text'; return;
      }
      if (this.erasing || this.markTool !== 'eraser') {
        this.snapshot();
        this.stroke = { color: this.erasing ? '#803B82F6' : this.penColor, width: this.brushWidth() / Math.min(this.imageWidth(), this.imageHeight()), points: [] };
        (this.erasing ? doc.masks : doc.strokes).push(this.stroke); this.editRevision++;
      }
    }
    if (!this.erasing && this.markTool === 'select') this.transformMark(point);
    else if (!this.erasing && this.markTool === 'eraser') {
      const hit = imageStrokeAt(doc.strokes, point, this.markEraserWidth / Math.min(this.imageWidth(), this.imageHeight()) / 2);
      if (hit >= 0) { if (!this.gestureChanged) this.snapshot(); this.gestureChanged = true; doc.strokes.splice(hit, 1); this.selectedMark = -1; this.editRevision++; }
    } else if (this.stroke) {
      if (!this.erasing && this.markTool !== 'pen' && this.gestureStart) this.stroke.points = imageShapePoints(this.markTool, this.gestureStart, point);
      else this.stroke.points.push(point);
    }
    this.paint();
  }
  private snapshot(): void {
    const doc = this.edits(), history = this.erasing ? doc.maskHistory : doc.history;
    history.push(copyStrokes(this.erasing ? doc.masks : doc.strokes)); if (history.length > 50) history.shift();
    if (this.erasing) doc.maskFuture = []; else doc.future = [];
  }
  private corners(rect: ImageRect): ImagePoint[] {
    return [{ x: rect.left, y: rect.top }, { x: rect.right, y: rect.top }, { x: rect.right, y: rect.bottom }, { x: rect.left, y: rect.bottom }];
  }
  private selectMark(point: ImagePoint): void {
    const selected = this.edits().strokes[this.selectedMark]; this.resizeCorner = -1;
    if (selected) this.resizeCorner = this.corners(imageStrokeBounds(selected)).findIndex((corner: ImagePoint): boolean =>
      Math.abs(corner.x - point.x) * this.imageWidth() < 14 && Math.abs(corner.y - point.y) * this.imageHeight() < 14);
    if (this.resizeCorner < 0) this.selectedMark = imageStrokeAt(this.edits().strokes, point, 12 / Math.min(this.imageWidth(), this.imageHeight()));
    this.selectionSource = this.selectedMark >= 0 ? copyStrokes([this.edits().strokes[this.selectedMark]])[0] : null; this.paint();
  }
  private transformMark(point: ImagePoint): void {
    if (!this.selectionSource || !this.gestureStart || this.selectedMark < 0) return;
    const dx = point.x - this.gestureStart.x, dy = point.y - this.gestureStart.y;
    if (!dx && !dy) return;
    if (!this.gestureChanged) this.snapshot(); this.gestureChanged = true;
    let stroke: ImageStroke;
    if (this.resizeCorner < 0) stroke = moveImageStroke(this.selectionSource, dx, dy);
    else {
      const rect = imageStrokeBounds(this.selectionSource);
      if (this.resizeCorner === 0 || this.resizeCorner === 3) rect.left = Math.max(0, Math.min(rect.right - 0.01, rect.left + dx));
      else rect.right = Math.min(1, Math.max(rect.left + 0.01, rect.right + dx));
      if (this.resizeCorner < 2) rect.top = Math.max(0, Math.min(rect.bottom - 0.01, rect.top + dy));
      else rect.bottom = Math.min(1, Math.max(rect.top + 0.01, rect.bottom + dy));
      stroke = resizeImageStroke(this.selectionSource, rect);
    }
    this.edits().strokes[this.selectedMark] = stroke; this.editRevision++;
  }
  private saveText(): void {
    if (!this.comment.trim()) return;
    this.snapshot();
    const previous = this.edits().strokes[this.textIndex], fontSize = previous?.fontSize ?? this.textSize / this.imageHeight();
    this.canvas.font = `${fontSize * this.imageHeight()}px sans-serif`;
    const text = this.comment.trim(), width = Math.max(...text.split('\n').map((line: string): number => this.canvas.measureText(line).width)) / this.imageWidth();
    const stroke: ImageStroke = { kind: 'text', text: text, color: this.penColor, width: 0, fontSize: fontSize, textWidth: width,
      points: previous?.points ?? [{ x: this.noteX, y: this.noteY }] };
    if (this.textIndex >= 0) this.edits().strokes[this.textIndex] = stroke; else this.edits().strokes.push(stroke);
    this.editRevision++; this.panel = ''; this.comment = ''; this.paint();
  }
  private brushWidth(): number { return this.erasing ? this.eraseWidth : this.markTool === 'eraser' ? this.markEraserWidth : this.penWidth; }
  private setBrushWidth(value: number): void {
    value = Math.round(Math.max(this.erasing ? 4 : 1, Math.min(this.erasing || this.markTool === 'eraser' ? 80 : 24, value)));
    if (this.erasing) this.eraseWidth = value; else if (this.markTool === 'eraser') this.markEraserWidth = value; else this.penWidth = value;
  }
  private chooseTool(tool: string): void { this.markTool = tool; this.selectedMark = -1; this.toolMenu = ''; this.paint(); }
  private shapes(): ImageToolChoice[] {
    return [{ name: 'line', label: '直线' }, { name: 'arrow', label: '箭头' }, { name: 'rectangle', label: '矩形' }, { name: 'ellipse', label: '椭圆' },
      { name: 'triangle', label: '三角形' }, { name: 'diamond', label: '菱形' }, { name: 'star', label: '星形' }, { name: 'heart', label: '心形' }];
  }
  private undo(redo: boolean = false): void {
    const doc = this.edits(), history = this.erasing ? doc.maskHistory : doc.history, future = this.erasing ? doc.maskFuture : doc.future;
    const from = redo ? future : history, to = redo ? history : future, strokes = from.pop();
    if (strokes) {
      to.push(copyStrokes(this.erasing ? doc.masks : doc.strokes));
      if (this.erasing) doc.masks = strokes; else doc.strokes = strokes;
      this.stroke = null; this.selectedMark = -1; this.editRevision++; this.paint();
    }
  }
  private canUndo(redo: boolean): boolean {
    const doc = this.edits();
    return this.editRevision >= 0 && (this.erasing ? redo ? doc.maskFuture : doc.maskHistory : redo ? doc.future : doc.history).length > 0;
  }
  private finishAnnotation(): void {
    this.annotating = false; this.erasing = false; this.toolMenu = ''; this.selectedMark = -1; this.stroke = null; this.paint();
  }
  private editTool(erase: boolean): void { this.resetZoom(); this.commenting = false; this.annotating = true; this.erasing = erase; this.stroke = null; this.selectedMark = -1; this.toolMenu = ''; this.paint(); }
  private notes(): ImageNote[] { return this.editRevision >= 0 ? this.edits().notes : []; }
  private beginNote(x: number, y: number, index: number = -1): void {
    this.noteX = x; this.noteY = y; this.noteIndex = index; this.comment = index >= 0 ? this.notes()[index].text : ''; this.panel = 'comment';
  }
  private saveNote(): void {
    if (!this.comment.trim()) return;
    const note: ImageNote = { x: this.noteX, y: this.noteY, text: this.comment.trim() };
    if (this.noteIndex < 0) this.edits().notes.push(note); else this.edits().notes[this.noteIndex] = note;
    this.editRevision++; this.panel = ''; this.comment = '';
  }
  private deleteNote(): void {
    if (this.noteIndex >= 0) { this.edits().notes.splice(this.noteIndex, 1); this.editRevision++; }
    this.panel = ''; this.comment = '';
  }
  private async imageBytes(mask: boolean = false): Promise<ArrayBuffer> {
    const doc = this.edits();
    if (doc.width <= 0 || doc.height <= 0) throw new Error('请等待图片加载完成');
    return ImageEditor.render(this.source, mask ? doc.strokes.concat(doc.masks) : doc.strokes, { width: doc.width, height: doc.height });
  }
  private async saveCopy(): Promise<void> {
    if (this.busy || !this.source) return;
    this.busy = true; this.error = '';
    try {
      const bytes = await this.imageBytes();
      const uris = await new picker.DocumentViewPicker().save({ newFileNames: [this.name.replace(/\.[^.]+$/, '') + '-编辑.png'], fileSuffixChoices: ['PNG 图片|.png'] });
      if (uris[0]) { await ImageEditor.write(uris[0], bytes); this.error = '已保存图片副本'; }
    } catch (error) { if (this.active) this.error = error instanceof Error ? error.message : String(error); }
    finally { if (this.active) this.busy = false; }
  }
  private async returnImage(action: string, text: string, withMask: boolean = false): Promise<void> {
    if (this.busy || this.extrasBusy || !this.imageReady || !this.commentThreadId) return;
    this.busy = true; this.error = '';
    const paths: string[] = [];
    try {
      const extras = this.extraStore?.images ?? [];
      if (extras.length + 1 + (withMask ? 1 : 0) > 8) throw new Error('每条消息最多 8 个附件，请先移除一个附件');
      if (extras.some((image: DraftImage) => !image.uploaded)) throw new Error('附件尚未上传完成，请点击附件重试');
      const uri = await ImageEditor.writeCopy(getContext(this).filesDir, await this.imageBytes()); paths.push(uri);
      let maskUri = '';
      if (withMask) { maskUri = await ImageEditor.writeCopy(getContext(this).filesDir, await this.imageBytes(true)); paths.push(maskUri); }
      const target = this.gallery[this.imageIndex].draftTarget;
      const returnAction = target && action === 'send' && !withMask && this.edits().strokes.length ? 'replace' : target && action !== 'replace' ? 'draft' : action;
      const draft: ImageCommentDraft = { id: util.generateRandomUUID(true), uri: uri, name: this.name.replace(/\.[^.]+$/, '') + '-编辑.png', text: text,
        action: returnAction, target: target, maskUri: maskUri || undefined,
        extras: extras.length ? extras : undefined, attachmentDraftId: extras.length ? this.extraDraftId : undefined };
      if (!this.active) throw new Error('图片预览已关闭');
      this.handedOff = true;
      router.back({ url: 'pages/Thread', params: { environmentId: this.environmentId, threadId: this.commentThreadId, draftScope: this.draftScope, imageComment: JSON.stringify(draft) } });
    } catch (error) {
      this.handedOff = false;
      for (const path of paths) await fs.unlink(path).catch(() => {});
      if (this.active) this.error = error instanceof Error ? error.message : String(error);
    } finally { if (this.active) this.busy = false; }
  }
  private removeBackground(): void {
    this.returnImage('send', '移除此图像的背景。保持所有前景主体不变且完整，边缘干净平滑。将背景设为透明。');
  }
  private eraseSelection(): void {
    if (!this.edits().masks.length) return;
    this.returnImage('send', '请编辑第一张图片：移除第二张图片中蓝色涂抹选区内的内容，并自然补全该区域。蓝色只是选区指示，不要将其保留在结果中；其余内容保持不变。' + (this.explanation.trim() ? '\n\n' + this.explanation.trim() : ''), true);
  }
  private resizeImage(ratio: ImageRatio): void {
    this.returnImage('send', `请将这张图片调整为${ratio.label}（${ratio.value}）比例。保留主体及重要内容，必要时自然扩展背景，不要拉伸变形。`);
  }
  private async prepareExtraRpc(): Promise<RpcClient> {
    if (!this.active) throw new Error('图片预览已关闭');
    const environment = EnvironmentSession.current;
    if (!environment || environment.descriptor.environmentId !== this.environmentId || !environment.rpc.isOpen()) throw new Error('请先连接图片所在的环境');
    const rpc = environment.rpc;
    if (this.extraRpc !== rpc || this.extraConnection === null) {
      this.extraRpc = rpc; this.maxFileBytes = 0;
      this.extraConnection = this.loadExtraConfig(rpc, environment.liveConfig);
    }
    const pending = this.extraConnection;
    try { return await pending; }
    catch (error) { if (this.extraConnection === pending) this.extraConnection = null; throw new Error(error instanceof Error ? error.message : String(error)); }
  }
  private async loadExtraConfig(rpc: RpcClient, known: ServerConfig | null): Promise<RpcClient> {
    let config = known;
    if (!config) {
      try { config = await rpc.call<ServerConfig>(WS.serverGetConfig, new EmptyPayload()); }
      catch (error) { if (!(error instanceof RpcRemoteError)) throw new Error(error instanceof Error ? error.message : String(error)); }
    }
    if (!this.active) throw new Error('图片预览已关闭');
    if (EnvironmentSession.current?.rpc !== rpc || this.extraRpc !== rpc) throw new Error('图片所在环境已切换');
    this.maxFileBytes = fileUploadLimit(config?.environment?.capabilities?.fileAttachments?.maxUploadBytes);
    return rpc;
  }
  private async pickExtra(files: boolean): Promise<void> {
    if (this.extrasBusy || this.busy) return;
    this.extrasBusy = true; this.error = '';
    try {
      const rpc = await this.prepareExtraRpc();
      if (files && !this.maxFileBytes) throw new Error('当前环境暂不支持文件附件');
      if (!this.extraStore) this.extraStore = await AttachmentDraftStore.open(getContext(this).filesDir, this.environmentId, 'image-editor:' + this.extraDraftId);
      if (!this.active || EnvironmentSession.current?.rpc !== rpc) return;
      const count = 7 - (this.erasing ? 1 : 0) - this.extraStore.images.length;
      if (count <= 0) throw new Error('每条消息最多 8 个附件');
      const uris = files ? await new picker.DocumentViewPicker().select({ maxSelectNumber: count }) :
        (await new photoAccessHelper.PhotoViewPicker().select({ MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE, maxSelectNumber: count })).photoUris;
      if (!this.active || EnvironmentSession.current?.rpc !== rpc) return;
      for (const uri of uris) {
        const name = new fileUri.FileUri(uri).name;
        if (files) await this.extraStore.addFile(uri, name, this.maxFileBytes); else await this.extraStore.add(uri, name);
        if (!this.active) { await this.extraStore.clear(); return; }
      }
      this.refreshExtras();
      await this.uploadExtras();
    } catch (error) { if (this.active) this.error = error instanceof Error ? error.message : String(error); }
    finally { this.extrasBusy = false; }
  }
  private refreshExtras(): void {
    this.extraImages = (this.extraStore?.images ?? []).map((image: DraftImage): DraftImageProgress => ({ uri: image.uri, type: image.type ?? 'image', name: image.name,
      sizeBytes: image.sizeBytes, status: image.uploaded ? 'uploaded' : 'waiting', progress: image.uploaded ? 100 : 0, error: '' }));
  }
  private async uploadExtras(): Promise<void> {
    const rpc = await this.prepareExtraRpc(), store = this.extraStore, environment = EnvironmentSession.current;
    if (!store || !environment || environment.rpc !== rpc) throw new Error('请先连接图片所在的环境');
    for (const image of store.images) {
      if (image.uploaded) continue;
      try {
        const uploaded = await uploadImage(rpc, environment.httpBaseUrl, image.uri, image.name ?? '', (progress: number) => {
          if (!this.active) return;
          this.extraImages = this.extraImages.map((entry: DraftImageProgress): DraftImageProgress => entry.uri === image.uri ? {
            uri: entry.uri, name: entry.name, type: entry.type, sizeBytes: entry.sizeBytes, status: 'uploading', progress: progress, error: '' } : entry);
        }, image.type ?? 'image', image.type === 'file' ? this.maxFileBytes : 10 * 1024 * 1024);
        if (!this.active) { await deleteImageUpload(rpc, uploaded.id).catch(() => {}); return; }
        await store.setUploaded(image.uri, uploaded); this.refreshExtras();
      } catch (error) {
        this.extraImages = this.extraImages.map((entry: DraftImageProgress): DraftImageProgress => entry.uri === image.uri ? {
          uri: entry.uri, name: entry.name, type: entry.type, sizeBytes: entry.sizeBytes, status: 'failed', progress: 0, error: error instanceof Error ? error.message : String(error) } : entry);
        throw new Error(error instanceof Error ? error.message : String(error));
      }
    }
  }
  private async retryExtras(): Promise<void> {
    if (this.extrasBusy) return;
    this.extrasBusy = true;
    try { await this.uploadExtras(); this.error = ''; } catch (error) { this.error = error instanceof Error ? error.message : String(error); }
    finally { this.extrasBusy = false; }
  }
  private async removeExtra(uri: string): Promise<void> {
    if (this.extrasBusy || !this.extraStore) return;
    this.extrasBusy = true;
    try {
      const image = this.extraStore.images.find((entry: DraftImage): boolean => entry.uri === uri);
      if (image?.uploaded) await deleteImageUpload(await this.prepareExtraRpc(), image.uploaded.id);
      await this.extraStore.remove(uri); this.refreshExtras();
    } catch (error) { this.error = error instanceof Error ? error.message : String(error); }
    finally { this.extrasBusy = false; }
  }
  private async discardExtras(store: AttachmentDraftStore | null): Promise<void> {
    if (!store) return;
    const environment = EnvironmentSession.current;
    if (environment?.descriptor.environmentId === this.environmentId) {
      for (const image of store.images) if (image.uploaded) await deleteImageUpload(environment.rpc, image.uploaded.id).catch(() => {});
    }
    await store.clear();
  }
  private sendEdits(): void {
    if (!this.canSendEdits()) return;
    if (this.erasing) { this.eraseSelection(); return; }
    const notes = this.notes().length ? imageNoteText(this.notes()) : '';
    const text = [notes, this.explanation.trim()].filter((part: string): boolean => !!part).join('\n\n');
    this.returnImage('send', text || '请查看这张图片中的标注。');
  }
  private canSendEdits(): boolean {
    return this.editRevision >= 0 && this.imageReady && !this.busy && !this.extrasBusy &&
      (this.erasing ? this.edits().masks.length > 0 : !!this.explanation.trim() || this.edits().strokes.length > 0 || this.notes().length > 0);
  }
  @Builder
  private icon(name: string, label: string, action: () => void, enabled: () => boolean = () => true) {
    // Read state inside the builder so ArkUI observes changes instead of capturing an initial boolean.
    Button({ type: ButtonType.Circle }) { AppIcon({ name: name, iconSize: 21, tint: enabled() ? '#FFFFFF' : '#66FFFFFF' }) }
      .id('image-action-' + label).width(44).height(44).padding(0).backgroundColor(Color.Transparent).enabled(enabled() && !this.busy && !this.extrasBusy).accessibilityText(label).onClick(action)
  }
  @Builder
  private dragHandle(height: number = COMPACT_TOOL_HEIGHT, width: number = 28, header: boolean = false) {
    Row() { AppIcon({ name: 'grip', iconSize: 20, tint: '#AAAAAA' }) }
      .id(header ? 'image-header-drag-handle' : 'image-drag-handle').width(width).height(height).justifyContent(FlexAlign.Center).padding({ left: 4 })
      .borderRadius({ topLeft: header ? 16 - TOOLBAR_INSET : height / 2, bottomLeft: header ? 16 - TOOLBAR_INSET : height / 2, topRight: 6, bottomRight: 6 }).backgroundColor('#18FFFFFF')
      .accessibilityText(header ? '上下拖动图片标题栏' : '拖动图片工具条').onTouch((event: TouchEvent) => { event.stopPropagation(); })
      .gesture(PanGesture({ direction: header ? PanDirection.Vertical : PanDirection.All })
        .onActionStart(() => {
          if (header) this.headerStartY = this.headerY;
          else { this.controlsStartX = this.controlsX; this.controlsStartY = this.controlsY; }
        })
        .onActionUpdate((event: GestureEvent) => {
          if (header) this.moveHeader(this.headerStartY + event.offsetY);
          else this.moveControls(this.controlsStartX + event.offsetX, this.controlsStartY + event.offsetY);
        }))
  }
  @Builder
  private markButton(name: string, label: string, action: () => void, selected: () => boolean = () => false, enabled: () => boolean = () => true) {
    Button({ type: ButtonType.Normal }) { AppIcon({ name: name, iconSize: 20, tint: enabled() ? selected() ? '#93C5FD' : '#FFFFFF' : '#66FFFFFF' }) }
      .id('image-mark-' + name).layoutWeight(1).height(40).padding(0).borderRadius(12).backgroundColor(selected() ? '#334C7FDB' : Color.Transparent)
      .enabled(enabled() && !this.busy).accessibilityText(label).onClick(action)
  }
  @Builder
  private brushSlider() {
    Column() {
      ChatGlass({ onImage: true, radius: 20 }) {
        Row({ space: 6 }) {
          Stack() { Circle().width(Math.min(22, this.brushWidth())).height(Math.min(22, this.brushWidth())).fill(this.erasing ? '#60A5FA' : this.markTool === 'eraser' ? '#FFFFFF' : this.penColor) }.width(24)
          Slider({ value: this.brushWidth(), min: this.erasing ? 4 : 1, max: this.erasing || this.markTool === 'eraser' ? 80 : 24, step: 1 })
            .layoutWeight(1).height(40).trackThickness(4).selectedColor('#93C5FD').trackColor('#66FFFFFF')
            .id('image-brush-width').onChange((value: number) => { this.setBrushWidth(value); }).accessibilityText(this.erasing ? '擦除选区粗细' : this.markTool === 'eraser' ? '橡皮擦粗细' : '画笔粗细')
          Text(String(this.brushWidth())).width(26).textAlign(TextAlign.Center).fontSize(this.font(12)).fontColor('#FFFFFF')
        }.height(40).width('100%').padding({ left: 10, right: 8 })
      }
    }.width(Math.min(196, this.viewportWidth - 24)).margin({ bottom: 8 })
  }
  @Builder
  private annotationMenu() {
    if (this.toolMenu === 'colors') {
      Row({ space: 6 }) {
        ForEach(['#EF4444', '#FB923C', '#FACC15', '#22C55E', '#3B82F6', '#A855F7', '#FFFFFF', '#111827'], (color: string) => {
          Button({ type: ButtonType.Circle }) { Circle().width(23).height(23).fill(color).stroke(this.penColor === color ? '#93C5FD' : '#777777').strokeWidth(this.penColor === color ? 3 : 1) }
            .width(34).height(38).padding(0).backgroundColor(Color.Transparent).accessibilityText(`选择标注颜色 ${color}`).onClick(() => { this.penColor = color; this.toolMenu = ''; })
        })
      }.padding(6)
    } else if (this.toolMenu === 'shapes') {
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.shapes(), (shape: ImageToolChoice) => {
          Button({ type: ButtonType.Circle }) { AppIcon({ name: shape.name, iconSize: 20, tint: this.markTool === shape.name ? this.color('primary') : this.color('foreground') }) }
            .width(36).height(40).padding(0).backgroundColor(Color.Transparent).accessibilityText(shape.label).onClick(() => { this.chooseTool(shape.name); })
        })
      }.width(156).padding(6)
    }
  }
  @Builder
  private markTools() {
    ChatGlass({ capsule: true, onImage: true, radius: COMPACT_TOOL_HEIGHT / 2 + TOOLBAR_INSET }) {
      Row({ space: 0 }) {
        this.dragHandle()
        this.markButton('pointer', '选择、移动或调整标注大小', () => { this.chooseTool('select'); }, () => this.markTool === 'select')
        this.markButton('edit', '画笔', () => { this.chooseTool('pen'); }, () => this.markTool === 'pen')
        this.markButton('text', '添加文字', () => { this.chooseTool('text'); }, () => this.markTool === 'text')
        this.markButton('shapes', '形状', () => { this.toolMenu = this.toolMenu === 'shapes' ? '' : 'shapes'; }, () => this.shapes().some((shape: ImageToolChoice) => shape.name === this.markTool))
        Button({ type: ButtonType.Circle }) { Circle().width(22).height(22).fill(this.penColor).stroke('#88FFFFFF').strokeWidth(1) }
          .layoutWeight(1).height(40).padding(0).backgroundColor(Color.Transparent).accessibilityText('标注颜色').onClick(() => { this.toolMenu = this.toolMenu === 'colors' ? '' : 'colors'; })
        this.markButton('eraser', '擦除标注', () => { this.chooseTool('eraser'); }, () => this.markTool === 'eraser')
        this.markButton('undo', '撤销标注', () => { this.undo(); }, () => false, () => this.canUndo(false))
        this.markButton('redo', '重做标注', () => { this.undo(true); }, () => false, () => this.canUndo(true))
        this.markButton('close', '完成标注', () => { this.finishAnnotation(); })
      }.width('100%').padding(TOOLBAR_INSET).bindPopup(!!this.toolMenu, { builder: this.annotationMenu(), placement: Placement.Top, enableArrow: false,
        radius: 22, systemMaterial: immersiveMaterial('popup'), onStateChange: (event: PopupStateChangeParam) => { if (!event.isVisible) this.toolMenu = ''; } })
    }
  }
  @Builder
  private imageComposer() {
    Column() {
      ChatGlass() {
        Column({ space: 4 }) {
          if (this.extraImages.length) {
            DraftImages({ images: this.extraImages, environmentId: this.environmentId, disabled: this.busy || this.extrasBusy,
              onRemove: (uri: string) => { this.removeExtra(uri); }, onRetry: () => { this.retryExtras(); } })
          }
          Row({ space: 4 }) {
            ComposerActions({ references: false, disabled: this.busy || this.extrasBusy, canAttach: this.extraImages.length < (this.erasing ? 6 : 7),
              canAttachFiles: this.maxFileBytes > 0, onPhotos: () => { this.pickExtra(false); }, onFiles: () => { this.pickExtra(true); } })
            ComposerEditor({ text: this.explanation, placeholder: '添加说明…', disabled: this.busy,
              onChange: (text: string) => { this.explanation = text; }, onSend: () => { this.sendEdits(); } }).layoutWeight(1)
            Button({ type: ButtonType.Circle }) { AppIcon({ name: 'send', iconSize: 20, tint: this.color('primary-foreground') }) }
              .id('image-send').width(40).height(40).padding(0).backgroundColor(this.color('primary')).enabled(this.canSendEdits())
              .accessibilityText(this.gallery[this.imageIndex]?.draftTarget ? '将图片和说明加入草稿' : '发送图片和说明').onClick(() => { this.sendEdits(); })
          }.width('100%')
        }.width('100%').padding(8)
      }
    }.margin({ top: 10 })
      .onAppear(() => { this.prepareExtraRpc().catch(() => {}); })
      .hitTestBehavior(HitTestMode.Default)
  }
  @Builder
  private tool(name: string, label: string, action: () => void, selected: boolean = false) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 4 }) { AppIcon({ name: name, iconSize: 20, tint: selected ? '#93C5FD' : '#FFFFFF' }); Text(label).fontSize(this.font(10)).fontColor(selected ? '#93C5FD' : '#DDFFFFFF') }
    }.id('image-tool-' + name).height(PREVIEW_TOOL_HEIGHT).layoutWeight(1).padding(0).borderRadius(14).backgroundColor(selected ? '#334C7FDB' : Color.Transparent)
      .enabled(!!this.source && !this.busy && this.imageReady).accessibilityText(label).onClick(action)
  }
  @Builder
  private currentImage(source: string, revision: number) {
    Image(source).objectFit(ImageFit.Fill).width(this.imageWidth()).height(this.imageHeight())
      .onError(() => { if (this.active && revision === this.revision && source === this.source) { this.imageReady = false; this.error = '图片加载失败，请重新加载'; } })
      .onComplete((event) => {
        if (!this.active || revision !== this.revision || source !== this.source || !event || event.width <= 0 || event.height <= 0) return;
        const doc = this.edits();
        if (!doc.width || !doc.height) { doc.width = event.width; doc.height = event.height; }
        this.aspect = doc.width / doc.height; this.imageReady = true; this.paint();
      })
  }
  @Builder
  private editPanelTitle() {
    Row({ space: 8 }) {
      Button('取消').height(40).fontSize(this.font(14)).fontColor(this.color('foreground')).backgroundColor(Color.Transparent)
        .onClick(() => { this.panel = ''; })
      Text(this.panel === 'comment' ? '图片评论' : '添加文字').layoutWeight(1).textAlign(TextAlign.Center)
        .fontSize(this.font(17)).fontWeight(FontWeight.Medium).fontColor(this.color('foreground'))
      Button('保存').height(40).fontSize(this.font(14)).backgroundColor('#3268D5').enabled(!!this.comment.trim() && !this.busy)
        .onClick(() => { if (this.panel === 'text') this.saveText(); else this.saveNote(); })
    }.width('100%').padding({ left: 16, right: 16, top: 4, bottom: 4 })
  }
  @Builder
  private editPanel() {
    Column({ space: 4 }) {
      if (this.error) { Text(this.error).fontColor(this.color('danger-foreground')).fontSize(this.font(12)) }
      if (this.panel === 'comment' || this.panel === 'text') {
        TextArea({ text: this.comment, placeholder: '说明图片中需要关注的内容…' }).height(120).fontSize(this.font(15)).fontColor(this.color('foreground')).backgroundColor(this.color('input')).borderRadius(12).onChange((value: string) => { this.comment = value; })
        if (this.panel === 'comment' && this.noteIndex >= 0) {
          Button('删除此评论').fontColor(this.color('danger-foreground')).backgroundColor(Color.Transparent).enabled(!this.busy).onClick(() => { this.deleteNote(); })
        }
      } else {
        ForEach(imageRatios(), (ratio: ImageRatio) => {
          Button({ type: ButtonType.Normal }) {
            Row({ space: 14 }) {
              Stack() { Rect().width(ratio.width).height(ratio.height).radius(3).fill(Color.Transparent).stroke(this.color('foreground-secondary')).strokeWidth(1.5) }.width(28).height(28)
              Text(ratio.label).fontSize(this.font(16)).fontColor(this.color('foreground')).layoutWeight(1).textAlign(TextAlign.Start)
              Text(ratio.value).fontSize(this.font(15)).fontColor(this.color('foreground-secondary'))
            }.width('100%')
          }.width('100%').height(48).padding({ left: 8, right: 10 }).backgroundColor(Color.Transparent).borderRadius(12).enabled(!this.busy).onClick(() => { this.resizeImage(ratio); })
        }, (ratio: ImageRatio) => ratio.value)
      }
    }.width('100%').padding(16)
  }
  build() {
    Stack({ alignContent: Alignment.Center }) {
      Swiper(this.swiper) {
        ForEach(this.gallery, (_image: PreviewImage, index: number) => {
          Stack() {
            if (index === this.imageIndex && this.source) {
              Stack() {
                this.currentImage(this.source, this.revision)
                Canvas(this.canvas).width(this.imageWidth()).height(this.imageHeight()).onReady(() => { this.paint(); }).onAreaChange(() => { this.paint(); })
                  .hitTestBehavior(this.annotating || this.commenting ? HitTestMode.Default : HitTestMode.None).onTouch((event: TouchEvent) => { this.draw(event); })
                ForEach(this.commenting ? this.notes() : [], (note: ImageNote, index: number) => {
                  Button(String(index + 1), { type: ButtonType.Circle }).width(28).height(28).padding(0).fontSize(this.font(12)).fontColor('#FFFFFF').backgroundColor('#328FFA')
                    .border({ width: 1.5, color: '#FFFFFF' }).position({ x: Math.max(0, Math.min(this.imageWidth() - 28, note.x * this.imageWidth() - 14)), y: Math.max(0, Math.min(this.imageHeight() - 28, note.y * this.imageHeight() - 14)) })
                    .accessibilityText(`评论 ${index + 1}：${note.text}`).onClick(() => { this.beginNote(note.x, note.y, index); })
                }, (_note: ImageNote, index: number) => String(index))
              }.width(this.imageWidth()).height(this.imageHeight()).scale({ x: this.zoom, y: this.zoom }).translate({ x: this.offsetX, y: this.offsetY })
            } else if (this.gallerySources[index]) {
              Image(this.gallerySources[index]).objectFit(ImageFit.Contain).width('100%').height('100%')
            }
            if (index === this.imageIndex && (this.loading || this.busy)) { LoadingProgress().width(32).height(32).color('#FFFFFF').hitTestBehavior(HitTestMode.Block) }
          }.width('100%').height('100%').clip(true)
        }, (_image: PreviewImage, index: number) => String(index))
      }.width('100%').height('100%').index(this.imageIndex).loop(false).indicator(false).duration(180)
        .disableSwipe(this.commenting || this.annotating || this.zoom > 1 || this.busy || this.extrasBusy || !!this.panel).onChange((index: number) => { this.selectImage(index); })
        .gesture(GestureGroup(GestureMode.Parallel,
          PinchGesture().onActionStart(() => { this.startZoom = this.zoom; }).onActionUpdate((event: GestureEvent) => {
            if (!this.commenting && !this.annotating && !this.panel && !this.busy) { this.zoom = Math.max(1, Math.min(4, this.startZoom * event.scale)); this.pan(this.offsetX, this.offsetY); }
          }),
          PanGesture({ direction: this.zoom > 1 ? PanDirection.All : PanDirection.Vertical }).onActionStart(() => { this.startX = this.offsetX; this.startY = this.offsetY; this.panningZoomed = this.zoom > 1; })
            .onActionUpdate((event: GestureEvent) => { if (this.zoom > 1 && !this.annotating && !this.commenting) this.pan(this.startX + event.offsetX, this.startY + event.offsetY); })
            .onActionEnd((event: GestureEvent) => {
              if (!this.commenting && !this.annotating && !this.busy && !this.panel && !this.panningZoomed && this.zoom === 1 && event.offsetY > 120 && event.offsetY > Math.abs(event.offsetX) * 1.5) router.back();
            }),
          TapGesture({ count: 2 }).onAction(() => { if (!this.commenting && !this.annotating && !this.panel && !this.busy) { if (this.zoom > 1) this.resetZoom(); else this.zoom = 2; } })
        )).onGestureJudgeBegin((_info: GestureInfo, _event: BaseGestureEvent) => this.commenting || this.annotating || !!this.panel || this.busy ? GestureJudgeResult.REJECT : GestureJudgeResult.CONTINUE)
      Column() {
        Column() {
          ChatGlass({ onImage: true }) {
            Row({ space: 4 }) {
              this.dragHandle(COMPACT_TOOL_HEIGHT - 2 * TOOLBAR_INSET, 36, true)
              Text(this.name).fontColor('#FFFFFF').fontSize(this.font(13)).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
              this.icon('refresh', '重新加载', () => { this.reload(true); }, () => !this.loading && !this.annotating && !this.commenting)
              this.icon('download', '保存图片副本', () => { this.saveCopy(); }, () => !!this.source && this.imageReady && !this.loading)
              this.icon('close', '关闭图片', () => { router.back(); })
            }.padding({ left: TOOLBAR_INSET, right: 4 }).width('100%').onTouch((event: TouchEvent) => { event.stopPropagation(); })
          }
        }.width(Math.max(1, this.viewportWidth - 24))
          .translate({ y: this.headerY }).hitTestBehavior(HitTestMode.Default)
        Blank(PREVIEW_BAR_GAP).layoutWeight(1).width('100%').hitTestBehavior(HitTestMode.None)
          .onAreaChange((_old: Area, area: Area) => { this.toolbarRoom = Number(area.height); this.fitToolbars(); })
        Column() {
          if (this.error) { Text(this.error).fontSize(this.font(12)).fontColor('#FFFFFF').padding(12).backgroundColor('#CC252528').borderRadius(12).margin({ bottom: 8 }).maxLines(3) }
          if (!this.panel) {
            if (this.annotating && (this.erasing || !['select', 'text'].includes(this.markTool))) { this.brushSlider() }
            if (this.commenting) {
              Text(this.notes().length ? '点击编号编辑评论，点击图片可继续添加' : '点击图片添加评论').fontSize(this.font(13)).fontColor('#DDFFFFFF').padding(10).backgroundColor('#A8252528').borderRadius(20).margin({ bottom: 8 })
              ChatGlass({ capsule: true, onImage: true, compact: true, radius: COMPACT_TOOL_HEIGHT / 2 + TOOLBAR_INSET }) {
                Row({ space: 8 }) {
                  this.dragHandle()
                  Text(`${this.notes().length} 条评论`).fontSize(this.font(14)).fontColor('#FFFFFF').margin({ left: 12 })
                  this.icon('close', '关闭图片评论', () => { this.commenting = false; })
                }.padding(TOOLBAR_INSET)
              }
            }
            else if (this.annotating) {
              if (!this.erasing) { this.markTools() }
              else {
              Text('涂抹需要移除的区域').fontSize(this.font(13)).fontColor('#DDFFFFFF').padding(10).backgroundColor('#A8252528').borderRadius(20).margin({ bottom: 8 })
              ChatGlass({ capsule: true, onImage: true, compact: true, radius: COMPACT_TOOL_HEIGHT / 2 + TOOLBAR_INSET }) {
                Row({ space: 4 }) {
                  this.dragHandle()
                  this.icon('undo', this.erasing ? '撤销选区' : '撤销标注', () => { this.undo(); }, () => this.canUndo(false))
                  this.icon('redo', this.erasing ? '重做选区' : '重做标注', () => { this.undo(true); }, () => this.canUndo(true))
                  this.icon('close', this.erasing ? '关闭擦除' : '关闭标注', () => { this.finishAnnotation(); })
                }.padding(TOOLBAR_INSET)
              }
              }
            } else {
              Column() {
                ChatGlass({ onImage: true }) {
                  Row({ space: 6 }) {
                    this.icon('back', '上一张图片', () => { this.moveImage(-1); }, () => this.imageIndex > 0)
                    Text(`${this.imageIndex + 1} / ${this.gallery.length}`).fontColor('#FFFFFF').fontSize(this.font(13)).layoutWeight(1).textAlign(TextAlign.Center)
                    Button(`${Math.round(this.zoom * 100)}%`).height(36).fontColor('#FFFFFF').fontSize(this.font(12)).backgroundColor('#33FFFFFF').onClick(() => { this.resetZoom(); })
                    this.icon('chevron', '下一张图片', () => { this.moveImage(1); }, () => this.imageIndex < this.gallery.length - 1)
                  }.width('100%').padding({ left: 6, right: 6 })
                }
              }.margin({ bottom: 6 })
              ChatGlass({ capsule: true, onImage: true, radius: PREVIEW_TOOL_HEIGHT / 2 + TOOLBAR_INSET }) {
                Row({ space: 2 }) {
                  this.dragHandle(PREVIEW_TOOL_HEIGHT, 38)
                  this.tool('edit', '标注', () => { this.editTool(false); })
                  if (this.commentThreadId) {
                    this.tool('chat', '评论', () => { this.resetZoom(); this.commenting = true; })
                    this.tool('cutout', '移除背景', () => { this.removeBackground(); })
                    this.tool('eraser', '擦除', () => { this.editTool(true); })
                    this.tool('resize', '调整大小', () => { this.panel = 'resize'; })
                  }
                }.width('100%').padding(TOOLBAR_INSET)
              }
              if (this.commentThreadId && this.gallery[this.imageIndex]?.draftTarget) { Button('应用到草稿').height(42).width('100%').margin({ top: 8 }).backgroundColor('#3268D5').enabled(this.imageReady && !this.busy).onClick(() => { this.returnImage('replace', ''); }) }
            }
          }
        }.width(Math.min(362, this.viewportWidth - 24)).translate({ x: this.controlsX, y: this.controlsY }).hitTestBehavior(HitTestMode.Default)
          .onAreaChange((_old: Area, area: Area) => { this.controlsWidth = Number(area.width); this.moveControls(this.controlsX, this.controlsY); })
        if (!this.panel && this.commentThreadId && (this.annotating || this.commenting || this.editRevision > 0 && this.edits().strokes.length > 0)) { this.imageComposer() }
      }.width('100%').height('100%').padding({ left: 12, right: 12, top: 8, bottom: 30 }).hitTestBehavior(HitTestMode.None)
    }.width('100%').height('100%').backgroundColor('#000000').clip(true).expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .bindSheet(!!this.panel, this.editPanel(), { systemMaterial: immersiveMaterial('popup'), height: SheetSize.FIT_CONTENT, dragBar: true, showClose: this.panel === 'resize',
        title: this.panel === 'resize' ? { title: '调整大小' } : () => { this.editPanelTitle(); },
        onWillDismiss: (action: DismissSheetAction) => { this.panel = ''; action.dismiss(); } })
      .onAreaChange((_old: Area, area: Area) => { this.viewportWidth = Number(area.width) || 1; this.viewportHeight = Number(area.height) || 1; this.fitToolbars(); this.pan(this.offsetX, this.offsetY); })
  }
  private color(role: string): string { return ThemeRuntime.color(this.themeKey, role); }
}
