# ADR-0001: State Management

- Status: Accepted
- Date: 2026-03-04

## Decision
Use `flutter_bloc`/`Cubit` as the single state-management standard across features.

## Rationale
- Deterministic state transitions for chat, sync, and call flows.
- Strong testing support with `bloc_test`.
- Clear event/state review model for large teams.

