import { Cipher, DbDriver, Kdf, ScryptParams } from '../ports';

export interface SecurityMetadataRow {
  id: number;
  vault_salt: Uint8Array;
  scrypt_n: number;
  scrypt_r: number;
  scrypt_p: number;
  wrapped_vault_key: Uint8Array;
  wrapped_nonce: Uint8Array;
  wrapped_tag: Uint8Array;
  created_at: number;
  updated_at: number;
}

export class VaultRepository {
  constructor(
    private readonly db: DbDriver,
    private readonly cipher: Cipher,
    private readonly kdf: Kdf
  ) {}

  public async hasVault(): Promise<boolean> {
    const row = await this.db.queryFirst<{ id: number }>('SELECT id FROM security_metadata WHERE id = 1;');
    return row !== null;
  }

  public async setupVault(passcode: string, customParams?: Partial<ScryptParams>): Promise<Uint8Array> {
    const exists = await this.hasVault();
    if (exists) {
      throw new Error('Vault is already configured');
    }

    const salt = new Uint8Array(16);
    if (typeof crypto !== 'undefined' && crypto.getRandomValues) {
      crypto.getRandomValues(salt);
    } else {
      for (let i = 0; i < 16; i++) {
        salt[i] = Math.floor(Math.random() * 256);
      }
    }

    const scryptParams: ScryptParams = {
      N: customParams?.N ?? 131072,
      r: customParams?.r ?? 8,
      p: customParams?.p ?? 1,
      maxmem: customParams?.maxmem ?? 140 * 1024 * 1024,
    };

    // Derive KEK (Key Encryption Key)
    const kek = await this.kdf.deriveKey(passcode, salt, scryptParams);

    // Generate random 256-bit Vault Key (DEK)
    const vaultKey = new Uint8Array(32);
    if (typeof crypto !== 'undefined' && crypto.getRandomValues) {
      crypto.getRandomValues(vaultKey);
    } else {
      for (let i = 0; i < 32; i++) {
        vaultKey[i] = Math.floor(Math.random() * 256);
      }
    }

    // Wrap the Vault Key
    const aad = new TextEncoder().encode('vault_key_wrapping_v1');
    const { ciphertext, nonce, authTag } = await this.cipher.encrypt(vaultKey, kek, aad);

    const now = Date.now();
    await this.db.runBatch([
      {
        sql: `INSERT INTO security_metadata(
          id, vault_salt, scrypt_n, scrypt_r, scrypt_p,
          wrapped_vault_key, wrapped_nonce, wrapped_tag, created_at, updated_at
        ) VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, ?);`,
        params: [
          salt,
          scryptParams.N,
          scryptParams.r,
          scryptParams.p,
          ciphertext,
          nonce,
          authTag,
          now,
          now,
        ],
      },
    ]);

    return vaultKey;
  }

  public async unlockVault(passcode: string): Promise<Uint8Array | null> {
    const row = await this.db.queryFirst<SecurityMetadataRow>('SELECT * FROM security_metadata WHERE id = 1;');
    if (!row) {
      return null;
    }

    try {
      const scryptParams: ScryptParams = {
        N: row.scrypt_n,
        r: row.scrypt_r,
        p: row.scrypt_p,
      };

      const kek = await this.kdf.deriveKey(passcode, row.vault_salt, scryptParams);
      const aad = new TextEncoder().encode('vault_key_wrapping_v1');
      const decrypted = await this.cipher.decrypt(
        row.wrapped_vault_key,
        kek,
        row.wrapped_nonce,
        row.wrapped_tag,
        aad
      );

      return decrypted;
    } catch {
      // Authentication tag mismatch or decryption failure
      return null;
    }
  }

  public async changePasscode(oldPasscode: string, newPasscode: string): Promise<boolean> {
    const vaultKey = await this.unlockVault(oldPasscode);
    if (!vaultKey) {
      return false;
    }

    const newSalt = new Uint8Array(16);
    if (typeof crypto !== 'undefined' && crypto.getRandomValues) {
      crypto.getRandomValues(newSalt);
    } else {
      for (let i = 0; i < 16; i++) {
        newSalt[i] = Math.floor(Math.random() * 256);
      }
    }

    const scryptParams: ScryptParams = {
      N: 131072,
      r: 8,
      p: 1,
    };

    const newKek = await this.kdf.deriveKey(newPasscode, newSalt, scryptParams);
    const aad = new TextEncoder().encode('vault_key_wrapping_v1');
    const { ciphertext, nonce, authTag } = await this.cipher.encrypt(vaultKey, newKek, aad);

    const now = Date.now();
    await this.db.runBatch([
      {
        sql: `UPDATE security_metadata SET
          vault_salt = ?, scrypt_n = ?, scrypt_r = ?, scrypt_p = ?,
          wrapped_vault_key = ?, wrapped_nonce = ?, wrapped_tag = ?, updated_at = ?
        WHERE id = 1;`,
        params: [
          newSalt,
          scryptParams.N,
          scryptParams.r,
          scryptParams.p,
          ciphertext,
          nonce,
          authTag,
          now,
        ],
      },
    ]);

    return true;
  }
}
