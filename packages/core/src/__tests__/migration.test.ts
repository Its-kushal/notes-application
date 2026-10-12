import { NodeDbDriver } from '../adapters/node/NodeDbDriver';
import { NodeFileStore } from '../adapters/node/NodeFileStore';
import { Migration, MigrationRunner } from '../services/MigrationRunner';
import fs from 'fs';
import path from 'path';

describe('MigrationRunner', () => {
  const testDbPath = path.join(__dirname, 'test_migration.db');
  let db: NodeDbDriver;
  let fileStore: NodeFileStore;

  beforeEach(() => {
    if (fs.existsSync(testDbPath)) {
      fs.unlinkSync(testDbPath);
    }
    db = new NodeDbDriver(testDbPath);
    fileStore = new NodeFileStore();
  });

  afterEach(async () => {
    await db.close();
    if (fs.existsSync(testDbPath)) {
      fs.unlinkSync(testDbPath);
    }
  });

  test('applies initial migration successfully', async () => {
    const runner = new MigrationRunner(db, fileStore, testDbPath);
    const initialMigration = MigrationRunner.getInitialMigration();

    await runner.applyMigrations([initialMigration]);
    const applied = await runner.getAppliedVersions();
    expect(applied).toEqual([1]);

    // Verify tables exist
    const noteTable = await db.queryFirst<any>(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='note';"
    );
    expect(noteTable).not.toBeNull();
  });

  test('aborts migration if available disk space is less than 2x DB size', async () => {
    // Mock fileStore with low free disk space
    const lowSpaceStore: NodeFileStore = {
      ...fileStore,
      readFile: fileStore.readFile.bind(fileStore),
      writeFile: fileStore.writeFile.bind(fileStore),
      deleteFile: fileStore.deleteFile.bind(fileStore),
      exists: fileStore.exists.bind(fileStore),
      getFreeDiskSpace: async () => 100, // Only 100 bytes available
    };

    const runner = new MigrationRunner(db, lowSpaceStore, testDbPath);
    await expect(runner.applyMigrations([MigrationRunner.getInitialMigration()])).rejects.toThrow(
      /Insufficient disk space/
    );
  });

  test('rolls back database from snapshot if a subsequent migration fails', async () => {
    const runner = new MigrationRunner(db, fileStore, testDbPath);
    await runner.applyMigrations([MigrationRunner.getInitialMigration()]);

    // Insert data into DB before failing migration
    await db.runBatch([
      {
        sql: "INSERT INTO note (id, title, created_at, updated_at) VALUES ('m_note_1', 'Original Note', 100, 100);",
      },
    ]);

    const failingMigration: Migration = {
      version: 2,
      description: 'Failing schema alteration',
      up: async (dbDriver) => {
        await dbDriver.runBatch([
          { sql: 'CREATE TABLE temp_valid (id INTEGER);' },
          { sql: 'SYNTAX ERROR THAT WILL DEFINITELY FAIL;' },
        ]);
      },
    };

    await expect(runner.applyMigrations([MigrationRunner.getInitialMigration(), failingMigration])).rejects.toThrow();

    // Re-open DB and verify data is still intact from snapshot
    const reopenedDb = new NodeDbDriver(testDbPath);
    const noteRow = await reopenedDb.queryFirst<any>("SELECT * FROM note WHERE id = 'm_note_1';");
    expect(noteRow).not.toBeNull();
    expect(noteRow.title).toBe('Original Note');

    // And temp_valid table does NOT exist
    const tempTable = await reopenedDb.queryFirst<any>(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='temp_valid';"
    );
    expect(tempTable).toBeNull();
    await reopenedDb.close();
  });
});
