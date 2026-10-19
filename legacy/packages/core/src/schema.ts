export const CURRENT_SCHEMA_VERSION = 1;

export const INITIAL_SCHEMA_SQL = `
-- Note Groups (Folders)
CREATE TABLE IF NOT EXISTS note_group (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  color TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
);

-- Notes
CREATE TABLE IF NOT EXISTS note (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  id TEXT NOT NULL UNIQUE,
  title TEXT NOT NULL DEFAULT '',
  is_title_generated INTEGER NOT NULL DEFAULT 0,
  group_id TEXT REFERENCES note_group(id) ON DELETE SET NULL,
  color TEXT,
  is_pinned INTEGER NOT NULL DEFAULT 0,
  is_archived INTEGER NOT NULL DEFAULT 0,
  is_locked INTEGER NOT NULL DEFAULT 0,
  is_hidden INTEGER NOT NULL DEFAULT 0,
  word_count INTEGER NOT NULL DEFAULT 0,
  char_count INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
);

-- Note Content (Plaintext JSON or Encrypted Ciphertext)
CREATE TABLE IF NOT EXISTS note_content (
  note_id TEXT PRIMARY KEY REFERENCES note(id) ON DELETE CASCADE,
  body_json TEXT,
  ciphertext BLOB,
  nonce BLOB,
  auth_tag BLOB,
  format_version INTEGER NOT NULL DEFAULT 1,
  CHECK (
    (body_json IS NOT NULL AND ciphertext IS NULL AND nonce IS NULL AND auth_tag IS NULL) OR
    (body_json IS NULL AND ciphertext IS NOT NULL AND nonce IS NOT NULL AND auth_tag IS NOT NULL)
  )
);

-- Tags
CREATE TABLE IF NOT EXISTS tag (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  created_at INTEGER NOT NULL
);

-- Note Tag Junction
CREATE TABLE IF NOT EXISTS note_tag (
  note_id TEXT NOT NULL REFERENCES note(id) ON DELETE CASCADE,
  tag_id TEXT NOT NULL REFERENCES tag(id) ON DELETE CASCADE,
  PRIMARY KEY (note_id, tag_id)
);

-- Task Lists
CREATE TABLE IF NOT EXISTS task_list (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
);

-- Tasks (Standalone and projected from Note Checklists)
CREATE TABLE IF NOT EXISTS task (
  id TEXT PRIMARY KEY,
  task_list_id TEXT REFERENCES task_list(id) ON DELETE CASCADE,
  note_id TEXT REFERENCES note(id) ON DELETE CASCADE,
  block_id TEXT,
  title TEXT NOT NULL,
  is_completed INTEGER NOT NULL DEFAULT 0,
  due_date INTEGER,
  priority TEXT CHECK (priority IN ('low', 'medium', 'high') OR priority IS NULL),
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
);

-- Reminders (Directly to Task OR directly to Note Checklist item)
CREATE TABLE IF NOT EXISTS reminder (
  id TEXT PRIMARY KEY,
  task_id TEXT REFERENCES task(id) ON DELETE CASCADE,
  note_id TEXT REFERENCES note(id) ON DELETE CASCADE,
  block_id TEXT,
  remind_at INTEGER NOT NULL,
  is_triggered INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  CHECK (
    (task_id IS NOT NULL AND note_id IS NULL AND block_id IS NULL) OR
    (task_id IS NULL AND note_id IS NOT NULL AND block_id IS NOT NULL)
  )
);

-- Attachments
CREATE TABLE IF NOT EXISTS attachment (
  id TEXT PRIMARY KEY,
  note_id TEXT REFERENCES note(id) ON DELETE CASCADE,
  filename TEXT NOT NULL,
  file_path TEXT NOT NULL,
  mime_type TEXT NOT NULL,
  byte_size INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);

-- App Settings (key-value)
CREATE TABLE IF NOT EXISTS app_setting (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);

-- Security Metadata (Singleton row for Vault scrypt params & wrapped key)
CREATE TABLE IF NOT EXISTS security_metadata (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  vault_salt BLOB NOT NULL,
  scrypt_n INTEGER NOT NULL DEFAULT 131072,
  scrypt_r INTEGER NOT NULL DEFAULT 8,
  scrypt_p INTEGER NOT NULL DEFAULT 1,
  wrapped_vault_key BLOB NOT NULL,
  wrapped_nonce BLOB NOT NULL,
  wrapped_tag BLOB NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

-- Trash Metadata
CREATE TABLE IF NOT EXISTS trash_metadata (
  id TEXT PRIMARY KEY,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  deleted_at INTEGER NOT NULL
);

-- Migration Tracking
CREATE TABLE IF NOT EXISTS migration (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  version INTEGER NOT NULL UNIQUE,
  applied_at INTEGER NOT NULL,
  description TEXT NOT NULL
);

-- FTS5 Full-Text Search Virtual Table
CREATE VIRTUAL TABLE IF NOT EXISTS note_fts USING fts5(
  title,
  body_text,
  group_name,
  tokenize = 'unicode61 remove_diacritics 2'
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_note_group ON note(group_id);
CREATE INDEX IF NOT EXISTS idx_note_deleted ON note(deleted_at);
CREATE INDEX IF NOT EXISTS idx_note_updated ON note(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_task_note ON task(note_id);
CREATE INDEX IF NOT EXISTS idx_task_deleted ON task(deleted_at);
CREATE INDEX IF NOT EXISTS idx_reminder_remind_at ON reminder(remind_at);
CREATE INDEX IF NOT EXISTS idx_reminder_note_block ON reminder(note_id, block_id);
`;
