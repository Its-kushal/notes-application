const Database = require('better-sqlite3-multiple-ciphers');
const dbPath = process.argv[2];

if (!dbPath) {
  process.exit(1);
}

const db = new Database(dbPath);
db.pragma('journal_mode = WAL;');
db.pragma('foreign_keys = ON;');

// Create tables if not exist
db.exec(`
  CREATE TABLE IF NOT EXISTS test_crash (
    id INTEGER PRIMARY KEY,
    val TEXT
  );
`);

// Signal parent that worker is ready
process.stdout.write('READY\n');

// Listen for START command from parent
process.stdin.once('data', () => {
  try {
    const insert = db.prepare('INSERT INTO test_crash(id, val) VALUES (?, ?);');
    const transaction = db.transaction(() => {
      process.stdout.write('IN_TRANSACTION\n');
      for (let i = 1; i <= 20000; i++) {
        insert.run(i, 'value_' + 'x'.repeat(200));
      }
    });
    transaction();
    process.stdout.write('COMMITTED\n');
  } catch (err) {
    process.exit(2);
  }
});
