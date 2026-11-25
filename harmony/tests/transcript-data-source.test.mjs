import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';

const source=readFileSync(new URL('../app/entry/src/main/ets/pages/TranscriptDataSource.ets',import.meta.url),'utf8').replace(/^import .*;$/gm,'');
const {TranscriptDataSource}=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
const row=(id,text=id)=>({id,kind:'message',role:'assistant',text,createdAt:'',detail:'',status:''});
function mountedList(data){
 const visible=new Map();const events=[];const cached=new Map();
 const render=index=>{
  const entry=data.getData(index);const key=data.key?.(entry)??entry.id;
  if(!cached.has(key))cached.set(key,entry);
  visible.set(index,cached.get(key));
 };
 const listener={
  onDataReloaded(){events.push('reload');visible.clear();for(let i=0;i<data.totalCount();i++)render(i);},
  onDataAdd(index){events.push(['add',index]);render(index);},
  onDataChange(index){events.push(['change',index]);render(index);}
 };
 data.registerDataChangeListener(listener);return {visible,events,listener};
}
test('an initially empty mounted list renders its first cached or synchronized history',()=>{
 const data=new TranscriptDataSource();const list=mountedList(data);
 assert.equal(data.totalCount(),0);
 data.update(Array.from({length:500},(_,index)=>row(String(index))));
 assert.deepEqual(list.events,['reload']);assert.equal(list.visible.size,500);
 assert.equal(list.visible.get(499).id,'499');
});
test('sent messages and existing reasoning refresh in the same mounted list while unchanged history is retained',()=>{
 const data=new TranscriptDataSource();const list=mountedList(data);const first=row('old');
 data.update([first,row('thought','Inspecting')]);list.events.length=0;
 data.update([first,row('thought','Inspecting the newest result'),row('sent','New message')]);
 assert.deepEqual(list.events,[['change',1],['add',2]]);
 assert.equal(list.visible.get(0),first);assert.equal(list.visible.get(1).text,'Inspecting the newest result');
 assert.equal(list.visible.get(2).text,'New message');
 list.events.length=0;data.update([first,list.visible.get(1),list.visible.get(2)]);
 assert.deepEqual(list.events,[]);
});
test('canonical reorder, folding and listener disposal cannot leave old rows on screen',()=>{
 const data=new TranscriptDataSource();const list=mountedList(data);
 data.update([row('tool'),row('reply')]);list.events.length=0;
 data.update([row('tool'),row('question'),row('reply')]);
 assert.deepEqual(list.events,['reload']);assert.equal(list.visible.get(1).id,'question');
 data.update([row('folded')]);assert.equal(list.visible.size,1);
 data.unregisterDataChangeListener(list.listener);list.events.length=0;data.update([row('new')]);
 assert.deepEqual(list.events,[]);
});

test('a keyed mounted list renders successive tokens and process updates without replacing unchanged history',()=>{
 const data=new TranscriptDataSource();const list=mountedList(data);const history=row('history');
 data.update([history,row('reply','First token'),row('process','Running one command')]);
 const retained=list.visible.get(0);list.events.length=0;
 for(let n=2;n<=4;n++){
  data.update([history,row('reply',`Token ${n}`),row('process',`Ran ${n} commands`)]);
  assert.equal(list.visible.get(1).text,`Token ${n}`);
  assert.equal(list.visible.get(2).text,`Ran ${n} commands`);
  assert.equal(list.visible.get(0),retained);
 }
 assert.ok(!list.events.includes('reload'));
 data.update([row('reply','Final answer'),history]);
 assert.equal(list.visible.get(0).text,'Final answer');
 assert.equal(list.visible.get(1),retained);
});
