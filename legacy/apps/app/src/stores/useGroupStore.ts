import { create } from 'zustand';
import { NoteGroup } from '@notes/core';
import { getServices } from '../services/bootstrap';

export interface GroupState {
  groups: NoteGroup[];
  loadGroups: () => Promise<void>;
  createGroup: (name: string, color?: string | null) => Promise<NoteGroup>;
  renameGroup: (id: string, newName: string) => Promise<void>;
  trashGroup: (id: string) => Promise<void>;
  restoreGroup: (id: string) => Promise<void>;
}

export const useGroupStore = create<GroupState>((set) => ({
  groups: [],

  loadGroups: async () => {
    const { db } = await getServices();
    const rows = await db.query<any>(
      'SELECT id, name, color, sort_order AS sortOrder, created_at AS createdAt, updated_at AS updatedAt, deleted_at AS deletedAt FROM note_group WHERE deleted_at IS NULL ORDER BY sort_order ASC, name ASC;'
    );
    set({ groups: rows });
  },

  createGroup: async (name: string, color?: string | null) => {
    const { groupRepo } = await getServices();
    const grp = await groupRepo.createGroup(name, color);
    const { loadGroups } = useGroupStore.getState();
    await loadGroups();
    return grp;
  },

  renameGroup: async (id: string, newName: string) => {
    const { groupRepo } = await getServices();
    await groupRepo.renameGroup(id, newName);
    const { loadGroups } = useGroupStore.getState();
    await loadGroups();
  },

  trashGroup: async (id: string) => {
    const { groupRepo } = await getServices();
    await groupRepo.trashGroup(id);
    const { loadGroups } = useGroupStore.getState();
    await loadGroups();
  },

  restoreGroup: async (id: string) => {
    const { groupRepo } = await getServices();
    await groupRepo.restoreGroup(id);
    const { loadGroups } = useGroupStore.getState();
    await loadGroups();
  },
}));
