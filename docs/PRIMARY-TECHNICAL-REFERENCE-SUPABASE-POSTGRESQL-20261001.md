# PRIMARY TECHNICAL REFERENCE — SUPABASE + POSTGRESQL

**Date:** 2026-10-01
**Purpose:** Primary technical reference for database/RPC/concurrency/security work in Atlas API Toolbox.
**Scope:** Supabase Database Functions/RPC, RLS/grants, PostgreSQL transactions and locking.
**Authority:** Technical reference only. Does not override COS constitution, contracts, decisions, authorizations or validations.

## 1. Supabase Database Functions / RPC

Official guide:
https://supabase.com/docs/guides/database/functions

Use for:
- PostgreSQL Database Functions exposed through rpc()
- SQL/PLpgSQL function semantics
- data-intensive operations executed inside Postgres
- SECURITY INVOKER / SECURITY DEFINER boundaries
- function EXECUTE privileges

Critical current guidance:
- Prefer SECURITY INVOKER by default.
- SECURITY DEFINER requires explicit search_path handling.
- Function EXECUTE privileges must be reviewed; PostgreSQL grants EXECUTE to PUBLIC by default unless restricted.
- For privileged/internal RPCs, explicitly revoke and grant the intended role.

## 2. Supabase RLS / Grants

Official guide:
https://supabase.com/docs/guides/database/postgres/row-level-security

Use for:
- RLS
- table grants
- Data API exposure
- service_role/server-side access
- RLS testing

Critical current guidance:
- RLS and grants are separate controls.
- Enabling RLS does not revoke existing grants.
- Exposed public tables require deliberate grants and policies.
- service_role bypasses RLS and must remain server-side.
- RLS changes should be tested with allow/deny assertions.

## 3. PostgreSQL 17 — Explicit Locking

Official guide:
https://www.postgresql.org/docs/17/explicit-locking.html

Use for:
- row-level locks
- FOR UPDATE / FOR NO KEY UPDATE / related locking clauses
- SKIP LOCKED
- advisory locks
- lock lifetime and transaction semantics
- evaluating concurrency and ownership primitives

## 4. PostgreSQL 17 — Functions

Official reference:
https://www.postgresql.org/docs/17/sql-createfunction.html

Use for:
- CREATE FUNCTION
- security attributes
- volatility
- execution context
- function-level privileges

## 5. Application to CLAIM / OWNERSHIP

This reference set is the primary technical baseline for evaluating:

CLAIM
→ OWNERSHIP
→ GOVERNANCE
→ RELEASE / RECLAIM
→ START
→ EXECUTION

It does not prescribe the COS implementation.

For the current CLAIM-START-COLLAPSE delta, the technical reference must be contrasted with:
1. COS TPP/OVR contracts.
2. Adopted Claim/Release Operation Contract.
3. Actual deployed runtime evidence.
4. Existing Supabase physical implementation.
5. External BenchMart patterns.

## 6. Version discipline

When implementing or validating Supabase-related changes:
- verify current official documentation before implementation;
- verify PostgreSQL major-version semantics against the deployed database;
- record the documentation date/version used for material decisions;
- do not treat a third-party benchmark as a normative platform reference.

## 7. Current relevance

Primary delta:
CLAIM-START-COLLAPSE-001

Relevant physical objects:
- public.rpc_claim_task
- public.task_claim_leases
- public.rpc_claim_lease
- public.rpc_release_lease
- public.task_claim_evidence

This file is a reference surface for ATLAS API Toolbox. It is not an authorization to modify any of these objects.
