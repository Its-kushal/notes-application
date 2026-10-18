import { Kdf, ScryptParams } from '@notes/core';
import QuickCrypto from 'react-native-quick-crypto';

export class NativeKdf implements Kdf {
  public async deriveKey(passcode: string, salt: Uint8Array, params: ScryptParams): Promise<Uint8Array> {
    return new Promise<Uint8Array>((resolve, reject) => {
      const options = {
        N: params.N,
        r: params.r,
        p: params.p,
        maxmem: params.maxmem ?? 140 * 1024 * 1024,
      };

      QuickCrypto.scrypt(
        passcode,
        QuickCrypto.Buffer.from(salt),
        32,
        options,
        (err: Error | null, key?: { length: number } | Uint8Array) => {
          if (err) {
            reject(err);
          } else if (key) {
            resolve(new Uint8Array(key as unknown as ArrayBuffer));
          } else {
            reject(new Error('No key derived by scrypt'));
          }
        }
      );
    });
  }
}
