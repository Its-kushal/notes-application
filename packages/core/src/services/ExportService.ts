import { Note, NoteBlock } from '../models';

const WINDOWS_RESERVED_NAMES = new Set([
  'CON', 'PRN', 'AUX', 'NUL',
  'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
  'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
]);

export class ExportService {
  /**
   * Sanitizes a string for use as a cross-platform safe filename.
   */
  public static sanitizeFilename(name: string, fallback = 'untitled_note'): string {
    let clean = name.replace(/[<>:"/\\|?*\x00-\x1F]/g, '').trim();
    if (!clean) clean = fallback;

    const baseName = clean.split('.')[0]?.toUpperCase() ?? '';
    if (WINDOWS_RESERVED_NAMES.has(baseName)) {
      clean = `_${clean}`;
    }

    return `${clean}.txt`;
  }

  /**
   * Formats a note and its blocks into plain-text (.txt).
   */
  public static formatNoteAsText(note: Note, blocks: NoteBlock[]): string {
    if (note.isLocked) {
      throw new Error('Cannot export locked note without unlocking first');
    }

    const lines: string[] = [];
    lines.push(note.title || 'Untitled Note');
    lines.push('='.repeat(Math.max((note.title || 'Untitled Note').length, 12)));
    lines.push(`Created: ${new Date(note.createdAt).toISOString()}`);
    lines.push(`Updated: ${new Date(note.updatedAt).toISOString()}`);
    lines.push('');

    let numberIndex = 1;
    for (let i = 0; i < blocks.length; i++) {
      const block = blocks[i]!;
      const indent = '  '.repeat(block.indent || 0);

      if (block.type === 'number') {
        lines.push(`${indent}${numberIndex}. ${block.text}`);
        numberIndex++;
      } else {
        numberIndex = 1; // reset number counter
        if (block.type === 'bullet') {
          lines.push(`${indent}- ${block.text}`);
        } else if (block.type === 'check') {
          const mark = block.checked ? '[x]' : '[ ]';
          lines.push(`${indent}${mark} ${block.text}`);
        } else {
          lines.push(`${indent}${block.text}`);
        }
      }
    }

    return lines.join('\n') + '\n';
  }
}
