import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const source=readFileSync(new URL('../app/entry/src/main/ets/model/CodeHighlight.ets',import.meta.url),'utf8');
const {highlightCode}=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
test('highlighting preserves every source character and isolates comments, strings and numbers',()=>{
 const source='const 名称 = "return 42"; // const 9\nreturn 42;\n';
 const tokens=highlightCode(source,'typescript');
 assert.equal(tokens.map(t=>t.text).join(''),source);
 assert.ok(tokens.some(t=>t.kind==='keyword'&&t.text==='const'));
 assert.ok(tokens.some(t=>t.kind==='string'&&t.text==='"return 42"'));
 assert.ok(tokens.some(t=>t.kind==='comment'&&t.text==='// const 9'));
 assert.ok(tokens.some(t=>t.kind==='number'&&t.text==='42'));
});
test('shell and JSON snippets keep literal entities and escaped quotes',()=>{
 for(const [language,source] of [['bash','pnpm dev:local-tuotu-login\n# run\necho "$HOME &amp;"\n'],
   ['json','{"key": "a\\"b &lt;", "number": 3, "enabled": true}\n']]){
   const tokens=highlightCode(source,language);assert.equal(tokens.map(t=>t.text).join(''),source);
   assert.ok(tokens.some(t=>t.kind==='string'));assert.ok(tokens.some(t=>t.kind!=='plain'));
 }
});
test('unknown languages and very large code blocks fall back to complete unmodified text',()=>{
 for(const [text,language] of [['const x = 1;','unknown'],['x'.repeat(40000),'ts']]){
   assert.deepEqual(highlightCode(text,language),[{kind:'plain',text}]);
 }
});
