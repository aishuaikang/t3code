import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
import {createHash} from 'node:crypto';
let forwardArgs=[], calls=[], stdout='', exitCode=0, connectArgs=[], disconnectGate=null, onDisconnect=null;
globalThis.__sshTest={ensure:()=>({
 async connect(...args){await Promise.resolve();connectArgs=args;calls.push('connect');},
 async exec(){await Promise.resolve();calls.push('exec');return {stdout,exitCode};},
 async openForward(...args){await Promise.resolve();forwardArgs=args;calls.push('forward');},
 async disconnect(){onDisconnect?.();if(disconnectGate) await disconnectGate;await Promise.resolve();calls.push('disconnect');}
})};
globalThis.__sshCrypto={createMd:()=>{let data;return {
 async update(blob){data=blob.data;},async digest(){return {data:createHash('sha256').update(data).digest()};}
};}};
let source=readFileSync(new URL('../app/entry/src/main/ets/connection/SshTunnel.ets',import.meta.url),'utf8')
 .replace("import { SshBridge, SshExecResult } from '../bridge/NativeBridge';",'const SshBridge=globalThis.__sshTest;')
 .replace("import http from '@ohos.net.http';",'const http={createHttp:()=>({destroy(){},request(_url,callback){callback(new Error("unavailable"));}})};')
 .replace("import cryptoFramework from '@ohos.security.cryptoFramework';",'const cryptoFramework=globalThis.__sshCrypto;')
 .replace("import util from '@ohos.util';",'const util={TextEncoder:class {encodeInto(text){return new TextEncoder().encode(text);}}};');
const {SshEnvironment}=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(source)+'\n//# sourceURL=ssh-environment-under-test.mjs').toString('base64'));
const target={hostname:'test.invalid',port:22,username:'test',password:'test-only',hostFingerprint:'SHA256:AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8'};
test('a retired SSH owner does not close a newer session',async()=>{
 await SshEnvironment.ensure({...target,serverPort:1773},'',()=>{});calls=[];
 await SshEnvironment.disconnect(target);assert.deepEqual(calls,[]);
});
test('invalid launch results reject without forwarding and release the session',async()=>{
 for(const value of ['not JSON','{}','{"remotePort":0,"serverKind":"managed"}','{"remotePort":65536,"serverKind":"external"}','{"remotePort":22.5,"serverKind":"external"}','{"remotePort":"13773","serverKind":"external"}','{"remotePort":13773,"serverKind":"unknown"}']){
  calls=[];stdout=value;exitCode=0;
  await assert.rejects(SshEnvironment.ensure(target,'t3@latest',()=>{}),/启动结果/);
  assert.deepEqual(calls,['connect','exec','disconnect']);
 }
});
test('remote launch failure releases the session',async()=>{
 calls=[];stdout='';exitCode=1;
 await assert.rejects(SshEnvironment.ensure(target,'t3@latest',()=>{}),/远端启动失败/);
 assert.deepEqual(calls,['connect','exec','disconnect']);
});
test('a validated external port establishes a tunnel and can disconnect locally',async()=>{
 calls=[];stdout='login banner\n{"remotePort":13773,"serverKind":"external"}\n';exitCode=0;
 const result=await SshEnvironment.ensure(target,'t3@latest',()=>{});
 assert.deepEqual(connectArgs,[target.hostname,target.port,target.username,target.password,target.hostFingerprint]);
 assert.equal(result.remotePort,13773);assert.equal(result.serverKind,'external');
 assert.deepEqual(calls,['connect','exec','forward']);
 await SshEnvironment.disconnect(target);assert.equal(calls.at(-1),'disconnect');
});

test('pairing waits for the native command result',async()=>{
 const owner={...target,serverPort:13773};await SshEnvironment.ensure(owner,'',()=>{});
 stdout='{"credential":"test-pairing-token"}';exitCode=0;
 assert.equal(await SshEnvironment.issuePairingToken(owner),'test-pairing-token');
});

test('disconnect resolves only after native cleanup finishes',async()=>{
 const owner={...target,serverPort:13773};await SshEnvironment.ensure(owner,'',()=>{});
 let release, started;
 disconnectGate=new Promise(resolve=>{release=resolve;});
 const beginning=new Promise(resolve=>{started=resolve;});onDisconnect=started;
 let completed=false;
 const pending=SshEnvironment.disconnect(owner).then(()=>{completed=true;});
 try {
  await beginning;await Promise.resolve();assert.equal(completed,false);
  release();await pending;assert.equal(completed,true);
 } finally {release();disconnectGate=null;onDisconnect=null;await pending;}
});
test('existing-server SSH uses the requested port without running remote commands',async()=>{
 calls=[];const existing={...target,serverPort:13773};
 const result=await SshEnvironment.ensure(existing,'t3@latest',()=>{});
 assert.equal(result.remotePort,13773);assert.equal(result.serverKind,'external');
 assert.deepEqual(calls,['connect','forward']);
 await SshEnvironment.disconnect(existing);
 for(const serverPort of [0,65536,1.5]){
  calls=[];await assert.rejects(SshEnvironment.ensure({...target,serverPort},'t3@latest',()=>{}),/服务端口/);
  assert.deepEqual(calls,[]);
 }
});

test('late SSH cleanup, pairing and recovery cannot use or close the new native owner',async()=>{
 const a={...target,serverPort:1111},b={...target,serverPort:2222};await SshEnvironment.ensure(a,'',()=>{});await SshEnvironment.ensure(b,'',()=>{});calls=[];
 await SshEnvironment.disconnect(a);await assert.rejects(SshEnvironment.issuePairingToken(a),/切换/);await assert.rejects(SshEnvironment.ensure(a,'',()=>{},true),/切换/);assert.deepEqual(calls,[]);
 await SshEnvironment.disconnect(b);assert.deepEqual(calls,['disconnect']);
});
test('a new SSH dial waits for native teardown already in progress',async()=>{
 const a={...target,serverPort:1111},b={...target,serverPort:2222};await SshEnvironment.ensure(a,'',()=>{});calls=[];
 const release=Promise.withResolvers(),started=Promise.withResolvers();disconnectGate=release.promise;onDisconnect=started.resolve;
 try{const cleanup=SshEnvironment.disconnect(a);await started.promise;const opening=SshEnvironment.ensure(b,'',()=>{});await Promise.resolve();assert.deepEqual(calls,[]);
 release.resolve();await Promise.all([opening,cleanup]);assert.deepEqual(calls,['disconnect','connect','forward']);}finally{release.resolve();disconnectGate=null;onDisconnect=null;await SshEnvironment.disconnect(b)}
});

test('existing service forwarding uses the T3 host as seen by the SSH gateway, with loopback for older routes',async()=>{
 for(const [serverHost,expected] of [[undefined,'127.0.0.1'],['t3.internal','t3.internal'],['fd00::5','fd00::5']]){
  const route={...target,serverHost,serverPort:13773};const boot=await SshEnvironment.ensure(route,'',()=>{});
  assert.deepEqual(forwardArgs,[expected,boot.localPort,13773]);await SshEnvironment.disconnect(route);
 }
});
