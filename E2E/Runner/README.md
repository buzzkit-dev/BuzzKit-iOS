# E2E

End-to-end tests that drive the real product: a harness app on a simulator, real APNs
sandbox delivery, and the production API. What the device actually observed is asserted
alongside what the API recorded, so a passing run means the whole path works.

```
runner --> POST /v1/messages --> queue --> APNs sandbox --> simulator --> SDK
   ^                                                                       |
   +---------------------- collector on 127.0.0.1 <------------------------+
```

## Why a simulator can do this

Since Xcode 14 on Apple Silicon a simulator registers with APNs and receives real remote
pushes. `PushEnvironmentDetector` already returns `.sandbox` there, so the SDK registers
the token as a sandbox token and BuzzKit sends to the sandbox gateway.

It does not cover the production APNs gateway, real background and low-power delivery, or
lock screen and Focus presentation. Those stay a manual pass on a physical device.

## What a run needs

| Variable | Meaning |
| --- | --- |
| `BUZZKIT_WORKSPACE_KEY` | Workspace key (`bk_ws_`) with `messages:send` and `subscribers:write` |
| `BUZZKIT_CLIENT_KEY` | Client key (`bk_pk_`) the harness app connects with |
| `BUZZKIT_TENANT` | Defaults to `default` |
| `BUZZKIT_IDENTITY_SECRET` | The tenant's identity secret (dashboard → tenant → identity secret). Optional: without it the two identity-verification scenarios skip |
| `BUZZKIT_API_URL` | Defaults to `https://api.buzzkit.dev` |
| `E2E_SIMULATOR` | Defaults to `iPhone 17` |
| `E2E_COLLECTOR_PORT` | Defaults to `8911` |

The tenant needs an APNs sandbox credential for bundle id `dev.buzzkit.e2e`.

The runner slims the simulator with `simslim` when it is installed but keeps the `store`
and `widgets` daemon groups: without `apsd` no push token is ever issued, and without
`liveactivitiesd` Live Activities never render. CI runners have no `simslim`, which is
fine, because an unslimmed simulator has both.

Runs share the tenant and isolate by subscriber: each run identifies as `e2e-<timestamp>`
and deletes that subscriber afterwards. Keys are not created per run, because `keys:write`
is a session-only scope (`libs/scopes.ts`) and no API key can mint another key.

## Running

```sh
bun install
bun run smoke   # no credentials: proves build, install, launch and reporting
bun run test    # the scenarios
```

Each run identifies as its own subscriber and deletes it afterwards, so runs never
collide and leave nothing behind. The client key is fixed, because `keys:write` is a
session-only scope and no API key can mint another key.

## CI

`.github/workflows/e2e.yml` runs this suite against production on every push to `main`,
on every `v*` tag, nightly, and on `workflow_dispatch`. The monorepo dispatches it on
every push to `main` once Cloudflare Workers Builds has deployed the API for that commit,
and waits for the result, so a commit there is green only when the device path still
works; rolling back is a person's call in the Cloudflare dashboard. Runs
queue behind each other (`concurrency: e2e-production`): the suite shares one tenant and
a remote Live Activity start could land on another run's device.

Repository secrets on `buzzkit-ios`: `BUZZKIT_WORKSPACE_KEY`, `BUZZKIT_CLIENT_KEY`. The
monorepo dispatches `gh workflow run e2e.yml -f reason=<why> -f sdk_ref=<ref>`, which
needs a token with Actions write on this repository.

## Layout

| Path | Role |
| --- | --- |
| `src/config.ts` | The variables a run needs, resolved once |
| `src/api.ts` | The production API client, envelope-unwrapping |
| `src/collector.ts` | The host HTTP server the harness reports to, and `waitFor` |
| `src/simulator.ts` | `simctl` and `xcodebuild`: resolve, boot, build, install, launch |
| `src/smoke.ts` | Credential-free check that the harness loop is intact |
| `src/harness.ts` | Boots a run: simulator, install, launch, and the first three reports |
| `scenarios/` | One file per area, asserting device reports and API state together |

## Scenarios

| File | Covers |
| --- | --- |
| `push.test.ts` | Real APNs delivery, settled deliveries, delivered receipts, deep links and action buttons in the payload, a rich push getting its image attached by the service extension with subtitle and badge intact |
| `interaction.test.ts` | Opening a notification (`didOpen`, deep link routing, `$notification.opened`, `$deeplink.opened`), action buttons with their identifier, text input actions, defined actions running their handler (`$action.triggered`) and recorded as unhandled when none is registered, the `onDeepLink` handler route when the delegate declines, dismissal |
| `identity.test.ts` | Subscription registration, identify and permission events, `setAttributes`, identity verification (a correct HMAC marks the subscriber verified, a wrong one is refused), custom events from the device, backgrounding and returning recording `$app.backgrounded`, `$session.ended` and `$app.opened`, logout disabling delivery |
| `preferences.test.ts` | Reading workspace topics on device, opting out and back in (`$preferences.updated`), a single channel opted out and in, and topic targeting honouring the opt-out |
| `local-notifications.test.ts` | A published workflow whose `waitUntil` + `deliver: local` send starts a run, builds the plan and gets its silent push accepted by APNs; the device then schedules that exact plan (`$local.scheduled`, the pending request with its title and body), a cancel push for the run removes it, and the `cancelOn` event removes it locally while canceling the run on the server |
| `live-activities.test.ts` | A real Live Activity started on device, its token registered, updated and ended through APNs, dismissed both by an end push carrying a dismissal date and locally with an immediate policy, marked stale by a stale date, and one started remotely through a push-to-start token |

Opening and dismissing go through `BuzzKit.openNotification` and `dismissNotification`,
an `@_spi(BuzzKitInternal)` seam that feeds a payload the device really received into
the same path a tap takes. Silent pushes are the other seam. SpringBoard refuses content-available pushes on a
simulator ("only supported on-device"), and `simctl push` never reaches the app
delegate either, so the local-notification scenario proves the engine half through the
API and then hands the server-built silent `userInfo` to
`BuzzKit.didReceiveRemoteNotification(userInfo:)`, the documented forwarding entry point
that the swizzled delegate itself calls. Everything BuzzKit owns on both sides runs for
real; only the hop Apple forbids is substituted.

Driving SpringBoard to tap banners is deliberately not done:
the tap itself is Apple's contract, and everything after it is what these scenarios
prove. What remains manual on a device is the production APNs gateway.

