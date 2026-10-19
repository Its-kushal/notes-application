// Crockford's Base32 encoding
const ENCODING = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
const ENCODING_LEN = ENCODING.length;

function encodeTime(now: number, len: number): string {
  let str = '';
  for (let i = len - 1; i >= 0; i--) {
    const mod = now % ENCODING_LEN;
    str = ENCODING.charAt(mod) + str;
    now = (now - mod) / ENCODING_LEN;
  }
  return str;
}

function encodeRandom(len: number, randomBytes: Uint8Array): string {
  let str = '';
  for (let i = 0; i < len; i++) {
    const byte = randomBytes[i] ?? 0;
    str += ENCODING.charAt(byte % ENCODING_LEN);
  }
  return str;
}

export function generateUlid(timestampMs?: number, randomBytesProvider?: (count: number) => Uint8Array): string {
  const time = timestampMs ?? Date.now();
  const timeStr = encodeTime(time, 10);
  
  const randBytes = randomBytesProvider
    ? randomBytesProvider(16)
    : (() => {
        const arr = new Uint8Array(16);
        if (typeof crypto !== 'undefined' && crypto.getRandomValues) {
          crypto.getRandomValues(arr);
        } else {
          for (let i = 0; i < 16; i++) {
            arr[i] = Math.floor(Math.random() * 256);
          }
        }
        return arr;
      })();

  const randStr = encodeRandom(16, randBytes);
  return timeStr + randStr;
}
