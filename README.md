# Chatify

Production-oriented Flutter messaging foundation aligned with:
- Clean Architecture (Presentation / Domain / Data)
- Feature-first module boundaries
- Firebase stack (Auth, Firestore, Functions, FCM, Crashlytics)
- Supabase Storage media pipeline (attachments + voice notes)
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
4. Add Supabase runtime defines file for media uploads:
   - Create `supabase.env.json` in project root:
   - `{"SUPABASE_URL":"https://<project>.supabase.co","SUPABASE_ANON_KEY":"<publishable-key>","SUPABASE_STORAGE_BUCKET":"chat-media"}`
5. Ensure bucket and policies exist in Supabase Storage:
   - Bucket name should match `SUPABASE_STORAGE_BUCKET`.
   - Allow `insert`, `update`, and `select` for your client role (for debug/dev, `anon` is common).
6. Run code generation:
   - `dart run build_runner build --delete-conflicting-outputs`
7. Launch app:
   - `flutter run -t lib/main.dart --dart-define-from-file=supabase.env.json`
8. For quick end-to-end smoke, use **Continue in demo mode** from the auth screen.

## Android Release Build (APK)

1. Build production flavor release APK:
   - `flutter build apk --release --dart-define-from-file=supabase.env.json`
2. Output path:
   - `build/app/outputs/flutter-apk/app-prod-release.apk`
3. Install on a real Android phone (USB debugging enabled):
   - `adb install -r build/app/outputs/flutter-apk/app-prod-release.apk`
   - Or on Windows when `adb` is not in PATH:
   - `& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" install -r "build\app\outputs\flutter-apk\app-prod-release.apk"`

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

## Latest Bug Fixes (v1.0.6+7)

- Fixed debug log sink close ordering so queued log lines are flushed before the sink is marked closed.
- Fixed `Result.logIfFailure` log persistence behavior in tests by ensuring pending writes are not dropped during logger shutdown.
- Stabilized `route_logging_test` by:
  - Moving I/O-bound logger setup/teardown and file reads into `tester.runAsync`.
  - Avoiding early route tracing initialization before router state is available.
  - Hardening temp-directory cleanup in teardown.
- Verified full test suite passes successfully (`flutter test`).

## Previous Bug Fixes (v1.0.5+6)

- Added contacts-driven direct chat creation sheet:
  - Lists registered contacts already on Chatify.
  - Supports search across name/phone.
  - Falls back to manual user-id/phone entry when contacts are unavailable.
  - Adds quick SMS invite action for contacts not yet on Chatify.
- Added contacts-driven group creation sheet:
  - Select members from registered contacts.
  - Supports preselected members when creating a group from an existing chat.
  - Supports manual fallback entry (uid/phone) when contacts are unavailable.
- Improved contacts/domain data pipeline:
  - Added shared phone normalization utility (`E.164` + digits fallback).
  - Added `ContactCandidate` model and repository API `fetchContactCandidates()`.
  - Added `phoneDigits` persistence on auth profile sync for robust matching.
- Hardened conversation member resolution:
  - Group and direct chat creation now resolve identifiers by user id, normalized phone, or phone digits.
  - Better validation for empty group titles and unresolved member lists.
- Added in-app message notification pipeline:
  - New notification orchestrator watching latest messages in user conversations.
  - New in-app notification center + top popup host integrated at app level.
  - Suppresses duplicate, self-sent, and currently-open-conversation notifications.
- Added contacts permission declarations:
  - Android: `READ_CONTACTS`
  - iOS: `NSContactsUsageDescription`
- Added tests for:
  - `PhoneNormalizer`
  - `MessageNotificationDecisionEngine`
  - `InAppNotificationHost`

## Older Bug Fixes (v1.0.4+5)

- Moved chat media uploads (images/files/voice notes) to Supabase Storage as primary provider.
- Added runtime configuration for media storage via `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_STORAGE_BUCKET`.
- Added clear user-facing diagnostics for common Supabase failures (missing bucket, blocked storage policy, missing runtime defines).
- Added VS Code and debug script support for `--dart-define-from-file=supabase.env.json` to avoid misconfigured runs.
- Hardened debug file log sink to avoid app crashes on write/flush stream-state errors (`StreamSink is bound to a stream`).

- Fixed Arabic localization for the chat overflow menu and message long-press actions.
- Fixed group menu behavior by hiding `Create group with this contact` for existing groups and showing `Group info` instead of `View contact`.
- Added a full group info sheet with creation date, participants list, and media/docs/links counters.
- Fixed media/docs browsing to show real entries and support open/copy actions (image preview, video/document links, URL copy).
- Improved attachment parsing compatibility for legacy message payloads (`downloadUrl`, `fileUrl`, `mediaUrl`, `attachmentUrl`, `storagePath`, `objectPath`, nested `file`/`media`, and more).
- Added fallback support for old attachment messages stored as plain text pointers (`https://`, `gs://`, or storage paths) when JSON payload is missing.
- Improved old voice-note playback compatibility by reusing the legacy attachment fallback path and broader duration-key parsing.
- Improved upload reliability by normalizing Firebase Storage bucket candidates and preferring explicit `.appspot.com` fallback for projects configured with `.firebasestorage.app`.
- Enabled Android `android:enableOnBackInvokedCallback="true"` to resolve back-invocation warnings on modern Android versions.
- Added smart chat auto-scroll behavior:
  - Auto-jumps to latest message on initial open.
  - Auto-scrolls on new incoming messages only when user is near bottom.
  - Keeps manual upward browsing stable (does not force-scroll while reading old messages).
- Fixed call signaling flow for real users:
  - Calls stream now scoped to current user via `participantIds` filtering.
  - `initiatorId`/`answeredBy` are persisted in call sessions.
  - Added accept/reject call actions in repository + cubit + calls UI.
- Added incoming-call local alerts in app bootstrap listener and requested notification permissions at runtime.
- Added Android `POST_NOTIFICATIONS` permission for reliable incoming call notifications.

### Supabase setup required for media uploads

- Create a Supabase Storage bucket (default expected name: `chat-media`).
- Ensure the app runs with:
  - `--dart-define-from-file=supabase.env.json`
- Example `supabase.env.json` content:
  - `{"SUPABASE_URL":"https://<project>.supabase.co","SUPABASE_ANON_KEY":"<publishable-key>","SUPABASE_STORAGE_BUCKET":"chat-media"}`
- Configure policies to allow your client role (e.g. `anon` in debug/dev) to:
  - `SELECT` from `storage.objects`
  - `INSERT` into `storage.objects`
  - `UPDATE` in `storage.objects` (required because uploads use upsert)
- Firebase Storage upload fallback is disabled by default in current builds.
- Enable Firebase fallback only when intentionally needed:
  - `--dart-define=ENABLE_FIREBASE_STORAGE_UPLOAD_FALLBACK=true`

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
