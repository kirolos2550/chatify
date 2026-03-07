# Free Local Setup

This guide keeps development costs at zero by using local Firebase emulators.

## Why this mode

- Firebase Storage, SMS auth, and Functions cloud deploy can require billing.
- Local emulator workflow allows full end-to-end development without paid usage.

## Start emulators

```bash
firebase emulators:start --project chatify-3d844 --only auth,firestore,functions,storage
```

Emulator UI:

- http://127.0.0.1:4000

## Run Flutter app

```bash
flutter run -t lib/main.dart
```

In debug/dev mode, app auto-connects to:

- Auth: `9099`
- Firestore: `8080`
- Functions: `5001`
- Storage: `9199`

## Use real backend from dev (optional)

```bash
flutter run -t lib/main.dart --dart-define=USE_FIREBASE_EMULATORS=false
```

## Real Android phone note

`10.0.2.2` works for Android Emulator only. For a physical phone, pass your machine LAN IP:

```bash
flutter run -t lib/main.dart --dart-define=FIREBASE_EMULATOR_HOST=192.168.1.10
```

## Project alias safety

`.firebaserc` defaults to `chatify-3d844` and keeps older projects under `legacy-*` aliases.
Always deploy with explicit `--project`.
