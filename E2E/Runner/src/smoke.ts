import { Collector } from './collector';
import { boot, build, install, launch, resolveDevice, terminate, uninstall } from './simulator';
import { resolveConfig } from './config';

const port = Number.parseInt(process.env.E2E_COLLECTOR_PORT ?? '8911', 10);
const simulator = process.env.E2E_SIMULATOR?.trim() ?? 'iPhone 17';

const collector = new Collector(port);
await collector.start();

const run = `smoke-${Date.now()}`;
const udid = await resolveDevice(simulator);
await boot(udid);
const app = await build(udid);
await uninstall(udid);
await install(udid, app);
await launch(udid, { E2E_RUN: run, E2E_COLLECTOR: collector.url });

const report = await collector.waitFor(run, 'configure.skipped', { timeoutMs: 60_000 });
console.log(`Harness reachable. Device reported "${report.kind}" at ${report.at}.`);

await terminate(udid);
await collector.stop();
