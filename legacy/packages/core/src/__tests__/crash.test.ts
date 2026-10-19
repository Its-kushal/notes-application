import { spawn } from 'child_process';
import path from 'path';
import fs from 'fs';
import { NodeDbDriver } from '../adapters/node/NodeDbDriver';

describe('Real Crash Test (SIGKILL atomicity)', () => {
  const testDbPath = path.join(__dirname, 'crash_test.db');
  const workerScript = path.join(__dirname, 'crash_worker.js');

  beforeEach(() => {
    for (const suffix of ['', '-wal', '-shm']) {
      const p = `${testDbPath}${suffix}`;
      if (fs.existsSync(p)) fs.unlinkSync(p);
    }
  });

  afterEach(() => {
    for (const suffix of ['', '-wal', '-shm']) {
      const p = `${testDbPath}${suffix}`;
      if (fs.existsSync(p)) fs.unlinkSync(p);
    }
  });

  test('killing process with SIGKILL mid-transaction preserves database integrity and rolls back cleanly', async () => {
    // 1. Spawn worker child process
    const child = spawn(process.execPath, [workerScript, testDbPath], {
      stdio: ['pipe', 'pipe', 'inherit'],
    });

    await new Promise<void>((resolve, reject) => {
      child.stdout.on('data', (chunk: Buffer) => {
        const text = chunk.toString();
        if (text.includes('READY')) {
          // Tell child to start the large batch transaction
          child.stdin.write('START\n');
        } else if (text.includes('IN_TRANSACTION')) {
          // Worker is right in the middle of executing 20,000 inserts!
          // Kill immediately with uncatchable SIGKILL
          setTimeout(() => {
            child.kill('SIGKILL');
            resolve();
          }, 5);
        }
      });

      child.on('error', reject);
    });

    // Wait briefly for process cleanup by kernel
    await new Promise(r => setTimeout(r, 200));

    // 2. Open the database in test runner
    const db = new NodeDbDriver(testDbPath);

    // 3. PRAGMA integrity_check MUST return 'ok'
    const integrity = await db.queryFirst<{ integrity_check: string }>('PRAGMA integrity_check;');
    expect(integrity?.integrity_check).toBe('ok');

    // 4. ACID check: since SIGKILL interrupted mid-transaction,
    // the uncommitted transaction MUST have rolled back cleanly (count is 0)
    const countRow = await db.queryFirst<{ count: number }>('SELECT count(*) as count FROM test_crash;');
    expect(countRow?.count).toBe(0);

    await db.close();
  });
});
