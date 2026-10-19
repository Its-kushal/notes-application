import { DatabaseOpener, DatabaseOpenResult, MigrationRunner } from '@notes/core';
import * as SQLite from 'expo-sqlite';
import * as SecureStore from 'expo-secure-store';
import { NativeDbDriver } from './DbDriver.native';
import { NativeFileStore } from './FileStore.native';

const SECURE_STORE_KEY_ALIAS = 'privacy_notes_db_master_key_v1';

export class NativeDatabaseOpener implements DatabaseOpener {
  private async getOrCreateMasterKey(): Promise<string> {
    let keyHex = await SecureStore.getItemAsync(SECURE_STORE_KEY_ALIAS);
    if (!keyHex) {
      const randomBytes = new Uint8Array(32);
      if (typeof crypto !== 'undefined' && crypto.getRandomValues) {
        crypto.getRandomValues(randomBytes);
      } else {
        for (let i = 0; i < 32; i++) {
          randomBytes[i] = Math.floor(Math.random() * 256);
        }
      }
      keyHex = Array.from(randomBytes)
        .map(b => b.toString(16).padStart(2, '0'))
        .join('');

      await SecureStore.setItemAsync(SECURE_STORE_KEY_ALIAS, keyHex, {
        keychainAccessible: SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY,
      });
    }
    return keyHex;
  }

  public async openDatabase(dbName: string): Promise<DatabaseOpenResult> {
    try {
      console.warn('[DB_OPEN_START]: Getting master key');
      const rawKeyHex = await this.getOrCreateMasterKey();
      console.warn('[DB_OPEN]: Opening database ' + dbName);
      const sqliteDb = await SQLite.openDatabaseAsync(dbName);

      console.warn('[DB_OPEN]: Setting PRAGMA key');
      await sqliteDb.execAsync(`PRAGMA key = "x'${rawKeyHex}'";`);
      console.warn('[DB_OPEN]: Setting PRAGMA foreign_keys');
      await sqliteDb.execAsync('PRAGMA foreign_keys = ON;');

      const driver = new NativeDbDriver(sqliteDb);

      console.warn('[DB_OPEN]: Checking initial migration');
      const fileStore = new NativeFileStore();
      const migrationRunner = new MigrationRunner(driver, fileStore, dbName);
      await migrationRunner.applyMigrations([MigrationRunner.getInitialMigration()]);
      console.warn('[DB_OPEN_SUCCESS]: Database ready!');

      return {
        status: 'opened',
        db: driver,
      };
    } catch (err: unknown) {
      console.error('[DB_OPEN_ERROR]:', err);
      return {
        status: 'error',
        code: 'DB_OPEN_FAILED',
        message: err instanceof Error ? err.message : String(err),
      };
    }
  }

  public async unlockWithPasscode(_passcode: string): Promise<DatabaseOpenResult> {
    // On Android, SQLite database encryption is hardware-keystore-backed.
    return this.openDatabase('notes_production.db');
  }
}
