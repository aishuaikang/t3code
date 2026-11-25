import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
async function load(name) {
  const source = readFileSync(new URL(`../app/entry/src/main/ets/model/${name}.ets`, import.meta.url), 'utf8').replace(/^import .*;$/gm, '');
  return import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
}
const labels = await load('AttachmentLabels'), reasoning = await load('Reasoning'), tasks = await load('TaskPresentation');
test('only actual attachment names become clickable while surrounding message text is preserved', () => {
  const attachments = [{ id: 'a', name: 'photo [1].jpg' }, { id: 'b', name: 'photo.png' }];
  const text = '看看 photo [1].jpg 再比较 photo.png；photo.png 也在这里';
  const parts = labels.attachmentParts(text, attachments);
  assert.equal(parts.map(p => p.text).join(''), text);
  assert.deepEqual(parts.filter(p => p.attachmentId).map(p => p.attachmentId), ['a', 'b', 'b']);
  assert.deepEqual(labels.attachmentParts('unrelated.jpg', attachments), [{ text: 'unrelated.jpg', attachmentId: '' }]);
  assert.equal(labels.attachmentSize(2048), '2 KB'); assert.equal(labels.attachmentSize(1572864), '1.5 MB');
});

test('image thumbnails do not also create filename rows while actual file attachments stay accessible',()=>{
 const image={id:'image',type:'image',name:'screenshot.jpg',sizeBytes:2048};
 const file={id:'file',type:'file',name:'notes.txt',sizeBytes:1024};
 assert.deepEqual(labels.attachmentFileRows('看看这些图片',[image,file]),[file]);
 assert.deepEqual(labels.attachmentFileRows('阅读 notes.txt',[image,file]),[]);
 assert.equal(labels.attachmentParts('看看 screenshot.jpg',[image]).find(p=>p.attachmentId)?.attachmentId,'image');
});
test('file cards show a compact format and size while preserving the original title',()=>{
 for(const [name,mimeType,format] of [['中文报告.pdf','application/pdf','PDF'],['资料.DOCX','application/octet-stream','DOCX'],['无扩展名','application/pdf','PDF'],['资料','application/octet-stream','文件']]){
  const attachment={id:'file',type:'file',name,mimeType,sizeBytes:163840};
  assert.equal(labels.attachmentFormat(attachment),format);
  assert.equal(labels.attachmentSize(attachment.sizeBytes),'160 KB');
  assert.deepEqual(labels.attachmentFileRows('',[attachment]),[attachment]);
 }
});
test('reasoning titles and body remove heading markup without flattening paragraphs', () => {
  assert.equal(reasoning.reasoningTitle('\n**Checking upload**\nDetails', true), '思考中 · Checking upload');
  assert.equal(reasoning.reasoningTitle('', true), '思考中…');
  assert.equal(reasoning.reasoningBody('## Inspect\n\n**Details**\n- Keep this'), 'Inspect\n\nDetails\n- Keep this');
});
test('internal image references render as attachment labels without exposing Markdown or context URLs', () => {
  const attachments = [{ id: 'server-image', name: '129902.png', sizeBytes: 534528 }];
  const parts = labels.attachmentParts('![129902.png](t3-context://v1/image/reference-id) 看看这里', attachments);
  assert.equal(parts[0].attachmentId, 'server-image');
  assert.equal(parts[0].text, '129902.png · 522 KB');
  assert.equal(parts.slice(1).map(p => p.text).join(''), ' 看看这里');
  const missing = labels.attachmentParts('![old.png](t3-context://v1/image/missing) 后面的文字', []);
  assert.equal(missing.map(p => p.text).join(''), 'old.png 后面的文字');
});
test('home time labels handle future or missing clocks and project badges stay stable', () => {
  const now = Date.parse('2026-11-15T12:00:00Z');
  assert.equal(tasks.relativeTaskTime(null, now), '');
  assert.equal(tasks.relativeTaskTime('2026-11-15T13:00:00Z', now), '刚刚');
  assert.equal(tasks.relativeTaskTime('2026-11-15T10:00:00Z', now), '2h');
  assert.equal(tasks.relativeTaskTime('2026-11-13T12:00:00Z', now), '2d');
  assert.equal(tasks.projectInitials('uav_defender'), 'UD'); assert.equal(tasks.projectInitials('健在'), '健在');
  assert.equal(tasks.projectTint('uav_defender'), tasks.projectTint('uav_defender'));
  assert.deepEqual(['completed', 'idle', 'waiting', 'running', 'queued'].sort((a,b) => tasks.taskSection(a)-tasks.taskSection(b)), ['waiting', 'running', 'queued', 'idle', 'completed']);
});
