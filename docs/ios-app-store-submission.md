# Codevoke iOS App Store Submission Pack

更新日期：2026-05-19

## App Review Notes

```text
Codevoke iOS is a free companion app for the user's own Mac running Codevoke.

The iOS app does not include in-app purchases, subscriptions, paid plans, renewal flows, paywalls, external purchase links, or payment prompts. It is only used to sign in, pair with a user-owned Mac, start an authorized remote session, send chat messages, and upload user-selected photos/files to the connected Mac.

Mac companion download:
https://acode.anna.vin/downloads/acode-macos.dmg

Privacy Policy:
https://acode.anna.vin/privacy-ios.html

Support:
https://acode.anna.vin/support.html

Test account:
Email: TODO_PROVIDE_REVIEW_TEST_EMAIL
Password: TODO_PROVIDE_REVIEW_TEST_PASSWORD

Test Mac:
We can provide a prepared Mac device code or keep a Mac online during review if needed.

Connection steps:
1. Install Codevoke on the Mac from the download link above.
2. Open Codevoke on the Mac and sign in with the same test account.
3. In the Mac app, enable remote connection and display the device code.
4. Open Codevoke iOS, sign in with the same test account, then enter the Mac device code.
5. Approve the connection on the Mac if prompted.
6. After the connection is established, send a message from iOS and optionally attach a photo or file selected through the system picker.
7. Account deletion is available in iOS Settings > Account & Security > Delete Account.

Notes:
- The iOS app connects only to a user-owned or user-authorized Mac.
- The Mac performs the local workspace and AI CLI work. The iOS app is not a cloud thin client, software store, or payment client.
- Local network permission is used to discover/connect to the user's Mac on the same LAN. WebRTC/signaling is used only to establish an authorized remote session.
```

## App Store Connect Privacy Labels

Use these labels to match current code and `AcodeIOS/Codevoke/PrivacyInfo.xcprivacy`.

| Category | Data Type | Linked | Tracking | Purpose |
| --- | --- | --- | --- | --- |
| Contact Info | Email Address | Yes | No | App Functionality |
| Identifiers | User ID | Yes | No | App Functionality |
| Identifiers | Device ID | Yes | No | App Functionality |
| User Content | Photos or Videos | Yes | No | App Functionality |
| User Content | Other User Content | Yes | No | App Functionality |
| Diagnostics | Performance Data | Yes | No | App Functionality |
| Diagnostics | Other Diagnostic Data | Yes | No | App Functionality |
| Other Data | Other Data Types | Yes | No | App Functionality |

Mapping notes:
- Email: registration, login, verification, account security.
- User ID: remote account/session identity.
- Device ID: local device UID, device name, server device record, public key binding.
- Photos or Videos: user-selected photo/camera attachments only.
- Other User Content: user-selected files, text messages, prompt/chat content sent to the connected Mac.
- Performance Data: connection quality, latency, transport path.
- Other Diagnostic Data: connection status, device-code attempts, safety logs.
- Other Data Types: device public key, LAN IP/port, transient token, WebRTC offer/answer/ICE/signaling metadata, Keychain-backed auth token transmitted as Authorization.

No tracking domains are declared.

## Privacy Manifest Evidence

- Added: `AcodeIOS/Codevoke/PrivacyInfo.xcprivacy`
- Required reason API found in code: `UserDefaults.standard` in `AcodeIOS/Codevoke/ViewModels/ChatViewModel.swift`
- Declared required reason: `NSPrivacyAccessedAPICategoryUserDefaults` / `CA92.1`
- Existing permission strings:
  - `NSCameraUsageDescription`
  - `NSLocalNetworkUsageDescription`
- Existing ATS state: `NSAllowsLocalNetworking = true`; no global `NSAllowsArbitraryLoads`.

## Domestic Listing Materials

| Item | Status |
| --- | --- |
| 主体名称 | TODO |
| 统一社会信用代码 | TODO |
| ICP 备案号 | TODO |
| APP 备案号 | TODO |
| 隐私政策 URL | `https://acode.anna.vin/privacy-ios.html` |
| 支持 URL | `https://acode.anna.vin/support.html` |
| 联系邮箱 | TODO |
| 应用名称 | Codevoke |
| 应用类型 | 免费远程伴侣工具 / 效率工具 |
| 付费说明 | iOS 端免费，无 IAP，无订阅，无购买入口 |

## Real Device E2E Checklist

Use a real iPhone and a real Mac on the same account.

| Case | Steps | Expected |
| --- | --- | --- |
| Register | iPhone register with email code and accept legal docs | Account created, token stored, iOS legal docs shown |
| Login | Log out/in on iPhone | Session restored from Keychain; no paid wording |
| Mac pairing | Mac shows device code, iPhone enters code | Device resolved and pending approval shown |
| LAN connection | iPhone and Mac on same Wi-Fi | LAN transport connects; Mac must approve if configured |
| WebRTC/signaling | Test on different networks if available | WebRTC/signaling connects or gives clear non-paid error |
| Photo attachment | Pick a photo through PhotosPicker | Only selected item uploads to connected Mac |
| Camera attachment | Take a photo in-app | Camera permission prompt matches use; image uploads |
| File attachment | Pick a file through system picker | Only selected file uploads to connected Mac |
| Account deletion | Settings > Account & Security > Delete Account | Requires `确认清理远程连接数据`; account is deleted; no paid/refund wording |

## Remaining Manual Items

- Replace test account placeholders before App Review submission.
- Confirm the Mac download DMG is public and not blocked by CDN rules.
- If the build uploaded to App Store Connect reports additional required reason APIs from WebRTC or other SDKs, update `PrivacyInfo.xcprivacy` accordingly and rebuild.
