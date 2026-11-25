import { DiffDisplayRow } from '../model/DiffPresentation';

export class DiffDataSource implements IDataSource {
  private rows: DiffDisplayRow[] = [];
  private listeners: DataChangeListener[] = [];
  private generation: number = 0;
  totalCount(): number { return this.rows.length; }
  getData(index: number): DiffDisplayRow { return this.rows[index]; }
  key(row: DiffDisplayRow): string { return `${this.generation}:${row.id}`; }
  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) this.listeners.push(listener);
  }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((entry: DataChangeListener) => entry !== listener);
  }
  update(rows: DiffDisplayRow[]): void {
    this.rows = rows;
    // A refresh can change content while retaining parser row IDs; invalidate cached LazyForEach children.
    this.generation++;
    this.listeners.forEach((listener: DataChangeListener) => { listener.onDataReloaded(); });
  }
}
