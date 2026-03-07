# ADR-0002: Backend Stack

- Status: Accepted
- Date: 2026-03-04

## Decision
Use Firebase stack:
- Firebase Auth for OTP
- Firestore for realtime metadata/events
- Cloud Storage for encrypted media
- Cloud Functions for server-side workflows
- FCM for push delivery

## Rationale
- Fastest production path with managed infra.
- Consistent client SDK support for Flutter.
- Lower initial DevOps overhead.

