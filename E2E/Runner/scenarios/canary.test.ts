import { expect, it } from 'vitest';
import { Api } from '../src/api';
import { resolveConfig } from '../src/config';

const slug = 'e2e-canary';
const subscriber = 'e2e-canary';
const segment = 'e2e-canary';
const HOUR_MS = 3_600_000;

const spec = {
  trigger: { schedule: { daily: '04:20' }, timezone: 'UTC', segment },
  concurrency: 'one-per-subscriber',
  steps: [
    { name: 'sleep', wait: '3h' },
    { name: 'mark', set: { attribute: 'canaryPassedAt', value: '{{ now | date: "long" }}' } },
  ],
};

async function ensureCanary(api: Api) {
  await api.upsertSubscriber(subscriber, { timezone: 'UTC', attributes: { canary: true } });
  await api
    .createSegment(segment, 'E2E canary', { ref: 'attributes.canary', eq: true })
    .catch((error: unknown) => {
      if (!String(error).includes('409')) throw error;
    });
  try {
    return await api.workflow(slug);
  } catch (error) {
    if (!String(error).includes('404')) throw error;
    await api.publishWorkflow(slug, spec);
    return await api.workflow(slug);
  }
}

it('the production canary keeps firing daily and its three-hour sleep survives the platform', async () => {
  const api = new Api(resolveConfig());
  const workflow = await ensureCanary(api);
  expect(workflow.status).toBe('active');

  const runs = (await api.runs(subscriber)).items;
  const age = Date.now() - Date.parse(workflow.createdAt);
  if (runs.length === 0) {
    expect(age).toBeLessThan(26 * HOUR_MS);
    console.log('[canary] published; the first daily fire has not come round yet');
    return;
  }

  const newest = runs
    .map((run) => Date.parse(run.startedAt))
    .sort((left, right) => right - left)[0] as number;
  expect(Date.now() - newest).toBeLessThan(26 * HOUR_MS);

  const settled = runs.filter((run) => Date.now() - Date.parse(run.startedAt) > 4 * HOUR_MS);
  for (const run of settled) {
    expect({ id: run.id, status: run.status, step: run.step }).toEqual({
      id: run.id,
      status: 'completed',
      step: 'mark',
    });
  }
  if (settled.length > 0) {
    const profile = await api.subscriber(subscriber);
    expect(typeof profile.attributes.canaryPassedAt).toBe('string');
  }
});
