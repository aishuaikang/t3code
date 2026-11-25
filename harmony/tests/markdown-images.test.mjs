import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const read=path=>readFileSync(new URL('../app/entry/src/main/ets/'+path,import.meta.url),'utf8').replace(/^import .*;$/gm,'');
const source=`export const cached=new Map();export const downloads=[];export const requests=[];
const ImageFileCache={cached:async(files,env,id)=>cached.get(JSON.stringify([env,id]))??'',source:async(files,env,id,resolve,refresh,mutable)=>{downloads.push({env,id,refresh,mutable});return !refresh && !mutable && cached.has(JSON.stringify([env,id])) ? cached.get(JSON.stringify([env,id])) : resolve();}};
export const EnvironmentSession={current:{descriptor:{environmentId:'env'},httpBaseUrl:'https://private.test',rpc:{call:async(method,payload)=>{requests.push(payload.resource);return {relativeUrl:'/assets/image',expiresAt:0};}}}};
${read('model/MarkdownLink.ets')}
${read('connection/ImageAssets.ets')}
${read('connection/MarkdownImages.ets')}`;
const m=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
test('relative document images use their document directory and authenticated host resources',async()=>{
 m.requests.length=0;
 assert.equal(await m.loadMarkdownImage('/files','env','thread','/repo','docs/guides','../images/plot.png'),'https://private.test/assets/image');
 assert.deepEqual(m.requests[0],{_tag:'media-file',threadId:'thread',path:'/repo/docs/images/plot.png'});
 await m.loadMarkdownImage('/files','env','','/repo','docs','../images/flow.svg');
 assert.deepEqual(m.requests[1],{_tag:'draft-workspace-file',cwd:'/repo',path:'images/flow.svg'});
});
test('remote images retain query strings, support protocol-relative sources, and do not request server credentials',async()=>{
 m.requests.length=0;
 const url='https://images.test/plot.svg?a=1&b=2';
 assert.equal(await m.loadMarkdownImage('/files','env','t','/repo','docs',url),url);
 assert.equal(await m.loadMarkdownImage('/files','env','t','/repo','docs','//images.test/plot.png'),'https://images.test/plot.png');
 assert.equal(m.requests.length,0);
});
test('cached project images work offline while wrong-environment and invalid paths cannot fetch private files',async()=>{
 const environment=m.EnvironmentSession.current;
 m.requests.length=0;m.EnvironmentSession.current=null;
 const id=m.ImageAssets.mediaId('t','/repo/docs/image.png');m.cached.set(JSON.stringify(['env',id]),'file:///cached/image');
 try {
  assert.equal(await m.loadMarkdownImage('/files','env','t','/repo','docs','image.png'),'file:///cached/image');
  await assert.rejects(m.loadMarkdownImage('/files','other','t','/repo','docs','image.png'),/环境/);
  for(const href of ['javascript:alert(1)','../../secret.png','file://other/image.png'])await assert.rejects(m.loadMarkdownImage('/files','env','t','/repo','docs',href),/地址/);
  await assert.rejects(m.loadMarkdownImage('/files','env','','/repo','docs','/outside/image.png'),/项目/);
  assert.equal(m.requests.length,0);
 } finally {m.EnvironmentSession.current=environment;m.cached.clear();}
});

// Exercise the image loader and the real native component callbacks with a simulated storage change.
const markdown = read('pages/MarkdownImage.ets'), chat = read('pages/ChatImage.ets');
const slice = (s, start, end) => s.slice(s.indexOf(start), s.indexOf(end, s.indexOf(start))).replaceAll('private ', '');
globalThis.__markdownImageLoader = m.loadMarkdownImage;
const ui=`const getContext=()=>({filesDir:'/files'});const loadMarkdownImage=globalThis.__markdownImageLoader;
export class Tile {active=false;loading=true;source='';error='';revision=0;fetching=false;retryAfterLoad=false;online=false;
${slice(chat,'  aboutToAppear():','  build() {')}
}
export class Markdown {active=true;source='';onlineEnvironmentId='';environmentId='env';href='image.png';cwd='/repo';baseDir='docs';label='figure';
${slice(markdown,'  private attachment():','  @Builder')}
props(){return ${markdown.match(/ChatImage\(\{([\s\S]+?)\}\)/)[0].replace(/^ChatImage\(/,'(')}}
}`;
const {Tile,Markdown}=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(ui)).toString('base64'));
const settle=()=>new Promise(resolve=>setImmediate(resolve));
for(const [where,id] of [['chat','t'],['file','']])test(`an uncached Markdown image in a ${where} resumes on its own environment; a cached image stays offline`,async()=>{
 const view=new Markdown();view.threadId=id;const tile=new Tile();Object.assign(tile,view.props());
 m.requests.length=0;tile.aboutToAppear();await settle();assert.match(tile.error,/尚未缓存/);assert.equal(m.requests.length,0);
 const publish=async value=>{view.onlineEnvironmentId=value;const next=view.props().online;if(next!==tile.online){tile.online=next;tile.connectionChanged()}await settle()};
 await publish('other');assert.equal(m.requests.length,0);await publish('env');assert.equal(m.requests.length,1);assert.equal(tile.source,'https://private.test/assets/image');
 assert.equal(m.requests[0]._tag,id?'media-file':'draft-workspace-file');tile.aboutToDisappear();
 const key=id?m.ImageAssets.mediaId(id,'/repo/docs/image.png'):m.ImageAssets.workspaceId('/repo','docs/image.png');
 m.cached.set(JSON.stringify(['env',key]),'file:///cached');view.onlineEnvironmentId='';const cached=new Tile();Object.assign(cached,view.props());cached.aboutToAppear();await settle();
 assert.equal(cached.source,'file:///cached');view.onlineEnvironmentId='env';cached.online=true;cached.connectionChanged();await settle();assert.equal(m.requests.length,2);assert.equal(m.downloads.at(-1).mutable,true);assert.equal(cached.source,'https://private.test/assets/image');m.cached.clear();cached.aboutToDisappear();
});
test('reconnection during an old image request retries once if that request fails late',async()=>{
 const tile=new Tile(),old=Promise.withResolvers();let calls=0;tile.loadSource=()=>++calls===1?old.promise:Promise.resolve('file:///recovered');
 tile.aboutToAppear();tile.online=true;tile.connectionChanged();old.reject(Error('old network'));await settle();
 assert.equal(calls,2);assert.equal(tile.source,'file:///recovered');tile.aboutToDisappear();
});
