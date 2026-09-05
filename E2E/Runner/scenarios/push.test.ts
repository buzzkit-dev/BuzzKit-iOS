import { afterAll, beforeAll, expect, it } from 'vitest';
import { type Harness, startHarness } from '../src/harness';

let harness: Harness;

beforeAll(async () => {
  harness = await startHarness();
});

afterAll(async () => {
  await harness?.stop();
});

it('delivers a real APNs push and reports it on the device', async () => {
  const { api, collector, run, subscriber } = harness;
  const message = await api.send({ to: subscriber, title: 'E2E', body: 'Plain push' });

  const report = await collector.waitFor(run, 'willPresent', {
    timeoutMs: 120_000,
    where: (entry) => entry.payload.messageId === message.id,
  });
  expect(report.payload.messageId).toBe(message.id);
});

it('settles the delivery without an error', async () => {
  const { api, collector, run, subscriber } = harness;
  const message = await api.send({ to: subscriber, title: 'E2E', body: 'Settled' });
  await collector.waitFor(run, 'willPresent', {
    timeoutMs: 120_000,
    where: (entry) => entry.payload.messageId === message.id,
  });

  const deliveries = await api.settledDeliveries(message.id);
  expect(deliveries.map((delivery) => delivery.lastErrorMessage)).toEqual([null]);
  expect(deliveries.every((delivery) => ['sent', 'delivered'].includes(delivery.status))).toBe(true);
});

it('reports a delivered receipt for a plain push and promotes the delivery', async () => {
  const { api, collector, run, subscriber } = harness;
  const message = await api.send({ to: subscriber, title: 'E2E', body: 'Receipt' });
  await collector.waitFor(run, 'willPresent', {
    timeoutMs: 120_000,
    where: (entry) => entry.payload.messageId === message.id,
  });

  await api.waitForEvent(subscriber, '$notification.delivered', {
    where: (event) => event.data?.messageId === message.id,
  });

  const deliveries = await api.settledDeliveries(message.id);
  expect(deliveries[0]?.status).toBe('delivered');
});

it('carries a deep link and action buttons through to the device', async () => {
  const { api, collector, run, subscriber } = harness;
  const message = await api.send({
    to: subscriber,
    title: 'E2E',
    body: 'Rich push',
    deepLink: 'buzzkit://workouts/42',
    actions: [
      { id: 'view', title: 'View' },
      { id: 'snooze', title: 'Snooze', destructive: true },
    ],
  });

  const report = await collector.waitFor(run, 'willPresent', {
    timeoutMs: 120_000,
    where: (entry) => entry.payload.messageId === message.id,
  });
  expect(report.payload.deepLink).toBe('buzzkit://workouts/42');
  expect(report.payload.actions).toEqual(['view', 'snooze']);
  expect(report.payload.categoryId).not.toBeNull();
});

it('a rich push gets its image attached by the service extension and keeps subtitle and badge', async () => {
  const { api, collector, run, subscriber } = harness;
  const title = `Rich ${run}`;
  const message = await api.send({
    to: subscriber,
    title,
    subtitle: 'From the extension',
    body: 'With an image',
    badge: 3,
    imageUrl: 'https://buzzkit.dev/logo.png',
  });
  await collector.waitFor(run, 'willPresent', {
    timeoutMs: 120_000,
    where: (entry) => entry.payload.messageId === message.id,
  });

  const deadline = Date.now() + 30_000;
  let match: Record<string, unknown> | undefined;
  while (Date.now() < deadline && !match) {
    const report = await collector.command(run, 'deliveredNotifications');
    const delivered = report.payload.delivered as Record<string, unknown>[];
    match = delivered.find((entry) => entry.messageId === message.id && Number(entry.attachments) > 0);
    if (!match) await new Promise((resolve) => setTimeout(resolve, 1_000));
  }
  expect(match, 'the extension never attached the image').toBeDefined();
  expect(match?.title).toBe(title);
  expect(match?.subtitle).toBe('From the extension');
  expect(match?.badge).toBe(3);
});
