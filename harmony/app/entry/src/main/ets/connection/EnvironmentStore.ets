import asset from '@ohos.security.asset';
import preferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';
import util from '@ohos.util';
import { BusinessError } from '@ohos.base';

export interface SavedSshTarget {
  hostname: string;
  port: number;
  username: string;
  hostFingerprint: string;
  serverHost?: string;
  serverPort: number;
}

export interface SshCredentials {
  bearer: string;
  password: string;
}

export interface SavedEnvironment {
  connectionId?: string;
  sshRole?: 'primary' | 'backup';
  ssh?: SavedSshTarget;
  environmentId: string;
  httpBaseUrl: string;
  label: string;
  updatedAt: string;
}

export function routeAddress(saved: SavedEnvironment): string {
  return saved.ssh ? `${saved.ssh.username}@${saved.ssh.hostname}:${saved.ssh.port}` : saved.httpBaseUrl;
}

function bytes(value: string): Uint8Array { return new util.TextEncoder().encodeInto(value); }
function decode(value: asset.Value | undefined): string {
  if (!(value instanceof Uint8Array)) throw new Error('已保存连接的数据格式错误');
  return util.TextDecoder.create('utf-8').decodeToString(value);
}
function queryFor(id: string = '', ssh: boolean = false): asset.AssetMap {
  const query: asset.AssetMap = new Map();
  query.set(asset.Tag.DATA_LABEL_NORMAL_2, bytes(ssh ? 't3-ssh-environment-v1' : 't3-direct-environment-v1'));
  if (id) query.set(asset.Tag.ALIAS, bytes((ssh ? 't3-ssh:' : 't3-environment:') + id));
  return query;
}

export async function saveEnvironment(environment: SavedEnvironment, bearer: string): Promise<void> {
  await saveAsset(environment, bearer, environment.environmentId, false);
}

export async function saveSshEnvironment(environment: SavedEnvironment, bearer: string, password: string): Promise<void> {
  if (!environment.connectionId || !environment.ssh) throw new Error('SSH 连接配置缺失');
  const credentials: SshCredentials = { bearer: bearer, password: password };
  await saveAsset(environment, JSON.stringify(credentials), environment.connectionId, true);
}

async function saveAsset(environment: SavedEnvironment, secret: string, id: string, ssh: boolean): Promise<void> {
  const attributes = queryFor(id, ssh);
  attributes.set(asset.Tag.SECRET, bytes(secret));
  attributes.set(asset.Tag.DATA_LABEL_NORMAL_1, bytes(JSON.stringify(environment)));
  attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_UNLOCKED);
  attributes.set(asset.Tag.SYNC_TYPE, asset.SyncType.NEVER);
  attributes.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
  await asset.add(attributes);
}

function routePreferences(context: common.Context): Promise<preferences.Preferences> {
  return preferences.getPreferences(context, { name: 't3-ssh-routes' });
}

function routeOrder(prefs: preferences.Preferences, environmentId: string): string[] {
  return prefs.getSync(environmentId, [] as string[]) as string[];
}

export async function setPrimarySshRoute(context: common.Context, saved: SavedEnvironment): Promise<void> {
  if (!saved.ssh || !saved.connectionId) return;
  const prefs = await routePreferences(context);
  const previous = routeOrder(prefs, saved.environmentId);
  prefs.putSync(saved.environmentId, [saved.connectionId, ...previous.filter(id => id !== saved.connectionId)]);
  try { await prefs.flush(); }
  catch (error) {
    if (routeOrder(prefs, saved.environmentId)[0] === saved.connectionId) prefs.putSync(saved.environmentId, previous);
    throw new Error(error instanceof Error ? error.message : String(error));
  }
}

export async function loadEnvironments(context?: common.Context): Promise<SavedEnvironment[]> {
  const direct = await loadSaved(false);
  const ssh = await loadSaved(true);
  const saved = direct.concat(ssh).sort((a: SavedEnvironment, b: SavedEnvironment) => b.updatedAt.localeCompare(a.updatedAt));
  if (!ssh.length || !context) return saved;
  // Route ordering is optional; the secure connection records remain usable if preferences are unavailable.
  const prefs = await routePreferences(context).catch((): preferences.Preferences | null => null);
  const groups = new Map<string, SavedEnvironment[]>();
  for (const route of saved) {
    if (!route.ssh || !route.connectionId) continue;
    const group = groups.get(route.environmentId) ?? [];
    group.push(route); groups.set(route.environmentId, group);
  }
  let changed = false;
  groups.forEach((routes: SavedEnvironment[], environmentId: string) => {
    const order: string[] = prefs ? routeOrder(prefs, environmentId) : [];
    const ids = routes.map((route: SavedEnvironment) => route.connectionId!);
    const added = ids.filter(id => !order.includes(id));
    if (prefs && added.length) { prefs.putSync(environmentId, order.concat(added)); changed = true; }
    const primary = order.find(id => ids.includes(id)) ?? ids[0];
    if (routes.length > 1) routes.forEach((route: SavedEnvironment) => { route.sshRole = route.connectionId === primary ? 'primary' : 'backup'; });
  });
  if (changed && prefs) await prefs.flush().catch(() => {});
  return saved;
}

async function loadSaved(ssh: boolean): Promise<SavedEnvironment[]> {
  const query = queryFor('', ssh);
  query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ATTRIBUTES);
  let assets: asset.AssetMap[];
  try { assets = await asset.query(query); }
  catch (error) {
    if ((error as BusinessError).code === asset.ErrorCode.NOT_FOUND) return [];
    throw new Error('无法读取已保存连接，请解锁手机后重试');
  }
  return assets.map((item: asset.AssetMap): SavedEnvironment =>
    JSON.parse(decode(item.get(asset.Tag.DATA_LABEL_NORMAL_1))) as SavedEnvironment);
}

export async function readBearer(id: string): Promise<string> {
  return readSecret(id, false);
}

export async function readSshCredentials(id: string): Promise<SshCredentials> {
  return JSON.parse(await readSecret(id, true)) as SshCredentials;
}

async function readSecret(id: string, ssh: boolean): Promise<string> {
  const query = queryFor(id, ssh);
  query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
  const items = await asset.query(query);
  if (items.length !== 1) throw new Error('已保存凭据不存在，请重新配对');
  return decode(items[0].get(asset.Tag.SECRET));
}

export async function forgetEnvironment(saved: SavedEnvironment, context: common.Context): Promise<void> {
  await asset.remove(queryFor(saved.connectionId ?? saved.environmentId, saved.ssh !== undefined));
  if (saved.ssh && saved.connectionId) {
    const prefs = await routePreferences(context).catch((): preferences.Preferences | null => null);
    if (!prefs) return;
    const order = routeOrder(prefs, saved.environmentId).filter(id => id !== saved.connectionId);
    if (order.length) prefs.putSync(saved.environmentId, order);
    else prefs.deleteSync(saved.environmentId);
    await prefs.flush().catch(() => {});
  }
}
