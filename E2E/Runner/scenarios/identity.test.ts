import { afterAll, beforeAll, expect, it } from 'vitest';
import { type Harness, startHarness } from '../src/harness';

let harness: Harness;

beforeAll(async () => {
  harness = await startHarness();
});

afterAll(async () => {
  await harness?.stop();
});

it('registers the device as an enabled subscription', async () => {
  const { api, subscriber } = harness;
  const page = await api.subscriptions(subscriber);
  expect(page.items.length).toBeGreaterThan(0);
  expect(page.items.some((subscription) => subscription.enabled)).toBe(true);
});

it('records registration, identify and permission events on the timeline', async () => {
  const { api, subscriber } = harness;
  await api.waitForEvent(subscriber, '$subscription.registered');
  await api.waitForEvent(subscriber, '$identify');
  const permission = await api.waitForEvent(subscriber, '$permission.changed');
  expect(permission.data?.status).toBe('provisional');
});

it('tracks a custom event from the device', async () => {
  const { api, collector, run, subscriber } = harness;
  await collector.command(run, 'track', { name: 'workout.completed' });
  const event = await api.waitForEvent(subscriber, 'workout.completed');
  expect(event.name).toBe('workout.completed');
});

it('setAttributes writes attributes onto the subscriber', async () => {
  const { api, collector, run, subscriber } = harness;
  await collector.command(run, 'setAttributes', { attributes: { plan: 'pro', level: 3 } });

  const deadline = Date.now() + 30_000;
  let attributes: Record<string, unknown> = {};
  while (Date.now() < deadline && attributes.plan !== 'pro') {
    attributes = (await api.subscriber(subscriber)).attributes;
    if (attributes.plan !== 'pro') await new Promise((resolve) => setTimeout(resolve, 1_000));
  }
  expect(attributes.plan).toBe('pro');
  expect(attributes.level).toBe(3);
});

it('backgrounding and returning later records the session on the identified subscriber', async () => {
  const { api, collector, run, subscriber } = harness;
  try {
    await harness.background();
    await new Promise((resolve) => setTimeout(resolve, 32_000));
  } finally {
    await harness.foreground();
  }
  await collector.command(run, 'flush');

  await api.waitForEvent(subscriber, '$app.backgrounded');
  const ended = await api.waitForEvent(subscriber, '$session.ended');
  expect(Number(ended.data?.durationSec ?? 0)).toBeGreaterThan(0);
  await api.waitForEvent(subscriber, '$app.opened');
});

it('stops delivering to the device after logout', async () => {
  const { api, collector, run, subscriber } = harness;
  await collector.command(run, 'logout');

  const page = await api.subscriptions(subscriber);
  const active = page.items.filter((subscription) => subscription.enabled);
  expect(active).toEqual([]);
});
