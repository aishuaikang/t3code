import { previewStreamDocument } from '../preview-stream/preview-stream-document';

const result = await Bun.build({ entrypoints: [new URL('../preview-stream/entry.ts', import.meta.url).pathname],
  target: 'browser', format: 'iife', minify: true });
if (!result.success) throw new Error(result.logs.join('\n'));
const script = await result.outputs[0].text();
const license = await Bun.file(new URL('../preview-stream/LICENSE', import.meta.url)).text();
const bridge = 'window.ReactNativeWebView={postMessage:function(value){HarmonyBrowser.postMessage(value);}};';
const html = previewStreamDocument('null', bridge + script).replace('T3PreviewStream.start(null);', '');
await Bun.write(new URL('../entry/src/main/resources/rawfile/preview-stream.html', import.meta.url), '<!-- ' + license + ' -->\n' + html);
