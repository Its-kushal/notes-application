import React, { useState } from 'react';
import { View, StyleSheet, TouchableOpacity, Text, Alert } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { theme, BlockEditor, VaultModal } from '@notes/ui';
import { useNoteStore } from '../src/stores/useNoteStore';
import { useVaultStore } from '../src/stores/useVaultStore';

export default function EditorScreen() {
  const router = useRouter();
  const {
    activeNote,
    activeBlocks,
    saveStatus,
    updateActiveDraft,
    flushPendingSave,
    lockActiveNote,
    unlockActiveNote,
    removeActiveLock,
    exportNote,
  } = useNoteStore();

  const {
    isConfigured: isVaultConfigured,
    vaultKey,
    checkVaultStatus,
    setupVault,
    unlockVault,
  } = useVaultStore();

  const [vaultModalVisible, setVaultModalVisible] = useState(false);
  const [isVaultSetupMode, setIsVaultSetupMode] = useState(false);

  if (!activeNote) {
    return (
      <SafeAreaView style={styles.emptyContainer}>
        <Text style={styles.emptyText}>No active note selected.</Text>
        <TouchableOpacity style={styles.backBtn} onPress={() => router.replace('/')}>
          <Text style={styles.backBtnText}>Return to Notes</Text>
        </TouchableOpacity>
      </SafeAreaView>
    );
  }

  const handleBack = async () => {
    await flushPendingSave(vaultKey);
    router.back();
  };

  const handleLockPress = async () => {
    await checkVaultStatus();
    if (!isVaultConfigured) {
      setIsVaultSetupMode(true);
      setVaultModalVisible(true);
      return;
    }

    if (activeNote.isLocked) {
      // Prompt to unlock or remove lock
      setIsVaultSetupMode(false);
      setVaultModalVisible(true);
    } else {
      // Lock note
      if (!vaultKey) {
        setIsVaultSetupMode(false);
        setVaultModalVisible(true);
      } else {
        await lockActiveNote(vaultKey);
      }
    }
  };

  const handleVaultSubmit = async (passcode: string): Promise<boolean> => {
    if (isVaultSetupMode) {
      const ok = await setupVault(passcode);
      if (ok && activeNote) {
        const key = useVaultStore.getState().vaultKey;
        if (key) {
          await lockActiveNote(key);
        }
      }
      return ok;
    } else {
      const ok = await unlockVault(passcode);
      if (ok) {
        const key = useVaultStore.getState().vaultKey;
        if (key) {
          if (activeNote.isLocked) {
            await unlockActiveNote(key);
          } else {
            await lockActiveNote(key);
          }
        }
      }
      return ok;
    }
  };

  const handleRemoveLock = async () => {
    if (vaultKey) {
      await removeActiveLock(vaultKey);
    } else {
      Alert.alert('Vault Locked', 'Please unlock with your passcode first.');
    }
  };

  const handleExport = async () => {
    if (activeNote.isLocked && !vaultKey) {
      Alert.alert('Locked Note', 'Please unlock the note with your passcode before exporting.');
      return;
    }
    const success = await exportNote(activeNote.id, vaultKey);
    if (!success) {
      Alert.alert('Export Failed', 'Unable to export note to file.');
    }
  };

  return (
    <SafeAreaView style={styles.container}>
      {/* Header Bar */}
      <View style={styles.header}>
        <TouchableOpacity onPress={handleBack} style={styles.headerBackBtn}>
          <Text style={styles.headerBackText}>← Back</Text>
        </TouchableOpacity>

        <Text style={styles.headerTitle} numberOfLines={1}>
          {activeNote.isLocked ? '🔒 Locked Note' : activeNote.title || 'Untitled'}
        </Text>

        <View style={styles.headerSpacer} />
      </View>

      {/* Block Editor */}
      <BlockEditor
        title={activeNote.title}
        blocks={activeBlocks}
        isLocked={activeNote.isLocked}
        saveStatus={saveStatus}
        onTitleChange={(title) => updateActiveDraft(title, activeBlocks)}
        onBlocksChange={(blocks) => updateActiveDraft(activeNote.title, blocks)}
        onLockPress={handleLockPress}
        onExportPress={handleExport}
      />

      {/* Vault Modal */}
      <VaultModal
        visible={vaultModalVisible}
        isSetup={isVaultSetupMode}
        onClose={() => setVaultModalVisible(false)}
        onSubmit={handleVaultSubmit}
        onRemoveLock={handleRemoveLock}
        allowRemoveLock={activeNote.isLocked}
      />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: theme.colors.background,
  },
  emptyContainer: {
    flex: 1,
    backgroundColor: theme.colors.background,
    alignItems: 'center',
    justifyContent: 'center',
    padding: theme.spacing.md,
  },
  emptyText: {
    ...theme.typography.body,
    color: theme.colors.textSecondary,
    marginBottom: theme.spacing.md,
  },
  backBtn: {
    backgroundColor: theme.colors.primary,
    paddingVertical: 10,
    paddingHorizontal: 20,
    borderRadius: theme.radii.md,
  },
  backBtnText: {
    color: '#FFFFFF',
    fontWeight: '600',
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: theme.spacing.md,
    paddingVertical: theme.spacing.sm,
    borderBottomWidth: 1,
    borderBottomColor: theme.colors.borderSubtle,
    backgroundColor: theme.colors.surface,
  },
  headerBackBtn: {
    paddingVertical: 6,
    paddingRight: 12,
  },
  headerBackText: {
    color: theme.colors.primary,
    fontWeight: '600',
    fontSize: 15,
  },
  headerTitle: {
    ...theme.typography.subheading,
    flex: 1,
    textAlign: 'center',
  },
  headerSpacer: {
    width: 48,
  },
});
