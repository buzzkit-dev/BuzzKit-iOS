export type Config = {
  apiUrl: string;
  workspaceKey: string;
  clientKey: string;
  tenant: string;
  identitySecret?: string;
  simulator: string;
  collectorPort: number;
};

function required(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing ${name}. See README.md for the variables a run needs.`);
  return value;
}

export function resolveConfig(): Config {
  return {
    apiUrl: process.env.BUZZKIT_API_URL?.trim() ?? 'https://api.buzzkit.dev',
    workspaceKey: required('BUZZKIT_WORKSPACE_KEY'),
    clientKey: required('BUZZKIT_CLIENT_KEY'),
    tenant: process.env.BUZZKIT_TENANT?.trim() ?? 'default',
    identitySecret: process.env.BUZZKIT_IDENTITY_SECRET?.trim() || undefined,
    simulator: process.env.E2E_SIMULATOR?.trim() ?? 'iPhone 17',
    collectorPort: Number.parseInt(process.env.E2E_COLLECTOR_PORT ?? '8911', 10),
  };
}
