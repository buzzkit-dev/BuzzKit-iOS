import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const run = promisify(execFile);

const BUNDLE_ID = 'dev.buzzkit.e2e';
const PROJECT = new URL('../..', import.meta.url).pathname;
async function simctl(...args: string[]): Promise<string> {
  const { stdout } = await run('xcrun', ['simctl', ...args], {
    maxBuffer: 32 * 1024 * 1024,
  });
  return stdout;
}

export async function resolveDevice(name: string): Promise<string> {
  const listing = JSON.parse(await simctl('list', 'devices', 'available', '--json')) as {
    devices: Record<string, { udid: string; name: string; state: string }[]>;
  };
  const devices = Object.values(listing.devices).flat();
  const device = devices.find((entry) => entry.name === name);
  if (!device) {
    const names = [...new Set(devices.map((entry) => entry.name))].join(', ');
    throw new Error(`No available simulator named "${name}". Available: ${names || '(none)'}`);
  }
  return device.udid;
}

const SLIM_KEEP = 'store,widgets';

export async function boot(udid: string): Promise<void> {
  await run('simslim', ['on', udid, '--except', SLIM_KEEP]).catch(() => undefined);
  await simctl('boot', udid).catch(() => undefined);
  await simctl('bootstatus', udid, '-b');
}

export async function build(udid: string): Promise<string> {
  try {
    await run(
      'xcodebuild',
      [
        '-project', `${PROJECT}/E2E.xcodeproj`,
        '-scheme', 'E2E',
        '-sdk', 'iphonesimulator',
        '-destination', `id=${udid}`,
        '-derivedDataPath', `${PROJECT}/build`,
        'build',
      ],
      { maxBuffer: 64 * 1024 * 1024 }
    );
  } catch (error) {
    const output = String((error as { stdout?: string }).stdout ?? '');
    const diagnostics = output
      .split('\n')
      .filter((line) => /: (error|warning): |BUILD FAILED/.test(line))
      .join('\n');
    throw new Error(`xcodebuild failed:\n${diagnostics || output.slice(-4000)}`);
  }
  return `${PROJECT}/build/Build/Products/Debug-iphonesimulator/E2E.app`;
}

export async function install(udid: string, app: string): Promise<void> {
  await simctl('install', udid, app);
}

export async function launch(udid: string, environment: Record<string, string>): Promise<void> {
  const childEnvironment = Object.fromEntries(
    Object.entries(environment).map(([key, value]) => [`SIMCTL_CHILD_${key}`, value])
  );
  await run('xcrun', ['simctl', 'launch', '--terminate-running-process', udid, BUNDLE_ID], {
    env: { ...process.env, ...childEnvironment },
  });
}

export async function background(udid: string): Promise<void> {
  await simctl('launch', udid, 'com.apple.Preferences');
}

export async function foreground(udid: string): Promise<void> {
  await simctl('terminate', udid, 'com.apple.Preferences').catch(() => undefined);
  await simctl('launch', udid, BUNDLE_ID);
}

export async function terminate(udid: string): Promise<void> {
  await simctl('terminate', udid, BUNDLE_ID).catch(() => undefined);
}

export async function uninstall(udid: string): Promise<void> {
  await simctl('uninstall', udid, BUNDLE_ID).catch(() => undefined);
}
