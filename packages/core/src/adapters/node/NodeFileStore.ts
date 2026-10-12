import fs from 'fs/promises';
import { FileStore } from '../../ports';

export class NodeFileStore implements FileStore {
  public async readFile(path: string): Promise<Uint8Array> {
    const buffer = await fs.readFile(path);
    return new Uint8Array(buffer);
  }

  public async writeFile(path: string, content: Uint8Array): Promise<void> {
    await fs.writeFile(path, Buffer.from(content));
  }

  public async deleteFile(path: string): Promise<void> {
    await fs.unlink(path);
  }

  public async exists(path: string): Promise<boolean> {
    try {
      await fs.access(path);
      return true;
    } catch {
      return false;
    }
  }

  public async getFreeDiskSpace(path: string = '/'): Promise<number> {
    try {
      if (typeof fs.statfs === 'function') {
        const stats = await fs.statfs(path);
        return Number(stats.bavail * stats.bsize);
      }
      return 1024 * 1024 * 1024 * 10; // 10 GB default fallback
    } catch {
      return 1024 * 1024 * 1024 * 10;
    }
  }
}
