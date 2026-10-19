import DatabaseConstructor, { Database } from 'better-sqlite3-multiple-ciphers';
import { DbDriver, DbStatement } from '../../ports';

export class NodeDbDriver implements DbDriver {
  private db: Database | null;

  constructor(dbPath: string, rawKeyHex?: string) {
    this.db = new DatabaseConstructor(dbPath);
    if (rawKeyHex) {
      this.db.pragma(`key = "x'${rawKeyHex}'"`);
    }
    this.db.pragma('foreign_keys = ON;');
  }

  public getRawDatabase(): Database {
    if (!this.db) {
      throw new Error('Database is closed');
    }
    return this.db;
  }

  public async query<T = Record<string, unknown>>(sql: string, params: unknown[] = []): Promise<T[]> {
    if (!this.db) {
      throw new Error('Database is closed');
    }
    const stmt = this.db.prepare(sql);
    if (!stmt.reader) {
      stmt.run(...params);
      return [];
    }
    const rows = stmt.all(...params) as T[];
    return rows;
  }

  public async queryFirst<T = Record<string, unknown>>(sql: string, params: unknown[] = []): Promise<T | null> {
    const rows = await this.query<T>(sql, params);
    return rows.length > 0 ? (rows[0] ?? null) : null;
  }

  public async runBatch(statements: DbStatement[]): Promise<void> {
    if (!this.db) {
      throw new Error('Database is closed');
    }
    const transaction = this.db.transaction((stmts: DbStatement[]) => {
      for (const statement of stmts) {
        const prep = this.db!.prepare(statement.sql);
        prep.run(...(statement.params ?? []));
      }
    });

    transaction(statements);
  }

  public async close(): Promise<void> {
    if (this.db) {
      this.db.close();
      this.db = null;
    }
  }
}
