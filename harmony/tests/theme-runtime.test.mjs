import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const url=s=>'data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(s)).toString('base64');
const read=p=>readFileSync(new URL('../app/entry/src/main/ets/'+p,import.meta.url),'utf8');
const selection=url(read('model/ThemeSelection.ets'));
let failRead=false;
let saved={light:'grove',dark:'iris',mode:'system'},fail=false,release=null;
const store={async themeSelection(){if(failRead)throw Error("read failed");return saved;},async saveThemeSelection(value){if(release)await release;if(fail)throw Error('save failed');saved=value;}};
globalThis.__themeStore={async open(){return store;}};
globalThis.AppStorage={values:new Map(),SetOrCreate(k,v){this.values.set(k,v);}};
const palettes=JSON.parse(readFileSync(new URL('../app/entry/src/main/resources/rawfile/theme-palettes.json',import.meta.url)));
let nativeMode;
const context={config:{colorMode:1},resourceManager:{getRawFileContentSync(){return new TextEncoder().encode(JSON.stringify(palettes));}},getApplicationContext(){return {setColorMode(v){nativeMode=v;}};}};
const source=read('connection/ThemeRuntime.ets')
.replace("import window from '@ohos.window';",'')
.replace("import common from '@ohos.app.ability.common';",'')
.replace("import util from '@ohos.util';",'const util={TextDecoder:{create(){return {decodeToString(v){return new TextDecoder().decode(v);}};}}};')
.replace("import ConfigurationConstant from '@ohos.app.ability.ConfigurationConstant';",'const ConfigurationConstant={ColorMode:{COLOR_MODE_DARK:0,COLOR_MODE_LIGHT:1,COLOR_MODE_NOT_SET:-1}};')
.replace("import { AppearanceStore } from './AppearanceStore';",'const AppearanceStore=globalThis.__themeStore;')
.replace("import { ThemeSelection,",'import {')
.replace("'../model/ThemeSelection'",JSON.stringify(selection));
const {ThemeRuntime}=await import(url(source));
test('cold startup loads the saved palette; configuration changes preserve independent choices',async()=>{
 await ThemeRuntime.initialize(context);
 assert.equal(AppStorage.values.get('themeKey'),'grove-light');assert.equal(nativeMode,-1);
 assert.equal(ThemeRuntime.color('grove-light','screen'),palettes.find(p=>p.id==='grove'&&p.scheme==='light').colors['--color-screen']);
 ThemeRuntime.configurationChanged(0);assert.equal(AppStorage.values.get('themeKey'),'iris-dark');
 ThemeRuntime.configurationChanged(undefined);assert.equal(AppStorage.values.get('themeKey'),'iris-dark');
});
test('saving publishes only after persistence and a failed change keeps the visible theme',async()=>{
 let finish;release=new Promise(r=>finish=r);
 const saving=ThemeRuntime.save({light:'ocean',dark:'ember',mode:'light'});
 await new Promise(r=>setImmediate(r));assert.equal(AppStorage.values.get('themeKey'),'iris-dark');
 finish();await saving;release=null;
 assert.equal(AppStorage.values.get('themeKey'),'ocean-light');assert.equal(nativeMode,1);
 ThemeRuntime.configurationChanged(0);assert.equal(AppStorage.values.get('themeKey'),'ocean-light');
 fail=true;await assert.rejects(ThemeRuntime.save({light:'t3-code',dark:'t3-code',mode:'dark'}));fail=false;
 assert.equal(AppStorage.values.get('themeKey'),'ocean-light');assert.equal(nativeMode,1);
 await ThemeRuntime.initialize(context);assert.equal(AppStorage.values.get('themeKey'),'ocean-light');
});

test('a failed startup read can be retried without writing over the saved selection',async()=>{
 failRead=true;await ThemeRuntime.initialize(context);
 assert.match(AppStorage.values.get('themeError'),/读取失败/);
 failRead=false;saved={light:'ember',dark:'ocean',mode:'light'};
 assert.deepEqual(await ThemeRuntime.reload(),saved);
 assert.equal(AppStorage.values.get('themeKey'),'ember-light');
 assert.equal(AppStorage.values.get('themeError'),'');
});

test('window background and system bars follow the saved palette on startup and theme changes',async()=>{
 const backgrounds=[],bars=[];
 const nativeWindow={setWindowBackgroundColor:v=>backgrounds.push(v),setWindowSystemBarProperties:async v=>bars.push(v)};
 await ThemeRuntime.attachWindow(nativeWindow);
 assert.equal(backgrounds.at(-1),ThemeRuntime.color(AppStorage.values.get('themeKey'),'screen'));
 assert.equal(bars.at(-1).statusBarColor,'#00000000');
 assert.equal(bars.at(-1).navigationBarColor,'#00000000');
 await ThemeRuntime.save({light:'t3-code',dark:'t3-code',mode:'dark'});await ThemeRuntime.syncWindow();
 assert.equal(backgrounds.at(-1),ThemeRuntime.color('t3-code-dark','screen'));
 assert.equal(bars.at(-1).statusBarContentColor,'#FFFFFFFF');
 await ThemeRuntime.save({light:'t3-code',dark:'t3-code',mode:'light'});await ThemeRuntime.syncWindow();
 assert.equal(bars.at(-1).statusBarContentColor,'#FF191919');
 ThemeRuntime.detachWindow();
});
test('a failed system-bar update does not prevent the next theme from applying',async()=>{
 let fail=true;const backgrounds=[];
 const nativeWindow={setWindowBackgroundColor:v=>backgrounds.push(v),setWindowSystemBarProperties:async()=>{if(fail)throw Error('window update failed')}};
 await ThemeRuntime.attachWindow(nativeWindow);assert.match(AppStorage.values.get('windowError'),/系统栏/);
 fail=false;await ThemeRuntime.syncWindow();assert.equal(AppStorage.values.get('windowError'),'');
 ThemeRuntime.detachWindow();const count=backgrounds.length;await ThemeRuntime.syncWindow();assert.equal(backgrounds.length,count);
});
test('settings summaries receive the saved mode even when the resolved palette does not change',async()=>{
 ThemeRuntime.configurationChanged(1);
 await ThemeRuntime.save({light:'t3-code',dark:'t3-code',mode:'system'});
 const key=AppStorage.values.get('themeKey');
 await ThemeRuntime.save({light:'t3-code',dark:'t3-code',mode:'light'});
 assert.equal(AppStorage.values.get('themeKey'),key);
 assert.equal(AppStorage.values.get('themeSelection').mode,'light');
 fail=true;
 try { await assert.rejects(ThemeRuntime.save({light:'t3-code',dark:'t3-code',mode:'dark'})); }
 finally { fail=false; }
 assert.equal(AppStorage.values.get('themeSelection').mode,'light');
 await ThemeRuntime.reload();
 assert.equal(AppStorage.values.get('themeSelection').mode,'light');
});

test('the image viewer keeps a black edge-to-edge surface and light system controls, then restores the current theme',async()=>{
 const backgrounds=[],bars=[];
 await ThemeRuntime.attachWindow({setWindowBackgroundColor:value=>backgrounds.push(value),setWindowSystemBarProperties:async value=>bars.push(value)});
 await ThemeRuntime.setImagePreview(true);
 assert.equal(backgrounds.at(-1),'#000000');
 assert.equal(bars.at(-1).statusBarContentColor,'#FFFFFFFF');
 assert.equal(bars.at(-1).navigationBarContentColor,'#FFFFFFFF');
 assert.equal(bars.at(-1).navigationBarColor,'#00000000');
 await ThemeRuntime.save({light:'ocean',dark:'ember',mode:'light'});await ThemeRuntime.syncWindow();
 assert.equal(backgrounds.at(-1),'#000000');
 await ThemeRuntime.setImagePreview(false);
 assert.equal(backgrounds.at(-1),ThemeRuntime.color('ocean-light','screen'));
 assert.equal(bars.at(-1).navigationBarContentColor,'#FF191919');
 ThemeRuntime.detachWindow();
});


function luminance(hex){
 assert.match(hex,/^#[0-9a-f]{6}$/i);
 const [r,g,b]=hex.slice(1).match(/../g).map(x=>parseInt(x,16)/255).map(c=>c<=0.04045?c/12.92:((c+0.055)/1.055)**2.4);
 return 0.2126*r+0.7152*g+0.0722*b+0.05;
}
const contrast=(a,b)=>Math.max(luminance(a),luminance(b))/Math.min(luminance(a),luminance(b));

test('chat messages have visible surfaces and readable body, secondary text and links in every shipped appearance',async()=>{
 await ThemeRuntime.initialize(context);
 for(const {id,scheme} of palettes){
  const key=`${id}-${scheme}`,color=role=>ThemeRuntime.color(key,role);
  assert.notEqual(color('chat-user'),color('chat-reply'),key);
  assert.ok(contrast(color('chat-outline'),color('card'))>=1.8,`${key} edge`);
  for(const role of ['chat-user','chat-reply']){
   assert.ok(contrast(color(role),color('card'))>=1.2,`${key} ${role} surface`);
   for(const text of ['foreground','md-body','chat-secondary','chat-link']){
    assert.ok(contrast(color(role),color(text))>=4.5,`${key} ${role} ${text}`);
   }
  }
 }
});

test('toolbar titles and small glass labels remain readable on chat surfaces across every palette',async()=>{
 await ThemeRuntime.initialize(context);
 for(const {id,scheme} of palettes){
  const color=role=>ThemeRuntime.color(`${id}-${scheme}`,role);
  for(const surface of ['screen','card','chat-reply','chat-user']){
   for(const text of ['foreground','glass-label']){
    assert.ok(contrast(color(text),color(surface))>=4.5,`${id}-${scheme}: ${text} on ${surface}`);
   }
  }
 }
});

test('both loading gradient stops keep the theme hue and a readable label in every appearance', async()=>{
 await ThemeRuntime.initialize(context);
 const channelOrder=hex=>{
  const rgb=hex.slice(1).match(/../g).map(c=>parseInt(c,16));
  return [0,1,2].sort((a,b)=>rgb[b]-rgb[a]);
 };
 for(const {id,scheme} of palettes){
  const color=role=>ThemeRuntime.color(`${id}-${scheme}`,role);
  assert.notEqual(color('progress-start'),color('progress-end'),`${id}-${scheme} gradient`);
  for(const stop of ['progress-start','progress-end']){
   if(id!=='t3-code')assert.deepEqual(channelOrder(color(stop)),channelOrder(color('primary')),`${id}-${scheme} hue at ${stop}`);
   assert.ok(contrast(color(stop),color('progress-foreground'))>=4.5,`${id}-${scheme} loading text on ${stop}`);
   assert.ok(contrast(color(stop),color('card'))>=3,`${id}-${scheme} loading edge at ${stop}`);
  }
 }
});
