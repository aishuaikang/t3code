import util from '@ohos.util';
import { RpcClient, RpcRemoteError } from './Rpc';
import { SendJournal } from './SendJournal';
import { uploadImage, imageUploadExists, deleteImageUpload, UploadedImage } from './ImageAttachment';
import { ImageCommentDraft } from '../model/ImageEdits';
import { ThreadDetail, startTurnCommand, WS } from '../model/Models';

export class ImageEditRequests {
  static async send(rpc: RpcClient, filesDir: string, environmentId: string, baseUrl: string,
    thread: ThreadDetail, request: ImageCommentDraft): Promise<void> {
    const journal = await SendJournal.open(filesDir, environmentId, thread.id, `image-edit:${thread.id}:${request.id}`);
    if (journal.pending === null) {
      const command = startTurnCommand(thread, request.text, util.generateRandomUUID(true), request.id, new Date().toISOString(), 'steer', null, false);
      const uploaded: UploadedImage[] = [];
      try {
        uploaded.push(await uploadImage(rpc, baseUrl, request.uri, request.name));
        if (request.maskUri) uploaded.push(await uploadImage(rpc, baseUrl, request.maskUri, '擦除选区.png'));
        command.message.attachments = uploaded.slice();
        for (const extra of request.extras ?? []) {
          const attachment = extra.uploaded;
          if (!attachment) throw new Error('请等待附件上传完成');
          if (!await imageUploadExists(rpc, attachment.id)) {
            const replacement = await uploadImage(rpc, baseUrl, extra.uri, extra.name ?? attachment.name,
              () => {}, attachment.type, attachment.sizeBytes);
            uploaded.push(replacement);
            command.message.attachments.push(replacement);
          } else command.message.attachments.push(attachment);
        }
        await journal.save(command);
      } catch (error) {
        for (const image of uploaded) await deleteImageUpload(rpc, image.id).catch(() => {});
        throw new Error(error instanceof Error ? error.message : String(error));
      }
    }
    const command = journal.pending!;
    try {
      await rpc.call(WS.threadStartTurn, command);
    } catch (error) {
      if (error instanceof RpcRemoteError && error.definitivelyRejected) {
        await journal.clear();
        for (const value of command.message.attachments) {
          const attachment = value as UploadedImage;
          if (!(request.extras ?? []).some((extra) => extra.uploaded?.id === attachment.id)) {
            await deleteImageUpload(rpc, attachment.id).catch(() => {});
          }
        }
      }
      if (error instanceof Error) throw error;
      throw new Error(String(error));
    }
    await journal.clear();
  }
}
