import crypto from 'crypto';
import { Cipher } from '../../ports';

export class NodeCipher implements Cipher {
  public async encrypt(
    plaintext: Uint8Array,
    key: Uint8Array,
    aad?: Uint8Array
  ): Promise<{ ciphertext: Uint8Array; nonce: Uint8Array; authTag: Uint8Array }> {
    const nonce = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv('aes-256-gcm', key, nonce);
    if (aad) {
      cipher.setAAD(aad);
    }
    const update = cipher.update(plaintext);
    const final = cipher.final();
    const ciphertext = Buffer.concat([update, final]);
    const authTag = cipher.getAuthTag();

    return {
      ciphertext: new Uint8Array(ciphertext),
      nonce: new Uint8Array(nonce),
      authTag: new Uint8Array(authTag),
    };
  }

  public async decrypt(
    ciphertext: Uint8Array,
    key: Uint8Array,
    nonce: Uint8Array,
    authTag: Uint8Array,
    aad?: Uint8Array
  ): Promise<Uint8Array> {
    const decipher = crypto.createDecipheriv('aes-256-gcm', key, nonce);
    if (aad) {
      decipher.setAAD(aad);
    }
    decipher.setAuthTag(authTag);
    const update = decipher.update(ciphertext);
    const final = decipher.final();
    const plaintext = Buffer.concat([update, final]);
    return new Uint8Array(plaintext);
  }
}
