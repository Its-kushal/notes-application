import { NodeCipher } from '../adapters/node/NodeCipher';
import { NodeDbDriver } from '../adapters/node/NodeDbDriver';
import { NoteRepository } from '../repositories/NoteRepository';
import { GroupRepository } from '../repositories/GroupRepository';
import { INITIAL_SCHEMA_SQL } from '../schema';
import fs from 'fs';
import path from 'path';

describe('GroupRepository & FTS Synchronization', () => {
  const testDbPath = path.join(__dirname, 'test_groups.db');
  let db: NodeDbDriver;
  let cipher: NodeCipher;
  let noteRepo: NoteRepository;
  let groupRepo: GroupRepository;

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
    groupRepo = new GroupRepository(db);
  });

  afterEach(async () => {
    await db.close();
    if (fs.existsSync(testDbPath)) {
      fs.unlinkSync(testDbPath);
    }
  });

  test('trashed group clears group_name in note_fts in the same batch, and restore restores it', async () => {
    const group = await groupRepo.createGroup('FinancePlans');
    const note = await noteRepo.savePlaintextNote({
      title: 'Quarterly Budget 2026',
      groupId: group.id,
      blocks: [{ id: 'b1', type: 'paragraph', text: 'Financial estimates and budget forecasts', indent: 0 }],
    });

    // Check initial FTS has group_name
    let ftsRow = await db.queryFirst<any>('SELECT rowid, group_name FROM note_fts WHERE rowid = ?;', [note.seq]);
    expect(ftsRow.group_name).toBe('FinancePlans');

    // FTS search by group name succeeds
    let searchResults = await noteRepo.searchNotes('FinancePlans');
    expect(searchResults.length).toBe(1);

    // TRASH GROUP
    await groupRepo.trashGroup(group.id);

    // Note's group_id remains intact in note table
    const noteAfterTrash = await noteRepo.getNoteById(note.id);
    expect(noteAfterTrash?.groupId).toBe(group.id);

    // Group deleted_at is set
    const groupAfterTrash = await groupRepo.getGroupById(group.id);
    expect(groupAfterTrash?.deletedAt).not.toBeNull();

    // IN THE SAME BATCH: group_name in note_fts is cleared to ''
    ftsRow = await db.queryFirst<any>('SELECT rowid, group_name FROM note_fts WHERE rowid = ?;', [note.seq]);
    expect(ftsRow.group_name).toBe('');

    // FTS search by old group name now returns 0
    searchResults = await noteRepo.searchNotes('FinancePlans');
    expect(searchResults.length).toBe(0);

    // RESTORE GROUP
    await groupRepo.restoreGroup(group.id);

    // group_name in note_fts is restored to 'FinancePlans'
    ftsRow = await db.queryFirst<any>('SELECT rowid, group_name FROM note_fts WHERE rowid = ?;', [note.seq]);
    expect(ftsRow.group_name).toBe('FinancePlans');

    // Search by group name works again
    searchResults = await noteRepo.searchNotes('FinancePlans');
    expect(searchResults.length).toBe(1);
  });

  test('renaming a group updates search results immediately', async () => {
    const group = await groupRepo.createGroup('OldFolderName');
    const note = await noteRepo.savePlaintextNote({
      title: 'Architecture Blueprint',
      groupId: group.id,
      blocks: [{ id: 'b1', type: 'paragraph', text: 'System diagram', indent: 0 }],
    });

    expect((await noteRepo.searchNotes('OldFolderName')).length).toBe(1);

    // Rename
    await groupRepo.renameGroup(group.id, 'NewFolderName');

    // FTS reflects new group name
    const ftsRow = await db.queryFirst<any>('SELECT group_name FROM note_fts WHERE rowid = ?;', [note.seq]);
    expect(ftsRow.group_name).toBe('NewFolderName');

    expect((await noteRepo.searchNotes('OldFolderName')).length).toBe(0);
    expect((await noteRepo.searchNotes('NewFolderName')).length).toBe(1);
  });
});
