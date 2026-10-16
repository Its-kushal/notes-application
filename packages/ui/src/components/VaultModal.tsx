import React, { useState } from 'react';
import {
  Modal,
  View,
  Text,
  TextInput,
  StyleSheet,
  TouchableOpacity,
} from 'react-native';
import { theme } from '../theme';
import { Button } from './Button';

export interface VaultModalProps {
  visible: boolean;
  isSetup?: boolean;
  onClose: () => void;
  onSubmit: (passcode: string) => Promise<boolean>;
  onRemoveLock?: () => Promise<void>;
  allowRemoveLock?: boolean;
}

export const VaultModal: React.FC<VaultModalProps> = ({
  visible,
  isSetup = false,
  onClose,
  onSubmit,
  onRemoveLock,
  allowRemoveLock = false,
}) => {
  const [passcode, setPasscode] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  React.useEffect(() => {
    if (!visible) {
      setPasscode('');
      setError(null);
    }
  }, [visible]);

  const handleSubmit = async () => {
    if (!passcode.trim()) {
      setError('Please enter your passcode');
      return;
    }

    setLoading(true);
    setError(null);
    try {
      const ok = await onSubmit(passcode);
      if (ok) {
        setPasscode('');
        onClose();
      } else {
        setError('Incorrect passcode');
      }
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Authentication failed');
    } finally {
      setLoading(false);
    }
  };

  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={onClose}>
      <View style={styles.backdrop}>
        <View style={styles.container}>
          <Text style={styles.title}>{isSetup ? 'Setup Secure Vault' : 'Unlock Vault'}</Text>
          <Text style={styles.subtitle}>
            {isSetup
              ? 'Choose a master passcode. Encrypted with hardware scrypt + AES-256-GCM.'
              : 'Enter your master passcode to decrypt this note in memory.'}
          </Text>

          <TextInput
            style={styles.input}
            value={passcode}
            onChangeText={(text) => {
              setPasscode(text);
              if (error) setError(null);
            }}
            placeholder="Enter passcode"
            placeholderTextColor={theme.colors.textMuted}
            secureTextEntry
            autoFocus
            selectionColor={theme.colors.vaultAccent}
          />

          {error && <Text style={styles.errorText}>{error}</Text>}

          <View style={styles.buttonRow}>
            <Button
              title="Cancel"
              variant="secondary"
              onPress={() => {
                setPasscode('');
                setError(null);
                onClose();
              }}
              style={styles.btn}
            />
            <Button
              title={isSetup ? 'Setup' : 'Unlock'}
              variant="vault"
              loading={loading}
              onPress={handleSubmit}
              style={styles.btn}
            />
          </View>

          {allowRemoveLock && onRemoveLock && (
            <TouchableOpacity
              style={styles.removeLockBtn}
              onPress={async () => {
                setLoading(true);
                try {
                  await onRemoveLock();
                  onClose();
                } finally {
                  setLoading(false);
                }
              }}
            >
              <Text style={styles.removeLockText}>Remove Lock Permanently</Text>
            </TouchableOpacity>
          )}
        </View>
      </View>
    </Modal>
  );
};

const styles = StyleSheet.create({
  backdrop: {
    flex: 1,
    backgroundColor: 'rgba(9, 13, 22, 0.85)',
    justifyContent: 'center',
    alignItems: 'center',
    padding: theme.spacing.md,
  },
  container: {
    backgroundColor: theme.colors.surfaceElevated,
    borderRadius: theme.radii.lg,
    padding: theme.spacing.lg,
    width: '100%',
    maxWidth: 380,
    borderWidth: 1,
    borderColor: theme.colors.border,
  },
  title: {
    ...theme.typography.heading,
    color: theme.colors.textPrimary,
    marginBottom: 4,
  },
  subtitle: {
    ...theme.typography.caption,
    color: theme.colors.textSecondary,
    marginBottom: theme.spacing.md,
    lineHeight: 18,
  },
  input: {
    backgroundColor: theme.colors.surface,
    borderRadius: theme.radii.md,
    padding: theme.spacing.md,
    color: theme.colors.textPrimary,
    borderWidth: 1,
    borderColor: theme.colors.border,
    fontSize: 16,
    marginBottom: theme.spacing.md,
  },
  errorText: {
    ...theme.typography.caption,
    color: theme.colors.error,
    marginBottom: theme.spacing.sm,
  },
  buttonRow: {
    flexDirection: 'row',
    gap: 12,
  },
  btn: {
    flex: 1,
  },
  removeLockBtn: {
    marginTop: theme.spacing.md,
    alignItems: 'center',
    paddingVertical: 6,
  },
  removeLockText: {
    ...theme.typography.caption,
    color: theme.colors.error,
    textDecorationLine: 'underline',
  },
});
