import { ThreadShell, taskStatus } from './Models';
import { sortPinnedThreads } from './TaskPresentation';

const ORDER_DIGITS: string = 'abcdefghijklmnopqrstuvwxyz';

function validOrderKey(key: string): boolean {
  if (!key || key.charAt(key.length - 1) === 'a') return false;
  for (let index = 0; index < key.length; index++) {
    if (!ORDER_DIGITS.includes(key.charAt(index))) return false;
  }
  return true;
}

function orderMidpoint(before: string, after: string): string {
  if (after) {
    let prefix = 0;
    while ((before.charAt(prefix) || 'a') === after.charAt(prefix)) prefix++;
    if (prefix > 0) return after.slice(0, prefix) + orderMidpoint(before.slice(prefix), after.slice(prefix));
  }
  const left = before ? ORDER_DIGITS.indexOf(before.charAt(0)) : 0;
  const right = after ? ORDER_DIGITS.indexOf(after.charAt(0)) : ORDER_DIGITS.length;
  if (right - left > 1) return ORDER_DIGITS.charAt(Math.round((left + right) / 2));
  if (after.length > 1) return after.charAt(0);
  return ORDER_DIGITS.charAt(left) + orderMidpoint(before.slice(1), '');
}

// Use the same fractional alphabet and midpoint as the PC client.
export function threadOrderKeyBetween(before: string | null, after: string | null): string | null {
  const left = before ?? '', right = after ?? '';
  if ((left && !validOrderKey(left)) || (right && !validOrderKey(right)) || (right && left >= right)) return null;
  return orderMidpoint(left, right);
}

export function spreadThreadOrderKeys(count: number): string[] {
  let width = 2, space = ORDER_DIGITS.length ** width;
  while (space <= (count + 1) * 2) { width++; space *= ORDER_DIGITS.length; }
  const keys: string[] = [];
  for (let index = 0; index < count; index++) {
    let value = Math.round(space / (count + 1) * (index + 1));
    if (value % ORDER_DIGITS.length === 0) value++;
    let key = '';
    for (let digit = 0; digit < width; digit++) {
      key = ORDER_DIGITS.charAt(value % ORDER_DIGITS.length) + key;
      value = Math.floor(value / ORDER_DIGITS.length);
    }
    keys.push(key);
  }
  return keys;
}

export function inThreadOrderGroup(thread: ThreadShell, pinned: boolean): boolean {
  return !thread.archivedAt && Boolean(thread.pinnedAt) === pinned && (pinned || taskStatus(thread) !== 'completed');
}

export function sortTaskThreads(threads: ThreadShell[]): ThreadShell[] {
  const active = threads.filter((thread: ThreadShell) => !thread.pinnedAt && taskStatus(thread) !== 'completed');
  active.sort((left: ThreadShell, right: ThreadShell) => {
    const a = left.activeOrderKey, b = right.activeOrderKey;
    if (a == null && b != null) return -1;
    if (a != null && b == null) return 1;
    if (a != null && b != null) return a < b ? -1 : a > b ? 1 : left.id.localeCompare(right.id);
    const leftTime = Math.max(Date.parse(left.createdAt ?? '') || 0, Date.parse(left.unsettledAt ?? '') || 0);
    const rightTime = Math.max(Date.parse(right.createdAt ?? '') || 0, Date.parse(right.unsettledAt ?? '') || 0);
    return rightTime - leftTime || left.id.localeCompare(right.id);
  });
  return sortPinnedThreads(threads.filter((thread: ThreadShell) => !!thread.pinnedAt)).concat(active,
    threads.filter((thread: ThreadShell) => !thread.pinnedAt && taskStatus(thread) === 'completed'));
}

export interface ThreadOrderAssignment { id: string; orderKey: string; }

export function planThreadReorder(threads: ThreadShell[], orderedIds: string[], movedIds: string[], pinned: boolean): ThreadOrderAssignment[] {
  if (orderedIds.length < 2 || movedIds.length === 0 || new Set(orderedIds).size !== orderedIds.length) return [];
  const keys = new Map<string, string | null>();
  for (const thread of threads) {
    if (inThreadOrderGroup(thread, pinned)) keys.set(thread.id, (pinned ? thread.pinOrderKey : thread.activeOrderKey) ?? null);
  }
  if (orderedIds.some((id: string) => !keys.has(id))) return [];
  const visible = new Set(orderedIds), reserved = new Set<string>();
  keys.forEach((key: string | null, id: string) => { if (!visible.has(id) && key !== null) reserved.add(key); });
  const movedIndex = movedIds.length === 1 ? orderedIds.indexOf(movedIds[0]) : -1;
  const remaining = orderedIds.filter((id: string) => id !== movedIds[0]);
  const current = sortTaskThreads(threads).filter((thread: ThreadShell) => visible.has(thread.id) && thread.id !== movedIds[0]);
  if (movedIndex >= 0 && current.every((thread: ThreadShell, index: number) => thread.id === remaining[index])) {
    const before = movedIndex > 0 ? keys.get(orderedIds[movedIndex - 1]) ?? null : null;
    const after = movedIndex < orderedIds.length - 1 ? keys.get(orderedIds[movedIndex + 1]) ?? null : null;
    if ((movedIndex === 0 || before !== null) && (movedIndex === orderedIds.length - 1 || after !== null)) {
      let key = threadOrderKeyBetween(before, after);
      while (key !== null && reserved.has(key)) key = threadOrderKeyBetween(key, after);
      if (key !== null) return keys.get(movedIds[0]) === key ? [] : [{ id: movedIds[0], orderKey: key }];
    }
  }
  const spread = spreadThreadOrderKeys(orderedIds.length + reserved.size).filter((key: string) => !reserved.has(key));
  const assignments: ThreadOrderAssignment[] = [];
  orderedIds.forEach((id: string, index: number) => { if (keys.get(id) !== spread[index]) assignments.push({ id: id, orderKey: spread[index] }); });
  return assignments;
}
