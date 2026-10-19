import { create } from 'zustand';
import { getServices } from '../services/bootstrap';

export interface VaultState {
  isConfigured: boolean;
  vaultKey: Uint8Array | null;
  isUnlocked: boolean;
  checkVaultStatus: () => Promise<boolean>;
  setupVault: (passcode: string) => Promise<boolean>;
  unlockVault: (passcode: string) => Promise<boolean>;
  lockVault: () => void;
}

export const useVaultStore = create<VaultState>((set, get) => ({
  isConfigured: false,
  vaultKey: null,
  isUnlocked: false,

  checkVaultStatus: async () => {
    const { vaultRepo } = await getServices();
    const has = await vaultRepo.hasVault();
    set({ isConfigured: has });
    return has;
  },

  setupVault: async (passcode: string) => {
    const { vaultRepo, privacyScreen } = await getServices();
    try {
      const key = await vaultRepo.setupVault(passcode);
      set({ vaultKey: key, isConfigured: true, isUnlocked: true });
      await privacyScreen.enable();
      return true;
    } catch {
      return false;
    }
  },

  unlockVault: async (passcode: string) => {
    const { vaultRepo, privacyScreen } = await getServices();
    const key = await vaultRepo.unlockVault(passcode);
    if (key) {
      set({ vaultKey: key, isUnlocked: true });
      await privacyScreen.enable();
      return true;
    }
    return false;
  },

  lockVault: () => {
    const { vaultKey } = get();
    if (vaultKey) {
      // Memory scrub: overwrite key buffer before dropping reference
      vaultKey.fill(0);
    }
    set({ vaultKey: null, isUnlocked: false });
    getServices().then(({ privacyScreen }) => {
      privacyScreen.disable();
    });
  },
}));
