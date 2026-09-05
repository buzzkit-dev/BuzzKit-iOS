import { afterAll, beforeAll, expect, it } from 'vitest';
import { type Harness, startHarness } from '../src/harness';

let harness: Harness;
const topic = `e2e-topic-${Date.now()}`;

beforeAll(async () => {
  harness = await startHarness();
  await harness.api.createTopic(topic, 'E2E topic');
});

afterAll(async () => {
  await harness?.api.removeTopic(topic).catch(() => undefined);
  await harness?.stop();
});

it('reads the workspace topics on the device', async () => {
  const { collector, run } = harness;
  const report = await collector.command(run, 'topics');
  expect(report.payload.topics).toContain(topic);
});

it('opts out and back in from the device', async () => {
  const { collector, run } = harness;

  const off = await collector.command(run, 'setTopic', { slug: topic, enabled: false });
  expect(off.payload.optedIn).toBe(false);

  const on = await collector.command(run, 'setTopic', { slug: topic, enabled: true });
  expect(on.payload.optedIn).toBe(true);

  await harness.api.waitForEvent(harness.subscriber, '$preferences.updated');
});

it('opts a single channel out and back in', async () => {
  const { collector, run } = harness;
  const off = await collector.command(run, 'setTopicChannel', { slug: topic, channel: 'push', enabled: false });
  expect(off.payload.optedIn).toBe(false);
  const on = await collector.command(run, 'setTopicChannel', { slug: topic, channel: 'push', enabled: true });
  expect(on.payload.optedIn).toBe(true);
});

it('does not deliver a topic push while opted out, and does once opted in', async () => {
  const { api, collector, run, subscriber } = harness;

  await collector.command(run, 'setTopic', { slug: topic, enabled: false });
  const skipped = await api.send({ topic, title: 'E2E', body: 'Opted out' });
  const afterOptOut = await api.settledDeliveries(skipped.id, { timeoutMs: 45_000 }).catch(() => []);
  expect(afterOptOut.filter((delivery) => delivery.externalId === subscriber)).toEqual([]);

  await collector.command(run, 'setTopic', { slug: topic, enabled: true });
  const delivered = await api.send({ topic, title: 'E2E', body: 'Opted in' });
  await collector.waitFor(run, 'willPresent', {
    timeoutMs: 120_000,
    where: (entry) => entry.payload.messageId === delivered.id,
  });
});
