import { DatabaseSync, type SQLInputValue } from 'node:sqlite';
import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import { digest, requireCondition } from './core.js';

// 编号只能追加；已发布迁移的内容不可修改。健康原图和识别内容不进入本数据库。
const migrations = [String.raw`
CREATE TABLE accounts (
  id TEXT PRIMARY KEY, username TEXT NOT NULL UNIQUE, password_hash TEXT NOT NULL,
  salt TEXT NOT NULL, created_at INTEGER NOT NULL, merit INTEGER NOT NULL DEFAULT 0 CHECK(merit >= 0),
  revision INTEGER NOT NULL DEFAULT 0 CHECK(revision >= 0)
);
CREATE TABLE sessions (
  token_hash TEXT PRIMARY KEY, account_id TEXT NOT NULL REFERENCES accounts(id),
  created_at INTEGER NOT NULL, expires_at INTEGER NOT NULL
);
CREATE INDEX sessions_account ON sessions(account_id);
CREATE TABLE cultivators (
  id TEXT PRIMARY KEY, account_id TEXT NOT NULL REFERENCES accounts(id), name TEXT NOT NULL,
  element TEXT NOT NULL, created_at INTEGER NOT NULL, lifecycle TEXT NOT NULL DEFAULT 'cultivating',
  realm TEXT NOT NULL DEFAULT 'qi_refining', spirit_stones INTEGER NOT NULL DEFAULT 0 CHECK(spirit_stones >= 0),
  realm_xp INTEGER NOT NULL DEFAULT 0 CHECK(realm_xp >= 0), materials INTEGER NOT NULL DEFAULT 0 CHECK(materials >= 0),
  pity INTEGER NOT NULL DEFAULT 0 CHECK(pity >= 0)
);
CREATE TABLE idempotency (
  principal TEXT NOT NULL, operation TEXT NOT NULL, request_key TEXT NOT NULL,
  fingerprint TEXT NOT NULL, response TEXT NOT NULL, created_at INTEGER NOT NULL,
  PRIMARY KEY(principal, operation, request_key)
);
CREATE TABLE invitations (
  token_hash TEXT PRIMARY KEY, account_id TEXT NOT NULL REFERENCES accounts(id),
  cultivator_id TEXT NOT NULL REFERENCES cultivators(id), expires_at INTEGER NOT NULL, used INTEGER NOT NULL DEFAULT 0,
  result_binding_id TEXT, confirmation_fingerprint TEXT
);
CREATE TABLE bindings (
  id TEXT PRIMARY KEY, account_id TEXT NOT NULL REFERENCES accounts(id), cultivator_id TEXT NOT NULL REFERENCES cultivators(id),
  channel TEXT NOT NULL, channel_account_id TEXT NOT NULL, sender_id TEXT NOT NULL, elder_ref TEXT NOT NULL,
  status TEXT NOT NULL, connected INTEGER NOT NULL, consent_status TEXT NOT NULL, consent_version INTEGER NOT NULL,
  consent_scope TEXT NOT NULL, consent_proof_id TEXT NOT NULL, created_at INTEGER NOT NULL
);
CREATE UNIQUE INDEX binding_character_active ON bindings(cultivator_id) WHERE status = 'active';
CREATE UNIQUE INDEX binding_sender_active ON bindings(channel, channel_account_id, sender_id) WHERE status = 'active';
CREATE TABLE tasks (
  id TEXT PRIMARY KEY, cultivator_id TEXT NOT NULL REFERENCES cultivators(id), template_id TEXT NOT NULL,
  template_version TEXT NOT NULL, rule_version TEXT NOT NULL, period TEXT NOT NULL,
  window_start INTEGER NOT NULL, window_end INTEGER NOT NULL, template_snapshot TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'assigned', created_at INTEGER NOT NULL,
  UNIQUE(cultivator_id, template_id, period)
);
CREATE TABLE submission_status (
  service_id TEXT NOT NULL, submission_id TEXT NOT NULL, task_id TEXT NOT NULL REFERENCES tasks(id),
  binding_id TEXT NOT NULL REFERENCES bindings(id), consent_version INTEGER NOT NULL,
  sequence INTEGER NOT NULL, status TEXT NOT NULL, updated_at INTEGER NOT NULL,
  PRIMARY KEY(service_id, submission_id)
);
CREATE TABLE verified_results (
  service_id TEXT NOT NULL, event_id TEXT NOT NULL, task_id TEXT NOT NULL REFERENCES tasks(id),
  binding_id TEXT NOT NULL REFERENCES bindings(id), consent_version INTEGER NOT NULL,
  fingerprint TEXT NOT NULL, payload TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'pending',
  error_code TEXT NOT NULL DEFAULT '', created_at INTEGER NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0, next_attempt_at INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY(service_id, event_id)
);
CREATE TABLE settlements (
  id TEXT PRIMARY KEY, task_id TEXT NOT NULL UNIQUE REFERENCES tasks(id), cultivator_id TEXT NOT NULL REFERENCES cultivators(id),
  event_type TEXT NOT NULL, rule_version TEXT NOT NULL, verification_level TEXT NOT NULL,
  spirit_stones INTEGER NOT NULL, realm_xp INTEGER NOT NULL, settled_at INTEGER NOT NULL, day TEXT NOT NULL,
  reason TEXT NOT NULL
);
CREATE INDEX settlement_limits ON settlements(cultivator_id, settled_at, event_type);
CREATE TABLE ledger (
  id TEXT PRIMARY KEY, operation_id TEXT NOT NULL, account_id TEXT NOT NULL REFERENCES accounts(id),
  cultivator_id TEXT REFERENCES cultivators(id), resource TEXT NOT NULL, delta INTEGER NOT NULL,
  balance INTEGER NOT NULL CHECK(balance >= 0), reason TEXT NOT NULL, created_at INTEGER NOT NULL,
  UNIQUE(operation_id, resource)
);
CREATE TABLE equipment (
  id TEXT PRIMARY KEY, cultivator_id TEXT NOT NULL REFERENCES cultivators(id), catalogue_id TEXT NOT NULL,
  slot TEXT NOT NULL, rarity TEXT NOT NULL, equipped INTEGER NOT NULL DEFAULT 0,
  UNIQUE(cultivator_id, catalogue_id)
);
CREATE UNIQUE INDEX equipped_slot ON equipment(cultivator_id, slot) WHERE equipped = 1;
CREATE TABLE outbox (
  id TEXT PRIMARY KEY, binding_id TEXT NOT NULL REFERENCES bindings(id), consent_version INTEGER NOT NULL,
  settlement_id TEXT NOT NULL UNIQUE REFERENCES settlements(id), payload TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending', attempts INTEGER NOT NULL DEFAULT 0,
  available_at INTEGER NOT NULL, lease_until INTEGER, lease_hash TEXT, lease_owner TEXT, acknowledged_hash TEXT
);
CREATE TABLE realtime_tickets (
  token_hash TEXT PRIMARY KEY, session_hash TEXT NOT NULL REFERENCES sessions(token_hash) ON DELETE CASCADE,
  expires_at INTEGER NOT NULL
);
`];

export class Database {
  readonly connection: DatabaseSync;
  private depth = 0;

  constructor(path: string) {
    if (path !== ':memory:') mkdirSync(dirname(path), { recursive: true });
    this.connection = new DatabaseSync(path);
    this.connection.exec('PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 5000; PRAGMA journal_mode = WAL;');
    try { this.migrate(); } catch (error) { this.connection.close(); throw error; }
  }

  run(sql: string, ...parameters: SQLInputValue[]) { return this.connection.prepare(sql).run(...parameters); }
  get<T>(sql: string, ...parameters: SQLInputValue[]): T | undefined { return this.connection.prepare(sql).get(...parameters) as T | undefined; }
  all<T>(sql: string, ...parameters: SQLInputValue[]): T[] { return this.connection.prepare(sql).all(...parameters) as T[]; }

  // SQLite 的同步事务不跨 await；嵌套服务使用 SAVEPOINT，确保失败不会留下部分扣款。
  transaction<T>(work: () => T): T {
    const level = this.depth++;
    const savepoint = `service_${level}`;
    try {
      this.connection.exec(level === 0 ? 'BEGIN IMMEDIATE' : `SAVEPOINT ${savepoint}`);
      const result = work();
      requireCondition(!(result instanceof Promise), 'ASYNC_TRANSACTION', '事务内禁止异步操作', 500);
      this.connection.exec(level === 0 ? 'COMMIT' : `RELEASE ${savepoint}`);
      return result;
    } catch (error) {
      if (this.connection.isTransaction) this.connection.exec(level === 0 ? 'ROLLBACK' : `ROLLBACK TO ${savepoint}; RELEASE ${savepoint}`);
      throw error;
    } finally { this.depth--; }
  }

  touch(accountId: string) { this.run('UPDATE accounts SET revision = revision + 1 WHERE id = ?', accountId); }
  close() { this.connection.close(); }

  private migrate() {
    const version = this.get<{ user_version: number }>('PRAGMA user_version')!.user_version;
    requireCondition(version <= migrations.length, 'DATABASE_VERSION', '数据库版本高于当前程序，停止启动', 500);
    this.transaction(() => {
      this.connection.exec('CREATE TABLE IF NOT EXISTS schema_migrations (version INTEGER PRIMARY KEY, checksum TEXT NOT NULL)');
      for (let index = 0; index < migrations.length; index++) {
        const sql = migrations[index]!;
        const recorded = this.get<{ checksum: string }>('SELECT checksum FROM schema_migrations WHERE version = ?', index + 1);
        if (index < version) {
          requireCondition(recorded?.checksum === digest(sql), 'MIGRATION_CHANGED', '已应用迁移被修改或记录缺失', 500);
        } else {
          this.connection.exec(sql);
          this.run('INSERT INTO schema_migrations VALUES (?, ?)', index + 1, digest(sql));
          this.connection.exec(`PRAGMA user_version = ${index + 1}`);
        }
      }
    });
  }
}
