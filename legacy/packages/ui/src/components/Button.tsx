import React from 'react';
import { TouchableOpacity, Text, StyleSheet, ActivityIndicator, ViewStyle, TextStyle } from 'react-native';
import { theme } from '../theme';

export interface ButtonProps {
  title: string;
  onPress: () => void;
  variant?: 'primary' | 'secondary' | 'danger' | 'ghost' | 'vault';
  size?: 'sm' | 'md' | 'lg';
  disabled?: boolean;
  loading?: boolean;
  style?: ViewStyle;
}

export const Button: React.FC<ButtonProps> = ({
  title,
  onPress,
  variant = 'primary',
  size = 'md',
  disabled = false,
  loading = false,
  style,
}) => {
  const getContainerStyle = (): ViewStyle[] => {
    const list: ViewStyle[] = [styles.base, styles[size]];
    if (variant === 'primary') list.push(styles.primary);
    if (variant === 'secondary') list.push(styles.secondary);
    if (variant === 'danger') list.push(styles.danger);
    if (variant === 'ghost') list.push(styles.ghost);
    if (variant === 'vault') list.push(styles.vault);
    if (disabled || loading) list.push(styles.disabled);
    if (style) list.push(style);
    return list;
  };

  const getTextStyle = (): TextStyle[] => {
    const list: TextStyle[] = [styles.textBase, styles[`text_${size}` as keyof typeof styles] as TextStyle];
    if (variant === 'ghost') list.push(styles.textGhost);
    if (variant === 'secondary') list.push(styles.textSecondary);
    if (disabled) list.push(styles.textDisabled);
    return list;
  };

  return (
    <TouchableOpacity
      style={getContainerStyle()}
      onPress={onPress}
      disabled={disabled || loading}
      activeOpacity={0.7}
    >
      {loading ? (
        <ActivityIndicator size="small" color={variant === 'ghost' ? theme.colors.primary : '#FFFFFF'} />
      ) : (
        <Text style={getTextStyle()}>{title}</Text>
      )}
    </TouchableOpacity>
  );
};

const styles = StyleSheet.create({
  base: {
    borderRadius: theme.radii.md,
    alignItems: 'center',
    justifyContent: 'center',
    flexDirection: 'row',
  },
  sm: {
    paddingVertical: 6,
    paddingHorizontal: 12,
  },
  md: {
    paddingVertical: 10,
    paddingHorizontal: 16,
  },
  lg: {
    paddingVertical: 14,
    paddingHorizontal: 20,
  },
  primary: {
    backgroundColor: theme.colors.primary,
  },
  secondary: {
    backgroundColor: theme.colors.surfaceElevated,
    borderWidth: 1,
    borderColor: theme.colors.border,
  },
  danger: {
    backgroundColor: theme.colors.error,
  },
  ghost: {
    backgroundColor: 'transparent',
  },
  vault: {
    backgroundColor: theme.colors.vaultAccent,
  },
  disabled: {
    opacity: 0.5,
  },
  textBase: {
    color: '#FFFFFF',
    fontWeight: '600',
  },
  text_sm: {
    fontSize: 13,
  },
  text_md: {
    fontSize: 14,
  },
  text_lg: {
    fontSize: 16,
  },
  textSecondary: {
    color: theme.colors.textPrimary,
  },
  textGhost: {
    color: theme.colors.primary,
  },
  textDisabled: {
    color: theme.colors.textMuted,
  },
});
