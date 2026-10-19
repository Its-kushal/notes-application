import { DbDriver, DbStatement } from '@notes/core';
import * as SQLite from 'expo-sqlite';

export class NativeDbDriver implements DbDriver {
  private db: SQLite.SQLiteDatabase | null;
  private writeQueue: Promise<void> = Promise.resolve();

  constructor(db: SQLite.SQLiteDatabase) {
    this.db = db;
  }

  private serializeWrite<T>(operation: () => Promise<T>): Promise<T> {
    const nextPromise = this.writeQueue.then(operation);
    this.writeQueue = nextPromise.then(
      () => {},
      () => {}
    );
    return nextPromise;
  }

  public async query<T = Record<string, unknown>>(sql: string, params: unknown[] = []): Promise<T[]> {
    if (!this.db) {
      throw new Error('Database is closed');
    }
    const rows = await this.db.getAllAsync<T>(sql, ...(params as SQLite.SQLiteBindValue[]));
    return rows;
  }

  public async queryFirst<T = Record<string, unknown>>(sql: string, params: unknown[] = []): Promise<T | null> {
    if (!this.db) {
      throw new Error('Database is closed');
    }
    const row = await this.db.getFirstAsync<T>(sql, ...(params as SQLite.SQLiteBindValue[]));
    return row ?? null;
  }

  public async runBatch(statements: DbStatement[]): Promise<void> {
    if (!this.db) {
      throw new Error('Database is closed');
    }

    return this.serializeWrite(async () => {
      if (!this.db) throw new Error('Database is closed');

      await this.db.execAsync('BEGIN TRANSACTION;');
      try {
        for (const statement of statements) {
          if (statement.params && statement.params.length > 0) {
            await this.db.runAsync(statement.sql, ...(statement.params as SQLite.SQLiteBindValue[]));
          } else {
            await this.db.execAsync(statement.sql);
          }
        }
        await this.db.execAsync('COMMIT;');
      } catch (err) {
        try {
          await this.db.execAsync('ROLLBACK;');
        } catch {
          // ignore rollback error
        }
        throw err;
      }
    });
  }

  public async close(): Promise<void> {
    if (this.db) {
      await this.db.closeAsync();
      this.db = null;
    }
  }
}
