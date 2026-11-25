import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
const source=readFileSync(new URL('../app/entry/src/main/ets/connection/ImageEditor.ets', import.meta.url),'utf8').replace(/^import .*;$/gm,'');
const { ImageEditor, mocks } = await import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(`
export const mocks={written:[],closed:0,limit:3,noProgress:false,paths:[],scales:[],releases:0,colors:[],texts:[]};
const fs={OpenMode:{CREATE:1,WRITE_ONLY:2,TRUNC:4},open:async()=>({fd:1}),close:async()=>{mocks.closed++;},
  write:async(fd,bytes)=>{if(mocks.noProgress)return 0;const data=new Uint8Array(bytes),count=Math.min(mocks.limit,data.length);mocks.written.push(...data.slice(0,count));return count;}};
const pixels={getImageInfo:async()=>({size:{width:100,height:50}}),scale:async(...args)=>mocks.scales.push(args),release:async()=>{mocks.releases++;}};
const drawing={Font:class{setSize(size){this.size=size}},TextBlob:{makeFromString:(text,font)=>({text,size:font.size})},Brush:class{setAntiAlias(){}setColor(){}},
 Canvas:class{attachBrush(){}detachBrush(){}drawTextBlob(blob,x,y){mocks.texts.push({...blob,x,y})}attachPen(){}detachPen(){}drawPath(path){mocks.paths.push(path.points);}},Pen:class{setAntiAlias(){}setCapStyle(){}setJoinStyle(){}setColor(value){mocks.colors.push(value);}setStrokeWidth(){}},
 Path:class{points=[];moveTo(...args){this.points.push(args);}lineTo(...args){this.points.push(args);}},CapStyle:{ROUND_CAP:1},JoinStyle:{ROUND_JOIN:1}};
const image={createImagePacker:()=>({packing:async()=>new Uint8Array([1,2]).buffer,release:async()=>{}})};

${source}
ImageEditor.decode=async()=>pixels;
`)).toString('base64'));

test('saving retries partial writes until every byte is stored and closes the destination',async()=>{
  mocks.written=[];mocks.closed=0;await ImageEditor.write('/copy.png',new Uint8Array([1,2,3,4,5,6,7]).buffer);
  assert.deepEqual(mocks.written,[1,2,3,4,5,6,7]);assert.equal(mocks.closed,1);
});
test('a stalled save fails rather than looping and still closes its file',async()=>{
  mocks.noProgress=true;const closed=mocks.closed;
  try {await assert.rejects(ImageEditor.write('/copy.png',new Uint8Array([1]).buffer),/保存未完成/);assert.equal(mocks.closed,closed+1);}
  finally {mocks.noProgress=false;}
});
test('export scales the source and paints normalized marks at the output dimensions, then releases pixels',async()=>{
  const released=mocks.releases;mocks.paths=[];
  await ImageEditor.render('file:///source.png',[{color:'#FF0000',width:0.01,points:[{x:0.1,y:0.2},{x:0.9,y:0.8}]}],{width:200,height:100});
  assert.deepEqual(mocks.scales.at(-1),[2,2]);assert.deepEqual(mocks.paths,[[[20,20],[180,80]]]);assert.equal(mocks.releases,released+1);
});
test('export preserves the translucent blue selection colour without changing annotation colours',async()=>{
  mocks.colors=[];
  await ImageEditor.render('source',[{color:'#803B82F6',width:0.1,points:[{x:0,y:0}]},{color:'#EF4444',width:0.01,points:[{x:1,y:1}]}],{width:100,height:50});
  assert.deepEqual(mocks.colors,[0x803B82F6,0xFFEF4444]);
});
test('text annotations export as real multiline text at the same normalized position and size as the preview',async()=>{
 mocks.texts=[];
 await ImageEditor.render('source',[{kind:'text',text:'说明\n第二行',fontSize:0.1,color:'#EF4444',width:0.01,points:[{x:0.2,y:0.3}]}],{width:200,height:100});
 assert.deepEqual(mocks.texts,[{text:'说明',size:10,x:40,y:40},{text:'第二行',size:10,x:40,y:52}]);
});
