export type BlockType = 'paragraph' | 'bullet' | 'number' | 'check';

export interface TaskMetadata {
  dueDate?: number | null; // epoch ms
  priority?: 'low' | 'medium' | 'high' | null;
  reminderId?: string | null;
}

export interface NoteBlock {
  id: string; // unique block id
  type: BlockType;
  text: string;
  indent: number;
  checked?: boolean; // For checklists
  taskMeta?: TaskMetadata; // Preserved across lock/unlock
}

export interface Note {
  id: string; // ULID
  seq: number;
  title: string;
  isTitleGenerated: boolean;
  groupId: string | null;
  color: string | null;
  isPinned: boolean;
  isArchived: boolean;
  isLocked: boolean;
  isHidden: boolean;
  wordCount: number;
  charCount: number;
  createdAt: number;
  updatedAt: number;
  deletedAt: number | null;
}

export interface NoteContent {
  noteId: string;
  bodyJson: NoteBlock[] | null; // null when locked
  ciphertext: Uint8Array | null;
  nonce: Uint8Array | null;
  authTag: Uint8Array | null;
  formatVersion: number;
}

export interface NoteGroup {
  id: string; // ULID
  name: string;
  color: string | null;
  sortOrder: number;
  createdAt: number;
  updatedAt: number;
  deletedAt: number | null;
}

export interface Task {
  id: string; // ULID or deterministic note_id + '_' + block_id
  taskListId: string | null;
  noteId: string | null;
  blockId: string | null;
  title: string;
  isCompleted: boolean;
  dueDate: number | null;
  priority: 'low' | 'medium' | 'high' | null;
  sortOrder: number;
  createdAt: number;
  updatedAt: number;
  deletedAt: number | null;
}

export interface Reminder {
  id: string;
  taskId: string | null;
  noteId: string | null;
  blockId: string | null;
  remindAt: number;
  isTriggered: boolean;
  createdAt: number;
}
