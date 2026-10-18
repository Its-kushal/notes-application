import { Exporter } from '@notes/core';
import { File, Paths } from 'expo-file-system';
import * as Sharing from 'expo-sharing';

export class NativeExporter implements Exporter {
  public async exportText(filename: string, content: string): Promise<{ success: boolean; uri?: string }> {
    try {
      const file = new File(Paths.cache, filename);
      file.write(content);

      const canShare = await Sharing.isAvailableAsync();
      if (canShare) {
        await Sharing.shareAsync(file.uri, {
          mimeType: 'text/plain',
          dialogTitle: `Export ${filename}`,
          UTI: 'public.plain-text',
        });
      }

      return { success: true, uri: file.uri };
    } catch {
      return { success: false };
    }
  }
}
