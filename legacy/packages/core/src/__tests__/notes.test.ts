import { NodeCipher } from '../adapters/node/NodeCipher';
import { NodeDbDriver } from '../adapters/node/NodeDbDriver';
import { NoteRepository } from '../repositories/NoteRepository';
import { TaskRepository } from '../repositories/TaskRepository';
import { INITIAL_SCHEMA_SQL } from '../schema';
import { NoteBlock } from '../models';
import fs from 'fs';
import path from 'path';

describe('NoteRepository & Security Invariants', () => {
  const testDbPath = path.join(__dirname, 'test_notes.db');
  let db: NodeDbDriver;
  let cipher: NodeCipher;
  let noteRepo: NoteRepository;
  let taskRepo: TaskRepository;
  const vaultKey = new Uint8Array(32).fill(42);

  beforeEach(async () => {
    if (fs.existsSync(testDbPath)) {
      fs.unlinkSync(testDbPath);
    }
    db = new NodeDbDriver(testDbPath);
    const stmts = INITIAL_SCHEMA_SQL.split(';')
      .map(s => s.trim())
      .filter(s => s.length > 0);
    for (const sql of stmts) {
      await db.runBatch([{ sql: `${sql};` }]);
    }

    cipher = new NodeCipher();
    noteRepo = new NoteRepository(db, cipher);
    taskRepo = new TaskRepository(db);
  });

  afterEach(async () => {
    await db.close();
    if (fs.existsSync(testDbPath)) {
      fs.unlinkSync(testDbPath);
    }
  });

  test('plain note creation populates FTS and projects checklist tasks', async () => {
    const blocks: NoteBlock[] = [
      { id: 'b1', type: 'paragraph', text: 'This is a public research note', indent: 0 },
      { id: 'b2', type: 'check', text: 'Buy milk', indent: 0, checked: false, taskMeta: { priority: 'high' } },
    ];

    const note = await noteRepo.savePlaintextNote({
      title: 'Groceries and Research',
      blocks,
    });

    expect(note.title).toBe('Groceries and Research');
    expect(note.isLocked).toBe(false);

    // Direct SQLite check: note table
    const noteRow = await db.queryFirst<any>('SELECT * FROM note WHERE id = ?;', [note.id]);
    expect(noteRow.title).toBe('Groceries and Research');
    expect(noteRow.word_count).toBeGreaterThan(0);

    // Direct SQLite check: note_content table
    const contentRow = await db.queryFirst<any>('SELECT * FROM note_content WHERE note_id = ?;', [note.id]);
    expect(contentRow.body_json).not.toBeNull();
    expect(contentRow.ciphertext).toBeNull();

    // Direct SQLite check: FTS table
    const ftsMatch = await db.query<any>("SELECT rowid, title, body_text FROM note_fts WHERE note_fts MATCH 'research*';");
    expect(ftsMatch.length).toBe(1);
    expect(ftsMatch[0]?.rowid).toBe(note.seq);

    // Direct SQLite check: projected task
    const tasks = await taskRepo.getTasksByNoteId(note.id);
    expect(tasks.length).toBe(1);
    expect(tasks[0]?.id).toBe(`${note.id}_b2`);
    expect(tasks[0]?.title).toBe('Buy milk');
    expect(tasks[0]?.priority).toBe('high');
  });

  test('viewing/editing a locked note writes zero plaintext title, body, FTS row, or task row', async () => {
    // 1. Create a note and then lock it
    const initialBlocks: NoteBlock[] = [
      { id: 'b1', type: 'paragraph', text: 'Initial private details', indent: 0 },
      { id: 'b2', type: 'check', text: 'Call agent', indent: 0, checked: false },
    ];
    const note = await noteRepo.savePlaintextNote({
      title: 'Confidential Strategy',
      blocks: initialBlocks,
    });

    await noteRepo.lockNote(note.id, vaultKey);

    // 2. Simulate session-unlocked editing and autosave
    const updatedBlocks: NoteBlock[] = [
      { id: 'b1', type: 'paragraph', text: 'Updated private nuclear codes 12345', indent: 0 },
      { id: 'b2', type: 'check', text: 'Destroy paper copies', indent: 0, checked: true },
    ];

    await noteRepo.saveSessionUnlockedNote(
      note.id,
      'Classified Nuclear Strategy',
      updatedBlocks,
      vaultKey
    );

    // 3. STRICT PROOF: Raw SQLite inspection
    const noteRow = await db.queryFirst<any>('SELECT title, word_count, char_count, is_locked FROM note WHERE id = ?;', [note.id]);
    expect(noteRow.is_locked).toBe(1);
    expect(noteRow.title).toBe(''); // ZERO plaintext title
    expect(noteRow.word_count).toBe(0);
    expect(noteRow.char_count).toBe(0);

    const contentRow = await db.queryFirst<any>('SELECT body_json, ciphertext, nonce, auth_tag FROM note_content WHERE note_id = ?;', [note.id]);
    expect(contentRow.body_json).toBeNull(); // ZERO plaintext body
    expect(contentRow.ciphertext).not.toBeNull();
    expect(contentRow.nonce).not.toBeNull();
    expect(contentRow.auth_tag).not.toBeNull();

    // Verify ZERO FTS rows
    const ftsRows = await db.query<any>('SELECT count(*) as count FROM note_fts WHERE rowid = ?;', [note.seq]);
    expect(ftsRows[0]?.count).toBe(0);

    // Search query should NOT find anything
    const searchResults = await noteRepo.searchNotes('Nuclear');
    expect(searchResults.length).toBe(0);

    // Verify ZERO projected task rows
    const taskRows = await db.query<any>('SELECT count(*) as count FROM task WHERE note_id = ?;', [note.id]);
    expect(taskRows[0]?.count).toBe(0);
  });

  test('removing lock restores title, body, FTS, and task projection', async () => {
    const blocks: NoteBlock[] = [
      { id: 'b1', type: 'paragraph', text: 'Secret message for the team', indent: 0 },
      { id: 'b2', type: 'check', text: 'Launch satellite', indent: 0, checked: false },
    ];
    const note = await noteRepo.savePlaintextNote({
      title: 'Mission Apollo',
      blocks,
    });

    await noteRepo.lockNote(note.id, vaultKey);
    expect((await noteRepo.getNoteById(note.id))?.isLocked).toBe(true);

    // Remove lock
    const unlockedNote = await noteRepo.removeLock(note.id, vaultKey);
    expect(unlockedNote.isLocked).toBe(false);
    expect(unlockedNote.title).toBe('Mission Apollo');

    // Direct SQLite check: note table
    const noteRow = await db.queryFirst<any>('SELECT title, is_locked FROM note WHERE id = ?;', [note.id]);
    expect(noteRow.title).toBe('Mission Apollo');
    expect(noteRow.is_locked).toBe(0);

    // Direct SQLite check: FTS table re-indexed
    const ftsMatches = await db.query<any>("SELECT rowid, title FROM note_fts WHERE note_fts MATCH 'Apollo*';");
    expect(ftsMatches.length).toBe(1);
    expect(ftsMatches[0]?.title).toBe('Mission Apollo');

    // Direct SQLite check: task re-projected with stable ID
    const tasks = await taskRepo.getTasksByNoteId(note.id);
    expect(tasks.length).toBe(1);
    expect(tasks[0]?.id).toBe(`${note.id}_b2`);
    expect(tasks[0]?.title).toBe('Launch satellite');
  });

  test('reminders survive note lock and task projection cleanup', async () => {
    const blocks: NoteBlock[] = [
      { id: 'b1', type: 'check', text: 'Important meeting', indent: 0, checked: false },
    ];
    const note = await noteRepo.savePlaintextNote({
      title: 'Meeting Notes',
      blocks,
    });

    // Add reminder for note checklist item (references note_id + block_id directly)
    const remindAt = Date.now() + 3600000;
    const reminder = await taskRepo.addNoteChecklistReminder(note.id, 'b1', remindAt);
    expect(reminder.noteId).toBe(note.id);
    expect(reminder.blockId).toBe('b1');
    expect(reminder.taskId).toBeNull();

    // Lock note (which deletes projected task rows)
    await noteRepo.lockNote(note.id, vaultKey);

    // Verify task row is deleted
    const tasksAfterLock = await taskRepo.getTasksByNoteId(note.id);
    expect(tasksAfterLock.length).toBe(0);

    // Verify reminder is STILL PRESENT in SQLite!
    const remindersAfterLock = await taskRepo.getRemindersForNote(note.id);
    expect(remindersAfterLock.length).toBe(1);
    expect(remindersAfterLock[0]?.id).toBe(reminder.id);
    expect(remindersAfterLock[0]?.blockId).toBe('b1');

    // Remove lock (tasks re-projected)
    await noteRepo.removeLock(note.id, vaultKey);
    const tasksAfterUnlock = await taskRepo.getTasksByNoteId(note.id);
    expect(tasksAfterUnlock.length).toBe(1);
    expect(tasksAfterUnlock[0]?.id).toBe(`${note.id}_b1`);

    // Reminder is STILL intact and references the identical note_id + block_id!
    const remindersAfterUnlock = await taskRepo.getRemindersForNote(note.id);
    expect(remindersAfterUnlock.length).toBe(1);
    expect(remindersAfterUnlock[0]?.id).toBe(reminder.id);
  });
});
