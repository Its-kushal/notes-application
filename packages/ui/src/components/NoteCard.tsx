import React from 'react';
import { View, Text, StyleSheet, TouchableOpacity } from 'react-native';
import { Note } from '@notes/core';
import { theme } from '../theme';
import { Badge } from './Badge';

export interface NoteCardProps {
  note: Note;
  groupName?: string | null;
  bodyPreview?: string;
  onPress: () => void;
  onLongPress?: () => void;
  selected?: boolean;
  selectionMode?: boolean;
}

export const NoteCard: React.FC<NoteCardProps> = ({
  note,
  groupName,
  bodyPreview,
  onPress,
  onLongPress,
  selected = false,
  selectionMode = false,
}) => {
  const formattedDate = new Date(note.updatedAt).toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
  });

  return (
    <TouchableOpacity
      style={[
        styles.card,
        note.isPinned && styles.pinnedCard,
        selected && styles.selectedCard,
      ]}
      onPress={onPress}
      onLongPress={onLongPress}
      activeOpacity={0.7}
    >
      <View style={styles.header}>
        <View style={styles.titleContainer}>
          {note.isPinned && <Text style={styles.pinIcon}>📌 </Text>}
          <Text style={styles.title} numberOfLines={1}>
            {note.isLocked ? 'Locked Note' : note.title || 'Untitled Note'}
          </Text>
        </View>

        {note.isLocked && <Badge label="Locked" variant="vault" />}
      </View>

      {/* Body preview: NEVER displayed if locked */}
      {!note.isLocked && bodyPreview ? (
        <Text style={styles.preview} numberOfLines={2}>
          {bodyPreview}
        </Text>
      ) : null}

      <View style={styles.footer}>
        <View style={styles.metaRow}>
          {groupName && <Badge label={groupName} variant="muted" />}
          <Text style={styles.dateText}>{formattedDate}</Text>
          {!note.isLocked && note.wordCount > 0 && (
            <Text style={styles.wordCount}>{note.wordCount} words</Text>
          )}
        </View>

        {selectionMode && (
          <View style={[styles.checkbox, selected && styles.checkboxSelected]}>
            {selected && <Text style={styles.checkmark}>✓</Text>}
          </View>
        )}
      </View>
    </TouchableOpacity>
  );
};

const styles = StyleSheet.create({
  card: {
    backgroundColor: theme.colors.surfaceElevated,
    borderRadius: theme.radii.md,
    padding: theme.spacing.md,
    borderWidth: 1,
    borderColor: theme.colors.border,
    marginBottom: theme.spacing.sm,
  },
  pinnedCard: {
    borderColor: theme.colors.primary,
    backgroundColor: 'rgba(30, 41, 59, 0.95)',
  },
  selectedCard: {
    borderColor: theme.colors.primary,
    backgroundColor: 'rgba(99, 102, 241, 0.12)',
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 6,
  },
  titleContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    flex: 1,
    marginRight: 8,
  },
  pinIcon: {
    fontSize: 12,
  },
  title: {
    ...theme.typography.heading,
    fontSize: 16,
    flex: 1,
  },
  preview: {
    ...theme.typography.body,
    color: theme.colors.textSecondary,
    fontSize: 13,
    lineHeight: 18,
    marginBottom: 10,
  },
  footer: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginTop: 4,
  },
  metaRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    flex: 1,
  },
  dateText: {
    ...theme.typography.caption,
  },
  wordCount: {
    ...theme.typography.caption,
    color: theme.colors.textMuted,
  },
  checkbox: {
    width: 20,
    height: 20,
    borderRadius: 4,
    borderWidth: 1,
    borderColor: theme.colors.border,
    alignItems: 'center',
    justifyContent: 'center',
  },
  checkboxSelected: {
    backgroundColor: theme.colors.primary,
    borderColor: theme.colors.primary,
  },
  checkmark: {
    color: '#FFFFFF',
    fontSize: 12,
    fontWeight: 'bold',
  },
});
