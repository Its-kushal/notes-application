import { Clock } from '@notes/core';

export class NativeClock implements Clock {
  public now(): number {
    return Date.now();
  }
}
