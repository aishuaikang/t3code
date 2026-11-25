import { DiffRow } from './DiffRows';

export interface DiffDisplayRow {
  id: string;
  kind: string;
  fileId: string;
  source: DiffRow;
  left?: DiffRow;
  right?: DiffRow;
}

export function diffDisplayRows(rows: DiffRow[], collapsed: string[], split: boolean): DiffDisplayRow[] {
  const result: DiffDisplayRow[] = [];
  const hidden = new Set<string>(collapsed);
  let deleted: DiffRow[] = [], added: DiffRow[] = [];
  const flush = (): void => {
    for (let index = 0; index < Math.max(deleted.length, added.length); index++) {
      const left = deleted[index], right = added[index], source = left ?? right;
      result.push({ id: `split:${left?.id ?? ''}:${right?.id ?? ''}`, kind: 'line', fileId: source.fileId, source, left, right });
    }
    deleted = []; added = [];
  };
  for (const row of rows) {
    if (row.kind !== 'file' && hidden.has(row.fileId)) continue;
    if (split && row.kind === 'line' && row.change !== 'context') {
      // A later deletion starts another change block; never pair across unchanged lines or hunks.
      if (row.change === 'delete') { if (added.length > 0) flush(); deleted.push(row); }
      else added.push(row);
      continue;
    }
    flush();
    result.push({ id: row.id, kind: row.kind, fileId: row.fileId, source: row,
      left: split && row.kind === 'line' ? row : undefined, right: split && row.kind === 'line' ? row : undefined });
  }
  flush();
  return result;
}

export function diffAnchorIndex(rows: DiffDisplayRow[], rowId: string, fileId: string): number {
  const index = rows.findIndex((row: DiffDisplayRow) => row.source.id === rowId || row.left?.id === rowId || row.right?.id === rowId);
  return index >= 0 ? index : Math.max(0, rows.findIndex((row: DiffDisplayRow) => row.kind === 'file' && row.fileId === fileId));
}

export function diffLineText(content: string | undefined, whitespace: boolean): string {
  return whitespace ? (content ?? '').replace(/ /g, '·').replace(/\t/g, '→   ') : content ?? '';
}
