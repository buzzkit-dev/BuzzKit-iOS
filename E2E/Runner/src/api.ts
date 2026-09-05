import type { Config } from './config';

type Envelope<T> = { success: boolean; data: T; error: unknown };

export class Api {
  constructor(private readonly config: Config) {}

  async call<T>(method: string, path: string, body?: unknown): Promise<T> {
    const response = await fetch(`${this.config.apiUrl}${path}`, {
      method,
      headers: {
        Authorization: `Bearer ${this.config.workspaceKey}`,
        'BuzzKit-Tenant': this.config.tenant,
        'Content-Type': 'application/json',
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await response.text();
    if (!response.ok) throw new Error(`${method} ${path} -> ${response.status} ${text}`);

    const envelope = JSON.parse(text) as Envelope<T>;
    if (!envelope.success) throw new Error(`${method} ${path} -> ${JSON.stringify(envelope.error)}`);
    return envelope.data;
  }

  send(message: Record<string, unknown>) {
    return this.call<{ id: string }>('POST', '/v1/messages', message);
  }

  deliveries(messageId: string) {
    return this.call<{ items: { status: string; lastErrorMessage: string | null; externalId: string }[] }>(
      'GET',
      `/v1/messages/${messageId}/deliveries`
    );
  }

  async settledDeliveries(
    messageId: string,
    options: { timeoutMs?: number } = {}
  ): Promise<{ status: string; lastErrorMessage: string | null; externalId: string }[]> {
    const deadline = Date.now() + (options.timeoutMs ?? 60_000);
    const pending = new Set(['pending', 'retrying']);
    let latest: { status: string; lastErrorMessage: string | null; externalId: string }[] = [];

    while (Date.now() < deadline) {
      latest = (await this.deliveries(messageId)).items;
      if (latest.length > 0 && latest.every((delivery) => !pending.has(delivery.status))) {
        return latest;
      }
      await new Promise((resolve) => setTimeout(resolve, 500));
    }

    throw new Error(
      `Deliveries for ${messageId} never settled: ${JSON.stringify(latest) || '(none)'}`
    );
  }

  timeline(externalId: string) {
    return this.call<{ items: { name: string; timestamp: string; data?: Record<string, unknown> }[] }>(
      'GET',
      `/v1/subscribers/${encodeURIComponent(externalId)}/timeline?limit=50`
    );
  }

  subscriber(externalId: string) {
    return this.call<{ externalId: string; attributes: Record<string, unknown> }>(
      'GET',
      `/v1/subscribers/${encodeURIComponent(externalId)}`
    );
  }

  subscriptions(externalId: string) {
    return this.call<{ items: { id: string; enabled: boolean; status: string }[] }>(
      'GET',
      `/v1/subscribers/${encodeURIComponent(externalId)}/subscriptions`
    );
  }

  sendLiveActivity(body: Record<string, unknown>) {
    return this.call<{ results: { id: string; ok: boolean; code?: string }[] }>(
      'POST',
      '/v1/live-activities/send',
      body
    );
  }

  async publishWorkflow(slug: string, spec: Record<string, unknown>) {
    await this.call<{ id: string }>('POST', '/v1/workflows', { slug, name: slug, spec });
    await this.call<unknown>('POST', `/v1/workflows/${slug}/publish`);
  }

  runs(externalId: string) {
    return this.call<{ items: { id: string; status: string; step: string | null }[] }>(
      'GET',
      `/v1/subscribers/${encodeURIComponent(externalId)}/runs`
    );
  }

  run(id: string) {
    return this.call<{
      status: string;
      events: { name: string; data?: Record<string, unknown> }[];
    }>('GET', `/v1/runs/${encodeURIComponent(id)}`);
  }

  message(id: string) {
    return this.call<{ id: string; payload: Record<string, unknown> }>('GET', `/v1/messages/${id}`);
  }

  removeWorkflow(slug: string) {
    return this.call<unknown>('DELETE', `/v1/workflows/${slug}`);
  }

  createTopic(slug: string, name: string) {
    return this.call<{ slug: string }>('POST', '/v1/topics', { slug, name });
  }

  removeTopic(slug: string) {
    return this.call<unknown>('DELETE', `/v1/topics/${slug}`);
  }

  async waitForEvent(
    externalId: string,
    name: string,
    options: { timeoutMs?: number; where?: (event: { data?: Record<string, unknown> }) => boolean } = {}
  ) {
    const deadline = Date.now() + (options.timeoutMs ?? 45_000);
    let seen: string[] = [];

    while (Date.now() < deadline) {
      const page = await this.timeline(externalId);
      seen = page.items.map((event) => event.name);
      const match = page.items.find(
        (event) => event.name === name && (options.where?.(event) ?? true)
      );
      if (match) return match;
      await new Promise((resolve) => setTimeout(resolve, 750));
    }

    throw new Error(`Timeline never showed "${name}". Saw: ${seen.join(', ') || '(nothing)'}`);
  }

  removeSubscriber(externalId: string) {
    return this.call<unknown>('DELETE', `/v1/subscribers/${encodeURIComponent(externalId)}`);
  }
}
