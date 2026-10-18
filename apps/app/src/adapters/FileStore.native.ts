import { FileStore } from '@notes/core';
import { File, Paths } from 'expo-file-system';

export class NativeFileStore implements FileStore {
  private resolveFile(path: string): File {
    if (path.startsWith('file://')) {
      return new File(path);
    }
    if (path.startsWith('/')) {
      return new File(`file://${path}`);
    }
    return new File(Paths.document, path);
  }

  public async readFile(path: string): Promise<Uint8Array> {
    const file = this.resolveFile(path);
    return file.bytes();
  }

  public async writeFile(path: string, content: Uint8Array): Promise<void> {
    const file = this.resolveFile(path);
    file.write(content);
  }

  public async deleteFile(path: string): Promise<void> {
    try {
      const file = this.resolveFile(path);
      if (file.exists) {
        file.delete();
      }
    } catch {
      // Best-effort
    }
  }

  public async exists(path: string): Promise<boolean> {
    try {
      const file = this.resolveFile(path);
      return file.exists;
    } catch {
      return false;
    }
  }

  public async getFreeDiskSpace(): Promise<number> {
    try {
      return Paths.availableDiskSpace;
    } catch {
      return 1024 * 1024 * 1024; // 1 GB fallback
    }
  }
}
