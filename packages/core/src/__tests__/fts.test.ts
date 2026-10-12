import { NodeCipher } from '../adapters/node/NodeCipher';
import { NodeDbDriver } from '../adapters/node/NodeDbDriver';
import { NoteRepository } from '../repositories/NoteRepository';
import { INITIAL_SCHEMA_SQL } from '../schema';
import fs from 'fs';
import path from 'path';

describe('FTS5 Invariants & Reliability', () => {
  const testDbPath = path.join(__dirname, 'test_fts.db');
  let db: NodeDbDriver;
  let cipher: NodeCipher;
  let noteRepo: NoteRepository;
  const vaultKey = new Uint8Array(32).fill(99);

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
  });

  afterEach(async () => {
    await db.close();
    if (fs.existsSync(testDbPath)) {
      fs.unlinkSync(testDbPath);
    }
  });

  test('FTS mappings survive VACUUM', async () => {
    // Insert several notes
    const n1 = await noteRepo.savePlaintextNote({
      title: 'First Article on Cryptography',
      blocks: [{ id: 'b1', type: 'paragraph', text: 'Quantum resistant algorithms', indent: 0 }],
    });
    const n2 = await noteRepo.savePlaintextNote({
      title: 'Second Article on Privacy',
      blocks: [{ id: 'b2', type: 'paragraph', text: 'Zero knowledge proofs', indent: 0 }],
    });
    const n3 = await noteRepo.savePlaintextNote({
      title: 'Third Article on SQLite',
      blocks: [{ id: 'b3', type: 'paragraph', text: 'Virtual table internals and btrees', indent: 0 }],
    });

    // Delete one note to create btree fragmentation
    await noteRepo.trashNote(n2.id);

    // Run SQLite VACUUM
    await db.query('VACUUM;');

    // Verify FTS still queries properly and maps to exact surviving seqs
    const results1 = await noteRepo.searchNotes('Quantum');
    expect(results1.length).toBe(1);
    expect(results1[0]?.id).toBe(n1.id);
    expect(results1[0]?.seq).toBe(n1.seq);

    const results3 = await noteRepo.searchNotes('btrees');
    expect(results3.length).toBe(1);
    expect(results3[0]?.id).toBe(n3.id);
    expect(results3[0]?.seq).toBe(n3.seq);

    // Trashed note must not appear
    const results2 = await noteRepo.searchNotes('knowledge');
    expect(results2.length).toBe(0);
  });

  test('FTS row count strictly equals unlocked, non-deleted notes after mixed operations', async () => {
    const createdNotes: string[] = [];

    // Create 10 notes
    for (let i = 0; i < 10; i++) {
      const note = await noteRepo.savePlaintextNote({
        title: `Note Title ${i}`,
        blocks: [{ id: `b_${i}`, type: 'paragraph', text: `Body content for index test note ${i}`, indent: 0 }],
      });
      createdNotes.push(note.id);
    }

    // Lock notes 0, 1, 2
    await noteRepo.lockNote(createdNotes[0]!, vaultKey);
    await noteRepo.lockNote(createdNotes[1]!, vaultKey);
    await noteRepo.lockNote(createdNotes[2]!, vaultKey);

    // Trash notes 3, 4
    await noteRepo.trashNote(createdNotes[3]!);
    await noteRepo.trashNote(createdNotes[4]!);

    // Notes 5, 6, 7, 8, 9 remain unlocked and active (5 notes)

    // Direct SQLite verification
    const activeUnlockedRows = await db.queryFirst<any>(
      'SELECT count(*) as count FROM note WHERE is_locked = 0 AND is_hidden = 0 AND deleted_at IS NULL;'
    );
    expect(activeUnlockedRows.count).toBe(5);

    const ftsRowCount = await db.queryFirst<any>('SELECT count(*) as count FROM note_fts;');
    expect(ftsRowCount.count).toBe(5);

    // Verify exact invariant: FTS count MUST equal active unlocked note count
    expect(ftsRowCount.count).toBe(activeUnlockedRows.count);
  });
});
