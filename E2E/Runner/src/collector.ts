import { createServer, type Server } from 'node:http';

export type Report = { run: string; kind: string; at: string; payload: Record<string, unknown> };

type Command = { id: string; name: string; arguments: Record<string, unknown> };

export class Collector {
  private server?: Server;
  private readonly reports: Report[] = [];
  private readonly queued = new Map<string, Command[]>();
  private issued = 0;

  constructor(private readonly port: number) {}

  async start(): Promise<void> {
    this.server = createServer((request, response) => {
      if (request.method === 'GET' && request.url?.startsWith('/commands')) {
        const run = new URL(request.url, 'http://localhost').searchParams.get('run') ?? '';
        const pending = this.queued.get(run) ?? [];
        this.queued.set(run, []);
        response.writeHead(200, { 'Content-Type': 'application/json' });
        response.end(JSON.stringify(pending));
        return;
      }
      if (request.method !== 'POST') {
        response.writeHead(405).end();
        return;
      }
      const chunks: Buffer[] = [];
      request.on('data', (chunk: Buffer) => chunks.push(chunk));
      request.on('end', () => {
        try {
          this.reports.push(JSON.parse(Buffer.concat(chunks).toString()) as Report);
        } catch {
          // A malformed report is a harness bug, not a product failure; the waiting
          // assertion will time out and say what it expected.
        }
        response.writeHead(204).end();
      });
    });

    await new Promise<void>((resolve, reject) => {
      this.server?.once('error', reject);
      this.server?.listen(this.port, '127.0.0.1', resolve);
    });
  }

  async stop(): Promise<void> {
    const server = this.server;
    if (!server) return;
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }

  get url(): string {
    return `http://127.0.0.1:${this.port}`;
  }

  async command(
    run: string,
    name: string,
    args: Record<string, unknown> = {},
    options: { timeoutMs?: number } = {}
  ): Promise<Report> {
    this.issued += 1;
    const id = `cmd-${this.issued}`;
    this.queued.set(run, [...(this.queued.get(run) ?? []), { id, name, arguments: args }]);

    const done = this.waitFor(run, 'command.done', {
      timeoutMs: options.timeoutMs ?? 30_000,
      where: (report) => report.payload.id === id,
    });
    const failed = this.waitFor(run, 'command.failed', {
      timeoutMs: options.timeoutMs ?? 30_000,
      where: (report) => report.payload.id === id,
    }).then(
      (report) => {
        throw new Error(`Command "${name}" failed on device: ${String(report.payload.error)}`);
      },
      () => new Promise<never>(() => undefined)
    );

    return await Promise.race([done, failed]);
  }

  count(): number {
    return this.reports.length;
  }

  seen(run: string): Report[] {
    return this.reports.filter((report) => report.run === run);
  }

  async waitFor(
    run: string,
    kind: string,
    options: { timeoutMs?: number; where?: (report: Report) => boolean; after?: number } = {}
  ): Promise<Report> {
    const timeoutMs = options.timeoutMs ?? 60_000;
    const deadline = Date.now() + timeoutMs;

    while (Date.now() < deadline) {
      const match = this.reports.slice(options.after ?? 0).find(
        (report) =>
          report.run === run && report.kind === kind && (options.where?.(report) ?? true)
      );
      if (match) return match;
      await new Promise((resolve) => setTimeout(resolve, 250));
    }

    const kinds = this.seen(run).map((report) => report.kind);
    throw new Error(
      `Timed out after ${timeoutMs}ms waiting for "${kind}". The device reported: ${kinds.join(', ') || '(nothing)'}`
    );
  }
}
