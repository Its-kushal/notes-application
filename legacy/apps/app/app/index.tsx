import React, { useEffect, useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TextInput,
  TouchableOpacity,
  Alert,
  FlatList,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { theme, NoteCard, VaultModal, Badge } from '@notes/ui';
import { useNoteStore } from '../src/stores/useNoteStore';
import { useGroupStore } from '../src/stores/useGroupStore';
import { useVaultStore } from '../src/stores/useVaultStore';

export default function HomeScreen() {
  const router = useRouter();

  const {
    notes,
    searchQuery,
    selectedGroupId,
    loadNotes,
    setSearchQuery,
    setSelectedGroupId,
    createNote,
    selectNote,
    trashNote,
  } = useNoteStore();

  const { groups, loadGroups, createGroup } = useGroupStore();

  const {
    isConfigured: isVaultConfigured,
    vaultKey,
    checkVaultStatus,
    unlockVault,
  } = useVaultStore();

  const [vaultModalVisible, setVaultModalVisible] = useState(false);
  const [selectedLockedNoteId, setSelectedLockedNoteId] = useState<string | null>(null);

  useEffect(() => {
    loadNotes();
    loadGroups();
    checkVaultStatus();
  }, [loadNotes, loadGroups, checkVaultStatus]);

  const handleCreateNote = async () => {
    await createNote(selectedGroupId);
    router.push('/editor');
  };

  const handleNotePress = async (noteId: string, isLocked: boolean) => {
    if (isLocked) {
      if (!vaultKey) {
        setSelectedLockedNoteId(noteId);
        setVaultModalVisible(true);
        return;
      }
    }
    const success = await selectNote(noteId, vaultKey);
    if (success || !isLocked) {
      router.push('/editor');
    }
  };

  const handleVaultUnlock = async (passcode: string): Promise<boolean> => {
    const ok = await unlockVault(passcode);
    if (ok && selectedLockedNoteId) {
      const key = useVaultStore.getState().vaultKey;
      await selectNote(selectedLockedNoteId, key);
      setSelectedLockedNoteId(null);
      router.push('/editor');
    }
    return ok;
  };

  const handleAddGroupPrompt = () => {
    Alert.prompt
      ? Alert.prompt('New Folder', 'Enter folder name', [
          { text: 'Cancel', style: 'cancel' },
          {
            text: 'Create',
            onPress: (text?: string) => {
              if (text && text.trim()) {
                createGroup(text.trim());
              }
            },
          },
        ])
      : (() => {
          const name = `Folder ${groups.length + 1}`;
          createGroup(name);
        })();
  };

  return (
    <SafeAreaView style={styles.container}>
      {/* Top Header */}
      <View style={styles.header}>
        <View style={styles.titleRow}>
          <Text style={styles.appTitle}>Privacy Notes</Text>
          <Badge label="100% Local" variant="success" />
        </View>
        <Text style={styles.appSubtitle}>Encrypted SQLite • Zero Cloud • Zero Telemetry</Text>
      </View>

      {/* Search Input */}
      <View style={styles.searchBox}>
        <Text style={styles.searchIcon}>🔍</Text>
        <TextInput
          style={styles.searchInput}
          value={searchQuery}
          onChangeText={setSearchQuery}
          placeholder="Search notes with FTS5..."
          placeholderTextColor={theme.colors.textMuted}
          selectionColor={theme.colors.primary}
          clearButtonMode="while-editing"
        />
        {searchQuery.length > 0 && (
          <TouchableOpacity onPress={() => setSearchQuery('')} style={styles.clearSearchBtn}>
            <Text style={styles.clearSearchText}>✕</Text>
          </TouchableOpacity>
        )}
      </View>

      {/* Folder Chips */}
      <View style={styles.groupScrollContainer}>
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.groupChips}>
          <TouchableOpacity
            style={[styles.chip, selectedGroupId === null && styles.activeChip]}
            onPress={() => setSelectedGroupId(null)}
          >
            <Text style={[styles.chipText, selectedGroupId === null && styles.activeChipText]}>
              All Notes
            </Text>
          </TouchableOpacity>

          {groups.map((group) => (
            <TouchableOpacity
              key={group.id}
              style={[styles.chip, selectedGroupId === group.id && styles.activeChip]}
              onPress={() => setSelectedGroupId(group.id)}
            >
              <Text style={[styles.chipText, selectedGroupId === group.id && styles.activeChipText]}>
                📁 {group.name}
              </Text>
            </TouchableOpacity>
          ))}

          <TouchableOpacity style={styles.addChip} onPress={handleAddGroupPrompt}>
            <Text style={styles.addChipText}>+ Folder</Text>
          </TouchableOpacity>
        </ScrollView>
      </View>

      {/* Notes List */}
      <FlatList
        data={notes}
        keyExtractor={(item) => item.id}
        contentContainerStyle={styles.listContent}
        renderItem={({ item }) => {
          const group = groups.find((g) => g.id === item.groupId);
          return (
            <NoteCard
              note={item}
              groupName={group?.name}
              onPress={() => handleNotePress(item.id, item.isLocked)}
              onLongPress={() => {
                Alert.alert('Delete Note', `Move "${item.title || 'Untitled'}" to Trash?`, [
                  { text: 'Cancel', style: 'cancel' },
                  { text: 'Delete', style: 'destructive', onPress: () => trashNote(item.id) },
                ]);
              }}
            />
          );
        }}
        ListEmptyComponent={
          <View style={styles.emptyState}>
            <Text style={styles.emptyIcon}>📝</Text>
            <Text style={styles.emptyTitle}>
              {searchQuery ? 'No notes matched your search' : 'No notes yet'}
            </Text>
            <Text style={styles.emptySubtitle}>
              {searchQuery
                ? 'Try a different keyword or prefix term'
                : 'Create your first encrypted note below'}
            </Text>
          </View>
        }
      />

      {/* Floating Action Button (FAB) */}
      <TouchableOpacity style={styles.fab} onPress={handleCreateNote} activeOpacity={0.8}>
        <Text style={styles.fabText}>+</Text>
      </TouchableOpacity>

      {/* Vault Unlock Modal */}
      <VaultModal
        visible={vaultModalVisible}
        isSetup={!isVaultConfigured}
        onClose={() => {
          setVaultModalVisible(false);
          setSelectedLockedNoteId(null);
        }}
        onSubmit={handleVaultUnlock}
      />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: theme.colors.background,
  },
  header: {
    paddingHorizontal: theme.spacing.md,
    paddingTop: theme.spacing.md,
    paddingBottom: theme.spacing.sm,
  },
  titleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 4,
  },
  appTitle: {
    ...theme.typography.title,
    fontSize: 26,
  },
  appSubtitle: {
    ...theme.typography.caption,
    color: theme.colors.textMuted,
  },
  searchBox: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: theme.colors.surfaceElevated,
    borderRadius: theme.radii.md,
    marginHorizontal: theme.spacing.md,
    marginVertical: theme.spacing.sm,
    paddingHorizontal: 12,
    borderWidth: 1,
    borderColor: theme.colors.border,
  },
  searchIcon: {
    marginRight: 8,
    fontSize: 14,
  },
  searchInput: {
    ...theme.typography.body,
    flex: 1,
    paddingVertical: 10,
    color: theme.colors.textPrimary,
  },
  clearSearchBtn: {
    padding: 4,
  },
  clearSearchText: {
    color: theme.colors.textMuted,
    fontSize: 14,
  },
  groupScrollContainer: {
    marginVertical: 4,
  },
  groupChips: {
    paddingHorizontal: theme.spacing.md,
    gap: 8,
  },
  chip: {
    paddingVertical: 6,
    paddingHorizontal: 12,
    borderRadius: theme.radii.full,
    backgroundColor: theme.colors.surfaceElevated,
    borderWidth: 1,
    borderColor: theme.colors.border,
  },
  activeChip: {
    backgroundColor: theme.colors.primary,
    borderColor: theme.colors.primary,
  },
  chipText: {
    ...theme.typography.caption,
    color: theme.colors.textSecondary,
    fontWeight: '600',
  },
  activeChipText: {
    color: '#FFFFFF',
  },
  addChip: {
    paddingVertical: 6,
    paddingHorizontal: 12,
    borderRadius: theme.radii.full,
    borderWidth: 1,
    borderColor: theme.colors.border,
    borderStyle: 'dashed',
  },
  addChipText: {
    ...theme.typography.caption,
    color: theme.colors.primary,
    fontWeight: '600',
  },
  listContent: {
    paddingHorizontal: theme.spacing.md,
    paddingBottom: 80,
    paddingTop: theme.spacing.sm,
  },
  emptyState: {
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 60,
  },
  emptyIcon: {
    fontSize: 48,
    marginBottom: 12,
  },
  emptyTitle: {
    ...theme.typography.heading,
    fontSize: 16,
    color: theme.colors.textSecondary,
    marginBottom: 4,
  },
  emptySubtitle: {
    ...theme.typography.caption,
    color: theme.colors.textMuted,
  },
  fab: {
    position: 'absolute',
    right: 20,
    bottom: 24,
    width: 56,
    height: 56,
    borderRadius: 28,
    backgroundColor: theme.colors.primary,
    alignItems: 'center',
    justifyContent: 'center',
    elevation: 6,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 6,
  },
  fabText: {
    color: '#FFFFFF',
    fontSize: 32,
    lineHeight: 34,
    fontWeight: '300',
  },
});
