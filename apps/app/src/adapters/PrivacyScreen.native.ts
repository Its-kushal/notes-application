import { PrivacyScreen } from '@notes/core';
import * as ScreenCapture from 'expo-screen-capture';

export class NativePrivacyScreen implements PrivacyScreen {
  public async enable(): Promise<void> {
    try {
      await ScreenCapture.preventScreenCaptureAsync();
    } catch {
      // Best-effort FLAG_SECURE
    }
  }

  public async disable(): Promise<void> {
    try {
      await ScreenCapture.allowScreenCaptureAsync();
    } catch {
      // Best-effort
    }
  }
}
