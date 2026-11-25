import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
const source=readFileSync(new URL('../app/entry/src/main/ets/model/ImageEdits.ets',import.meta.url),'utf8');
const edits=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(source)).toString('base64'));

test('shape tools produce normalized outlines inside the selected rectangle',()=>{
 for(const kind of ['rectangle','ellipse','triangle','diamond','star','heart']) {
  const points=edits.imageShapePoints(kind,{x:0.8,y:0.7},{x:0.2,y:0.1});
  assert.ok(points.length>=4,kind);assert.deepEqual(points[0],points.at(-1),kind);
  for(const point of points) {assert.ok(point.x>=0.2-1e-10&&point.x<=0.8+1e-10,kind);assert.ok(point.y>=0.1-1e-10&&point.y<=0.7+1e-10,kind);}
 }
 const arrow=edits.imageShapePoints('arrow',{x:0.2,y:0.1},{x:0.8,y:0.7});
 assert.deepEqual(arrow.slice(0,2),[{x:0.2,y:0.1},{x:0.8,y:0.7}]);assert.equal(arrow.length,5);
});
test('select and erase hit visible line segments rather than empty areas within their bounds',()=>{
 const line={color:'#F00',width:0.01,points:[{x:0.1,y:0.1},{x:0.9,y:0.9}]};
 assert.equal(edits.imageStrokeAt([line],{x:0.5,y:0.5},0.01),0);
 assert.equal(edits.imageStrokeAt([line],{x:0.1,y:0.9},0.01),-1);
 assert.equal(edits.imageStrokeAt([line,{...line,color:'#00F'}],{x:0.5,y:0.5},0.01),1);
});
test('moving and resizing a selected mark is bounded and preserves undo snapshots',()=>{
 const original={color:'#F00',width:0.01,points:[{x:0.1,y:0.1},{x:0.5,y:0.5}]};
 const before=edits.copyStrokes([original]);
 const moved=edits.moveImageStroke(original,0.8,-0.8);
 assert.deepEqual(moved.points,[{x:0.6,y:0},{x:1,y:0.4}]);
 const resized=edits.resizeImageStroke(original,{left:0.2,top:0.2,right:0.8,bottom:0.9});
 assert.deepEqual(resized.points[0],{x:0.2,y:0.2});assert.ok(Math.abs(resized.points[1].y-0.9)<1e-10);
 moved.points[0].x=0;assert.deepEqual(before[0].points,original.points);
});
test('text bounds, movement and resizing retain the content and scale the font',()=>{
 const text={kind:'text',color:'#F00',width:0.01,fontSize:0.05,text:'hello\nworld',textWidth:0.2,points:[{x:0.2,y:0.3}]};
 assert.equal(edits.imageStrokeAt([text],{x:0.3,y:0.34},0.01),0);
 const bounds=edits.imageStrokeBounds(text);assert.equal(bounds.left,0.2);assert.ok(bounds.bottom>bounds.top);
 const resized=edits.resizeImageStroke(text,{left:0.1,top:0.1,right:0.5,bottom:0.34});
 assert.equal(resized.text,text.text);assert.ok(resized.fontSize>text.fontSize);assert.equal(resized.textWidth,0.4);
});
