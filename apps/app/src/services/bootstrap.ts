import {
  NoteRepository,
  GroupRepository,
  TaskRepository,
  VaultRepository,
  DbDriver,
} from '@notes/core';
import {
  NativeDatabaseOpener,
  NativeCipher,
  NativeKdf,
  NativePrivacyScreen,
  NativeExporter,
  NativeClock,
} from '../adapters';

export interface AppServices {
  db: DbDriver;
  noteRepo: NoteRepository;
  groupRepo: GroupRepository;
  taskRepo: TaskRepository;
  vaultRepo: VaultRepository;
  cipher: NativeCipher;
  kdf: NativeKdf;
  privacyScreen: NativePrivacyScreen;
  exporter: NativeExporter;
  clock: NativeClock;
}

let servicesInstance: AppServices | null = null;
let initPromise: Promise<AppServices> | null = null;

export async function getServices(): Promise<AppServices> {
  if (servicesInstance) {
    return servicesInstance;
  }

  if (initPromise) {
    return initPromise;
  }

  initPromise = (async () => {
    const opener = new NativeDatabaseOpener();
    const result = await opener.openDatabase('notes_production.db');

    if (result.status !== 'opened') {
      throw new Error(`Failed to open database: ${result.status === 'error' ? result.message : result.status}`);
    }

    const cipher = new NativeCipher();
    const kdf = new NativeKdf();
    const privacyScreen = new NativePrivacyScreen();
    const exporter = new NativeExporter();
    const clock = new NativeClock();

    const noteRepo = new NoteRepository(result.db, cipher);
    const groupRepo = new GroupRepository(result.db);
    const taskRepo = new TaskRepository(result.db);
    const vaultRepo = new VaultRepository(result.db, cipher, kdf);

    servicesInstance = {
      db: result.db,
      noteRepo,
      groupRepo,
      taskRepo,
      vaultRepo,
      cipher,
      kdf,
      privacyScreen,
      exporter,
      clock,
    };

    return servicesInstance;
  })();

  return initPromise;
}
