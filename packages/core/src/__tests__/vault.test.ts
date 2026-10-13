import { NodeCipher } from '../adapters/node/NodeCipher';
import { NodeKdf } from '../adapters/node/NodeKdf';
import { NodeDbDriver } from '../adapters/node/NodeDbDriver';
import { VaultRepository } from '../repositories/VaultRepository';
import { INITIAL_SCHEMA_SQL } from '../schema';
import fs from 'fs';
import path from 'path';

describe('VaultRepository & Cryptography', () => {
  const testDbPath = path.join(__dirname, 'test_vault.db');
  let db: NodeDbDriver;
  let cipher: NodeCipher;
  let kdf: NodeKdf;
  let vaultRepo: VaultRepository;

  beforeEach(async () => {
    if (fs.existsSync(testDbPath)) {
      fs.unlinkSync(testDbPath);
    }
    db = new NodeDbDriver(testDbPath);
    const stmts = INITIAL_SCHEMA_SQL.split(';')
      .map(s => s.trim())
      .filter(s => s.length > 0);
    for (const sql of stmts) {
      await db.runBatch([{ sql: `${sql};` }]);
    }

    cipher = new NodeCipher();
    kdf = new NodeKdf();
    vaultRepo = new VaultRepository(db, cipher, kdf);
  });

  afterEach(async () => {
    await db.close();
    if (fs.existsSync(testDbPath)) {
      fs.unlinkSync(testDbPath);
    }
  });

  test('setupVault creates salt and wrapped vault key', async () => {
    expect(await vaultRepo.hasVault()).toBe(false);
    // Use smaller N for fast unit test
    const vaultKey = await vaultRepo.setupVault('Secret123!', { N: 1024 });
    expect(vaultKey.length).toBe(32);
    expect(await vaultRepo.hasVault()).toBe(true);

    const row = await db.queryFirst<any>('SELECT * FROM security_metadata WHERE id = 1;');
    expect(row).not.toBeNull();
    expect(row.scrypt_n).toBe(1024);
    expect(row.wrapped_vault_key).toBeDefined();
    expect(row.wrapped_nonce).toBeDefined();
    expect(row.wrapped_tag).toBeDefined();
  });

  test('unlockVault succeeds with correct passcode', async () => {
    const originalKey = await vaultRepo.setupVault('CorrectPass!', { N: 1024 });
    const unlockedKey = await vaultRepo.unlockVault('CorrectPass!');
    expect(unlockedKey).not.toBeNull();
    expect(Buffer.from(unlockedKey!).equals(Buffer.from(originalKey))).toBe(true);
  });

  test('unlockVault fails cleanly with wrong passcode', async () => {
    await vaultRepo.setupVault('CorrectPass!', { N: 1024 });
    const unlockedKey = await vaultRepo.unlockVault('WrongPass!');
    expect(unlockedKey).toBeNull();
  });

  test('AES-GCM tamper detection fails if ciphertext or tag is modified', async () => {
    const key = new Uint8Array(32).fill(7);
    const plaintext = new TextEncoder().encode('Sensitive data');
    const aad = new TextEncoder().encode('note_1');

    const encrypted = await cipher.encrypt(plaintext, key, aad);

    // Tamper with ciphertext
    const tamperedCiphertext = new Uint8Array(encrypted.ciphertext);
    tamperedCiphertext[0] = (tamperedCiphertext[0] ?? 0) ^ 0xff;

    await expect(
      cipher.decrypt(tamperedCiphertext, key, encrypted.nonce, encrypted.authTag, aad)
    ).rejects.toThrow();

    // Tamper with auth tag
    const tamperedTag = new Uint8Array(encrypted.authTag);
    tamperedTag[0] = (tamperedTag[0] ?? 0) ^ 0xff;

    await expect(
      cipher.decrypt(encrypted.ciphertext, key, encrypted.nonce, tamperedTag, aad)
    ).rejects.toThrow();
  });
});
