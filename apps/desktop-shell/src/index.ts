// Desktop bridge interface stub for Stage 2
export interface DesktopBridge {
  getSecurityStatus(): Promise<{ backend: string }>;
}
