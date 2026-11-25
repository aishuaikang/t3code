import { TimelineRow } from '../model/Models';

export class TranscriptDataSource implements IDataSource {
  private rows: TimelineRow[] = [];
  private listeners: DataChangeListener[] = [];
  private keys: Map<string, string> = new Map();
  private nextKey: number = 0;

  totalCount(): number { return this.rows.length; }
  getData(index: number): TimelineRow { return this.rows[index]; }
  key(row: TimelineRow): string { return this.keys.get(row.id) ?? row.id; }
  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) this.listeners.push(listener);
  }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((entry: DataChangeListener) => entry !== listener);
  }

  update(rows: TimelineRow[]): void {
    const previous = this.rows;
    const existing: Map<string, TimelineRow> = new Map(previous.map((row: TimelineRow) => [row.id, row]));
    const keys: Map<string, string> = new Map();
    // LazyForEach retains a cached child when its key is unchanged, even after onDataChange.
    for (const row of rows) keys.set(row.id, existing.get(row.id) === row ? this.key(row) : `${row.id}:${this.nextKey++}`);
    this.keys = keys;
    this.rows = rows;
    const retained = Math.min(previous.length, rows.length);
    if ((previous.length === 0 && rows.length > 0) || rows.length < previous.length ||
      previous.slice(0, retained).some((row: TimelineRow, index: number) => row.id !== rows[index].id)) {
      this.listeners.forEach((listener: DataChangeListener) => { listener.onDataReloaded(); });
      return;
    }
    for (let index = 0; index < retained; index++) {
      if (previous[index] !== rows[index]) this.listeners.forEach((listener: DataChangeListener) => { listener.onDataChange(index); });
    }
    for (let index = retained; index < rows.length; index++) {
      this.listeners.forEach((listener: DataChangeListener) => { listener.onDataAdd(index); });
    }
  }
}
