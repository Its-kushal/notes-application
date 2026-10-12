import { ExportService } from '../services/ExportService';
import { Note, NoteBlock } from '../models';

describe('ExportService', () => {
  test('sanitizes illegal characters and guards against Windows reserved names', () => {
    expect(ExportService.sanitizeFilename('My/Dangerous:File*Name?')).toBe('MyDangerousFileName.txt');
    expect(ExportService.sanitizeFilename('CON')).toBe('_CON.txt');
    expect(ExportService.sanitizeFilename('prn.doc')).toBe('_prn.doc.txt');
    expect(ExportService.sanitizeFilename('aux')).toBe('_aux.txt');
    expect(ExportService.sanitizeFilename('NUL')).toBe('_NUL.txt');
    expect(ExportService.sanitizeFilename('COM1')).toBe('_COM1.txt');
    expect(ExportService.sanitizeFilename('Normal Note')).toBe('Normal Note.txt');
    expect(ExportService.sanitizeFilename('')).toBe('untitled_note.txt');
  });

  test('refuses to export locked notes', () => {
    const lockedNote: Note = {
      id: 'ulid_locked',
      seq: 1,
      title: '',
      isTitleGenerated: false,
      groupId: null,
      color: null,
      isPinned: false,
      isArchived: false,
      isLocked: true,
      isHidden: false,
      wordCount: 0,
      charCount: 0,
      createdAt: Date.now(),
      updatedAt: Date.now(),
      deletedAt: null,
    };

    expect(() => ExportService.formatNoteAsText(lockedNote, [])).toThrow(
      'Cannot export locked note without unlocking first'
    );
  });

  test('formats note blocks cleanly into UTF-8 plain text with checklists, bullets, and numbering', () => {
    const note: Note = {
      id: 'ulid_plain',
      seq: 2,
      title: 'Project Roadmap',
      isTitleGenerated: false,
      groupId: null,
      color: null,
      isPinned: false,
      isArchived: false,
      isLocked: false,
      isHidden: false,
      wordCount: 15,
      charCount: 80,
      createdAt: 1770000000000,
      updatedAt: 1770000000000,
      deletedAt: null,
    };

    const blocks: NoteBlock[] = [
      { id: 'b1', type: 'paragraph', text: 'Overview of Q1 priorities:', indent: 0 },
      { id: 'b2', type: 'bullet', text: 'Hardware acceleration verification', indent: 1 },
      { id: 'b3', type: 'bullet', text: 'Native encryption benchmarking', indent: 1 },
      { id: 'b4', type: 'number', text: 'Setup developer environment', indent: 0 },
      { id: 'b5', type: 'number', text: 'Write automated unit tests', indent: 0 },
      { id: 'b6', type: 'check', text: 'Pass all tests', indent: 0, checked: true },
      { id: 'b7', type: 'check', text: 'Deploy to production', indent: 0, checked: false },
    ];

    const formatted = ExportService.formatNoteAsText(note, blocks);
    expect(formatted).toContain('Project Roadmap\n===============');
    expect(formatted).toContain('Overview of Q1 priorities:');
    expect(formatted).toContain('  - Hardware acceleration verification');
    expect(formatted).toContain('  - Native encryption benchmarking');
    expect(formatted).toContain('1. Setup developer environment');
    expect(formatted).toContain('2. Write automated unit tests');
    expect(formatted).toContain('[x] Pass all tests');
    expect(formatted).toContain('[ ] Deploy to production');
  });
});
