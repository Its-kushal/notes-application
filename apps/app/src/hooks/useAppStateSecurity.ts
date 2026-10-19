import { useEffect } from 'react';
import { AppState, AppStateStatus } from 'react-native';
import { useNoteStore } from '../stores/useNoteStore';
import { useVaultStore } from '../stores/useVaultStore';
import { useRouter } from 'expo-router';

export function useAppStateSecurity() {
  const router = useRouter();

  useEffect(() => {
    const handleAppStateChange = async (nextState: AppStateStatus) => {
      if (nextState === 'background' || nextState === 'inactive') {
        const { vaultKey, lockVault } = useVaultStore.getState();
        const { activeNote, flushPendingSave } = useNoteStore.getState();

        // 1. Flush any pending autosaves immediately
        if (activeNote) {
          await flushPendingSave(vaultKey);
        }

        // 2. Drop vault key from memory and scrub buffer
        if (vaultKey) {
          lockVault();
        }

        // 3. If a locked note or vault route is open, navigate to home
        if (activeNote?.isLocked) {
          router.replace('/');
        }
      }
    };

    const subscription = AppState.addEventListener('change', handleAppStateChange);
    return () => {
      subscription.remove();
    };
  }, [router]);
}
