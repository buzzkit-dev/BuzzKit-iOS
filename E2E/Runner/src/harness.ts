import { Api } from './api';
import { Collector } from './collector';
import { type Config, resolveConfig } from './config';
import {
  background,
  boot,
  build,
  foreground,
  install,
  launch,
  resolveDevice,
  terminate,
  uninstall,
} from './simulator';

export type Harness = {
  api: Api;
  collector: Collector;
  config: Config;
  run: string;
  subscriber: string;
  background: () => Promise<void>;
  foreground: () => Promise<void>;
  relaunch: (overrides?: Record<string, string>) => Promise<void>;
  stop: () => Promise<void>;
};

export async function startHarness(
  options: { actions?: string[] } = {}
): Promise<Harness> {
  const config = resolveConfig();
  const api = new Api(config);
  const collector = new Collector(config.collectorPort);
  const run = `${Date.now()}`;
  const subscriber = `e2e-${run}`;

  await collector.start();
  const udid = await resolveDevice(config.simulator);
  await boot(udid);
  const app = await build(udid);
  await uninstall(udid);
  await install(udid, app);
  const environment = {
    E2E_RUN: run,
    E2E_API_KEY: config.clientKey,
    E2E_API_URL: config.apiUrl,
    E2E_COLLECTOR: collector.url,
    E2E_SUBSCRIBER: subscriber,
    E2E_ACTIONS: (options.actions ?? []).join(','),
  };
  await launch(udid, environment);

  try {
    await collector.waitFor(run, 'configure.ok');
    await collector.waitFor(run, 'registerForPush', { timeoutMs: 120_000 });
    await collector.waitFor(run, 'permission');
  } catch (error) {
    const reports = collector.seen(run).map((report) => `${report.kind} ${JSON.stringify(report.payload)}`);
    throw new Error(`${String(error)}\nEvery report from the device:\n${reports.join('\n')}`);
  }

  return {
    api,
    collector,
    config,
    run,
    subscriber,
    background: () => background(udid),
    foreground: () => foreground(udid),
    relaunch: async (overrides = {}) => {
      const after = collector.count();
      await launch(udid, { ...environment, ...overrides });
      await collector.waitFor(run, 'configure.ok', { after, timeoutMs: 120_000 });
    },
    stop: async () => {
      await terminate(udid).catch(() => undefined);
      await api.removeSubscriber(subscriber).catch(() => undefined);
      await collector.stop();
    },
  };
}
