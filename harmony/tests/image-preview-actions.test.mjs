import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
const read = p => readFileSync(new URL('../app/entry/src/main/ets/' + p, import.meta.url), 'utf8');
const src = read('pages/ImagePreview.ets');
const methods = src.slice(src.indexOf('  private resetZoom('), src.indexOf('  @Builder\n  private icon(')).replaceAll('private ', '');
const { Page, mocks, imageRatios, imageNoteText } = await import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(`
${read('model/ImageEdits.ets')}
${src.slice(src.indexOf('const TOOLBAR_INSET'),src.indexOf('interface ImageToolChoice'))}
export const mocks={returns:[],renders:[],deleted:[],next:0};
const router={back:args=>mocks.returns.push(args)},getContext=()=>({filesDir:'/private'}),util={generateRandomUUID:()=>crypto.randomUUID()};
const fs={unlink:async path=>mocks.deleted.push(path)},TouchType={Down:0,Move:1,Up:2,Cancel:3};
const ImageEditor={render:async (source,strokes,size)=>{mocks.renders.push({source,strokes,size});return new ArrayBuffer(1);},writeCopy:async()=> '/private/image-edits/'+ ++mocks.next+'.png'};
export class Page {
  headerY=0;toolbarRoom=0;controlsX=0;controlsY=0;controlsWidth=0;
  zoom=1;offsetX=0;offsetY=0;viewportWidth=400;viewportHeight=600;aspect=1;annotating=false;erasing=false;busy=false;active=true;imageReady=true;penColor='#EF4444';editRevision=0;stroke=null;
  commenting=false;panel='';comment='';explanation='';noteIndex=-1;noteX=0;noteY=0;markTool='pen';penWidth=3;eraseWidth=28;markEraserWidth=18;selectedMark=-1;gestureChanged=false;gestureStart=null;selectionSource=null;resizeCorner=-1;toolMenu='';textSize=24;textIndex=-1;
  source='original';name='图.png';commentThreadId='thread';environmentId='env';draftScope='';gallery=[{}];imageIndex=0;
  doc=emptyImageEdits();canvas={width:400,height:400,clearRect(){},beginPath(){},moveTo(){},lineTo(){},stroke(){},setLineDash(){},strokeRect(){},fillRect(){},fillText(){},measureText(text){return{width:text.length*12}}};
  imageDrafts=new Map();extraDraftId=util.generateRandomUUID();extraImages=[];extrasBusy=false;extraStore=null;
  reload(){this.source=this.name=this.gallery[this.imageIndex].name;}
  edits(){return this.doc;}
  ${src.slice(src.indexOf('  onBackPress()'),src.indexOf('  private edits()'))}
  ${src.slice(src.indexOf('  private selectImage('),src.indexOf('  private resetZoom(')).replaceAll('private ', '')}
  ${methods}
}
`)).toString('base64'));
const down=(p,x,y)=>p.draw({type:0,touches:[{x,y}],stopPropagation(){}});
const move=(p,x,y)=>p.draw({type:1,touches:[{x,y}],stopPropagation(){}});
const up=p=>p.draw({type:2,touches:[],stopPropagation(){}});

test('annotations and erase masks undo and redo independently without deleting original marks',()=>{
 const p=new Page();p.editTool(false);down(p,20,20);move(p,80,80);up(p);
 assert.equal(p.doc.strokes.length,1);p.undo();assert.equal(p.doc.strokes.length,0);assert.equal(p.canUndo(true),true);
 p.undo(true);assert.equal(p.doc.strokes[0].points.length,2);
 p.editTool(true);down(p,100,100);move(p,160,100);up(p);
 assert.equal(p.doc.masks.length,1);assert.equal(p.doc.strokes.length,1);assert.equal(p.doc.masks[0].color,'#803B82F6');
 p.undo();assert.equal(p.doc.masks.length,0);assert.equal(p.doc.strokes.length,1);
 p.undo(true);assert.equal(p.doc.masks[0].points.length,2);
 p.editTool(false);p.undo();assert.equal(p.doc.strokes.length,0);assert.equal(p.doc.masks.length,1);
 p.editTool(true);p.undo();down(p,240,240);up(p);assert.equal(p.canUndo(true),false);
});
test('the undo limit retains recent actions and a new stroke invalidates redo only in its own layer',()=>{
 const p=new Page();p.editTool(false);for(let i=0;i<60;i++){down(p,i,i);up(p);}assert.equal(p.doc.history.length,50);
 p.undo();p.editTool(true);down(p,0,0);up(p);assert.equal(p.doc.future.length,1);
 p.editTool(false);down(p,100,100);up(p);assert.equal(p.doc.future.length,0);
});
test('background removal and every ratio create actual image requests with the original included',async()=>{
 mocks.returns=[];mocks.renders=[];const p=new Page();p.doc.width=100;p.doc.height=100;
 await p.returnImage('send','移除背景');
 let r=mocks.returns.at(-1);assert.equal(r.params.threadId,'thread');assert.equal(JSON.parse(r.params.imageComment).action,'send');assert.equal(mocks.renders.at(-1).source,'original');
 for(const ratio of imageRatios()) {p.resizeImage(ratio);await new Promise(resolve=>setImmediate(resolve));assert.match(JSON.parse(mocks.returns.at(-1).params.imageComment).text,new RegExp(ratio.value));}
});
test('erase requests export both the original and selection overlay and remain inert without a selection',async()=>{
 mocks.returns=[];mocks.renders=[];const p=new Page();p.doc.width=100;p.doc.height=100;
 p.eraseSelection();assert.equal(mocks.returns.length,0);
 p.editTool(true);down(p,10,10);up(p);p.eraseSelection();await new Promise(resolve=>setImmediate(resolve));
 const r=JSON.parse(mocks.returns.at(-1).params.imageComment);assert.ok(r.maskUri);assert.match(r.text,/蓝色/);
 assert.equal(mocks.renders.at(-2).strokes.length,0);assert.equal(mocks.renders.at(-1).strokes.length,1);
});
test('draft and queued images return editable requests instead of sending, and applying marks replaces only their target',async()=>{
 for(const scope of ['', 'queued-run']) {
  const p=new Page();p.doc.width=100;p.doc.height=100;p.draftScope=scope;p.gallery=[{draftTarget:'selected'}];
  await p.returnImage('send','移除背景');let r=mocks.returns.at(-1);assert.equal(r.params.draftScope,scope);
  let value=JSON.parse(r.params.imageComment);assert.equal(value.action,'draft');assert.equal(value.target,'selected');
  await p.returnImage('replace','');value=JSON.parse(mocks.returns.at(-1).params.imageComment);assert.equal(value.action,'replace');assert.equal(value.target,'selected');
 }
});

test('point comments record image-relative coordinates, save edits in place and delete only the chosen note',()=>{
 const p=new Page();p.commenting=true;down(p,175.2,178);assert.equal(p.panel,'comment');assert.equal(p.notes().length,0);
 p.comment=' 测试 ';p.saveNote();assert.equal(p.notes().length,1);assert.ok(Math.abs(p.notes()[0].x-0.438)<1e-12);assert.equal(p.notes()[0].y,0.445);assert.equal(p.notes()[0].text,'测试');
 assert.equal(imageNoteText(p.notes()),'图像 1：\n1.（x：43.8%，y：44.5%）测试');
 p.beginNote(0.438,0.445,0);p.comment='修改';p.saveNote();assert.equal(p.notes().length,1);assert.equal(p.notes()[0].text,'修改');
 p.beginNote(0.8,0.8);p.comment='第二条';p.saveNote();p.beginNote(0.438,0.445,0);p.deleteNote();assert.equal(p.notes()[0].text,'第二条');
});
test('saved point comments remain in the sent request after switching to annotation',async()=>{
 for(const drawMark of [false,true]) {
  mocks.returns=[];mocks.renders=[];
  const p=new Page();p.doc.width=100;p.doc.height=100;p.commenting=true;
  p.beginNote(0.3,0.4);p.comment='修复这里';p.saveNote();p.commenting=false;p.editTool(false);
  if(drawMark) {down(p,20,20);up(p);p.explanation='保留主体';}
  assert.equal(p.canSendEdits(),true);p.sendEdits();await new Promise(resolve=>setImmediate(resolve));
  const request=JSON.parse(mocks.returns.at(-1).params.imageComment);
  assert.equal(request.text,'图像 1：\n1.（x：30.0%，y：40.0%）修复这里'+(drawMark?'\n\n保留主体':''));
  assert.equal(mocks.renders.at(-1).strokes.length,drawMark?1:0);
 }
});
test('unsaved or cancelled point comments do not change existing notes or mark up the image',()=>{
 const p=new Page();p.commenting=true;p.beginNote(0.5,0.5);p.comment='';p.saveNote();assert.equal(p.notes().length,0);
 p.comment='未保存';p.panel='';assert.equal(p.notes().length,0);assert.equal(p.doc.strokes.length,0);assert.equal(p.doc.masks.length,0);
});
test('either drag stops short of the other bar using the visible space, including a changing footer',()=>{
 const p=new Page();p.controlsWidth=320;
 // The emulator's at-rest glass edges were 318px and 2231px at 3.5px/vp.
 const top=318/3.5;let bottom=2231/3.5;p.toolbarRoom=bottom-top;
 const gap=()=>bottom+p.controlsY-(top+p.headerY);
 p.moveHeader(2000);assert.ok(gap()>=11.9 && gap()<=12.1);assert.equal(p.controlsY,0);
 p.moveHeader(80);p.moveControls(500,-2000);assert.ok(gap()>=11.9 && gap()<=12.1);assert.equal(p.headerY,80);assert.equal(p.controlsX,28);
 p.moveControls(-500,200);assert.equal(p.controlsY,0);assert.equal(p.controlsX,-28);
 p.moveHeader(2000);bottom-=180;p.toolbarRoom=bottom-top;p.fitToolbars();assert.ok(gap()>=11.9 && gap()<=12.1);
 p.moveHeader(0);p.moveControls(0,-2000);bottom=top+30;p.toolbarRoom=bottom-top;p.fitToolbars();assert.ok(gap()>=11.9 && gap()<=12.1);
 p.toolbarRoom=5;p.fitToolbars();assert.equal(p.controlsY,0);assert.equal(p.headerY,0);
});
test('pen and erase widths are independent, survive tool switches and are captured in each stroke',()=>{
 const p=new Page();p.editTool(false);p.setBrushWidth(11);down(p,20,20);up(p);
 assert.equal(p.doc.strokes[0].width,11/400);
 p.editTool(true);p.setBrushWidth(54);down(p,20,20);up(p);assert.equal(p.doc.masks[0].width,54/400);
 p.editTool(false);assert.equal(p.brushWidth(),11);p.editTool(true);assert.equal(p.brushWidth(),54);
});
test('image send becomes available for a drawn erase mask and follows undo, redo and busy state',()=>{
 const p=new Page();p.editTool(true);assert.equal(p.canSendEdits(),false);
 down(p,20,20);up(p);assert.equal(p.canSendEdits(),true);
 p.undo();assert.equal(p.canSendEdits(),false);p.undo(true);assert.equal(p.canSendEdits(),true);
 p.extrasBusy=true;assert.equal(p.canSendEdits(),false);p.extrasBusy=false;
 p.imageReady=false;assert.equal(p.canSendEdits(),false);p.imageReady=true;
 p.busy=true;assert.equal(p.canSendEdits(),false);
});
test('the image composer cannot submit an empty comment through its keyboard shortcut',()=>{
 const p=new Page();let submitted=0;p.returnImage=()=>{submitted++};p.commenting=true;
 p.sendEdits();assert.equal(submitted,0);
 p.explanation='图片说明';p.sendEdits();assert.equal(submitted,1);
 p.busy=true;p.sendEdits();assert.equal(submitted,1);
});
test('shape, text, selection movement and mark erasure participate in the annotation undo history',()=>{
 const p=new Page();p.editTool(false);p.markTool='rectangle';down(p,40,40);move(p,160,160);up(p);
 assert.equal(p.doc.strokes[0].points.length,5);
 p.markTool='select';down(p,40,100);move(p,80,100);up(p);assert.equal(p.doc.strokes[0].points[0].x,0.2);
 p.undo();assert.equal(p.doc.strokes[0].points[0].x,0.1);
 p.markTool='text';down(p,240,240);assert.equal(p.panel,'text');p.comment='标注说明';p.saveText();
 assert.equal(p.doc.strokes[1].text,'标注说明');
 p.markTool='eraser';down(p,260,245);up(p);assert.equal(p.doc.strokes.length,1);
 p.undo();assert.equal(p.doc.strokes[1].text,'标注说明');
});

function galleryWithReference() {
 const p=new Page();p.gallery=[{name:'A.png'},{name:'B.png'}];p.doc.width=100;p.doc.height=100;
 addReference(p,'A');return p;
}
function addReference(page,label) {
 const uri=label.toLowerCase();page.explanation=`instructions ${label}`;
 page.extraStore={images:[{uri,uploaded:{id:`ref-${label}`}}]};page.extraImages=[{uri,status:'uploaded'}];
}
test('a background removal on the next image does not include the previous image’s attachments',async()=>{
 const p=galleryWithReference();const aId=p.extraDraftId;p.selectImage(1);
 assert.equal(p.explanation,'');assert.equal(p.extraImages.length,0);assert.notEqual(p.extraDraftId,aId);
 p.removeBackground();await new Promise(setImmediate);
 const draft=JSON.parse(mocks.returns.at(-1).params.imageComment);assert.equal(draft.name,'B-编辑.png');assert.equal(draft.extras,undefined);
});
for(const [index,label] of [[0,'A'],[1,'B']]) test(`returning to image ${label} restores its own explanation and references`,async()=>{
 const p=galleryWithReference(),aId=p.extraDraftId;p.selectImage(1);addReference(p,'B');const bId=p.extraDraftId;
 p.selectImage(0);if(index===1)p.selectImage(1);
 assert.equal(p.extraImages[0].uri,label.toLowerCase());p.sendEdits();await new Promise(setImmediate);
 const draft=JSON.parse(mocks.returns.at(-1).params.imageComment);assert.equal(draft.name,`${label}-编辑.png`);
 assert.equal(draft.text,`instructions ${label}`);assert.equal(draft.attachmentDraftId,index===0?aId:bId);
 assert.deepEqual(draft.extras.map(e=>e.uploaded.id),[`ref-${label}`]);
});
test('system Back hides the erase overlay immediately, preserving real marks and the editable mask',()=>{
 const p=new Page();let colors=[];p.canvas.clearRect=()=>{colors=[]};p.canvas.stroke=()=>colors.push(p.canvas.strokeStyle);
 p.editTool(false);down(p,10,10);up(p);p.editTool(true);down(p,40,40);move(p,80,80);up(p);
 assert.ok(colors.includes('#803B82F6'));assert.equal(p.onBackPress(),true);assert.equal(p.erasing,false);
 assert.deepEqual(colors,[p.penColor]);p.editTool(true);assert.ok(colors.includes('#803B82F6'));
});
