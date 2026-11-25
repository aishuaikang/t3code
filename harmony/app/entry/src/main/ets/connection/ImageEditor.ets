import image from '@ohos.multimedia.image';
import fs from '@ohos.file.fs';
import http from '@ohos.net.http';
import drawing from '@ohos.graphics.drawing';
import util from '@ohos.util';
import { ImageStroke, ImageSize } from '../model/ImageEdits';

export class ImageEditor {
  static async decode(source: string): Promise<image.PixelMap> {
    let file: fs.File | null = null;
    let decoder: image.ImageSource | null = null;
    try {
      if (/^https?:\/\//.test(source)) {
        const client = http.createHttp();
        try {
          const response = await client.request(source, { expectDataType: http.HttpDataType.ARRAY_BUFFER,
            connectTimeout: 15000, readTimeout: 60000, maxLimit: 20 * 1024 * 1024 });
          if (response.responseCode !== 200 || !(response.result instanceof ArrayBuffer)) throw new Error('图片下载失败，请重试');
          decoder = image.createImageSource(response.result);
        } finally { client.destroy(); }
      } else {
        file = await fs.open(source.replace(/^file:\/\//, ''), fs.OpenMode.READ_ONLY);
        decoder = image.createImageSource(file.fd);
      }
      const info = await decoder.getImageInfo();
      if (info.size.width * info.size.height > 32 * 1024 * 1024) throw new Error('图片过大，暂时无法编辑');
      return await decoder.createPixelMap({ editable: true, desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
    } finally { await decoder?.release(); if (file !== null) await fs.close(file); }
  }
  static async render(source: string, strokes: ImageStroke[], size: ImageSize): Promise<ArrayBuffer> {
    const pixels = await ImageEditor.decode(source);
    try {
      const info = await pixels.getImageInfo();
      if (size.width !== info.size.width || size.height !== info.size.height) await pixels.scale(size.width / info.size.width, size.height / info.size.height);
      const canvas = new drawing.Canvas(pixels);
      for (const stroke of strokes) {
        if (stroke.points.length === 0) continue;
        const color = parseInt((stroke.color.length === 9 ? '' : 'FF') + stroke.color.substring(1), 16);
        if (stroke.kind === 'text') {
          const font = new drawing.Font(), brush = new drawing.Brush(), fontSize = (stroke.fontSize ?? 0.05) * size.height;
          font.setSize(fontSize); brush.setAntiAlias(true); brush.setColor(color); canvas.attachBrush(brush);
          const lines = (stroke.text ?? '').split('\n');
          for (let index = 0; index < lines.length; index++) canvas.drawTextBlob(drawing.TextBlob.makeFromString(lines[index], font),
            stroke.points[0].x * size.width, stroke.points[0].y * size.height + fontSize * (1 + index * 1.2));
          canvas.detachBrush(); continue;
        }
        const pen = new drawing.Pen();
        pen.setAntiAlias(true); pen.setCapStyle(drawing.CapStyle.ROUND_CAP);
        pen.setJoinStyle(drawing.JoinStyle.ROUND_JOIN);
        pen.setColor(color);
        pen.setStrokeWidth(stroke.width * Math.min(size.width, size.height));
        canvas.attachPen(pen);
        const path = new drawing.Path(), first = stroke.points[0];
        path.moveTo(first.x * size.width, first.y * size.height);
        if (stroke.points.length === 1) path.lineTo(first.x * size.width + 0.01, first.y * size.height + 0.01);
        for (let index = 1; index < stroke.points.length; index++) path.lineTo(stroke.points[index].x * size.width, stroke.points[index].y * size.height);
        canvas.drawPath(path); canvas.detachPen();
      }
      return await ImageEditor.pack(pixels);
    } finally { await pixels.release(); }
  }
  private static async pack(pixels: image.PixelMap): Promise<ArrayBuffer> {
    const packer = image.createImagePacker();
    try { return await packer.packing(pixels, { format: 'image/png', quality: 100 }); }
    finally { await packer.release(); }
  }
  static async writeCopy(filesDir: string, bytes: ArrayBuffer): Promise<string> {
    const root = `${filesDir}/image-edits`;
    if (!fs.accessSync(root)) fs.mkdirSync(root);
    const path = `${root}/${util.generateRandomUUID(true)}.png`;
    try { await ImageEditor.write(path, bytes); }
    catch (error) { if (fs.accessSync(path)) await fs.unlink(path).catch(() => {}); throw new Error(error instanceof Error ? error.message : String(error)); }
    return path;
  }
  static async write(uri: string, bytes: ArrayBuffer): Promise<void> {
    const file = await fs.open(uri, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      let offset = 0;
      while (offset < bytes.byteLength) {
        const count = await fs.write(file.fd, bytes.slice(offset));
        if (count <= 0) throw new Error('图片保存未完成，请重试');
        offset += count;
      }
    } finally { await fs.close(file); }
  }
}
