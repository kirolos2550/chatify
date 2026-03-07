# MASVS Tracking (Initial)

## Storage
- [x] Keys/pin persisted in `flutter_secure_storage`.
- [ ] Add hardware-backed key attestation checks.

## Network
- [x] TLS-only Firebase channels.
- [ ] Certificate pinning strategy per flavor.

## Data Privacy
- [x] Message contract enforces ciphertext payload.
- [x] Firestore rules created.
- [ ] Add log redaction for all Function handlers.

## Crypto
- [x] `CryptoEngine` abstraction implemented.
- [ ] Replace placeholder engine internals with audited Signal implementation.
- [ ] Add forward-secrecy regression tests.

