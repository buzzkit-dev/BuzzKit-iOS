import { afterAll, beforeAll, expect, it } from 'vitest';
import { type Harness, startHarness } from '../src/harness';

let harness: Harness;
const slug = `e2e-local-${Date.now()}`;

type Pending = { id: string; title: string; body: string };
type Plan = { id: string; at: string; cancelOn: string[] };
type Reminder = { runId: string; messageId: string; plan: Plan; title: string; body: string };

let reminder: Reminder;

async function pending(): Promise<Pending[]> {
  const { collector, run } = harness;
  const report = await collector.command(run, 'pendingLocalNotifications');
  return report.payload.pending as Pending[];
}

async function waitForPending(
  predicate: (requests: Pending[]) => boolean,
  timeoutMs = 45_000
): Promise<Pending[]> {
  const deadline = Date.now() + timeoutMs;
  let latest: Pending[] = [];
  while (Date.now() < deadline) {
    latest = await pending();
    if (predicate(latest)) return latest;
    await new Promise((resolve) => setTimeout(resolve, 1_000));
  }
  throw new Error(`Pending local notifications never matched. Device has: ${JSON.stringify(latest)}`);
}

async function triggerUntilRunStarts(timeoutMs = 150_000): Promise<string> {
  const { api, collector, run, subscriber } = harness;
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    await collector.command(run, 'track', { name: 'e2e.reminder' });
    await new Promise((resolve) => setTimeout(resolve, 10_000));
    const started = (await api.runs(subscriber)).items.find((entry) => entry.status !== 'canceled');
    if (started) return started.id;
  }
  throw new Error('The published workflow never started a run; definitions take up to a minute to reach the actor');
}

async function waitForRun(
  id: string,
  predicate: (run: { status: string; events: { name: string; data?: Record<string, unknown> }[] }) => boolean,
  timeoutMs = 60_000
) {
  const { api } = harness;
  const deadline = Date.now() + timeoutMs;
  let latest = await api.run(id);
  while (Date.now() < deadline) {
    if (predicate(latest)) return latest;
    await new Promise((resolve) => setTimeout(resolve, 1_500));
    latest = await api.run(id);
  }
  throw new Error(`Run ${id} never matched. Status ${latest.status}, events ${latest.events.map((e) => e.name).join(', ')}`);
}

function planUserInfo(): Record<string, unknown> {
  const { messageId, plan, title, body } = reminder;
  return { aps: { 'content-available': 1 }, bk: { messageId, local: { ...plan, title, body } } };
}

async function receive(userInfo: Record<string, unknown>): Promise<string> {
  const { collector, run } = harness;
  const report = await collector.command(run, 'receive', { userInfo });
  return String(report.payload.outcome);
}

beforeAll(async () => {
  harness = await startHarness();
  await harness.api.publishWorkflow(slug, {
    trigger: { event: 'e2e.reminder' },
    concurrency: 'one-per-subscriber',
    cancelOn: [{ event: 'e2e.done' }],
    steps: [
      { name: 'window', waitUntil: { delay: '30m' } },
      { name: 'remind', send: { title: 'Time to move', body: 'Keep the streak.', deliver: 'local' } },
    ],
  });
});

afterAll(async () => {
  await harness?.api.removeWorkflow(slug).catch(() => undefined);
  await harness?.stop();
});

it('the engine starts the run, builds the local plan and APNs accepts the silent push', async () => {
  const { api } = harness;
  const runId = await triggerUntilRunStarts();

  const run = await waitForRun(runId, (entry) =>
    entry.events.some((event) => event.name === '$run.step' && event.data?.step === 'remind' && event.data?.status === 'completed')
  );
  const scheduled = run.events.find((event) => event.name === '$run.step' && event.data?.step === 'remind');
  const messageId = String(scheduled?.data?.messageId ?? '');
  expect(messageId).toMatch(/^msg_/);
  expect(run.status).toBe('sleeping');

  const message = await api.message(messageId);
  const plan = message.payload.local as Plan;
  expect(message.payload.deliver).toBe('local');
  expect(plan.id).toBe(`${runId}:remind`);
  expect(plan.cancelOn).toEqual(['e2e.done']);
  expect(plan.at).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$/);

  const deliveries = await api.settledDeliveries(messageId);
  expect(deliveries.map((delivery) => [delivery.status, delivery.lastErrorMessage])).toEqual([['sent', null]]);

  reminder = { runId, messageId, plan, title: String(message.payload.title), body: String(message.payload.body) };
});

it('the device schedules the plan, reports it and keeps it pending', async () => {
  const { api, collector, run, subscriber } = harness;
  expect(await receive(planUserInfo())).toBe('newData');

  const received = await collector.waitFor(run, 'didReceive', {
    where: (entry) => entry.payload.localPlanId === reminder.plan.id,
  });
  expect(received.payload.localCancelOn).toEqual(['e2e.done']);

  const scheduled = await api.waitForEvent(subscriber, '$local.scheduled', {
    where: (entry) => entry.data?.localId === reminder.plan.id,
  });
  expect(scheduled.data?.messageId).toBe(reminder.messageId);

  const requests = await waitForPending((list) => list.some((request) => request.id === `bk.local.${reminder.plan.id}`));
  const request = requests.find((entry) => entry.id === `bk.local.${reminder.plan.id}`);
  expect(request?.title).toBe(reminder.title);
  expect(request?.body).toBe(reminder.body);
});

it('a cancel push for the run removes the pending reminder', async () => {
  const { collector, run } = harness;
  expect(await receive({ aps: { 'content-available': 1 }, bk: { cancel: { id: reminder.runId } } })).toBe('newData');

  const canceled = await collector.waitFor(run, 'didReceive', {
    where: (entry) => entry.payload.cancelPlanId === reminder.runId,
  });
  expect(canceled.payload.cancelPlanId).toBe(reminder.runId);
  await waitForPending((list) => !list.some((request) => request.id.startsWith(`bk.local.${reminder.runId}`)));
});

it('the cancelOn event removes the reminder on the device and cancels the run on the server', async () => {
  const { collector, run } = harness;
  await receive(planUserInfo());
  await waitForPending((list) => list.some((request) => request.id === `bk.local.${reminder.plan.id}`));

  await collector.command(run, 'track', { name: 'e2e.done' });

  await waitForPending((list) => !list.some((request) => request.id === `bk.local.${reminder.plan.id}`));
  const canceled = await waitForRun(reminder.runId, (entry) => entry.status === 'canceled');
  expect(canceled.events.some((event) => event.name === '$run.canceled')).toBe(true);
});
