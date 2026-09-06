import { createHmac } from 'node:crypto';
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
    await new Promise((resolve) => setTimeout(resolve, 45_000));
  } finally {
    await harness.foreground();
  }
  await collector.command(run, 'flush');

  await api.waitForEvent(subscriber, '$app.backgrounded');
  const ended = await api.waitForEvent(subscriber, '$session.ended');
  expect(Number(ended.data?.durationSec ?? 0)).toBeGreaterThan(0);
  await api.waitForEvent(subscriber, '$app.opened');
});

function identityHash(externalId: string): string {
  return createHmac('sha256', harness.config.identitySecret ?? '').update(externalId).digest('hex');
}

it.skipIf(!process.env.BUZZKIT_IDENTITY_SECRET)('a correct identity hash marks the subscriber verified', async () => {
  const { api, collector, run, subscriber } = harness;
  expect((await api.subscriber(subscriber)).verified).toBe(false);

  await collector.command(run, 'identify', { externalId: subscriber, identityHash: identityHash(subscriber) });

  const deadline = Date.now() + 30_000;
  let verified = false;
  while (Date.now() < deadline && !verified) {
    verified = (await api.subscriber(subscriber)).verified;
    if (!verified) await new Promise((resolve) => setTimeout(resolve, 1_000));
  }
  expect(verified).toBe(true);
});

it.skipIf(!process.env.BUZZKIT_IDENTITY_SECRET)('a wrong identity hash is refused and creates nothing', async () => {
  const { api, collector, run, subscriber } = harness;
  const impostor = `${subscriber}-impostor`;

  await collector.command(run, 'identify', { externalId: impostor, identityHash: identityHash('someone-else') });
  await new Promise((resolve) => setTimeout(resolve, 5_000));
  await expect(api.subscriber(impostor)).rejects.toThrow(/404/);

  await collector.command(run, 'identify', { externalId: subscriber, identityHash: identityHash(subscriber) });
});

it('stops delivering to the device after logout', async () => {
  const { api, collector, run, subscriber } = harness;
  await collector.command(run, 'logout');

  const page = await api.subscriptions(subscriber);
  const active = page.items.filter((subscription) => subscription.enabled);
  expect(active).toEqual([]);
});

it('mints a fresh anonymous identity after logout', async () => {
  const { collector, run } = harness;
  const report = await collector.command(run, 'identity');

  expect(report.payload.anonymous).toBe(true);
  expect(String(report.payload.externalId)).toMatch(/^anon_/);
});

it('carries the anonymous device and its events onto the identity it signs up as', async () => {
  const { api, collector, run, subscriber } = harness;
  const identity = await collector.command(run, 'identity');
  const anonymousId = String(identity.payload.externalId);
  const signedUp = `${subscriber}-signup`;

  await collector.command(run, 'track', { name: 'onboarding.completed' });
  await api.waitForEvent(anonymousId, 'onboarding.completed');
  const anonymous = await api.subscriptions(anonymousId);
  expect(anonymous.items.length).toBeGreaterThan(0);

  await collector.command(run, 'identify', { externalId: signedUp });

  try {
    const merged = await api.waitForEvent(signedUp, '$subscriber.merged');
    expect(merged.data?.from).toBe(anonymousId);

    const carried = await api.subscriptions(signedUp);
    expect(carried.items.map((subscription) => subscription.id)).toEqual(
      anonymous.items.map((subscription) => subscription.id)
    );

    const timeline = await api.timeline(signedUp);
    expect(timeline.items.map((event) => event.name)).toContain('onboarding.completed');

    const aliases = await api.aliases(signedUp);
    expect(aliases.items.map((alias) => alias.externalId)).toContain(anonymousId);
    expect(aliases.items.find((alias) => alias.externalId === anonymousId)?.source).toBe('system');

    const byAlias = await api.subscriber(anonymousId);
    expect(byAlias.externalId).toBe(signedUp);
  } finally {
    await api.removeSubscriber(signedUp).catch(() => undefined);
  }
});

it('folds a second anonymous install into the identity that already exists', async () => {
  const { api, collector, run, subscriber } = harness;
  const signedUp = `${subscriber}-second`;

  await api.upsertSubscriber(signedUp, { attributes: { seat: 'first' } });
  await collector.command(run, 'logout');
  const identity = await collector.command(run, 'identity');
  const anonymousId = String(identity.payload.externalId);

  await collector.command(run, 'track', { name: 'second.device.opened' });
  await api.waitForEvent(anonymousId, 'second.device.opened');

  await collector.command(run, 'identify', { externalId: signedUp });

  try {
    const merged = await api.waitForEvent(signedUp, '$subscriber.merged');
    expect(merged.data?.from).toBe(anonymousId);

    const carried = await api.subscriptions(signedUp);
    expect(carried.items.length).toBeGreaterThan(0);
    expect((await api.subscriber(anonymousId)).externalId).toBe(signedUp);
  } finally {
    await api.removeSubscriber(signedUp).catch(() => undefined);
  }
});

it('settles the merge so identifying again on every launch never repeats it', async () => {
  const { api, collector, run, subscriber } = harness;
  const signedUp = `${subscriber}-settled`;
  await collector.command(run, 'logout');
  const identity = await collector.command(run, 'identity');
  const anonymousId = String(identity.payload.externalId);

  await collector.command(run, 'track', { name: 'settled.opened' });
  await api.waitForEvent(anonymousId, 'settled.opened');

  await collector.command(run, 'identify', { externalId: signedUp });

  try {
    const merged = await api.waitForEvent(signedUp, '$subscriber.merged');
    expect(merged.data?.from).toBe(anonymousId);

    const settled = await collector.command(run, 'pendingMerge');
    expect(settled.payload.pending).toBe(false);

    await collector.command(run, 'identify', { externalId: signedUp });
    await collector.command(run, 'track', { name: 'settled.again' });
    await api.waitForEvent(signedUp, 'settled.again');

    const timeline = await api.timeline(signedUp);
    const merges = timeline.items.filter((event) => event.name === '$subscriber.merged');
    expect(merges.length).toBe(1);
  } finally {
    await api.removeSubscriber(signedUp).catch(() => undefined);
  }
});

it('has nothing pending to merge on a device that never went anonymous to identified', async () => {
  const { collector, run } = harness;
  await collector.command(run, 'logout');

  const anonymous = await collector.command(run, 'pendingMerge');
  expect(anonymous.payload.pending).toBe(false);
});

it('keeps the merge pending through a failed identify and completes it on the next launch', async () => {
  const { api, collector, relaunch, run, subscriber } = harness;
  const signedUp = `${subscriber}-retried`;
  await collector.command(run, 'logout');
  const identity = await collector.command(run, 'identity');
  const anonymousId = String(identity.payload.externalId);

  await collector.command(run, 'track', { name: 'retried.opened' });
  await api.waitForEvent(anonymousId, 'retried.opened');

  await relaunch({ E2E_API_URL: 'http://127.0.0.1:1' });
  await collector.command(run, 'identify', { externalId: signedUp });

  try {
    const pending = await collector.command(run, 'pendingMerge');
    expect(pending.payload.pending).toBe(true);
    await expect(api.subscriber(signedUp)).rejects.toThrow();

    await relaunch();

    const merged = await api.waitForEvent(signedUp, '$subscriber.merged');
    expect(merged.data?.from).toBe(anonymousId);

    const settled = await collector.command(run, 'pendingMerge');
    expect(settled.payload.pending).toBe(false);

    const timeline = await api.timeline(signedUp);
    expect(timeline.items.map((event) => event.name)).toContain('retried.opened');
    expect((await api.subscriber(anonymousId)).externalId).toBe(signedUp);
  } finally {
    await api.removeSubscriber(signedUp).catch(() => undefined);
  }
});

it('links a legacy id onto the device subscriber through the alias endpoint', async () => {
  const { api, collector, run, subscriber } = harness;
  const legacy = `${subscriber}-legacy`;
  await collector.command(run, 'identify', { externalId: subscriber });
  await api.waitForEvent(subscriber, '$identify');

  const linked = await api.addAlias(subscriber, legacy);
  expect(linked.items.map((alias) => alias.externalId)).toContain(legacy);
  expect(linked.items.find((alias) => alias.externalId === legacy)?.source).toBe('manual');
  expect((await api.subscriber(legacy)).externalId).toBe(subscriber);
});
