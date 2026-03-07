# Chatify Phases

This file tracks delivery in practical phases focused on fast testability.

## Phase 1: Foundation

- [x] Clean architecture module layout.
- [x] Dependency injection with `get_it` + `injectable`.
- [x] App routing with shell tabs.
- [x] Firebase bootstrap + environment flavors.
- [x] Core domain entities, repositories, and use-case contracts.
- [x] CI workflows for analyze + test + release build.

## Phase 2: Feature Wiring (Fast Testable)

- [x] Auth screen wired with OTP flow.
- [x] Demo-mode entry from auth for rapid local testing.
- [x] Chat list + chat thread test flows (with local fallback).
- [x] Status page wired with create-status flow and fallback.
- [x] Calls page wired with start/end call flow and fallback.
- [x] Linked devices page wired with start/confirm link flow and fallback.
- [x] Backup page wired with enable/restore flow and fallback.
- [x] Settings page actions (privacy toggles + sign out entry).
- [x] Search page wired with query state and navigation results.

## Phase 3: Hardening

- [ ] Replace placeholder crypto internals with audited Signal implementation.
- [ ] Strengthen Firestore/Storage rules for strict least-privilege access.
- [ ] Add full outbox/offline sync reconciliation tests.
- [ ] Add failure-path coverage for auth, messaging, status, and calls.
- [ ] Complete production observability (redaction, tracing, metrics).

## Phase 4: Production Readiness

- [ ] Full E2E suite on connected Android/iOS devices.
- [ ] Security hardening checklist completion (MASVS pending items).
- [ ] Staged rollout gates with release quality metrics.

