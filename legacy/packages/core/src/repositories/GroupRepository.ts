import { DbDriver, DbStatement } from '../ports';
import { NoteGroup } from '../models';
import { generateUlid } from '../ulid';
import { FtsService } from '../services/FtsService';

export class GroupRepository {
  constructor(private readonly db: DbDriver) {}

  public async getGroupById(id: string): Promise<NoteGroup | null> {
    const row = await this.db.queryFirst<any>(
      `SELECT id, name, color, sort_order AS sortOrder,
              created_at AS createdAt, updated_at AS updatedAt,
              deleted_at AS deletedAt
       FROM note_group WHERE id = ?;`,
      [id]
    );
    return row ?? null;
  }

  public async createGroup(name: string, color?: string | null): Promise<NoteGroup> {
    const id = generateUlid();
    const now = Date.now();
    await this.db.runBatch([
      {
        sql: `INSERT INTO note_group(id, name, color, sort_order, created_at, updated_at, deleted_at)
              VALUES (?, ?, ?, 0, ?, ?, NULL);`,
        params: [id, name, color ?? null, now, now],
      },
    ]);
    return (await this.getGroupById(id))!;
  }

  public async renameGroup(id: string, newName: string): Promise<NoteGroup> {
    const group = await this.getGroupById(id);
    if (!group) throw new Error(`Group not found: ${id}`);

    const now = Date.now();
    // Update group name in table and update FTS for all active member notes
    const statements: DbStatement[] = [
      {
        sql: 'UPDATE note_group SET name = ?, updated_at = ? WHERE id = ?;',
        params: [newName, now, id],
      },
    ];

    if (group.deletedAt === null) {
      // If group is active, update note_fts rows
      const memberNotes = await this.db.query<{ seq: number; title: string; body_json: string }>(
        `SELECT n.seq, n.title, c.body_json
         FROM note n
         JOIN note_content c ON n.id = c.note_id
         WHERE n.group_id = ? AND n.deleted_at IS NULL AND n.is_locked = 0 AND n.is_hidden = 0;`,
        [id]
      );

      for (const note of memberNotes) {
        const blocks = note.body_json ? JSON.parse(note.body_json) : [];
        const bodyText = FtsService.extractPlainText(blocks);
        statements.push({
          sql: 'DELETE FROM note_fts WHERE rowid = ?;',
          params: [note.seq],
        });
        statements.push({
          sql: 'INSERT INTO note_fts(rowid, title, body_text, group_name) VALUES (?, ?, ?, ?);',
          params: [note.seq, note.title, bodyText, newName],
        });
      }
    }

    await this.db.runBatch(statements);
    return (await this.getGroupById(id))!;
  }

  /**
   * Trashes a group.
   * Group deleted_at is set. note.group_id remains intact.
   * In the same batch, group_name in note_fts for all member notes is cleared to ''.
   */
  public async trashGroup(id: string): Promise<void> {
    const group = await this.getGroupById(id);
    if (!group) return;

    const now = Date.now();
    const statements: DbStatement[] = [
      {
        sql: 'UPDATE note_group SET deleted_at = ?, updated_at = ? WHERE id = ?;',
        params: [now, now, id],
      },
    ];

    // Clear group_name in note_fts for member notes
    const memberNotes = await this.db.query<{ seq: number; title: string; body_json: string }>(
      `SELECT n.seq, n.title, c.body_json
       FROM note n
       JOIN note_content c ON n.id = c.note_id
       WHERE n.group_id = ? AND n.deleted_at IS NULL AND n.is_locked = 0 AND n.is_hidden = 0;`,
      [id]
    );

    for (const note of memberNotes) {
      const blocks = note.body_json ? JSON.parse(note.body_json) : [];
      const bodyText = FtsService.extractPlainText(blocks);
      statements.push({
        sql: 'DELETE FROM note_fts WHERE rowid = ?;',
        params: [note.seq],
      });
      statements.push({
        sql: 'INSERT INTO note_fts(rowid, title, body_text, group_name) VALUES (?, ?, ?, ?);',
        params: [note.seq, note.title, bodyText, ''],
      });
    }

    await this.db.runBatch(statements);
  }

  /**
   * Restores a trashed group.
   * Restores group_name across all member notes in note_fts in one batch.
   */
  public async restoreGroup(id: string): Promise<void> {
    const group = await this.getGroupById(id);
    if (!group) return;

    const now = Date.now();
    const statements: DbStatement[] = [
      {
        sql: 'UPDATE note_group SET deleted_at = NULL, updated_at = ? WHERE id = ?;',
        params: [now, id],
      },
    ];

    const memberNotes = await this.db.query<{ seq: number; title: string; body_json: string }>(
      `SELECT n.seq, n.title, c.body_json
       FROM note n
       JOIN note_content c ON n.id = c.note_id
       WHERE n.group_id = ? AND n.deleted_at IS NULL AND n.is_locked = 0 AND n.is_hidden = 0;`,
      [id]
    );

    for (const note of memberNotes) {
      const blocks = note.body_json ? JSON.parse(note.body_json) : [];
      const bodyText = FtsService.extractPlainText(blocks);
      statements.push({
        sql: 'DELETE FROM note_fts WHERE rowid = ?;',
        params: [note.seq],
      });
      statements.push({
        sql: 'INSERT INTO note_fts(rowid, title, body_text, group_name) VALUES (?, ?, ?, ?);',
        params: [note.seq, note.title, bodyText, group.name],
      });
    }

    await this.db.runBatch(statements);
  }
}
