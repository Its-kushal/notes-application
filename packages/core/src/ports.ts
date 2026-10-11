export interface DbStatement {
  sql: string;
  params?: unknown[];
}

export interface DbDriver {
  query<T = Record<string, unknown>>(sql: string, params?: unknown[]): Promise<T[]>;
  queryFirst<T = Record<string, unknown>>(sql: string, params?: unknown[]): Promise<T | null>;
  runBatch(statements: DbStatement[]): Promise<void>;
  close(): Promise<void>;
}

export type DatabaseOpenResult =
  | { status: 'opened'; db: DbDriver }
  | { status: 'needs-passcode' }
  | { status: 'error'; code: string; message: string };

export interface DatabaseOpener {
  openDatabase(dbName: string): Promise<DatabaseOpenResult>;
  unlockWithPasscode(passcode: string): Promise<DatabaseOpenResult>;
}

export interface KeyStore {
  get(key: string): Promise<string | null>;
  set(key: string, value: string): Promise<void>;
  delete(key: string): Promise<void>;
}

export interface Cipher {
  encrypt(plaintext: Uint8Array, key: Uint8Array, aad?: Uint8Array): Promise<{
    ciphertext: Uint8Array;
    nonce: Uint8Array;
    authTag: Uint8Array;
  }>;
  decrypt(
    ciphertext: Uint8Array,
    key: Uint8Array,
    nonce: Uint8Array,
    authTag: Uint8Array,
    aad?: Uint8Array
  ): Promise<Uint8Array>;
}

export interface ScryptParams {
  N: number;
  r: number;
  p: number;
  maxmem?: number;
}

export interface Kdf {
  deriveKey(passcode: string, salt: Uint8Array, params: ScryptParams): Promise<Uint8Array>;
}

export interface FileStore {
  readFile(path: string): Promise<Uint8Array>;
  writeFile(path: string, content: Uint8Array): Promise<void>;
  deleteFile(path: string): Promise<void>;
  exists(path: string): Promise<boolean>;
  getFreeDiskSpace(): Promise<number>; // Bytes
}

export interface Exporter {
  exportText(filename: string, content: string): Promise<{ success: boolean; uri?: string }>;
}

export interface PrivacyScreen {
  enable(): Promise<void>;
  disable(): Promise<void>;
}

export interface Clock {
  now(): number; // epoch ms
}
