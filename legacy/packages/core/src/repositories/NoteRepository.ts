import { Cipher, DbDriver, DbStatement } from '../ports';
import { Note, NoteBlock, NoteContent } from '../models';
import { generateUlid } from '../ulid';
import { FtsService } from '../services/FtsService';

export interface DecryptedNotePayload {
  title: string;
  blocks: NoteBlock[];
}

export class NoteRepository {
  constructor(
    private readonly db: DbDriver,
    private readonly cipher: Cipher
  ) {}

  public async getNoteById(id: string): Promise<Note | null> {
    const row = await this.db.queryFirst<any>(
      `SELECT id, seq, title, is_title_generated AS isTitleGenerated,
              group_id AS groupId, color, is_pinned AS isPinned,
              is_archived AS isArchived, is_locked AS isLocked,
              is_hidden AS isHidden, word_count AS wordCount,
              char_count AS charCount, created_at AS createdAt,
              updated_at AS updatedAt, deleted_at AS deletedAt
       FROM note WHERE id = ?;`,
      [id]
    );

    if (!row) return null;
    return {
      ...row,
      isTitleGenerated: Boolean(row.isTitleGenerated),
      isPinned: Boolean(row.isPinned),
      isArchived: Boolean(row.isArchived),
      isLocked: Boolean(row.isLocked),
      isHidden: Boolean(row.isHidden),
    };
  }

  public async getNoteContent(noteId: string): Promise<NoteContent | null> {
    const row = await this.db.queryFirst<any>(
      `SELECT note_id AS noteId, body_json AS bodyJson,
              ciphertext, nonce, auth_tag AS authTag,
              format_version AS formatVersion
       FROM note_content WHERE note_id = ?;`,
      [noteId]
    );

    if (!row) return null;
    return {
      noteId: row.noteId,
      bodyJson: row.bodyJson ? JSON.parse(row.bodyJson) : null,
      ciphertext: row.ciphertext ? new Uint8Array(row.ciphertext) : null,
      nonce: row.nonce ? new Uint8Array(row.nonce) : null,
      authTag: row.authTag ? new Uint8Array(row.authTag) : null,
      formatVersion: row.formatVersion,
    };
  }

  /**
   * Creates or saves a plaintext note, updates FTS, and projects checklist tasks.
   */
  public async savePlaintextNote(params: {
    id?: string;
    title: string;
    blocks: NoteBlock[];
    groupId?: string | null;
    color?: string | null;
    isPinned?: boolean;
    isArchived?: boolean;
    now?: number;
  }): Promise<Note> {
    const now = params.now ?? Date.now();
    const id = params.id ?? generateUlid(now);
    const existing = await this.getNoteById(id);

    const bodyText = FtsService.extractPlainText(params.blocks);
    const wordCount = bodyText.trim() ? bodyText.trim().split(/\s+/).length : 0;
    const charCount = bodyText.length;
    const jsonStr = JSON.stringify(params.blocks);

    let groupName = '';
    if (params.groupId) {
      const g = await this.db.queryFirst<{ name: string; deleted_at: number | null }>(
        'SELECT name, deleted_at FROM note_group WHERE id = ?;',
        [params.groupId]
      );
      if (g && g.deleted_at === null) {
        groupName = g.name;
      }
    }

    const statements: DbStatement[] = [];

    if (!existing) {
      statements.push({
        sql: `INSERT INTO note (
          id, title, is_title_generated, group_id, color,
          is_pinned, is_archived, is_locked, is_hidden,
          word_count, char_count, created_at, updated_at, deleted_at
        ) VALUES (?, ?, 0, ?, ?, ?, ?, 0, 0, ?, ?, ?, ?, NULL);`,
        params: [
          id,
          params.title,
          params.groupId ?? null,
          params.color ?? null,
          params.isPinned ? 1 : 0,
          params.isArchived ? 1 : 0,
          wordCount,
          charCount,
          now,
          now,
        ],
      });
      statements.push({
        sql: `INSERT INTO note_content (
          note_id, body_json, ciphertext, nonce, auth_tag, format_version
        ) VALUES (?, ?, NULL, NULL, NULL, 1);`,
        params: [id, jsonStr],
      });
    } else {
      statements.push({
        sql: `UPDATE note SET
          title = ?, group_id = ?, color = ?, is_pinned = ?,
          is_archived = ?, is_locked = 0, is_hidden = 0,
          word_count = ?, char_count = ?, updated_at = ?
        WHERE id = ?;`,
        params: [
          params.title,
          params.groupId ?? null,
          params.color ?? null,
          params.isPinned ? 1 : 0,
          params.isArchived ? 1 : 0,
          wordCount,
          charCount,
          now,
          id,
        ],
      });
      statements.push({
        sql: `INSERT OR REPLACE INTO note_content (
          note_id, body_json, ciphertext, nonce, auth_tag, format_version
        ) VALUES (?, ?, NULL, NULL, NULL, 1);`,
        params: [id, jsonStr],
      });
    }

    // Execute note and content update first to ensure seq is generated if new
    await this.db.runBatch(statements);

    const savedNote = (await this.getNoteById(id))!;
    const ftsAndTaskStatements: DbStatement[] = [];

    // FTS sync
    ftsAndTaskStatements.push({
      sql: 'DELETE FROM note_fts WHERE rowid = ?;',
      params: [savedNote.seq],
    });
    ftsAndTaskStatements.push({
      sql: 'INSERT INTO note_fts(rowid, title, body_text, group_name) VALUES (?, ?, ?, ?);',
      params: [savedNote.seq, params.title, bodyText, groupName],
    });

    // Project checklist tasks
    ftsAndTaskStatements.push({
      sql: 'DELETE FROM task WHERE note_id = ? AND block_id IS NOT NULL;',
      params: [id],
    });

    for (let i = 0; i < params.blocks.length; i++) {
      const block = params.blocks[i];
      if (block && block.type === 'check') {
        const taskId = `${id}_${block.id}`;
        ftsAndTaskStatements.push({
          sql: `INSERT INTO task (
            id, task_list_id, note_id, block_id, title,
            is_completed, due_date, priority, sort_order,
            created_at, updated_at, deleted_at
          ) VALUES (?, NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL);`,
          params: [
            taskId,
            id,
            block.id,
            block.text,
            block.checked ? 1 : 0,
            block.taskMeta?.dueDate ?? null,
            block.taskMeta?.priority ?? null,
            i,
            now,
            now,
          ],
        });
      }
    }

    await this.db.runBatch(ftsAndTaskStatements);
    return savedNote;
  }

  /**
   * Locks an existing note. Encrypts payload with vaultKey, scrubs plaintext title,
   * removes FTS row, and deletes projected tasks without touching reminders.
   */
  public async lockNote(noteId: string, vaultKey: Uint8Array): Promise<void> {
    const note = await this.getNoteById(noteId);
    if (!note) throw new Error(`Note not found: ${noteId}`);
    if (note.isLocked) return;

    const content = await this.getNoteContent(noteId);
    const blocks = content?.bodyJson ?? [];

    const payload: DecryptedNotePayload = {
      title: note.title,
      blocks,
    };
    const plaintext = new TextEncoder().encode(JSON.stringify(payload));
    const aad = new TextEncoder().encode(noteId);
    const { ciphertext, nonce, authTag } = await this.cipher.encrypt(plaintext, vaultKey, aad);

    const now = Date.now();
    await this.db.runBatch([
      {
        sql: `UPDATE note SET
          is_locked = 1, title = '', word_count = 0, char_count = 0, updated_at = ?
        WHERE id = ?;`,
        params: [now, noteId],
      },
      {
        sql: `UPDATE note_content SET
          body_json = NULL, ciphertext = ?, nonce = ?, auth_tag = ?, format_version = 1
        WHERE note_id = ?;`,
        params: [ciphertext, nonce, authTag, noteId],
      },
      {
        sql: 'DELETE FROM note_fts WHERE rowid = ?;',
        params: [note.seq],
      },
      {
        sql: 'DELETE FROM task WHERE note_id = ? AND block_id IS NOT NULL;',
        params: [noteId],
      },
    ]);
  }

  /**
   * Autosaves a note while session-unlocked.
   * In-memory only: re-encrypts with vaultKey, writes NO plaintext title/body,
   * writes ZERO rows in note_fts, and writes ZERO rows in task.
   */
  public async saveSessionUnlockedNote(
    noteId: string,
    title: string,
    blocks: NoteBlock[],
    vaultKey: Uint8Array
  ): Promise<void> {
    const note = await this.getNoteById(noteId);
    if (!note) throw new Error(`Note not found: ${noteId}`);

    const payload: DecryptedNotePayload = { title, blocks };
    const plaintext = new TextEncoder().encode(JSON.stringify(payload));
    const aad = new TextEncoder().encode(noteId);
    const { ciphertext, nonce, authTag } = await this.cipher.encrypt(plaintext, vaultKey, aad);

    const now = Date.now();
    await this.db.runBatch([
      {
        sql: `UPDATE note SET
          is_locked = 1, title = '', word_count = 0, char_count = 0, updated_at = ?
        WHERE id = ?;`,
        params: [now, noteId],
      },
      {
        sql: `UPDATE note_content SET
          body_json = NULL, ciphertext = ?, nonce = ?, auth_tag = ?, format_version = 1
        WHERE note_id = ?;`,
        params: [ciphertext, nonce, authTag, noteId],
      },
      // Ensure no FTS row or task row exists
      {
        sql: 'DELETE FROM note_fts WHERE rowid = ?;',
        params: [note.seq],
      },
      {
        sql: 'DELETE FROM task WHERE note_id = ? AND block_id IS NOT NULL;',
        params: [noteId],
      },
    ]);
  }

  /**
   * Decrypts in memory for active session viewing/editing.
   */
  public async unlockSession(noteId: string, vaultKey: Uint8Array): Promise<DecryptedNotePayload> {
    const content = await this.getNoteContent(noteId);
    if (!content || !content.ciphertext || !content.nonce || !content.authTag) {
      throw new Error('Note content is not encrypted');
    }

    const aad = new TextEncoder().encode(noteId);
    const decryptedBytes = await this.cipher.decrypt(
      content.ciphertext,
      vaultKey,
      content.nonce,
      content.authTag,
      aad
    );

    const jsonStr = new TextDecoder().decode(decryptedBytes);
    return JSON.parse(jsonStr) as DecryptedNotePayload;
  }

  /**
   * Permanently removes lock, restoring note to plaintext, re-inserting FTS row,
   * and re-projecting checklist tasks with stable IDs.
   */
  public async removeLock(noteId: string, vaultKey: Uint8Array): Promise<Note> {
    const note = await this.getNoteById(noteId);
    if (!note) throw new Error(`Note not found: ${noteId}`);
    if (!note.isLocked) return note;

    const payload = await this.unlockSession(noteId, vaultKey);
    const bodyText = FtsService.extractPlainText(payload.blocks);
    const wordCount = bodyText.trim() ? bodyText.trim().split(/\s+/).length : 0;
    const charCount = bodyText.length;
    const jsonStr = JSON.stringify(payload.blocks);

    let groupName = '';
    if (note.groupId) {
      const g = await this.db.queryFirst<{ name: string; deleted_at: number | null }>(
        'SELECT name, deleted_at FROM note_group WHERE id = ?;',
        [note.groupId]
      );
      if (g && g.deleted_at === null) {
        groupName = g.name;
      }
    }

    const now = Date.now();
    const statements: DbStatement[] = [
      {
        sql: `UPDATE note SET
          is_locked = 0, title = ?, word_count = ?, char_count = ?, updated_at = ?
        WHERE id = ?;`,
        params: [payload.title, wordCount, charCount, now, noteId],
      },
      {
        sql: `UPDATE note_content SET
          body_json = ?, ciphertext = NULL, nonce = NULL, auth_tag = NULL, format_version = 1
        WHERE note_id = ?;`,
        params: [jsonStr, noteId],
      },
      {
        sql: 'DELETE FROM note_fts WHERE rowid = ?;',
        params: [note.seq],
      },
      {
        sql: 'INSERT INTO note_fts(rowid, title, body_text, group_name) VALUES (?, ?, ?, ?);',
        params: [note.seq, payload.title, bodyText, groupName],
      },
      {
        sql: 'DELETE FROM task WHERE note_id = ? AND block_id IS NOT NULL;',
        params: [noteId],
      },
    ];

    for (let i = 0; i < payload.blocks.length; i++) {
      const block = payload.blocks[i];
      if (block && block.type === 'check') {
        const taskId = `${noteId}_${block.id}`;
        statements.push({
          sql: `INSERT INTO task (
            id, task_list_id, note_id, block_id, title,
            is_completed, due_date, priority, sort_order,
            created_at, updated_at, deleted_at
          ) VALUES (?, NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL);`,
          params: [
            taskId,
            noteId,
            block.id,
            block.text,
            block.checked ? 1 : 0,
            block.taskMeta?.dueDate ?? null,
            block.taskMeta?.priority ?? null,
            i,
            now,
            now,
          ],
        });
      }
    }

    await this.db.runBatch(statements);
    return (await this.getNoteById(noteId))!;
  }

  /**
   * Soft deletes a note.
   */
  public async trashNote(noteId: string): Promise<void> {
    const note = await this.getNoteById(noteId);
    if (!note) return;

    const now = Date.now();
    await this.db.runBatch([
      {
        sql: 'UPDATE note SET deleted_at = ?, updated_at = ? WHERE id = ?;',
        params: [now, now, noteId],
      },
      {
        sql: 'DELETE FROM note_fts WHERE rowid = ?;',
        params: [note.seq],
      },
      {
        sql: 'DELETE FROM task WHERE note_id = ? AND block_id IS NOT NULL;',
        params: [noteId],
      },
    ]);
  }

  /**
   * Restores a soft-deleted note.
   */
  public async restoreNote(noteId: string): Promise<void> {
    const note = await this.getNoteById(noteId);
    if (!note) return;

    const now = Date.now();
    const statements: DbStatement[] = [
      {
        sql: 'UPDATE note SET deleted_at = NULL, updated_at = ? WHERE id = ?;',
        params: [now, noteId],
      },
    ];

    if (!note.isLocked) {
      const content = await this.getNoteContent(noteId);
      const blocks = content?.bodyJson ?? [];
      const bodyText = FtsService.extractPlainText(blocks);

      let groupName = '';
      if (note.groupId) {
        const g = await this.db.queryFirst<{ name: string; deleted_at: number | null }>(
          'SELECT name, deleted_at FROM note_group WHERE id = ?;',
          [note.groupId]
        );
        if (g && g.deleted_at === null) {
          groupName = g.name;
        }
      }

      statements.push({
        sql: 'DELETE FROM note_fts WHERE rowid = ?;',
        params: [note.seq],
      });
      statements.push({
        sql: 'INSERT INTO note_fts(rowid, title, body_text, group_name) VALUES (?, ?, ?, ?);',
        params: [note.seq, note.title, bodyText, groupName],
      });

      statements.push({
        sql: 'DELETE FROM task WHERE note_id = ? AND block_id IS NOT NULL;',
        params: [noteId],
      });
      for (let i = 0; i < blocks.length; i++) {
        const block = blocks[i];
        if (block && block.type === 'check') {
          const taskId = `${noteId}_${block.id}`;
          statements.push({
            sql: `INSERT INTO task (
              id, task_list_id, note_id, block_id, title,
              is_completed, due_date, priority, sort_order,
              created_at, updated_at, deleted_at
            ) VALUES (?, NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL);`,
            params: [
              taskId,
              noteId,
              block.id,
              block.text,
              block.checked ? 1 : 0,
              block.taskMeta?.dueDate ?? null,
              block.taskMeta?.priority ?? null,
              i,
              now,
              now,
            ],
          });
        }
      }
    }

    await this.db.runBatch(statements);
  }

  /**
   * Search notes using FTS5 MATCH with sanitized prefix query.
   */
  public async searchNotes(query: string): Promise<Note[]> {
    const sanitized = FtsService.sanitizeQuery(query);
    if (!sanitized) return [];

    const rows = await this.db.query<any>(
      `SELECT n.id, n.seq, n.title, n.is_title_generated AS isTitleGenerated,
              n.group_id AS groupId, n.color, n.is_pinned AS isPinned,
              n.is_archived AS isArchived, n.is_locked AS isLocked,
              n.is_hidden AS isHidden, n.word_count AS wordCount,
              n.char_count AS charCount, n.created_at AS createdAt,
              n.updated_at AS updatedAt, n.deleted_at AS deletedAt
       FROM note n
       JOIN note_fts f ON n.seq = f.rowid
       WHERE note_fts MATCH ?
         AND n.deleted_at IS NULL
         AND n.is_locked = 0
         AND n.is_hidden = 0
       ORDER BY n.updated_at DESC;`,
      [sanitized]
    );

    return rows.map(r => ({
      ...r,
      isTitleGenerated: Boolean(r.isTitleGenerated),
      isPinned: Boolean(r.isPinned),
      isArchived: Boolean(r.isArchived),
      isLocked: Boolean(r.isLocked),
      isHidden: Boolean(r.isHidden),
    }));
  }
}
