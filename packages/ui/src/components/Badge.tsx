import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { theme } from '../theme';

export interface BadgeProps {
  label: string;
  variant?: 'primary' | 'success' | 'warning' | 'error' | 'vault' | 'muted';
}

export const Badge: React.FC<BadgeProps> = ({ label, variant = 'primary' }) => {
  return (
    <View style={[styles.badge, styles[variant]]}>
      <Text style={[styles.text, styles[`text_${variant}` as keyof typeof styles]]}>
        {label}
      </Text>
    </View>
  );
};

const styles = StyleSheet.create({
  badge: {
    paddingVertical: 3,
    paddingHorizontal: 8,
    borderRadius: theme.radii.full,
    alignSelf: 'flex-start',
  },
  text: {
    fontSize: 11,
    fontWeight: '600',
  },
  primary: {
    backgroundColor: theme.colors.primaryLight,
  },
  text_primary: {
    color: '#818CF8',
  },
  success: {
    backgroundColor: theme.colors.successLight,
  },
  text_success: {
    color: '#34D399',
  },
  warning: {
    backgroundColor: theme.colors.warningLight,
  },
  text_warning: {
    color: '#FBBF24',
  },
  error: {
    backgroundColor: theme.colors.errorLight,
  },
  text_error: {
    color: '#F87171',
  },
  vault: {
    backgroundColor: theme.colors.vaultLight,
  },
  text_vault: {
    color: '#C084FC',
  },
  muted: {
    backgroundColor: 'rgba(148, 163, 184, 0.1)',
  },
  text_muted: {
    color: theme.colors.textSecondary,
  },
});
