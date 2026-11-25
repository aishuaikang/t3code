import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
const source=readFileSync(new URL('../app/entry/src/main/ets/model/ComposerDocument.ets',import.meta.url),'utf8');
const m=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
const skills=[{insertion:'$review',label:'代码审查',icon:'skill'}];
test('references and skills become atomic chips while serialized drafts preserve exact provider syntax',()=>{
 const text='看看 [目标任务](t3-thread://v1/abc) 和 [中文.md](docs/%E4%B8%AD%E6%96%87.md) $review 后缀';
 const spans=m.composerSpans(text,skills);
 assert.deepEqual(spans.filter(s=>s.kind!=='text').map(s=>[s.kind,s.label]),[['thread','目标任务'],['file','中文.md'],['skill','代码审查']]);
 assert.equal(m.composerRawText(spans),text);
 assert.equal(m.composerRawOffset(spans,4),text.indexOf(' 和'));
 assert.equal(m.composerViewOffset(spans,text.indexOf(' 和')),4);
 assert.equal(m.composerSpans('https://site.test $HOME [site](https://site.test)',skills).filter(s=>s.kind!=='text').length,0);
});
test('typing and deleting next to chips preserve their raw links and a backspace removes the whole reference',()=>{
 const spans=m.composerSpans('甲[任务](t3-thread://v1/id)乙 $review',skills);
 const typed=m.editComposerSpans(spans,2,2,'你好');
 assert.equal(m.composerRawText(typed),'甲[任务](t3-thread://v1/id)你好乙 $review');
 assert.equal(typed.filter(s=>s.kind==='thread').length,1);
 const deleted=m.editComposerSpans(typed,1,2,'');
 assert.equal(m.composerRawText(deleted),'甲你好乙 $review');
 const replaced=m.editComposerSpans(typed,1,6,'替换');
 assert.equal(m.composerRawText(replaced),'甲替换$review');
});
test('selection, cut and paste round-trip emoji, Chinese, escaped filenames and multiple chips',()=>{
 const text='😀[a\\[1\\].md](docs/a%5B1%5D.md) $review 结束';
 const spans=m.composerSpans(text,skills);
 assert.equal(spans.find(s=>s.kind==='file').label,'a[1].md');
 const from=m.composerRawOffset(spans,2),to=m.composerRawOffset(spans,5);
 const copied=text.slice(from,to);
 assert.equal(copied,'[a\\[1\\].md](docs/a%5B1%5D.md) $review');
 const cut=m.editComposerSpans(spans,2,5,'');
 const pasted=m.editComposerSpans(cut,2,2,copied);
 assert.equal(m.composerRawText(pasted),text);
 assert.equal(m.composerRawText(m.composerSpans(m.composerRawText(pasted),skills)),text);
});

test('sent-message skill labels reuse the catalog while literal code and ordinary dollar text remain unchanged',()=>{
 const text='请用 $review 检查，保留 $HOME 和 [说明](README.md)\n😀 $review';
 const spans=m.messageSkillSpans(text,skills);
 assert.deepEqual(spans.filter(s=>s.kind==='skill').map(s=>s.label),['代码审查','代码审查']);
 assert.equal(m.composerRawText(spans),text);
 assert.ok(spans.some(s=>s.raw==='$HOME 和 '||s.raw.includes('$HOME')));
 assert.equal(spans.filter(s=>s.kind==='file').length,0);
 assert.deepEqual(m.messageSkillSpans('$review',skills,true).map(s=>s.kind),['text']);
 assert.equal(m.composerRawText(m.messageSkillSpans('$review',[],false)),'$review');
});

test('PC thread references stay distinct from following text, skills and attachment labels',()=>{
 const text='[Review Linux 媒体组件与 Util 发布](t3-context://v1/thread/thread_source) 继续 $review';
 const spans=m.messageReferenceSpans(text,skills);
 assert.deepEqual(spans.filter(s=>s.kind==='thread').map(s=>[s.label,s.href]),
  [['Review Linux 媒体组件与 Util 发布','t3-context://v1/thread/thread_source']]);
 assert.equal(spans.find(s=>s.kind==='text').raw,' 继续 ');
 assert.equal(m.composerRawText(spans),text);
 assert.deepEqual(m.messageReferenceSpans(text,skills,true).map(s=>s.kind),['text']);
 assert.equal(m.composerSpans('[Task](t3-thread://v2/mac/thread)',[])[0].kind,'thread');
});

test('thread reference syntax inside inline code and fenced examples remains literal',()=>{
 const text='`[Example](t3-thread://v2/mac/example)`\n```md\n[Example](t3-context://v1/thread/example)\n```\n[Live](t3-thread://v2/mac/live)';
 const spans=m.messageReferenceSpans(text,[]);
 assert.deepEqual(spans.filter(s=>s.kind==='thread').map(s=>s.label),['Live']);
 assert.equal(m.composerRawText(spans),text);
});
