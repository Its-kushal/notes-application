import { Cipher } from '@notes/core';
import QuickCrypto from 'react-native-quick-crypto';

export class NativeCipher implements Cipher {
  public async encrypt(
    plaintext: Uint8Array,
    key: Uint8Array,
    aad?: Uint8Array
  ): Promise<{ ciphertext: Uint8Array; nonce: Uint8Array; authTag: Uint8Array }> {
    const nonce = QuickCrypto.randomBytes(12);
    const cipher = QuickCrypto.createCipheriv(
      'aes-256-gcm',
      QuickCrypto.Buffer.from(key),
      QuickCrypto.Buffer.from(nonce)
    );

    if (aad) {
      cipher.setAAD(QuickCrypto.Buffer.from(aad));
    }

    const update = cipher.update(QuickCrypto.Buffer.from(plaintext));
    const final = cipher.final();
    const ciphertext = QuickCrypto.Buffer.concat([update, final]);
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
    const decipher = QuickCrypto.createDecipheriv(
      'aes-256-gcm',
      QuickCrypto.Buffer.from(key),
      QuickCrypto.Buffer.from(nonce)
    );

    if (aad) {
      decipher.setAAD(QuickCrypto.Buffer.from(aad));
    }
    decipher.setAuthTag(QuickCrypto.Buffer.from(authTag));

    const update = decipher.update(QuickCrypto.Buffer.from(ciphertext));
    const final = decipher.final();
    const plaintext = QuickCrypto.Buffer.concat([update, final]);
    return new Uint8Array(plaintext);
  }
}
