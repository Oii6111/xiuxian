import type { Result } from '../core.js';
import type { ConfirmBinding } from './bindings.js';
import type { SubmissionUpdate, VerifiedResult } from './health.js';

// D 在可信服务端使用；令牌不传给微信用户、网页或模型。所有方法返回统一 Result。
export class HealthClient {
  constructor(private baseUrl: string, private serviceToken: string) {}

  async request<T = unknown>(path: string, body?: unknown): Promise<Result<T>> {
    if (!path.startsWith('/internal/v1/') || path.includes('..')) throw new Error('仅允许健康内部接缝');
    const response = await fetch(`${this.baseUrl.replace(/\/$/, '')}${path}`, {
      method: body === undefined ? 'GET' : 'POST',
      headers: { authorization: `Bearer ${this.serviceToken}`, ...(body !== undefined ? { 'content-type': 'application/json' } : {}) },
      ...(body !== undefined ? { body: JSON.stringify(body) } : {}), signal: AbortSignal.timeout(10000),
    });
    const result = await response.json() as Result<T>;
    if (typeof result.ok !== 'boolean' || typeof result.code !== 'string' || typeof result.message !== 'string' || !('data' in result) || (!response.ok && result.ok)) throw new Error('健康接缝返回了无效 Result');
    return result;
  }

  confirmBinding(input: ConfirmBinding) { return this.request('/internal/v1/bindings/confirm', input); }
  tasks(bindingId: string) { return this.request(`/internal/v1/bindings/${encodeURIComponent(bindingId)}/tasks`); }
  submission(input: SubmissionUpdate) { return this.request('/internal/v1/submissions/status', input); }
  verify(input: VerifiedResult) { return this.request('/internal/v1/task-results', input); }
  settle(eventId: string) { return this.request(`/internal/v1/task-results/${encodeURIComponent(eventId)}/settle`, {}); }
  result(eventId: string) { return this.request(`/internal/v1/task-results/${encodeURIComponent(eventId)}`); }
  claimNotifications(limit = 10) { return this.request('/internal/v1/notifications/claim', { limit }); }
  acknowledge(notificationId: string, leaseToken: string) { return this.request(`/internal/v1/notifications/${encodeURIComponent(notificationId)}/ack`, { lease_token: leaseToken }); }
  retryNotification(notificationId: string, leaseToken: string) { return this.request(`/internal/v1/notifications/${encodeURIComponent(notificationId)}/nack`, { lease_token: leaseToken }); }
}
