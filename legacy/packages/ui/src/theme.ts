export const theme = {
  colors: {
    background: '#090D16',
    surface: '#111827',
    surfaceElevated: '#1E293B',
    surfaceHighlight: '#273549',
    border: '#334155',
    borderSubtle: '#1E293B',

    primary: '#6366F1',
    primaryHover: '#4F46E5',
    primaryLight: 'rgba(99, 102, 241, 0.15)',

    success: '#10B981',
    successLight: 'rgba(16, 185, 129, 0.15)',
    error: '#EF4444',
    errorLight: 'rgba(239, 68, 68, 0.15)',
    warning: '#F59E0B',
    warningLight: 'rgba(245, 158, 11, 0.15)',

    textPrimary: '#F8FAFC',
    textSecondary: '#94A3B8',
    textMuted: '#64748B',
    textInverse: '#090D16',

    vaultAccent: '#A855F7',
    vaultLight: 'rgba(168, 85, 247, 0.15)',
  },
  spacing: {
    xs: 4,
    sm: 8,
    md: 16,
    lg: 24,
    xl: 32,
  },
  radii: {
    sm: 6,
    md: 10,
    lg: 16,
    full: 9999,
  },
  typography: {
    title: {
      fontSize: 24,
      fontWeight: '700' as const,
      lineHeight: 32,
      color: '#F8FAFC',
    },
    heading: {
      fontSize: 18,
      fontWeight: '600' as const,
      lineHeight: 24,
      color: '#F8FAFC',
    },
    subheading: {
      fontSize: 15,
      fontWeight: '600' as const,
      lineHeight: 20,
      color: '#CBD5E1',
    },
    body: {
      fontSize: 14,
      fontWeight: '400' as const,
      lineHeight: 20,
      color: '#F8FAFC',
    },
    caption: {
      fontSize: 12,
      fontWeight: '400' as const,
      lineHeight: 16,
      color: '#94A3B8',
    },
  },
};
