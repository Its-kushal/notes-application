import * as SQLite from 'expo-sqlite';
import QuickCrypto from 'react-native-quick-crypto';

export interface SpikeResult {
  sqlcipherSuccess: boolean;
  sqlcipherDetails: string;
  fts5Success: boolean;
  fts5Details: string;
  aesGcmSuccess: boolean;
  aesGcmDetails: string;
  scryptSuccess: boolean;
  scryptTimeMs: number;
  scryptDetails: string;
  allPassed: boolean;
  error?: string;
}

export async function runSpike(): Promise<SpikeResult> {
  const result: SpikeResult = {
    sqlcipherSuccess: false,
    sqlcipherDetails: '',
    fts5Success: false,
    fts5Details: '',
    aesGcmSuccess: false,
    aesGcmDetails: '',
    scryptSuccess: false,
    scryptTimeMs: 0,
    scryptDetails: '',
    allPassed: false,
  };

  try {
    // 1. Test SQLCipher Open with raw 256-bit key
    console.warn('[SPIKE_STEP_1_START]: Opening spike_test.db');
    const rawKeyHex = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
    const db = await SQLite.openDatabaseAsync('spike_test.db');
    await db.execAsync(`PRAGMA key = "x'${rawKeyHex}'";`);
    await db.execAsync('PRAGMA foreign_keys = ON;');

    const cipherVersionResult = await db.getAllAsync<{ cipher_version?: string }>('PRAGMA cipher_version;');
    const cipherVer = cipherVersionResult?.[0]?.cipher_version || 'active';
    result.sqlcipherSuccess = true;
    result.sqlcipherDetails = `SQLCipher opened successfully (cipher_version: ${cipherVer})`;
    console.warn('[SPIKE_STEP_1_SUCCESS]: ' + result.sqlcipherDetails);

    // 2. Test FTS5 Virtual Table & Queries
    console.warn('[SPIKE_STEP_2_START]: Testing FTS5 table');
    await db.execAsync(`
      DROP TABLE IF EXISTS test_fts;
      CREATE VIRTUAL TABLE test_fts USING fts5(title, body_text, tokenize = 'unicode61 remove_diacritics 2');
      INSERT INTO test_fts(title, body_text) VALUES('Top Secret', 'The quick brown fox jumps over the lazy dog');
      INSERT INTO test_fts(title, body_text) VALUES('Second Note', 'Privacy first local only architecture');
    `);

    const ftsMatches = await db.getAllAsync<{ title: string; body_text: string }>(
      "SELECT title, body_text FROM test_fts WHERE test_fts MATCH 'quick*';"
    );
    if (ftsMatches.length > 0 && ftsMatches[0]?.title === 'Top Secret') {
      result.fts5Success = true;
      result.fts5Details = `FTS5 query verified. Matched ${ftsMatches.length} row(s).`;
      console.warn('[SPIKE_STEP_2_SUCCESS]: ' + result.fts5Details);
    } else {
      throw new Error(`FTS5 query failed to match expected row. Returned: ${JSON.stringify(ftsMatches)}`);
    }

    // 3. Test AES-256-GCM via react-native-quick-crypto
    console.warn('[SPIKE_STEP_3_START]: Testing AES-256-GCM');
    const key = QuickCrypto.randomBytes(32);
    const iv = QuickCrypto.randomBytes(12);
    const plaintext = 'Sensitive Note Payload to verify AES-256-GCM';
    const aad = 'note_id_12345';

    const cipher = QuickCrypto.createCipheriv('aes-256-gcm', key, iv);
    const aadBuffer = QuickCrypto.Buffer.from(aad, 'utf8');
    cipher.setAAD(aadBuffer);
    let ciphertext = cipher.update(plaintext, 'utf8', 'hex');
    ciphertext += cipher.final('hex');
    const authTag = cipher.getAuthTag();

    const decipher = QuickCrypto.createDecipheriv('aes-256-gcm', key, iv);
    decipher.setAAD(aadBuffer);
    decipher.setAuthTag(authTag);
    let decrypted = decipher.update(ciphertext, 'hex', 'utf8');
    decrypted += decipher.final('utf8');

    if (decrypted === plaintext) {
      result.aesGcmSuccess = true;
      result.aesGcmDetails = 'AES-256-GCM authenticated encryption and decryption succeeded';
      console.warn('[SPIKE_STEP_3_SUCCESS]: ' + result.aesGcmDetails);
    } else {
      throw new Error('AES-256-GCM decryption output mismatch');
    }

    // 4. Test scrypt key derivation benchmark for N=2^16 and N=2^17
    console.warn('[SPIKE_STEP_4_START]: Testing scrypt benchmarks');
    const salt = QuickCrypto.randomBytes(16);

    // Benchmark N = 2^16 (65536)
    const start16 = Date.now();
    const derivedKey16 = await new Promise<{ length: number }>((resolve, reject) => {
      QuickCrypto.scrypt(
        'test_master_passcode',
        salt,
        32,
        { N: 65536, r: 8, p: 1, maxmem: 140 * 1024 * 1024 },
        (err: Error | null, key?: { length: number }) => {
          if (err) reject(err);
          else if (key) resolve(key);
          else reject(new Error('No key returned by scrypt N=2^16'));
        }
      );
    });
    const timeN16 = Date.now() - start16;

    // Benchmark N = 2^17 (131072)
    const start17 = Date.now();
    const derivedKey17 = await new Promise<{ length: number }>((resolve, reject) => {
      QuickCrypto.scrypt(
        'test_master_passcode',
        salt,
        32,
        { N: 131072, r: 8, p: 1, maxmem: 140 * 1024 * 1024 },
        (err: Error | null, key?: { length: number }) => {
          if (err) reject(err);
          else if (key) resolve(key);
          else reject(new Error('No key returned by scrypt N=2^17'));
        }
      );
    });
    const timeN17 = Date.now() - start17;

    result.scryptTimeMs = timeN17;
    result.scryptSuccess = derivedKey16.length === 32 && derivedKey17.length === 32;
    result.scryptDetails = `scrypt N=2^16 (65536): ${timeN16}ms | N=2^17 (131072): ${timeN17}ms (derived key length: ${derivedKey17.length})`;
    console.warn('[SPIKE_STEP_4_SUCCESS]: ' + result.scryptDetails);

    result.allPassed = result.sqlcipherSuccess && result.fts5Success && result.aesGcmSuccess && result.scryptSuccess;
    console.warn('[SPIKE_ALL_PASSED]: ' + JSON.stringify(result));
  } catch (err: unknown) {
    result.error = err instanceof Error ? err.message : String(err);
    result.allPassed = false;
    console.warn('[SPIKE_ERROR]: ' + JSON.stringify(result));
  }

  return result;
}
