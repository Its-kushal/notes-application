import { DbDriver, FileStore } from '../ports';
import { INITIAL_SCHEMA_SQL } from '../schema';

export interface Migration {
  version: number;
  description: string;
  up(db: DbDriver): Promise<void>;
}

export class MigrationRunner {
  constructor(
    private readonly db: DbDriver,
    private readonly fileStore: FileStore,
    private readonly dbPath: string
  ) {}

  public async getAppliedVersions(): Promise<number[]> {
    // Check if migration table exists
    const hasTable = await this.db.queryFirst<{ name: string }>(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='migration';"
    );
    if (!hasTable) {
      return [];
    }

    const rows = await this.db.query<{ version: number }>(
      'SELECT version FROM migration ORDER BY version ASC;'
    );
    return rows.map(r => r.version);
  }

  public async applyMigrations(migrations: Migration[]): Promise<void> {
    const applied = await this.getAppliedVersions();
    const pending = migrations.filter(m => !applied.includes(m.version));

    if (pending.length === 0) {
      return;
    }

    // 1. Check free disk space before touching database
    const freeSpace = await this.fileStore.getFreeDiskSpace();
    let currentDbSize = 1024 * 1024; // Default 1MB if new
    if (await this.fileStore.exists(this.dbPath)) {
      const dbBytes = await this.fileStore.readFile(this.dbPath);
      currentDbSize = Math.max(dbBytes.length, 1024 * 1024);
    }

    if (freeSpace < currentDbSize * 2) {
      throw new Error(`Insufficient disk space for migration snapshot. Required: ${currentDbSize * 2} bytes, Available: ${freeSpace} bytes`);
    }

    // 2. Checkpoint WAL
    try {
      await this.db.query('PRAGMA wal_checkpoint(TRUNCATE);');
    } catch {
      // If table doesn't exist or not in WAL mode, continue
    }

    // 3. Create pre-migration snapshot if db file exists
    const snapshotPath = `${this.dbPath}.snapshot_${Date.now()}`;
    let createdSnapshot = false;
    if (await this.fileStore.exists(this.dbPath)) {
      const content = await this.fileStore.readFile(this.dbPath);
      await this.fileStore.writeFile(snapshotPath, content);
      createdSnapshot = true;
    }

    try {
      for (const migration of pending) {
        await migration.up(this.db);
        const now = Date.now();
        await this.db.runBatch([
          {
            sql: 'INSERT INTO migration (version, applied_at, description) VALUES (?, ?, ?);',
            params: [migration.version, now, migration.description],
          },
        ]);
      }

      // Cleanup snapshot on success
      if (createdSnapshot && (await this.fileStore.exists(snapshotPath))) {
        await this.fileStore.deleteFile(snapshotPath);
      }
    } catch (err) {
      // Rollback from snapshot if failure occurred
      if (createdSnapshot && (await this.fileStore.exists(snapshotPath))) {
        await this.db.close();
        const snapshotBytes = await this.fileStore.readFile(snapshotPath);
        await this.fileStore.writeFile(this.dbPath, snapshotBytes);
        await this.fileStore.deleteFile(snapshotPath);
      }
      throw err;
    }
  }

  public static getInitialMigration(): Migration {
    return {
      version: 1,
      description: 'Initial schema setup',
      up: async (db: DbDriver) => {
        // Split by statement and run
        const stmts = INITIAL_SCHEMA_SQL
          .split(';')
          .map(s => s.trim())
          .filter(s => s.length > 0);

        for (const sql of stmts) {
          await db.runBatch([{ sql: `${sql};` }]);
        }
      },
    };
  }
}
