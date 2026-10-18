import { Clock } from '@notes/core';

export class WebClock implements Clock {
  public now(): number {
    return Date.now();
  }
}
