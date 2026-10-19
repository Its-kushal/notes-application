import React, { useState, useCallback, useRef } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  ScrollView,
} from 'react-native';
import { BlockType, NoteBlock } from '@notes/core';
import { theme } from '../theme';

export interface BlockEditorProps {
  title: string;
  blocks: NoteBlock[];
  isLocked?: boolean;
  saveStatus?: 'saved' | 'saving' | 'error';
  onTitleChange: (title: string) => void;
  onBlocksChange: (blocks: NoteBlock[]) => void;
  onLockPress?: () => void;
  onExportPress?: () => void;
}

export const BlockEditor: React.FC<BlockEditorProps> = ({
  title,
  blocks,
  isLocked = false,
  saveStatus = 'saved',
  onTitleChange,
  onBlocksChange,
  onLockPress,
  onExportPress,
}) => {
  // In-memory undo / redo stack
  const historyRef = useRef<NoteBlock[][]>([blocks]);
  const historyIndexRef = useRef<number>(0);
  const [canUndo, setCanUndo] = useState(false);
  const [canRedo, setCanRedo] = useState(false);

  const pushHistory = useCallback((newBlocks: NoteBlock[]) => {
    const currentHist = historyRef.current.slice(0, historyIndexRef.current + 1);
    currentHist.push(newBlocks);
    // Keep last 30 actions
    if (currentHist.length > 30) currentHist.shift();
    historyRef.current = currentHist;
    historyIndexRef.current = currentHist.length - 1;
    setCanUndo(historyIndexRef.current > 0);
    setCanRedo(false);
    onBlocksChange(newBlocks);
  }, [onBlocksChange]);

  const handleUndo = useCallback(() => {
    if (historyIndexRef.current > 0) {
      historyIndexRef.current -= 1;
      const prev = historyRef.current[historyIndexRef.current];
      if (prev) {
        onBlocksChange(prev);
        setCanUndo(historyIndexRef.current > 0);
        setCanRedo(true);
      }
    }
  }, [onBlocksChange]);

  const handleRedo = useCallback(() => {
    if (historyIndexRef.current < historyRef.current.length - 1) {
      historyIndexRef.current += 1;
      const next = historyRef.current[historyIndexRef.current];
      if (next) {
        onBlocksChange(next);
        setCanUndo(true);
        setCanRedo(historyIndexRef.current < historyRef.current.length - 1);
      }
    }
  }, [onBlocksChange]);

  const updateBlockText = (index: number, text: string) => {
    const updated = [...blocks];
    const b = updated[index];
    if (b) {
      updated[index] = { ...b, text };
      pushHistory(updated);
    }
  };

  const toggleCheck = (index: number) => {
    const updated = [...blocks];
    const b = updated[index];
    if (b && b.type === 'check') {
      updated[index] = { ...b, checked: !b.checked };
      pushHistory(updated);
    }
  };

  const changeBlockType = (index: number, newType: BlockType) => {
    const updated = [...blocks];
    const b = updated[index];
    if (b) {
      updated[index] = {
        ...b,
        type: newType,
        checked: newType === 'check' ? false : undefined,
      };
      pushHistory(updated);
    }
  };

  const addBlockAfter = (index: number) => {
    const current = blocks[index];
    const newBlock: NoteBlock = {
      id: `blk_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`,
      type: current ? current.type : 'paragraph',
      text: '',
      indent: current ? current.indent : 0,
      checked: current && current.type === 'check' ? false : undefined,
    };
    const updated = [...blocks];
    updated.splice(index + 1, 0, newBlock);
    pushHistory(updated);
  };

  const indentBlock = (index: number, delta: number) => {
    const updated = [...blocks];
    const b = updated[index];
    if (b) {
      const nextIndent = Math.max(0, Math.min(3, b.indent + delta));
      updated[index] = { ...b, indent: nextIndent };
      pushHistory(updated);
    }
  };

  let numberSeq = 1;

  return (
    <View style={styles.container}>
      {/* Top Bar with Status and Actions */}
      <View style={styles.topBar}>
        <View style={styles.statusBox}>
          <Text style={[styles.statusText, saveStatus === 'saving' && styles.statusSaving]}>
            {saveStatus === 'saving' ? '● Saving...' : saveStatus === 'error' ? '✕ Error' : '✓ Saved'}
          </Text>
        </View>

        <View style={styles.topActions}>
          <TouchableOpacity
            style={[styles.iconButton, !canUndo && styles.disabledButton]}
            onPress={handleUndo}
            disabled={!canUndo}
          >
            <Text style={styles.iconText}>⤺</Text>
          </TouchableOpacity>

          <TouchableOpacity
            style={[styles.iconButton, !canRedo && styles.disabledButton]}
            onPress={handleRedo}
            disabled={!canRedo}
          >
            <Text style={styles.iconText}>⤻</Text>
          </TouchableOpacity>

          {onLockPress && (
            <TouchableOpacity style={styles.iconButton} onPress={onLockPress}>
              <Text style={styles.iconText}>{isLocked ? '🔒' : '🔓'}</Text>
            </TouchableOpacity>
          )}

          {onExportPress && (
            <TouchableOpacity style={styles.iconButton} onPress={onExportPress}>
              <Text style={styles.iconText}>📤</Text>
            </TouchableOpacity>
          )}
        </View>
      </View>

      {/* Title Input */}
      <TextInput
        style={styles.titleInput}
        value={title}
        onChangeText={onTitleChange}
        placeholder="Note Title"
        placeholderTextColor={theme.colors.textMuted}
        selectionColor={theme.colors.primary}
      />

      {/* Block List */}
      <ScrollView style={styles.scrollArea} keyboardShouldPersistTaps="handled">
        {blocks.map((block, index) => {
          if (block.type === 'number') {
            numberSeq++;
          } else {
            numberSeq = 1;
          }

          const indentPadding = block.indent * 16;

          return (
            <View key={block.id} style={[styles.blockRow, { paddingLeft: indentPadding }]}>
              {/* Prefix indicator */}
              {block.type === 'bullet' && <Text style={styles.bulletSymbol}>•</Text>}

              {block.type === 'number' && (
                <Text style={styles.numberSymbol}>{numberSeq - 1}.</Text>
              )}

              {block.type === 'check' && (
                <TouchableOpacity
                  style={[styles.checkbox, block.checked && styles.checkboxChecked]}
                  onPress={() => toggleCheck(index)}
                  activeOpacity={0.7}
                >
                  {block.checked && <Text style={styles.checkboxTick}>✓</Text>}
                </TouchableOpacity>
              )}

              {/* Text input */}
              <TextInput
                style={[styles.blockInput, block.checked && styles.checkedText]}
                value={block.text}
                onChangeText={(text) => updateBlockText(index, text)}
                onSubmitEditing={() => addBlockAfter(index)}
                placeholder={index === 0 && blocks.length === 1 ? 'Start typing your note...' : ''}
                placeholderTextColor={theme.colors.textMuted}
                multiline
                blurOnSubmit={false}
                selectionColor={theme.colors.primary}
              />

              {/* Block formatting options */}
              <View style={styles.blockQuickTools}>
                <TouchableOpacity
                  onPress={() => indentBlock(index, -1)}
                  style={styles.toolBtn}
                  disabled={block.indent === 0}
                >
                  <Text style={styles.toolBtnText}>⇤</Text>
                </TouchableOpacity>
                <TouchableOpacity
                  onPress={() => indentBlock(index, 1)}
                  style={styles.toolBtn}
                  disabled={block.indent >= 3}
                >
                  <Text style={styles.toolBtnText}>⇥</Text>
                </TouchableOpacity>
                <TouchableOpacity
                  onPress={() => {
                    const next: BlockType =
                      block.type === 'paragraph'
                        ? 'bullet'
                        : block.type === 'bullet'
                        ? 'check'
                        : block.type === 'check'
                        ? 'number'
                        : 'paragraph';
                    changeBlockType(index, next);
                  }}
                  style={styles.toolBtn}
                >
                  <Text style={styles.toolBtnText}>
                    {block.type === 'check'
                      ? '☑'
                      : block.type === 'bullet'
                      ? '•'
                      : block.type === 'number'
                      ? '1.'
                      : '¶'}
                  </Text>
                </TouchableOpacity>
              </View>
            </View>
          );
        })}
      </ScrollView>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: theme.colors.background,
    padding: theme.spacing.md,
  },
  topBar: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: theme.spacing.sm,
    paddingBottom: theme.spacing.xs,
    borderBottomWidth: 1,
    borderBottomColor: theme.colors.borderSubtle,
  },
  statusBox: {
    paddingVertical: 2,
    paddingHorizontal: 6,
    borderRadius: 4,
  },
  statusText: {
    ...theme.typography.caption,
    color: theme.colors.success,
  },
  statusSaving: {
    color: theme.colors.warning,
  },
  topActions: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  iconButton: {
    width: 32,
    height: 32,
    borderRadius: theme.radii.sm,
    backgroundColor: theme.colors.surfaceElevated,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: theme.colors.border,
  },
  disabledButton: {
    opacity: 0.3,
  },
  iconText: {
    fontSize: 16,
    color: theme.colors.textPrimary,
  },
  titleInput: {
    ...theme.typography.title,
    color: theme.colors.textPrimary,
    marginBottom: theme.spacing.md,
    paddingVertical: 4,
  },
  scrollArea: {
    flex: 1,
  },
  blockRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    marginBottom: 6,
  },
  bulletSymbol: {
    color: theme.colors.primary,
    fontSize: 18,
    marginRight: 8,
    marginTop: 2,
  },
  numberSymbol: {
    color: theme.colors.primary,
    fontSize: 14,
    fontWeight: '600',
    marginRight: 6,
    marginTop: 3,
  },
  checkbox: {
    width: 18,
    height: 18,
    borderRadius: 4,
    borderWidth: 1.5,
    borderColor: theme.colors.border,
    marginRight: 8,
    marginTop: 4,
    alignItems: 'center',
    justifyContent: 'center',
  },
  checkboxChecked: {
    backgroundColor: theme.colors.primary,
    borderColor: theme.colors.primary,
  },
  checkboxTick: {
    color: '#FFFFFF',
    fontSize: 11,
    fontWeight: 'bold',
  },
  blockInput: {
    ...theme.typography.body,
    flex: 1,
    color: theme.colors.textPrimary,
    paddingVertical: 2,
    minHeight: 24,
  },
  checkedText: {
    textDecorationLine: 'line-through',
    color: theme.colors.textMuted,
  },
  blockQuickTools: {
    flexDirection: 'row',
    alignItems: 'center',
    marginLeft: 4,
  },
  toolBtn: {
    paddingHorizontal: 4,
    paddingVertical: 2,
  },
  toolBtnText: {
    color: theme.colors.textMuted,
    fontSize: 12,
  },
});
