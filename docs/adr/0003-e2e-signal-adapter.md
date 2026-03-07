# ADR-0003: E2E Encryption Strategy

- Status: Accepted
- Date: 2026-03-04

## Decision
Expose a stable `CryptoEngine` abstraction and implement it with `SignalCryptoEngine`.
Current implementation is an adapter scaffold; production rollout must replace internals with audited Signal bindings.

## Rationale
- Keeps business logic independent from cryptographic library details.
- Allows incremental hardening without breaking repository/use-case contracts.

