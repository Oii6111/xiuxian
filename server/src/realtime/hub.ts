import type { FastifyInstance, FastifyRequest } from 'fastify';
import type { WebSocket } from 'ws';
import { type Clock, digest, requireCondition, secret } from '../core.js';
import { Database } from '../database.js';
import { AuthService, type Session } from '../auth.js';
import { GameService } from '../game/service.js';
import { objectSchema, stringField } from '../contracts.js';

export class RealtimeHub {
  private clients = new Map<WebSocket, { session: Session; revision: number; alive: boolean }>();
  private authorized = new WeakMap<FastifyRequest, Session>();
  private timer?: NodeJS.Timeout;
  constructor(private db: Database, private now: Clock, private auth: AuthService, private game: GameService) {}

  ticket(session: Session) {
    const ticket = secret();
    const expiresAt = this.now() + 60;
    this.db.transaction(() => {
      this.db.run('DELETE FROM realtime_tickets WHERE expires_at <= ?', this.now());
      this.db.run('INSERT INTO realtime_tickets VALUES (?, ?, ?)', digest(ticket), session.token_hash, expiresAt);
    });
    return { ticket, expires_at: expiresAt };
  }

  register(app: FastifyInstance, allowedOrigins: string[]) {
    app.get('/api/v2/realtime', {
      websocket: true,
      schema: { tags: ['realtime'], summary: '一次性票据建立 WebSocket；消息协议见团队接入指南', querystring: objectSchema({ ticket: stringField }) },
      preValidation: async request => {
        requireCondition(request.headers.upgrade?.toLowerCase() === 'websocket', 'UPGRADE_REQUIRED', '需要 WebSocket 升级', 426);
        requireCondition(!request.headers.origin || allowedOrigins.includes(request.headers.origin), 'ORIGIN_REJECTED', '来源未允许', 403);
        const ticket = (request.query as { ticket: string }).ticket;
        const session = this.db.transaction(() => {
          const stored = this.db.get<{ session_hash: string; expires_at: number }>('SELECT * FROM realtime_tickets WHERE token_hash = ?', digest(ticket));
          requireCondition(stored && stored.expires_at > this.now(), 'UNAUTHORIZED', '连接票据无效或过期', 401);
          const authenticated = this.auth.fromHash(stored.session_hash);
          this.db.run('DELETE FROM realtime_tickets WHERE token_hash = ?', digest(ticket));
          return authenticated;
        });
        this.authorized.set(request, session);
      },
    }, (socket, request) => {
      const session = this.authorized.get(request)!;
      this.clients.set(socket, { session, revision: -1, alive: true });
      this.sendSnapshot(socket);
      socket.on('pong', () => { const client = this.clients.get(socket); if (client) client.alive = true; });
      socket.on('close', () => this.clients.delete(socket));
      socket.on('error', () => this.clients.delete(socket));
      socket.on('message', raw => {
        try {
          this.auth.fromHash(session.token_hash);
          const message = JSON.parse(raw.toString()) as Record<string, unknown>;
          requireCondition(message && Object.keys(message).length === 1, 'INVALID_MESSAGE', '消息字段无效');
          if (message.type === 'resync') this.sendSnapshot(socket);
          else if (message.type === 'ping') socket.send(JSON.stringify({ type: 'pong', version: 1 }));
          else socket.close(1008, 'Unknown message');
        } catch { socket.close(1008, 'Invalid message or session'); }
      });
    });
    this.timer = setInterval(() => {
      this.flush();
      for (const [socket, client] of this.clients) {
        if (!client.alive) { socket.terminate(); this.clients.delete(socket); continue; }
        client.alive = false;
        socket.ping();
      }
    }, 15000);
    this.timer.unref();
  }

  flush() {
    for (const [socket, client] of this.clients) {
      if (socket.readyState !== 1) continue;
      if (socket.bufferedAmount > 1048576) { socket.terminate(); this.clients.delete(socket); continue; }
      try { this.auth.fromHash(client.session.token_hash); }
      catch { socket.close(4001, 'Session revoked'); this.clients.delete(socket); continue; }
      const revision = this.db.get<{ revision: number }>('SELECT revision FROM accounts WHERE id = ?', client.session.account_id)!.revision;
      if (revision !== client.revision) {
        socket.send(JSON.stringify({ type: 'state_changed', version: 1, revision }));
        client.revision = revision;
      }
    }
  }

  private sendSnapshot(socket: WebSocket) {
    const client = this.clients.get(socket)!;
    const snapshot = this.game.snapshot(client.session.account_id);
    socket.send(JSON.stringify({ type: 'snapshot', version: 1, revision: snapshot.revision, data: snapshot }));
    client.revision = snapshot.revision;
  }

  close() {
    if (this.timer) clearInterval(this.timer);
    for (const socket of this.clients.keys()) socket.terminate();
    this.clients.clear();
  }
}
