import { DbDriver } from '../ports';
import { Reminder, Task } from '../models';
import { generateUlid } from '../ulid';

export class TaskRepository {
  constructor(private readonly db: DbDriver) {}

  public async getTaskById(id: string): Promise<Task | null> {
    const row = await this.db.queryFirst<any>(
      `SELECT id, task_list_id AS taskListId, note_id AS noteId,
              block_id AS blockId, title, is_completed AS isCompleted,
              due_date AS dueDate, priority, sort_order AS sortOrder,
              created_at AS createdAt, updated_at AS updatedAt,
              deleted_at AS deletedAt
       FROM task WHERE id = ?;`,
      [id]
    );

    if (!row) return null;
    return {
      ...row,
      isCompleted: Boolean(row.isCompleted),
    };
  }

  public async getTasksByNoteId(noteId: string): Promise<Task[]> {
    const rows = await this.db.query<any>(
      `SELECT id, task_list_id AS taskListId, note_id AS noteId,
              block_id AS blockId, title, is_completed AS isCompleted,
              due_date AS dueDate, priority, sort_order AS sortOrder,
              created_at AS createdAt, updated_at AS updatedAt,
              deleted_at AS deletedAt
       FROM task WHERE note_id = ? AND deleted_at IS NULL ORDER BY sort_order ASC;`,
      [noteId]
    );

    return rows.map(r => ({
      ...r,
      isCompleted: Boolean(r.isCompleted),
    }));
  }

  public async createStandaloneTask(params: {
    title: string;
    dueDate?: number | null;
    priority?: 'low' | 'medium' | 'high' | null;
    taskListId?: string | null;
  }): Promise<Task> {
    const id = generateUlid();
    const now = Date.now();
    await this.db.runBatch([
      {
        sql: `INSERT INTO task (
          id, task_list_id, note_id, block_id, title,
          is_completed, due_date, priority, sort_order,
          created_at, updated_at, deleted_at
        ) VALUES (?, ?, NULL, NULL, ?, 0, ?, ?, 0, ?, ?, NULL);`,
        params: [
          id,
          params.taskListId ?? null,
          params.title,
          params.dueDate ?? null,
          params.priority ?? null,
          now,
          now,
        ],
      },
    ]);

    return (await this.getTaskById(id))!;
  }

  // Reminders
  public async addStandaloneTaskReminder(taskId: string, remindAt: number): Promise<Reminder> {
    const id = generateUlid();
    const now = Date.now();
    await this.db.runBatch([
      {
        sql: `INSERT INTO reminder (id, task_id, note_id, block_id, remind_at, is_triggered, created_at)
              VALUES (?, ?, NULL, NULL, ?, 0, ?);`,
        params: [id, taskId, remindAt, now],
      },
    ]);
    return (await this.getReminderById(id))!;
  }

  public async addNoteChecklistReminder(noteId: string, blockId: string, remindAt: number): Promise<Reminder> {
    const id = generateUlid();
    const now = Date.now();
    await this.db.runBatch([
      {
        sql: `INSERT INTO reminder (id, task_id, note_id, block_id, remind_at, is_triggered, created_at)
              VALUES (?, NULL, ?, ?, ?, 0, ?);`,
        params: [id, noteId, blockId, remindAt, now],
      },
    ]);
    return (await this.getReminderById(id))!;
  }

  public async getReminderById(id: string): Promise<Reminder | null> {
    const row = await this.db.queryFirst<any>(
      `SELECT id, task_id AS taskId, note_id AS noteId, block_id AS blockId,
              remind_at AS remindAt, is_triggered AS isTriggered, created_at AS createdAt
       FROM reminder WHERE id = ?;`,
      [id]
    );
    if (!row) return null;
    return {
      ...row,
      isTriggered: Boolean(row.isTriggered),
    };
  }

  public async getRemindersForNote(noteId: string): Promise<Reminder[]> {
    const rows = await this.db.query<any>(
      `SELECT id, task_id AS taskId, note_id AS noteId, block_id AS blockId,
              remind_at AS remindAt, is_triggered AS isTriggered, created_at AS createdAt
       FROM reminder WHERE note_id = ?;`,
      [noteId]
    );
    return rows.map(r => ({
      ...r,
      isTriggered: Boolean(r.isTriggered),
    }));
  }
}
