import { randomBytes, scrypt, timingSafeEqual } from 'node:crypto';
import { promisify } from 'node:util';
import { Database } from './database.js';
import { type Clock, digest, id, requireCondition, secret } from './core.js';

const derive = promisify(scrypt);
export type Session = { account_id: string; username: string; token_hash: string; expires_at: number };
type Account = { id: string; username: string; password_hash: string; salt: string };

export class AuthService {
  private failures = new Map<string, { count: number; until: number }>();
  constructor(private db: Database, private now: Clock) {}

  private username(value: string) {
    const normalized = value.normalize('NFKC').trim().toLowerCase();
    requireCondition(/^[a-z0-9_]{3,32}$/.test(normalized), 'INVALID_USERNAME', '用户名使用 3–32 位字母、数字或下划线');
    return normalized;
  }

  async register(input: { username: string; password: string }) {
    const username = this.username(input.username);
    requireCondition(input.password.length >= 12 && input.password.length <= 128, 'INVALID_PASSWORD', '密码长度必须为 12–128 位');
    const salt = randomBytes(16).toString('hex');
    const hash = (await derive(input.password, salt, 64)) as Buffer;
    return this.db.transaction(() => {
      requireCondition(!this.db.get('SELECT id FROM accounts WHERE username = ?', username), 'USERNAME_TAKEN', '用户名已存在', 409);
      const accountId = id('account');
      this.db.run('INSERT INTO accounts (id, username, password_hash, salt, created_at) VALUES (?, ?, ?, ?, ?)', accountId, username, hash.toString('hex'), salt, this.now());
      return { account_id: accountId, username };
    });
  }

  async login(input: { username: string; password: string }) {
    const username = input.username.normalize('NFKC').trim().toLowerCase();
    // IP 限速在路由层；这里补充用户名限速，不因更换 IP 而无限尝试同一账号。
    for (const [key, state] of this.failures) if (state.until <= this.now()) this.failures.delete(key);
    const failure = this.failures.get(username);
    requireCondition(!failure || failure.count < 5, 'RATE_LIMITED', '尝试次数过多，请稍后再试', 429);
    const account = this.db.get<Account>('SELECT * FROM accounts WHERE username = ?', username);
    const hash = (await derive(input.password, account?.salt ?? '00000000000000000000000000000000', 64)) as Buffer;
    const expected = account ? Buffer.from(account.password_hash, 'hex') : Buffer.alloc(64);
    if (!account || !timingSafeEqual(hash, expected)) {
      if (this.failures.size >= 5000) this.failures.delete(this.failures.keys().next().value!);
      const latest = this.failures.get(username);
      this.failures.set(username, { count: (latest?.count ?? 0) + 1, until: latest?.until ?? this.now() + 900 });
      requireCondition(false, 'INVALID_CREDENTIALS', '用户名或密码错误', 401);
    }
    this.failures.delete(username);
    const token = secret();
    const expiresAt = this.now() + 7 * 86400;
    this.db.run('DELETE FROM sessions WHERE expires_at <= ?', this.now());
    this.db.run('INSERT INTO sessions VALUES (?, ?, ?, ?)', digest(token), account.id, this.now(), expiresAt);
    return { account_id: account.id, username: account.username, token, expires_at: expiresAt };
  }

  authenticate(header: string | undefined): Session {
    requireCondition(typeof header === 'string' && header.startsWith('Bearer '), 'UNAUTHORIZED', '需要有效会话', 401);
    return this.fromHash(digest(header.slice(7)));
  }

  fromHash(tokenHash: string): Session {
    const session = this.db.get<Session>('SELECT sessions.*, accounts.username FROM sessions JOIN accounts ON accounts.id = sessions.account_id WHERE token_hash = ?', tokenHash);
    requireCondition(session && session.expires_at > this.now(), 'UNAUTHORIZED', '会话无效或已过期', 401);
    return session;
  }

  logout(session: Session, all = false) {
    this.db.run(all ? 'DELETE FROM sessions WHERE account_id = ?' : 'DELETE FROM sessions WHERE token_hash = ?', all ? session.account_id : session.token_hash);
    return {};
  }
}
