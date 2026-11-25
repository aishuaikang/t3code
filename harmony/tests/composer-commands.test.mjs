import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const source=readFileSync(new URL('../app/entry/src/main/ets/model/ComposerCommands.ets',import.meta.url),'utf8');
const m=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
test('menu shortcuts insert at the caret without consuming surrounding draft text',()=>{
 assert.deepEqual(m.insertComposerTrigger('前文后文',2,2,'@'),{text:'前文 @ 后文',cursor:4});
 assert.deepEqual(m.insertComposerTrigger('keep selected tail',5,13,'/'),{text:'keep / tail',cursor:6});
 assert.deepEqual(m.insertComposerTrigger('',0,0,'/'),{text:'/',cursor:1});
});
test('slash suggestions follow the selected provider and workspace, hide disabled skills and deduplicate commands',()=>{
 const catalog=m.commandCatalog([{instanceId:'a',slashCommands:[{name:'/review',description:'Review changes'}],skills:[{name:'hidden',enabled:true,userInvocable:false},{name:'off',enabled:false}],workspaceSnapshots:[{cwd:'/work',slashCommands:[{name:'compact'},{name:'review',description:'Local review'}],skills:[{name:'local',enabled:true}]}]},{instanceId:'b',slashCommands:[{name:'other'}]}]);
 const local=m.commandsFor(catalog,'a','/work');assert.equal(local.filter(c=>c.name==='review').length,1);
 assert.ok(local.some(c=>c.name==='skill:local'));assert.ok(!local.some(c=>['hidden','off','other'].includes(c.name)));
 assert.ok(!m.commandsFor(catalog,'a','/elsewhere').some(c=>c.name==='skill:local'));
 assert.equal(m.commandSuggestions('/rev',4,4,local)[0].name,'review');
 assert.ok(m.commandSuggestions('/',1,1,local).some(c=>c.name==='compact'));
});
test('menu preserves all workspace commands, uses skill labels and inserts provider skill syntax',()=>{
 const skills=Array.from({length:30},(_,i)=>({name:`skill-${i}`,enabled:true}));
 const catalog=m.commandCatalog([{instanceId:'p',slashCommands:[{name:'skill-0'},{name:'review'}],skills}]);
 const commands=m.commandsFor(catalog,'p','/work');
 assert.equal(m.commandSuggestions('/',1,1,commands).length,35);
 assert.ok(!commands.some(c=>c.name==='skill-0'));
 const skill=commands.find(c=>c.name==='skill:skill-29');
 assert.deepEqual(m.insertCommand('/skill:skill-29 argument',15,15,skill),{text:'$skill-29 argument',cursor:10});
 assert.ok(commands.some(c=>c.name==='model'));assert.ok(commands.some(c=>c.name==='clear'));
 assert.ok(commands.some(c=>c.name==='side'));assert.ok(commands.some(c=>c.name==='btw'));
 assert.ok(!m.commandsFor(catalog,'p','/work',false).some(c=>['clear','side','btw'].includes(c.name)));
 assert.ok(!m.commandsFor(catalog,'p','/work',true,false).some(c=>['side','btw'].includes(c.name)));
 const model=commands.find(c=>c.name==='model');
 assert.deepEqual(m.insertCommand('/model preserved',6,6,model),{text:'preserved',cursor:0});
});
test('slash insertion preserves text and arguments, and never triggers inside paths or URLs',()=>{
 for(const text of ['https://example.test/','/work/file',' /compact already'])assert.equal(m.commandSuggestions(text,text.length,text.length,[{name:'compact'}]).length,0);
 assert.equal(m.commandSuggestions('/c',0,2,[{name:'compact'}]).length,0);
 const inserted=m.insertCommand('/com more text',4,4,{name:'compact'});
 assert.deepEqual(inserted,{text:'/compact more text',cursor:9});
 assert.deepEqual(m.insertCommand('/',1,1,{name:'compact'}),{text:'/compact ',cursor:9});
});
test('commands open at the caret in the middle of a draft, including directly after Chinese text',()=>{
 const commands=[{name:'compact'},{name:'review',kind:'skill',insertion:'$review'}];
 for(const text of ['hello /','请/','前文\n这里／'])assert.equal(m.commandSuggestions(text,text.length,text.length,commands).length,2);
 const text='请/comp 后面的内容';
 assert.equal(m.commandSuggestions(text,4,4,commands)[0].name,'compact');
 assert.deepEqual(m.insertCommand(text,4,4,commands[0]),{text:'请/compact 后面的内容',cursor:10});
 assert.equal(m.commandQuery('说明/审查 后面',5,5),'审查');
 for(const text of ['https://example.test/rev','../review','/src/review','[x](t3-thread://v1/id)'])assert.equal(m.commandQuery(text,text.length,text.length),null);
});

test('Chinese keywords and full-width slash find actual provider commands and insert their original syntax',()=>{
 const catalog=m.commandCatalog([{instanceId:'p',slashCommands:[{name:'compact',description:'Compact context'},{name:'review',description:'Review changes'}],skills:[{name:'检查质量',enabled:true,description:'分析中文项目'}]}]);
 const commands=m.commandsFor(catalog,'p','/work');
 assert.deepEqual(m.commandSuggestions('/压缩',3,3,commands).map(c=>c.name),['compact']);
 const review=m.commandSuggestions('／审查',3,3,commands);
 assert.deepEqual(review.map(c=>c.name),['review']);assert.deepEqual(m.insertCommand('／审查',3,3,review[0]),{text:'/review ',cursor:8});
 assert.equal(m.commandSuggestions('/模型',3,3,commands)[0].kind,'model');
 assert.equal(m.commandSuggestions('／中文',3,3,commands)[0].name,'skill:检查质量');
 assert.deepEqual(m.commandSuggestions('/费用',3,3,commands),[]);
});

test('slash skills match Chinese names, full descriptions and review aliases without changing the inserted command',()=>{
 const catalog=m.commandCatalog([{instanceId:'p',skills:[
  {name:'review',enabled:true,shortDescription:'Check changes',description:'检查当前项目的完整代码质量',displayName:'代码审查',scope:'user'},
  {name:'other',enabled:true,shortDescription:'Other',description:'分析构建日志'}
 ]}]);
 const commands=m.commandsFor(catalog,'p','/work');
 for(const query of ['审查','质量','review','skill:rev']){
  const found=m.commandSuggestions('/'+query,query.length+1,query.length+1,commands);
  assert.equal(found[0]?.name,'skill:review',query);
  assert.equal(m.insertCommand('/'+query,query.length+1,query.length+1,found[0]).text,'$review ');
 }
 assert.deepEqual(m.commandSuggestions('/构建',3,3,commands).map(c=>c.name),['skill:other']);
});
