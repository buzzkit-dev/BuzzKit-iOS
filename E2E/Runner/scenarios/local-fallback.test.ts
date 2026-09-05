import { afterAll, beforeAll, expect, it } from 'vitest';
import { type Harness, startHarness } from '../src/harness';

let harness: Harness;
const slug = `e2e-fallback-${Date.now()}`;

type RunView = { status: string; events: { name: string; data?: Record<string, unknown> }[] };

async function triggerUntilRunStarts(timeoutMs = 150_000): Promise<string> {
  const { api, collector, run, subscriber } = harness;
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    await collector.command(run, 'track', { name: 'e2e.fallback' });
    await new Promise((resolve) => setTimeout(resolve, 10_000));
    const started = (await api.runs(subscriber)).items.find((entry) => entry.status !== 'canceled');
    if (started) return started.id;
  }
  throw new Error('The published workflow never started a run; definitions take up to a minute to reach the actor');
}

async function waitForRun(id: string, predicate: (run: RunView) => boolean, timeoutMs: number): Promise<RunView> {
  const { api } = harness;
  const deadline = Date.now() + timeoutMs;
  let latest = await api.run(id);
  while (Date.now() < deadline) {
    if (predicate(latest)) return latest;
    await new Promise((resolve) => setTimeout(resolve, 2_000));
    latest = await api.run(id);
  }
  throw new Error(`Run ${id} never matched. Status ${latest.status}, events ${latest.events.map((e) => e.name).join(', ')}`);
}

beforeAll(async () => {
  harness = await startHarness();
  await harness.api.publishWorkflow(slug, {
    trigger: { event: 'e2e.fallback' },
    concurrency: 'one-per-subscriber',
    steps: [
      { name: 'window', waitUntil: { delay: '1m' } },
      { name: 'remind', send: { title: 'Fallback push', body: 'No device confirmed the plan.', deliver: 'local' } },
    ],
  });
});

afterAll(async () => {
  await harness?.api.removeWorkflow(slug).catch(() => undefined);
  await harness?.stop();
});

it('sends the reminder as a real push when no device acknowledged the local plan by the window', async () => {
  const { api, collector, run, subscriber } = harness;
  const runId = await triggerUntilRunStarts();

  const finished = await waitForRun(runId, (entry) => entry.status === 'completed', 240_000);
  const remindSteps = finished.events.filter(
    (event) => event.name === '$run.step' && event.data?.step === 'remind' && event.data?.status === 'completed'
  );
  const summaries = remindSteps.map((event) => String(event.data?.summary));
  expect(summaries[0]).toBe('Scheduled “Fallback push” on the device');

  const acknowledged = (await api.timeline(subscriber)).items.some(
    (event) => event.name === '$local.scheduled' && event.data?.localId === `${runId}:remind`
  );
  if (acknowledged) {
    expect(summaries).toEqual(['Scheduled “Fallback push” on the device']);
    console.log('[fallback] the simulator received the silent plan and acknowledged it, so the local path ran');
    return;
  }

  expect(summaries).toEqual([
    'Scheduled “Fallback push” on the device',
    'No device confirmed the local schedule; sent as a push instead',
  ]);
  const fallbackMessageId = String(remindSteps[1]?.data?.messageId ?? '');
  expect(fallbackMessageId).toMatch(/^msg_/);
  const message = await api.message(fallbackMessageId);
  expect(message.payload.deliver).toBeUndefined();
  expect(message.payload.title).toBe('Fallback push');

  const report = await collector.waitFor(run, 'willPresent', {
    timeoutMs: 120_000,
    where: (entry) => entry.payload.messageId === fallbackMessageId,
  });
  expect(report.payload.messageId).toBe(fallbackMessageId);
  const deliveries = await api.settledDeliveries(fallbackMessageId);
  expect(deliveries.every((delivery) => ['sent', 'delivered'].includes(delivery.status))).toBe(true);
});
