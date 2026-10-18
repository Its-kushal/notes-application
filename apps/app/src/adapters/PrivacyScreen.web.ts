import { PrivacyScreen } from '@notes/core';

export class WebPrivacyScreen implements PrivacyScreen {
  public async enable(): Promise<void> {
    // No-op in browser environment
  }

  public async disable(): Promise<void> {
    // No-op in browser environment
  }
}
