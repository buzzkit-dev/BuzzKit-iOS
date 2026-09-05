import { afterAll, beforeAll, expect, it } from 'vitest';
import { type Harness, startHarness } from '../src/harness';

let harness: Harness;
let activityId = '';

type Listed = { id: string; name: string; state: string; status: string; step: number };

async function activities(): Promise<Listed[]> {
  const { collector, run } = harness;
  const report = await collector.command(run, 'activities');
  return report.payload.activities as Listed[];
}

async function waitForActivity(
  predicate: (activity: Listed) => boolean,
  timeoutMs = 60_000
): Promise<Listed> {
  const deadline = Date.now() + timeoutMs;
  let latest: Listed[] = [];
  while (Date.now() < deadline) {
    latest = await activities();
    const match = latest.find(predicate);
    if (match) return match;
    await new Promise((resolve) => setTimeout(resolve, 1_000));
  }
  throw new Error(`No activity matched. Device has: ${JSON.stringify(latest)}`);
}

async function waitForActivityGone(id: string, timeoutMs = 60_000): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  let latest: Listed[] = [];
  while (Date.now() < deadline) {
    latest = await activities();
    if (!latest.some((activity) => activity.id === id)) return;
    await new Promise((resolve) => setTimeout(resolve, 1_000));
  }
  throw new Error(`Activity ${id} is still on the device: ${JSON.stringify(latest)}`);
}

async function startActivity(name: string): Promise<string> {
  const { api, collector, run, subscriber } = harness;
  const started = await collector.command(run, 'startActivity', { activityName: name });
  const id = String(started.payload.activityId);
  await api.waitForEvent(subscriber, '$activity.started', { where: (entry) => entry.data?.activityId === id });
  return id;
}

beforeAll(async () => {
  harness = await startHarness();
  await harness.collector.command(harness.run, 'observeActivities');
});

afterAll(async () => {
  await harness?.stop();
});

it('starts a Live Activity on the device and registers its push token', async () => {
  const { api, collector, run, subscriber } = harness;
  const started = await collector.command(run, 'startActivity', { activityName: 'workout' });
  activityId = String(started.payload.activityId);
  expect(activityId).not.toBe('');

  const event = await api.waitForEvent(subscriber, '$activity.started', {
    where: (entry) => entry.data?.activityId === activityId,
  });
  expect(event.data?.attributesType).toBe('E2EAttributes');
});

it('updates the activity through APNs and the device shows the new state', async () => {
  const { api } = harness;
  const sent = await api.sendLiveActivity({
    to: harness.subscriber,
    event: 'update',
    activityId,
    contentState: { status: 'halfway', step: 1 },
  });
  expect(sent.results.map((result) => [result.ok, result.code ?? null])).toEqual([[true, null]]);

  const updated = await waitForActivity((activity) => activity.id === activityId && activity.step === 1);
  expect(updated.status).toBe('halfway');
});

it('ends the activity through APNs and the device sees it end', async () => {
  const { api, subscriber } = harness;
  const sent = await api.sendLiveActivity({
    to: subscriber,
    event: 'end',
    activityId,
    contentState: { status: 'done', step: 2 },
  });
  expect(sent.results[0]?.ok).toBe(true);

  await waitForActivity((activity) => activity.id === activityId && activity.state !== 'active');
  await api.waitForEvent(subscriber, '$activity.ended', {
    where: (entry) => entry.data?.activityId === activityId,
  });
});

it('starts an activity remotely through a push-to-start token', async () => {
  const { api, subscriber } = harness;
  const sent = await api.sendLiveActivity({
    to: subscriber,
    event: 'start',
    attributesType: 'E2EAttributes',
    attributes: { name: 'remote' },
    contentState: { status: 'remote', step: 0 },
    alert: { title: 'Remote workout', body: 'Started from the server' },
  });
  expect(sent.results.map((result) => [result.ok, result.code ?? null])).toEqual([[true, null]]);

  const remote = await waitForActivity((activity) => activity.name === 'remote', 90_000);
  expect(remote.status).toBe('remote');
  await api.waitForEvent(subscriber, '$activity.started', {
    where: (entry) => entry.data?.activityId === remote.id,
  });
});

it('an end push with a dismissal date removes the activity from the device', async () => {
  const { api, subscriber } = harness;
  const id = await startActivity('dismissed-remotely');

  const sent = await api.sendLiveActivity({
    to: subscriber,
    event: 'end',
    activityId: id,
    contentState: { status: 'done', step: 3 },
    dismissalDate: new Date().toISOString(),
  });
  expect(sent.results[0]?.ok).toBe(true);

  await api.waitForEvent(subscriber, '$activity.dismissed', {
    where: (entry) => entry.data?.activityId === id,
  });
  await waitForActivityGone(id);
});

it('ending on the device with immediate dismissal reports dismissed', async () => {
  const { api, collector, run, subscriber } = harness;
  const id = await startActivity('dismissed-locally');

  const ended = await collector.command(run, 'endActivity', { activityId: id, dismissal: 'immediate' });
  expect(ended.payload.dismissal).toBe('immediate');

  await api.waitForEvent(subscriber, '$activity.dismissed', {
    where: (entry) => entry.data?.activityId === id,
  });
  await waitForActivityGone(id);
});

it('an update with a stale date marks the activity stale on the device', async () => {
  const { api, subscriber } = harness;
  const id = await startActivity('going-stale');

  const sent = await api.sendLiveActivity({
    to: subscriber,
    event: 'update',
    activityId: id,
    contentState: { status: 'stale', step: 1 },
    staleDate: new Date(Date.now() - 1_000).toISOString(),
  });
  expect(sent.results[0]?.ok).toBe(true);

  const stale = await waitForActivity((activity) => activity.id === id && activity.state === 'stale');
  expect(stale.status).toBe('stale');
  await api.waitForEvent(subscriber, '$activity.stale', {
    where: (entry) => entry.data?.activityId === id,
  });
});
