import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const source=readFileSync(new URL('../app/entry/src/main/ets/model/MarkdownBlocks.ets',import.meta.url),'utf8').replace(/^import .*;$/gm,'');
const {markdownBlocks,markdownParts}=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
const n=(type,children=[],extra={})=>({type,children,...extra});
const t=text=>n('text',[],{content:text});
test('keeps nested inline styles, escaped code and paragraph breaks',()=>{
 const blocks=markdownBlocks(n('document',[n('heading',[t('Title')],{level:2}),n('paragraph',[n('bold',[n('italic',[t('nested')])]),n('code_inline',[t('<x>')]),n('line_break'),t('next')])]));
 assert.equal(blocks[0].level,2);assert.equal(blocks[1].runs[0].bold,true);assert.equal(blocks[1].runs[0].italic,true);
 assert.equal(blocks[1].runs[1].code,true);assert.equal(blocks[1].runs.map(r=>r.text).join(''),'nested<x>\nnext');
});
test('preserves ordered start, unchecked tasks, nested list depth and table cells',()=>{
 const blocks=markdownBlocks(n('document',[n('list',[n('list_item',[n('paragraph',[t('one')]),n('list',[n('task_list_item',[t('todo')],{checked:false})])]),n('list_item',[t('two')])],{ordered:true,start:3}),n('table',[n('table_head',[n('table_row',[n('table_cell',[t('A')],{isHeader:true})])]),n('table_body',[n('table_row',[n('table_cell',[t('B')])])])])]));
 assert.deepEqual(blocks.slice(0,3).map(b=>[b.marker,b.depth]),[['3.',0],['☐',1],['4.',0]]);
 assert.equal(blocks[3].rows[0].cells[0].runs[0].text,'A');assert.equal(blocks[3].rows[1].cells[0].runs[0].text,'B');
});
test('decodes prose entities without changing inline or fenced code',()=>{
 const blocks=markdownBlocks(n('document',[
   n('paragraph',[t('A &amp; B &#x1F642; &lt;tag&gt; &amp;amp; &#1114112;')]),
   n('paragraph',[n('code_inline',[],{content:'&amp; &lt;x&gt;'})]),
   n('code_block',[t('&amp; &#65;\n')],{language:'txt'})
 ]));
 assert.equal(blocks[0].runs.map(r=>r.text).join(''),'A & B 🙂 <tag> & &#1114112;');
 assert.equal(blocks[1].runs[0].text,'&amp; &lt;x&gt;');
 assert.equal(blocks[2].runs[0].text,'&amp; &#65;\n');
});

test('uses spaces for soft prose breaks and newlines for explicit breaks',()=>{
 const result=markdownBlocks(n('paragraph',[t('one'),n('soft_break'),t('two'),n('line_break'),t('three')]));
 assert.equal(result[0].runs.map(r=>r.text).join(''),'one two\nthree');
});

test('keeps tight-list inline siblings in one paragraph around nested block boundaries',()=>{
 const item=n('list_item',[t('alpha '),n('bold',[t('bold')]),t(' omega'),
   n('list',[n('list_item',[t('nested '),n('italic',[t('tail')])])]),
   n('paragraph',[t('loose')]),n('code_block',[t('const x = 1;\n')],{language:'js'})]);
 const blocks=markdownBlocks(n('list',[item]));
 assert.deepEqual(blocks.map(b=>[b.kind,b.marker,b.depth,b.runs.map(r=>r.text).join('')]),[
   ['paragraph','•',0,'alpha bold omega'],['paragraph','•',1,'nested tail'],
   ['paragraph','',0,'loose'],['code_block','',0,'const x = 1;\n']]);
 assert.equal(blocks[0].runs[1].bold,true);assert.equal(blocks[1].runs[1].italic,true);
});

test('keeps one blockquote around its paragraphs, distinct from list markers and surrounding prose',()=>{
 const result=markdownBlocks(n('list',[n('list_item',[t('outer'),
   n('blockquote',[n('paragraph',[t('a long first paragraph')]),n('paragraph',[t('second')]),
     n('list',[n('list_item',[t('bullet')])]),n('blockquote',[n('paragraph',[n('link',[t('linked')],{href:'notes.md'})])])]),
   n('table',[n('table_row',[n('table_cell',[t('cell')])])])])]));
 assert.deepEqual(result.map(b=>[b.kind,b.marker,b.depth]),[['paragraph','•',0],['blockquote','',0],['table','',0]]);
 const quoted=result[1].children;
 assert.deepEqual(quoted.map(b=>[b.kind,b.marker,b.runs.map(r=>r.text).join('')]),[
   ['paragraph','','a long first paragraph'],['paragraph','','second'],['paragraph','•','bullet'],['blockquote','','']]);
 assert.equal(quoted[3].children[0].runs[0].href,'notes.md');
 assert.equal(result[2].rows[0].cells[0].runs[0].text,'cell');
});

test('image nodes retain their source even without alt text and preserve surrounding paragraph order',()=>{
 const doc=n('paragraph',[t('Before '),n('image',[t('duplicate alt')],{href:'figures/flow.svg',alt:'Flow'}),t(' after '),n('image',[],{href:'https://example.test/plot.png?a=1&amp;b=2',alt:''})]);
 const runs=markdownBlocks(doc)[0].runs;
 assert.equal(runs[1].imageSource,'figures/flow.svg');assert.equal(runs[1].text,'Flow');
 assert.equal(runs[3].imageSource,'https://example.test/plot.png?a=1&b=2');assert.equal(runs[3].text,'');
 assert.deepEqual(markdownParts(runs).map(p=>p.image?.imageSource??p.runs.map(r=>r.text).join('')),['Before ','figures/flow.svg',' after ','https://example.test/plot.png?a=1&b=2']);
});
test('images in list items and table cells remain images while code keeps literal image syntax',()=>{
 const image=n('image',[],{href:'../media/image.png',alt:'A'});
 const blocks=markdownBlocks(n('document',[n('list',[n('list_item',[image])]),n('table',[n('table_row',[n('table_cell',[image])])]),n('code_block',[t('![A](image.png)')],{language:'md'})]));
 assert.equal(blocks[0].marker,'•');assert.equal(markdownParts(blocks[0].runs)[0].image.imageSource,'../media/image.png');
 assert.equal(markdownParts(blocks[1].rows[0].cells[0].runs)[0].image.imageSource,'../media/image.png');
 assert.equal(markdownParts(blocks[2].runs)[0].image,undefined);assert.equal(blocks[2].runs[0].text,'![A](image.png)');
});
