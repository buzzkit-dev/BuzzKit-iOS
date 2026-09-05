import { afterAll, beforeAll, expect, it } from 'vitest';
import type { Report } from '../src/collector';
import { type Harness, startHarness } from '../src/harness';

let harness: Harness;

beforeAll(async () => {
  harness = await startHarness({ actions: ['show_offer'] });
});

afterAll(async () => {
  await harness?.stop();
});

async function receive(message: Record<string, unknown>): Promise<{ id: string; report: Report }> {
  const { api, collector, run, subscriber } = harness;
  const sent = await api.send({ to: subscriber, ...message });
  const report = await collector.waitFor(run, 'willPresent', {
    timeoutMs: 120_000,
    where: (entry) => entry.payload.messageId === sent.id,
  });
  return { id: sent.id, report };
}

it('opening a notification reports didOpen and routes its deep link', async () => {
  const { api, collector, run, subscriber } = harness;
  const { id } = await receive({ title: 'E2E', body: 'Open me', deepLink: 'buzzkit://workouts/42' });

  await collector.command(run, 'open', { messageId: id });

  const opened = await collector.waitFor(run, 'didOpen', { where: (entry) => entry.payload.messageId === id });
  expect(opened.payload.actionIdentifier).toBeNull();
  const routed = await collector.waitFor(run, 'openDeepLink');
  expect(routed.payload.url).toBe('buzzkit://workouts/42');

  const event = await api.waitForEvent(subscriber, '$notification.opened', {
    where: (entry) => entry.data?.messageId === id,
  });
  expect(event.data?.deepLink).toBe('buzzkit://workouts/42');
  expect(event.data?.action).toBeUndefined();

  const link = await api.waitForEvent(subscriber, '$deeplink.opened', {
    where: (entry) => entry.data?.messageId === id,
  });
  expect(link.data?.url).toBe('buzzkit://workouts/42');
  expect(link.data?.via).toBe('delegate');
});

it('tapping an action button reports its identifier on the device and the timeline', async () => {
  const { api, collector, run, subscriber } = harness;
  const { id, report } = await receive({
    title: 'E2E',
    body: 'Pick one',
    actions: [
      { id: 'view', title: 'View' },
      { id: 'snooze', title: 'Snooze', destructive: true },
    ],
  });
  expect(report.payload.actions).toEqual(['view', 'snooze']);

  await collector.command(run, 'open', { messageId: id, actionIdentifier: 'snooze' });

  const opened = await collector.waitFor(run, 'didOpen', { where: (entry) => entry.payload.messageId === id });
  expect(opened.payload.actionIdentifier).toBe('snooze');
  const event = await api.waitForEvent(subscriber, '$notification.opened', {
    where: (entry) => entry.data?.messageId === id,
  });
  expect(event.data?.action).toBe('snooze');
});

it('a text input action carries the typed text to the timeline', async () => {
  const { api, collector, run, subscriber } = harness;
  const { id } = await receive({
    title: 'E2E',
    body: 'Reply',
    actions: [{ id: 'reply', title: 'Reply', input: true, placeholder: 'Say something' }],
  });

  await collector.command(run, 'open', { messageId: id, actionIdentifier: 'reply', input: 'on my way' });

  const event = await api.waitForEvent(subscriber, '$notification.opened', {
    where: (entry) => entry.data?.messageId === id,
  });
  expect(event.data?.action).toBe('reply');
  expect(event.data?.input).toBe('on my way');
});

it('a push naming a registered action runs its handler with the data', async () => {
  const { collector, run } = harness;
  const { id } = await receive({
    title: 'E2E',
    body: 'Runs a handler',
    action: { name: 'show_offer', data: { offer: 'spring' } },
  });

  await collector.command(run, 'open', { messageId: id });

  const fired = await collector.waitFor(run, 'action');
  expect(fired.payload.name).toBe('show_offer');
  expect(String(fired.payload.data)).toContain('spring');

  const triggered = await harness.api.waitForEvent(harness.subscriber, '$action.triggered', {
    where: (entry) => entry.data?.messageId === id,
  });
  expect(triggered.data?.name).toBe('show_offer');
  expect(triggered.data?.handled).toBe(true);
});

it('dismissing a notification records a dismissed event', async () => {
  const { api, collector, run, subscriber } = harness;
  const { id } = await receive({ title: 'E2E', body: 'Swipe away' });

  await collector.command(run, 'dismiss', { messageId: id });

  await api.waitForEvent(subscriber, '$notification.dismissed', {
    where: (entry) => entry.data?.messageId === id,
  });
});

it('a deep link the delegate declines is routed through the onDeepLink handler', async () => {
  const { api, collector, run, subscriber } = harness;
  const { id } = await receive({ title: 'E2E', body: 'Handler route', deepLink: 'buzzkit://handler/7' });

  await collector.command(run, 'open', { messageId: id });

  const declined = await collector.waitFor(run, 'openDeepLink', {
    where: (entry) => entry.payload.url === 'buzzkit://handler/7',
  });
  expect(declined.payload.handled).toBe(false);
  const handled = await collector.waitFor(run, 'deepLink', {
    where: (entry) => entry.payload.url === 'buzzkit://handler/7',
  });
  expect(handled.payload.url).toBe('buzzkit://handler/7');

  const link = await api.waitForEvent(subscriber, '$deeplink.opened', {
    where: (entry) => entry.data?.messageId === id,
  });
  expect(link.data?.via).toBe('handler');
});

it('a defined action with no registered handler is recorded as unhandled', async () => {
  const { api, collector, run, subscriber } = harness;
  await collector.command(run, 'unregisterAction', { name: 'show_offer' });
  const { id } = await receive({
    title: 'E2E',
    body: 'No handler',
    action: { name: 'show_offer', data: { offer: 'winter' } },
  });

  await collector.command(run, 'open', { messageId: id });

  const triggered = await api.waitForEvent(subscriber, '$action.triggered', {
    where: (entry) => entry.data?.messageId === id,
  });
  expect(triggered.data?.name).toBe('show_offer');
  expect(triggered.data?.handled).toBe(false);
  expect(collector.seen(run).filter((entry) => entry.kind === 'action' && String(entry.payload.data).includes('winter'))).toEqual([]);
});
