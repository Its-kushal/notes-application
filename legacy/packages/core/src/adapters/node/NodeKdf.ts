import crypto from 'crypto';
import { Kdf, ScryptParams } from '../../ports';

export class NodeKdf implements Kdf {
  public async deriveKey(passcode: string, salt: Uint8Array, params: ScryptParams): Promise<Uint8Array> {
    return new Promise<Uint8Array>((resolve, reject) => {
      const options: crypto.ScryptOptions = {
        N: params.N,
        r: params.r,
        p: params.p,
        maxmem: params.maxmem ?? 140 * 1024 * 1024,
      };

      crypto.scrypt(passcode, salt, 32, options, (err, derivedKey) => {
        if (err) {
          reject(err);
        } else {
          resolve(new Uint8Array(derivedKey));
        }
      });
    });
  }
}
