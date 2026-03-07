# Chatify

Production-oriented Flutter messaging foundation aligned with:
- Clean Architecture (Presentation / Domain / Data)
- Feature-first module boundaries
- Firebase stack (Auth, Firestore, Storage, Functions, FCM, Crashlytics)
- Drift offline-first storage
- Bloc/Cubit state management
- DI using get_it + injectable
- Arabic + English localization
- Voice notes (record, upload, play/pause, seek)
- Per-user archive / unarchive chats
- User profile pages (name, phone, avatar, shared groups)
- Message reactions, stars, and pinned messages
- Privacy controls persisted in Firebase (read receipts, last seen, typing visibility)

## Project Structure

```text
lib/
  app/                # bootstrap, router, DI, theme
  core/               # entities, repositories, db, crypto, utils
  features/
    auth/
    contacts/
    chats/
    status/
    calls/
    settings/
    search/
    linked_devices/
    backup/
functions/            # Firebase Cloud Functions endpoints
.github/workflows/    # CI/CD pipelines
```

## Firebase Collections Contract

- `users/{uid}`
- `users/{uid}/devices/{deviceId}`
- `users/{uid}/privacy/settings`
- `conversations/{conversationId}`
- `conversations/{conversationId}/members/{uid}`
- `conversations/{conversationId}/messages/{messageId}`
- `conversations/{conversationId}/receipts/{messageId_uid}`
- `conversations/{conversationId}/typing/{uid}`
- `status/{uid}/items/{statusId}`
- `calls/{callId}`
- `presence/{uid}`
- `abuse_reports/{reportId}`
- `prekeys/{uid_deviceId}`
- `outbox_acks/{uid}/{clientMessageId}`

`conversations/{conversationId}` currently contains:
- `memberIds: string[]`
- `archivedByUserIds: string[]` (per-user archive state)
- `type`, `title`, `createdAt`, `updatedAt`, etc.

## Cloud Functions Endpoints

- `issuePreKeyBundle`
- `rotateSignedPreKey`
- `linkDeviceStart`
- `linkDeviceConfirm`
- `backupKeyWrap`
- `backupKeyRestore`
- `sendCallInvite`
- `fanoutMessageEvent`
- `expireStatus24h`
- `outboxRetryAssist`
- `sendWhatsappText` (callable)
- `sendWhatsappTemplate` (callable)
- `whatsappWebhook` (HTTP webhook verify + inbound events)

## WhatsApp Business Bridge (Beta)

Implemented from WhatsApp Business Platform docs:
- Cloud API text sending bridge.
- Cloud API template-message sending bridge.
- Webhook endpoint for verification and inbound event capture.
- Flutter admin screen under Settings:
  - `WhatsApp Business (Beta)`
  - Send text/template to E.164 recipients for testing.

### Function env vars

Set these before deploying functions:
- `WHATSAPP_ACCESS_TOKEN`
- `WHATSAPP_PHONE_NUMBER_ID`
- `WHATSAPP_VERIFY_TOKEN`
- Optional: `WHATSAPP_GRAPH_VERSION` (default `v23.0`)

### Webhook setup

Use deployed function URL:
- `https://<region>-<project-id>.cloudfunctions.net/whatsappWebhook`

Verify token must match `WHATSAPP_VERIFY_TOKEN`.

## Run Locally

1. Install Flutter 3.38+ and Dart 3.10+.
2. Add Firebase platform configs:
   - `android/app/google-services.json`
   - `ios/Runner/GoogleService-Info.plist`
3. Get dependencies:
   - `flutter pub get`
4. Run code generation:
   - `dart run build_runner build --delete-conflicting-outputs`
5. Launch app:
   - `flutter run -t lib/main.dart`
6. For quick end-to-end smoke, use **Continue in demo mode** from the auth screen.

## Free Local Workflow (No Billing)

1. Start Firebase emulators:
   - `firebase emulators:start --project chatify-3d844 --only auth,firestore,functions,storage`
2. Run app in dev:
   - `flutter run -t lib/main.dart`
3. App will auto-connect to emulators in debug/dev mode.
4. To force real Firebase from dev (optional):
   - `flutter run -t lib/main.dart --dart-define=USE_FIREBASE_EMULATORS=false`
5. If testing on a real Android phone, set host to your PC LAN IP:
   - `flutter run -t lib/main.dart --dart-define=FIREBASE_EMULATOR_HOST=192.168.1.10`

## Real Phone Auth (Production Firebase)

1. In Firebase Console, open Authentication and click **Get started**.
2. Enable **Phone** sign-in provider.
3. Add your Android SHA fingerprints (`SHA-1` and `SHA-256`) to the Firebase Android app, then download the updated `android/app/google-services.json`.
4. For iOS, ensure `ios/Runner/GoogleService-Info.plist` matches the same Firebase project.
5. Run the app against real Firebase (not emulators):
   - `flutter run -t lib/main.dart --dart-define=USE_FIREBASE_EMULATORS=false`
6. Enter phone numbers in E.164 format (example: `+2010XXXXXXXX`).
7. After successful OTP verification, the app now auto-creates/updates `users/{uid}` in Firestore.

## Crashlytics

- Integrated and wired in app bootstrap for:
  - Flutter framework uncaught errors
  - Platform dispatcher uncaught errors
  - `runZonedGuarded` uncaught errors
- Crashlytics collection is enabled by default in release builds.
- In debug builds, collection is disabled by default. Enable it with:
  - `flutter run -t lib/main.dart --dart-define=CRASHLYTICS_IN_DEBUG=true`
- Android Gradle Crashlytics plugin is enabled in `android/app/build.gradle.kts`.

### Flavor note

- Each Android flavor package must exist in Firebase:
  - `dev` uses `com.chatify.app.dev`
  - `stage` uses `com.chatify.app.stage`
  - `prod` uses `com.chatify.app`
- If a flavor is missing from Firebase config, you'll get:
  - `No matching client found for package name ...`

## Firebase Project Safety

- This repo default alias now points to `chatify-3d844`.
- Old project aliases are preserved as:
  - `legacy-dev`
  - `legacy-stage`
  - `legacy-prod`
- Always pass `--project <id-or-alias>` in deploy commands to avoid mistakes.

## Tests

- Unit + widget:
  - `flutter test`
- Integration:
  - `flutter test integration_test`
  - Requires a connected Android/iOS device.

## Delivery Phases

- See [docs/phases.md](docs/phases.md) for tracked phase status.

## Notes

- `SignalCryptoEngine` currently exposes a stable adapter with placeholder internals.
- Current implementation is **not WhatsApp-grade end-to-end encryption** yet.
- Replace crypto internals with audited Signal protocol bindings while keeping repository/use-case contracts stable.

## Implemented in this iteration

- Voice note recording and send flow.
- Voice note playback inside chat bubbles.
- Playback controls:
  - Play/Pause
  - Seek from any time using slider
  - Elapsed/total duration display
- Archive / Unarchive conversation from chat list long-press menu.
- Pin / Unpin conversation from chat list long-press menu.
- Archived view toggle in chats screen.
- Message reactions (emoji) and starred messages.
- Pinned messages inside chat threads (up to 3 per user per chat).
- Real report-contact submission to Firestore (`abuse_reports`).
- Basic anti-spam send limiter in chat thread flow.
- Privacy controls connected to backend:
  - Read receipts toggle persisted and enforced when marking messages read.
  - Last-seen visibility persisted and reflected in presence documents.
  - Typing visibility persisted and used for typing indicator publish/hide.
- Chat header subtitle for direct chats:
  - Typing state
  - Online state
  - Last seen (when peer allows visibility)
- User profile page:
  - Public name, phone and avatar display
  - Self profile editing (display name, about, avatar URL)
  - Groups that user is in
  - Shared groups between current user and viewed user
- Settings top profile tile now opens your editable profile screen.
- Profile opening/edit flow hardened to avoid crashes on invalid/missing
  Firestore values (safe string parsing, avatar URL validation, timeout/error
  handling).

## WhatsApp Comparison (Current Snapshot)

### Already available in Chatify
- Phone OTP authentication.
- 1:1 and group conversations.
- Text messages, attachments, voice notes.
- Delivery/read indicators (basic).
- Localized UI (Arabic/English).
- Archive chats (per user).
- Pinned chats (per user).
- Message reactions and starred messages.
- Pinned messages (per user).
- Basic presence/typing/last-seen privacy controls.
- In-app contact abuse reports.

### Missing or partial vs WhatsApp
- Full Signal-protocol E2EE with audited key management.
- Multi-device key sync and safety-number verification UX.
- Reliable push notification delivery pipeline at scale.
- Chat backup/restore parity with production-grade encryption.
- Robust anti-spam/abuse controls and account recovery flows (currently basic only).
- Presence/typing/last-seen privacy controls parity (currently basic only).
- End-to-end encrypted calls pipeline parity.

### Not implemented yet and why
- Full audited Signal protocol stack:
  - Needs dedicated cryptographic bindings, key lifecycle, migration, and external security review. Current adapter is placeholder-oriented.
- Safety-number verification + multi-device trust UX:
  - Requires device identity graph, trust-change detection, and cross-device key sync backend.
- Push delivery pipeline parity at scale:
  - Requires server fanout workers, retry queues, token hygiene, observability, and SLA-focused infra.
- Backup parity with production-grade encryption:
  - Current backup flow is not full encrypted message-history export/import parity across devices.
- Robust anti-abuse + account recovery:
  - We added reporting and a basic send limiter, but robust moderation needs backend policy engine, abuse scoring, review tooling, and recovery processes.
- E2EE calls parity:
  - Current call signaling is present, but full encrypted media-session parity needs hardened WebRTC key/session architecture.

### Priority roadmap to close gap
1. Replace placeholder crypto with audited Signal implementation.
2. Add key verification UX and trust-change warnings.
3. Harden media pipeline (upload retries, background resume, caching, media player UX).
4. Expand advanced chat productivity features (bulk actions, message management tools, search quality).
5. Strengthen reliability and moderation (rate limits, abuse reports, recovery).
