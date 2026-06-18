# Remote Transport Residual Scan - 2026-05-20

Scope: residual scan for ICE/TURN aliases, user-facing transport text, backend TURN settings, and release/package validation targets. This pass avoided iOS/macOS core implementation files and backend core implementation changes.

## Findings

1. `remote/turn/ice-servers` is still a live compatibility alias.
   - Backend exposes both `remote/ice-config` and `remote/turn/ice-servers`: `后端/server/router/biz/remote.go:40-41`.
   - iOS and macOS account clients already call `remote/ice-config`: `AcodeIOS/Acode/Networking/RemoteDeviceClient.swift:61-63`, `ClaudeMac/Services/AccountRemote/DeviceRegistrationClient.swift:39-41`.
   - Android now calls `remote/ice-config`: `Android/app/src/main/java/com/acode/android/data/RemoteApiClient.kt:133-134`.
   - Recommendation: do not delete the alias yet. Mark it deprecated, keep current clients on `remote/ice-config`, then remove the alias after one release window.

2. Mac local remote-chat router still exposes `/remote/turn/ice-servers`.
   - Local router route: `ClaudeMac/Services/RemoteChat/RemoteChatRouter.swift:85-90`.
   - It returns STUN-only ICE configuration: `ClaudeMac/Services/RemoteChat/RemoteChatRouter.swift:167-171`.
   - Recommendation: keep during compatibility, but add `/remote/ice-config` there too when core implementation ownership is clear. Then deprecate the old path.

3. User-facing transport text no longer exposes LAN/TURN as usable transport modes.
   - `RemoteUserFacingText.transport` maps `p2p` to "remote connection" and maps `lan` / `turn` to "unsupported transport": `AcodeIOS/Acode/Utils/RemoteUserFacingText.swift:49-57`.
   - Localized error strings still mention `P2P` and `UDP/STUN` to explain direct-connect failure, but no longer mention fallback relay / server relay / TURN as a supported option.
   - Recommendation: keep protocol terms in diagnostics unless product copy should hide technical detail completely.

4. Backend TURN settings are still present but runtime currently does not issue relay credentials.
   - Settings fields remain: `turn-credential-ttl`, `turn-realm`, `turn-secret`, `turn-urls` in `后端/server/setting/remote.go:5-9`.
   - Runtime reads TURN config only to log `turnConfigured`; `relayAllowed` and `hasTurn` are hard false, and the response is STUN-only: `后端/server/service/biz/remote_turn.go:25-43`.
   - Config files still expose empty `turn-secret` and `turn-urls`: `后端/server/config.yaml:125-130`, `后端/server/config.deploy.yaml:130-135`, `后端/server/config.deploy-init.yaml:130-135`.
   - Recommendation: keep fields only if near-term TURN work is planned; otherwise add comments/docs that they are reserved/deprecated so deployers do not assume setting them enables relay.

5. Release/package scripts target `Codevoke.app` and `acode-macos.dmg`; no `ClaudeMac.app` script target was found.
   - Package script defaults: `scripts/package-macos-app.sh:7,10,153`.
   - Verification script checks Release product at `Codevoke.app`: `scripts/verify-build.sh:38-43`.
   - README and packaging docs also point at `~/Desktop/Codevoke.app` and `build/releases/acode-macos.dmg`.
   - Recommendation: no script target change needed for `acode.app`; keep validating these names in release smoke.

## Test Gap Filled

- Added backend regression coverage: even with only TURN config (`turn-urls`, `turn-secret`, `turn-realm`) and an active subscription, `GetICEServers` must not issue relay URLs or credentials while the current policy is STUN/direct-only.

## Follow-Up Candidates

1. Mac local router compatibility: add `/remote/ice-config` alongside `/remote/turn/ice-servers`.
2. Product copy cleanup: replace visible `P2P` and `UDP/STUN` wording only if protocol terms should not be exposed.
3. Backend config documentation: mark TURN fields reserved/deprecated or remove them from deploy templates after confirming no planned relay rollout.
