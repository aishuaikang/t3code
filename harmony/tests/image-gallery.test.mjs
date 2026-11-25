import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
const read = p => readFileSync(new URL('../app/entry/src/main/ets/' + p, import.meta.url), 'utf8');
const load = s => import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(s)).toString('base64'));
const gallery = await load(read('model/ImageGallery.ets').replace(/^import .*;$/gm, ''));
const edits = await load(read('model/ImageEdits.ets'));

test('a gallery retains image order, skips files and opens the tapped image with bounded navigation', () => {
  const images = gallery.attachmentGallery([{type:'image',id:'a',name:'甲.png'}, {type:'file',id:'f',name:'文档.pdf'}, {type:'image',id:'b',name:'乙.jpg'}]);
  assert.deepEqual(images.map(i => i.attachmentId), ['a', 'b']);
  assert.equal(gallery.previewGallery({gallery:JSON.stringify(images), imageIndex:'1'}).index, 1);
  assert.equal(gallery.previewGallery({gallery:JSON.stringify(images), imageIndex:'99'}).index, 1);
  assert.equal(gallery.imageStep(0, 2, -1), 0); assert.equal(gallery.imageStep(1, 2, 1), 1);
  assert.equal(gallery.previewGallery({gallery:'bad',attachmentId:'a',name:'甲.png'}).images[0].attachmentId, 'a');
});
test('tool-image galleries retain their original source thread', () => {
  assert.deepEqual(gallery.viewedImageGallery([{path:'C:\\图片\\甲.png',threadId:'origin'}, {path:'/b.png',threadId:''}], 'current'),
    [{name:'甲.png',mediaPath:'C:\\图片\\甲.png',mediaThreadId:'origin'}, {name:'b.png',mediaPath:'/b.png',mediaThreadId:'current'}]);

});
test('image documents are independent and undo snapshots do not change with subsequent drawing', () => {
  const first = edits.emptyImageEdits(), second = edits.emptyImageEdits();
  first.strokes.push({color:'#FF0000',width:0.01,points:[{x:0,y:0}]});
  const snapshot = edits.copyStrokes(first.strokes); first.strokes[0].points.push({x:1,y:1});
  assert.equal(snapshot[0].points.length, 1); assert.equal(second.strokes.length, 0);
});
test('the resize menu offers the reference aspect ratios and comments preserve existing drafts', () => {
  assert.deepEqual(edits.imageRatios().map(ratio => [ratio.label, ratio.value]), [['正方形','1:1'],['竖向','3:4'],['故事版式','9:16'],['横向','4:3'],['宽屏','16:9']]);
  assert.equal(edits.appendImageComment('已有草稿', '图片.png', '  看这里  '), '已有草稿\n\n[图片评论：图片.png]\n看这里');
});
test('comment returns accept only application-created copies, with valid content and identifiers', () => {
  const id='12345678-1234-1234-1234-123456789012';
  const draft={id,uri:`/private/image-edits/${id}.png`,name:'图片.png',text:'看这里'};
  assert.deepEqual(edits.parseImageComment(JSON.stringify(draft), '/private'), draft);
  for (const change of [{uri:'/other/image-edits/'+id+'.png'}, {uri:'/private/image-edits/../secret.png'}, {text:' '}, {id:'bad'}]) {
    assert.equal(edits.parseImageComment(JSON.stringify({...draft,...change}), '/private'), null);
  }
});

test('odd galleries span the last photo across the final row without a blank half or extra margin',()=>{
 for(const count of [5,7]){
  const first=gallery.attachmentTileLayout(count,0,320),last=gallery.attachmentTileLayout(count,count-1,320);
  assert.equal(first.width,159);assert.equal(first.right,2);assert.equal(first.bottom,2);
  assert.equal(last.width,320);assert.equal(last.right,0);assert.equal(last.bottom,0);
  assert.equal(last.width/last.aspect,first.width/first.aspect);
 }
 for(const count of [2,4,6]){
  const last=gallery.attachmentTileLayout(count,count-1,320);
  assert.equal(last.width,159);assert.equal(last.right,0);assert.equal(last.bottom,0);
 }
 assert.deepEqual(gallery.attachmentTileLayout(1,0,320),{width:320,aspect:0,right:0,bottom:0});
});
