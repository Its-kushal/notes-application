import { create } from 'zustand';
import { Note, NoteBlock, ExportService } from '@notes/core';
import { getServices } from '../services/bootstrap';

export interface NoteState {
  notes: Note[];
  activeNote: Note | null;
  activeBlocks: NoteBlock[];
  activeGroupId: string | null;
  searchQuery: string;
  selectedGroupId: string | null;
  saveStatus: 'saved' | 'saving' | 'error';
  isSelectionMode: boolean;
  selectedNoteIds: string[];

  loadNotes: () => Promise<void>;
  setSearchQuery: (query: string) => void;
  setSelectedGroupId: (groupId: string | null) => void;
  createNote: (groupId?: string | null) => Promise<Note>;
  selectNote: (id: string, vaultKey?: Uint8Array | null) => Promise<boolean>;
  updateActiveDraft: (title: string, blocks: NoteBlock[]) => void;
  flushPendingSave: (vaultKey?: Uint8Array | null) => Promise<void>;
  lockActiveNote: (vaultKey: Uint8Array) => Promise<void>;
  unlockActiveNote: (vaultKey: Uint8Array) => Promise<boolean>;
  removeActiveLock: (vaultKey: Uint8Array) => Promise<void>;
  trashNote: (id: string) => Promise<void>;
  restoreNote: (id: string) => Promise<void>;
  exportNote: (id: string, vaultKey?: Uint8Array | null) => Promise<boolean>;
}

let autosaveTimer: ReturnType<typeof setTimeout> | null = null;
let pendingDraft: { title: string; blocks: NoteBlock[] } | null = null;

export const useNoteStore = create<NoteState>((set, get) => ({
  notes: [],
  activeNote: null,
  activeBlocks: [],
  activeGroupId: null,
  searchQuery: '',
  selectedGroupId: null,
  saveStatus: 'saved',
  isSelectionMode: false,
  selectedNoteIds: [],

  loadNotes: async () => {
    const { db, noteRepo } = await getServices();
    const { searchQuery, selectedGroupId } = get();

    if (searchQuery.trim()) {
      const results = await noteRepo.searchNotes(searchQuery);
      set({ notes: results });
      return;
    }

    let sql = `SELECT id, seq, title, is_title_generated AS isTitleGenerated,
                      group_id AS groupId, color, is_pinned AS isPinned,
                      is_archived AS isArchived, is_locked AS isLocked,
                      is_hidden AS isHidden, word_count AS wordCount,
                      char_count AS charCount, created_at AS createdAt,
                      updated_at AS updatedAt, deleted_at AS deletedAt
               FROM note WHERE deleted_at IS NULL`;
    const params: unknown[] = [];

    if (selectedGroupId) {
      sql += ' AND group_id = ?';
      params.push(selectedGroupId);
    }

    sql += ' ORDER BY is_pinned DESC, updated_at DESC;';

    const rows = await db.query<any>(sql, params);
    const mapped: Note[] = rows.map(r => ({
      ...r,
      isTitleGenerated: Boolean(r.isTitleGenerated),
      isPinned: Boolean(r.isPinned),
      isArchived: Boolean(r.isArchived),
      isLocked: Boolean(r.isLocked),
      isHidden: Boolean(r.isHidden),
    }));

    set({ notes: mapped });
  },

  setSearchQuery: (query: string) => {
    set({ searchQuery: query });
    get().loadNotes();
  },

  setSelectedGroupId: (groupId: string | null) => {
    set({ selectedGroupId: groupId });
    get().loadNotes();
  },

  createNote: async (groupId?: string | null) => {
    const { noteRepo } = await getServices();
    const initialBlock: NoteBlock = {
      id: `blk_${Date.now()}`,
      type: 'paragraph',
      text: '',
      indent: 0,
    };

    const newNote = await noteRepo.savePlaintextNote({
      title: '',
      blocks: [initialBlock],
      groupId: groupId ?? get().selectedGroupId,
    });

    set({
      activeNote: newNote,
      activeBlocks: [initialBlock],
      activeGroupId: newNote.groupId,
      saveStatus: 'saved',
    });

    await get().loadNotes();
    return newNote;
  },

  selectNote: async (id: string, vaultKey?: Uint8Array | null) => {
    const { noteRepo } = await getServices();
    const note = await noteRepo.getNoteById(id);
    if (!note) return false;

    if (note.isLocked) {
      if (!vaultKey) {
        // Must unlock with passcode first
        set({ activeNote: note, activeBlocks: [], activeGroupId: note.groupId });
        return false;
      }
      try {
        const decrypted = await noteRepo.unlockSession(note.id, vaultKey);
        set({
          activeNote: { ...note, title: decrypted.title },
          activeBlocks: decrypted.blocks,
          activeGroupId: note.groupId,
          saveStatus: 'saved',
        });
        return true;
      } catch {
        return false;
      }
    } else {
      const content = await noteRepo.getNoteContent(id);
      const blocks = content?.bodyJson ?? [
        { id: `blk_${Date.now()}`, type: 'paragraph', text: '', indent: 0 },
      ];
      set({
        activeNote: note,
        activeBlocks: blocks,
        activeGroupId: note.groupId,
        saveStatus: 'saved',
      });
      return true;
    }
  },

  updateActiveDraft: (title: string, blocks: NoteBlock[]) => {
    const { activeNote } = get();
    if (!activeNote) return;

    set({
      activeNote: { ...activeNote, title },
      activeBlocks: blocks,
      saveStatus: 'saving',
    });

    pendingDraft = { title, blocks };

    if (autosaveTimer) clearTimeout(autosaveTimer);
    autosaveTimer = setTimeout(() => {
      get().flushPendingSave();
    }, 600); // 600ms debounce
  },

  flushPendingSave: async (vaultKey?: Uint8Array | null) => {
    if (autosaveTimer) {
      clearTimeout(autosaveTimer);
      autosaveTimer = null;
    }

    const { activeNote, activeBlocks } = get();
    if (!activeNote || !pendingDraft) return;

    const draft = pendingDraft;
    pendingDraft = null;

    const { noteRepo } = await getServices();
    try {
      if (activeNote.isLocked) {
        if (!vaultKey) {
          // Cannot autosave locked note without vault key
          set({ saveStatus: 'error' });
          return;
        }
        await noteRepo.saveSessionUnlockedNote(
          activeNote.id,
          draft.title,
          draft.blocks,
          vaultKey
        );
      } else {
        await noteRepo.savePlaintextNote({
          id: activeNote.id,
          title: draft.title,
          blocks: draft.blocks,
          groupId: activeNote.groupId,
          isPinned: activeNote.isPinned,
          isArchived: activeNote.isArchived,
        });
      }

      set({ saveStatus: 'saved' });
      await get().loadNotes();
    } catch {
      set({ saveStatus: 'error' });
    }
  },

  lockActiveNote: async (vaultKey: Uint8Array) => {
    const { activeNote } = get();
    if (!activeNote || activeNote.isLocked) return;

    await get().flushPendingSave();

    const { noteRepo } = await getServices();
    await noteRepo.lockNote(activeNote.id, vaultKey);

    const reloaded = await noteRepo.getNoteById(activeNote.id);
    set({
      activeNote: reloaded,
      activeBlocks: [],
    });
    await get().loadNotes();
  },

  unlockActiveNote: async (vaultKey: Uint8Array) => {
    const { activeNote } = get();
    if (!activeNote) return false;

    const { noteRepo } = await getServices();
    try {
      const payload = await noteRepo.unlockSession(activeNote.id, vaultKey);
      set({
        activeNote: { ...activeNote, title: payload.title },
        activeBlocks: payload.blocks,
      });
      return true;
    } catch {
      return false;
    }
  },

  removeActiveLock: async (vaultKey: Uint8Array) => {
    const { activeNote } = get();
    if (!activeNote || !activeNote.isLocked) return;

    const { noteRepo } = await getServices();
    const unlocked = await noteRepo.removeLock(activeNote.id, vaultKey);
    const content = await noteRepo.getNoteContent(unlocked.id);

    set({
      activeNote: unlocked,
      activeBlocks: content?.bodyJson ?? [],
    });
    await get().loadNotes();
  },

  trashNote: async (id: string) => {
    const { noteRepo } = await getServices();
    await noteRepo.trashNote(id);
    if (get().activeNote?.id === id) {
      set({ activeNote: null, activeBlocks: [] });
    }
    await get().loadNotes();
  },

  restoreNote: async (id: string) => {
    const { noteRepo } = await getServices();
    await noteRepo.restoreNote(id);
    await get().loadNotes();
  },

  exportNote: async (id: string, vaultKey?: Uint8Array | null) => {
    const { noteRepo, exporter } = await getServices();
    const note = await noteRepo.getNoteById(id);
    if (!note) return false;

    let blocks: NoteBlock[] = [];
    let titleToExport = note.title;

    if (note.isLocked) {
      if (!vaultKey) return false;
      const decrypted = await noteRepo.unlockSession(id, vaultKey);
      blocks = decrypted.blocks;
      titleToExport = decrypted.title;
    } else {
      const content = await noteRepo.getNoteContent(id);
      blocks = content?.bodyJson ?? [];
    }

    const noteForExport = { ...note, isLocked: false, title: titleToExport };
    const textContent = ExportService.formatNoteAsText(noteForExport, blocks);
    const filename = ExportService.sanitizeFilename(titleToExport || 'Untitled Note');

    const result = await exporter.exportText(filename, textContent);
    return result.success;
  },
}));
