import { Exporter } from '@notes/core';

export class WebExporter implements Exporter {
  public async exportText(filename: string, content: string): Promise<{ success: boolean; uri?: string }> {
    try {
      if (typeof document !== 'undefined') {
        const blob = new Blob([content], { type: 'text/plain;charset=utf-8' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = filename;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);
        return { success: true, uri: url };
      }
      return { success: true };
    } catch {
      return { success: false };
    }
  }
}
