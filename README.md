# LICITRA-MMR

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.18843032.svg)](https://doi.org/10.5281/zenodo.18843032)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Python](https://img.shields.io/badge/python-3.12-blue)]()
[![Research](https://img.shields.io/badge/type-security--research-blue)]()
[![Ledger](https://img.shields.io/badge/system-cryptographic--ledger-purple)]()
[![Tests](https://img.shields.io/badge/tests-11%2F11%20pass-brightgreen)]()

**LICITRA-MMR is a tamper-evident audit ledger for AI agent systems that makes any retroactive modification to agent actions cryptographically detectable using a Merkle Mountain Range (MMR).**

Every action taken by an AI agent is committed to an append-only cryptographic structure. If any historical event is modified — even a single byte — the Merkle root changes and verification fails. The design uses a Merkle Mountain Range (MMR), an append-only authenticated data structure widely used in blockchain-adjacent systems, and adapts it for AI runtime accountability. Verification of any individual event requires **O(log n)** hashing operations using Merkle inclusion proofs, allowing large ledgers to be audited efficiently.

---

## Table of Contents

- [Relationship to LICITRA-SENTRY](#relationship-to-licitra-sentry)
- [Core Security Invariant](#core-security-invariant)
- [The Problem](#the-problem)
- [How It Works](#how-it-works)
- [Architecture](#architecture)
- [API Reference](#api-reference)
- [Quick Start](#quick-start)
- [Environment Modes](#environment-modes-important)
- [Test Suite](#test-suite)
- [Experiments](#experiments)
- [Evidence Bundles](#evidence-bundles)
- [Inclusion Proofs](#inclusion-proofs)
- [Project Structure](#project-structure)
- [Design Decisions](#design-decisions)
- [Citation](#citation)
- [References](#references)
- [License](#license)

---

## Relationship to LICITRA-SENTRY

LICITRA-MMR provides the tamper-evident audit ledger for the LICITRA runtime security architecture.

- **LICITRA-SENTRY** enforces runtime authorization for AI agents using execution tickets and mandatory mediation.
- **LICITRA-MMR** records the resulting actions in an append-only cryptographic ledger.

Together they provide both:
- Runtime enforcement of agent permissions
- Post-execution cryptographic verifiability of agent actions

---

## Core Security Invariant

If any historical event is modified, the MMR root hash changes and ledger verification fails.

```
tamper(event_i)
→ leaf hash changes
→ ancestor nodes change
→ MMR root mismatch
→ epoch hash mismatch
→ ledger verification failure
```

This invariant guarantees that agent activity cannot be silently altered after the fact. Log files can be deleted. Databases can be edited. Timestamps can be forged. LICITRA-MMR makes tampering **cryptographically detectable**, not just policy-prohibited.

---

## The Problem

Agentic AI systems act autonomously — browsing the web, writing code, calling APIs, managing files. There is currently no standard mechanism to prove, after the fact, that an agent did exactly what it claims to have done, and nothing more.

Current approaches store audit records in mutable databases. An operator with database access — or an attacker who compromises the operator's infrastructure — can rewrite historical records without detection. Regulators, auditors, and counterparties must trust the operator's infrastructure.

LICITRA-MMR provides **cryptographic tamper-evidence**: any modification to any event, at any point in history, is mathematically detectable through Merkle root divergence.

---

## How It Works

### 1. Canonical JSON Hashing

Every agent action is serialized to canonical JSON — keys sorted alphabetically, no whitespace — and hashed with SHA-256. Key order is irrelevant: the same logical payload always produces the same hash.

```
canonical_json = sort_keys(payload)
leaf_hash      = SHA256(canonical_json)
```

### 2. Merkle Mountain Range (MMR)

Each `leaf_hash` is appended to a binary MMR. Internal nodes are computed as:

```
node_hash = SHA256(left_child || right_child)
```

The MMR root summarizes the entire ledger at any point in time. Any modification to any historical leaf changes every ancestor node up to the root.

### 3. Epoch Hash Chain

Every 1,000 events (configurable via `BLOCK_SIZE`), the MMR is sealed into an epoch:

```
epoch_hash = SHA256(prev_epoch_hash || mmr_root || canonical_metadata)
```

Epochs chain together like blockchain blocks. Modifying epoch N breaks the hash of epoch N+1, N+2, and every subsequent epoch. The genesis epoch uses `prev_epoch_hash = "00" * 32`.

### 4. Two-Phase Commit Pipeline

No event enters the ledger without passing a policy check:

```
POST /agent/propose   →  policy engine evaluates risk
                      →  APPROVED or REJECTED (both recorded)
POST /agent/commit    →  only APPROVED proposals can be committed
```

Rejected proposals are retained in the staged events table — a permanent audit trail of what was attempted and why it was blocked.

### 5. Per-Organization Isolation

Each organization has a completely independent MMR, epoch chain, and event sequence. Tampering with one org's ledger has zero effect on any other org's cryptographic state.

---

## Architecture

![LICITRA-MMR Architecture](docs/architecture.png)

*Figure 1 — LICITRA-MMR pipeline: agent actions pass through policy evaluation, canonical serialization, SHA-256 hashing, MMR append, and epoch sealing before commitment to persistent storage. Rejected proposals are permanently recorded in staged_events.*

```
┌─────────────────────────────────────────────────────┐
│                    FastAPI Service                   │
├──────────────┬──────────────┬───────────────────────┤
│  /agent      │  /verify     │  /evidence  /proof    │
│  propose     │  full chain  │  JSON + PDF bundles   │
│  commit      │  validation  │  inclusion proofs     │
└──────┬───────┴──────┬───────┴───────────────────────┘
       │              │
┌──────▼──────┐ ┌─────▼──────────────────────────────┐
│   Policy    │ │           PostgreSQL 16              │
│   Engine    │ │  events  │ mmr_nodes │ epochs        │
│  hard rules │ │  staged_events                       │
│  risk score │ └──────────────────────────────────────┘
└─────────────┘
```

**Stack:** Python 3.12 · FastAPI · PostgreSQL 16 · SQLAlchemy · reportlab

The API layer orchestrates a pipeline consisting of canonical JSON serialization, SHA-256 hashing, MMR append operations, and epoch sealing before events are committed to persistent storage.

---

## API Reference

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/health` | Service health + active runtime configuration |
| `POST` | `/agent/propose` | Submit action for policy evaluation |
| `POST` | `/agent/commit/{staged_id}` | Commit an APPROVED proposal |
| `GET` | `/verify/{org_id}` | Full cryptographic verification |
| `GET` | `/evidence/{org_id}` | JSON evidence bundle with self-checksum |
| `GET` | `/evidence/{org_id}/pdf` | PDF evidence bundle for audit/legal |
| `GET` | `/proof/{org_id}/{event_id}` | MMR inclusion proof for a single event |

**DEV_MODE only:**

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/tamper/{org_id}/{event_id}` | Corrupt a leaf (for experiment demos) |
| `POST` | `/tamper-epoch/{org_id}/{epoch_id}` | Corrupt an epoch hash |
| `POST` | `/dev/reset/{org_id}` | Wipe all data for an org |

---

## Quick Start

### Prerequisites

- Python 3.12
- PostgreSQL 16
- Windows (PowerShell) or Linux/macOS

### Setup

```bash
git clone https://github.com/narendrakumarnutalapati/licitra-mmr-core
cd licitra-mmr-core

python -m venv .venv
.\.venv\Scripts\Activate.ps1          # Windows
# source .venv/bin/activate           # Linux/macOS

pip install -r requirements.txt
```

### Configure

LICITRA-MMR ships with explicit environment templates (`.env.default`, `.env.test`, and `.env.experiment`).

Edit the templates to match your local PostgreSQL configuration, then select a mode:

```powershell
.\scripts\switch_env.ps1 -mode default
.\scripts\switch_env.ps1 -mode test
.\scripts\switch_env.ps1 -mode experiment
```

This copies the selected template into `.env`.

### Environment Modes (Important)

LICITRA-MMR operates in three explicit modes:

| Mode | BLOCK_SIZE | DEV_MODE | Purpose |
|------|-----------|----------|---------|
| Default | 1000 | false | Production-like behavior (no dev endpoints) |
| Test | 1000 | true | Test suite validation with production-like epoch size |
| Experiment | 2 | true | Fast experiment validation with immediate proof availability |

- `DEV_MODE=true` is **required** for the test suite and experiment suite. It enables `/dev/*` and tamper endpoints used by tests.
- `BLOCK_SIZE` affects epoch finalization speed, not correctness. `BLOCK_SIZE=2` makes MMR proofs immediately available; `BLOCK_SIZE=1000` is production-like behavior.

> **Mode Consistency Warning:**
>
> Mixing configurations (e.g., `BLOCK_SIZE=1000` with `DEV_MODE=true` outside `test` mode) can produce valid but non-reproducible behavior relative to documented test or experiment expectations.
>
> Always use:
> - `test` mode for test suite validation
> - `experiment` mode for experiment reproducibility

### Run

On first startup the service automatically creates the required database tables if they do not exist.

```bash
.\scripts\run_server.ps1
```

Or directly:

```bash
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

Server starts at `http://localhost:8000`. API docs at `http://localhost:8000/docs`.

---

## Test Suite

11 independent test suites. Each is a standalone reproducible artifact.

**Requires:**

- Running server
- `BLOCK_SIZE=1000`
- `DEV_MODE=true`

```powershell
.\scripts\switch_env.ps1 -mode test
.\scripts\run_server.ps1
```

Then:

```powershell
.\tests\run_all_tests.ps1
```

Expected output:

```
════════════════════════════════════════════════════════════
  LICITRA-MMR TEST RESULTS
════════════════════════════════════════════════════════════

  [PASS]  t01_health.ps1                              2.53s
  [PASS]  t02_guarded_commit.ps1                      3.07s
  [PASS]  t03_canonicalization.ps1                    62.25s
  [PASS]  t04_mmr_epoch.ps1                          227.81s
  [PASS]  t05_verification.ps1                       192.84s
  [PASS]  t06_inclusion_proofs.ps1                    65.80s
  [PASS]  t07_evidence_bundle.ps1                     77.79s
  [PASS]  t08_multiorg_isolation.ps1                 124.62s
  [PASS]  t09_devmode.ps1                             67.90s
  [PASS]  t10_determinism.ps1                         64.20s
  [PASS]  t11_powershell_scripts.ps1                   0.41s

  11 / 11 suites passed  |  total time: 889s

  ALL INVARIANTS SATISFIED
```

| Suite | What It Validates |
|-------|-------------------|
| T01 | Health endpoint, DB connectivity |
| T02 | Propose→approve→commit pipeline, reject path, HTTP 4xx on bad commit |
| T03 | Canonical JSON key-order stability, SHA-256 tamper detection |
| T04 | MMR epoch finalization at exactly BLOCK_SIZE, partial epoch safety, multi-epoch chain linkage |
| T05 | Clean verification, event tamper detection, epoch hash tamper detection |
| T06 | Inclusion proof structure, leaf hash consistency, 404 on unknown event |
| T07 | JSON bundle fields and self-checksum, PDF bundle generation |
| T08 | Per-org cryptographic isolation — tampering org A does not affect org B |
| T09 | DEV_MODE tamper/reset endpoints |
| T10 | Monotonic seq constraints, deterministic canonicalization, deterministic epoch hashing |
| T11 | All workflow scripts present and non-empty |

---

## Experiments

Five reproducible MMR-specific experiments demonstrate the ledger's cryptographic guarantees end-to-end.

**Requires:**

- Running server
- `BLOCK_SIZE=2`
- `DEV_MODE=true`

`experiment` mode is required for reproducible experiment results because it sets `BLOCK_SIZE=2`, ensuring immediate epoch finalization and proof availability.

```powershell
.\scripts\switch_env.ps1 -mode experiment
.\scripts\run_server.ps1
```

Then (in a separate terminal):

```powershell
.\scripts\run_all_experiments.ps1
```

| Experiment | Demonstrates |
|------------|-------------|
| EXP-01 — Clean Commit | Full pipeline from proposal to verified MMR root |
| EXP-02 — Event Tamper | Direct DB mutation detected by leaf integrity check |
| EXP-03 — Epoch Tamper | Epoch hash corruption detected by chain verification |
| EXP-04 — Multi-Org Isolation | Two orgs, one tampered — the other unaffected |
| EXP-05 — Guarded Commit | Policy engine blocking high-risk actions |

---

## Evidence Bundles

Every organization can produce a cryptographically signed evidence bundle:

```powershell
# JSON bundle (machine-readable, self-checksummed)
Invoke-RestMethod -Uri "http://localhost:8000/evidence/my-org" -Method GET

# PDF bundle (human-readable, audit/legal submission)
Invoke-WebRequest -Uri "http://localhost:8000/evidence/my-org/pdf" `
  -Method GET -OutFile "evidence.pdf" -UseBasicParsing
```

The JSON bundle includes:

- **summary** — org_id, ledger_version, hash_alg, block_size, ok, bundle_sha256
- **epochs** — full epoch chain with mmr_root, epoch_hash, prev_epoch_hash
- **last_20_events** — most recent committed events with leaf hashes
- **proof_example** — MMR inclusion proof for a sample event
- **last_20_staged** — audit trail of all policy decisions

The `bundle_sha256` field is a SHA-256 hash of the entire bundle excluding itself — a self-integrity check.

---

## Inclusion Proofs

Any single event can be verified against the MMR root without replaying the full ledger:

```
GET /proof/{org_id}/{event_id}

{
  "event_id":   "abc123...",
  "epoch_id":   0,
  "leaf_hash":  "sha256...",
  "mmr_root":   "sha256...",
  "proof_path": [{"hash": "sha256...", "side": "right"}, ...],
  "epoch_hash": "sha256..."
}
```

**To verify:** hash the leaf, walk the proof path, compare to `mmr_root`. If they match, the event was in the ledger at the time the epoch was sealed.

Verification complexity is **O(log n)** — approximately log₂(n) hash operations (≈14 for ~10,000 events), compared to 10,000 operations for a simple hash chain.

---

## Project Structure

```
licitra-mmr-core/
│
├── app/                                # Core ledger service
│   ├── __init__.py
│   ├── main.py                        # FastAPI application, router registration
│   ├── database.py                    # PostgreSQL connection and session management
│   ├── models.py                      # SQLAlchemy ORM: Event, Epoch, MmrNode, StagedEvent
│   ├── mmr.py                         # MMR append, proof generation, root computation
│   ├── canon.py                       # Canonical JSON serialization (sorted keys, no whitespace)
│   ├── hashing.py                     # SHA-256 leaf and epoch hash functions
│   ├── pipeline.py                    # Two-phase commit pipeline (propose → commit)
│   ├── policy.py                      # Policy engine: hard rules + risk scorer
│   ├── verify.py                      # Full chain verification (events + epochs + MMR)
│   ├── evidence.py                    # JSON + PDF evidence bundle generation
│   ├── config.py                      # BLOCK_SIZE, GENESIS_HASH, LEDGER_VERSION
│   └── routers/                       # API route handlers
│       ├── __init__.py
│       ├── agent.py                   # /agent/propose, /agent/commit endpoints
│       ├── query.py                   # /verify, /evidence, /proof endpoints
│       └── dev.py                     # DEV_MODE tamper/reset endpoints
│
├── tests/                              # 11 reproducible test suites
│   ├── run_all_tests.ps1              # Run full test suite
│   ├── _common.ps1                    # Shared helpers: Invoke-Api, Commit-N, Pass/Fail
│   ├── __init__.py
│   ├── t01_health.ps1                 # Health endpoint + DB connectivity
│   ├── t02_guarded_commit.ps1         # Two-phase commit pipeline tests
│   ├── t03_canonicalization.ps1       # Canonical JSON stability + tamper detection
│   ├── t04_mmr_epoch.ps1             # Epoch finalization + chain linkage
│   ├── t05_verification.ps1           # Chain verification + tamper detection
│   ├── t06_inclusion_proofs.ps1       # MMR inclusion proof validation
│   ├── t07_evidence_bundle.ps1        # JSON/PDF bundle generation + checksum
│   ├── t08_multiorg_isolation.ps1     # Per-org cryptographic isolation
│   ├── t09_devmode.ps1                # DEV_MODE tamper/reset endpoints
│   ├── t10_determinism.ps1            # Deterministic hashing invariants
│   └── t11_powershell_scripts.ps1     # Script presence validation
│
├── demo/                               # Pre-generated evidence bundles used for demonstration and verification examples
│   ├── evidence_org-big.json          # Large-scale evidence bundle (JSON)
│   ├── evidence_org-big.pdf           # Large-scale evidence bundle (PDF)
│   ├── evidence_org1.json             # Org 1 evidence (JSON)
│   ├── evidence_org1.pdf              # Org 1 evidence (PDF)
│   ├── evidence_org2.json             # Org 2 evidence (JSON)
│   ├── evidence_org2.pdf              # Org 2 evidence (PDF)
│   ├── S01_S02_exp_org1.*             # Experiment 1-2 artifacts
│   ├── S03_exp_org3.*                 # Experiment 3 artifacts
│   ├── S04_exp_org4a.*, S04_exp_org4b.*  # Experiment 4 artifacts (multi-org)
│   └── S05_exp_org5.*                 # Experiment 5 artifacts
│
├── paper/                              # Research artifacts
│   ├── licitra_mmr_TR-2026-01_v0.2.tex    # Technical report (LaTeX source)
│   └── licitra_mmr_TR-2026-01_v0.2.pdf    # Technical report (compiled PDF)
│
├── migrations/                         # Database migration scripts
│
├── scripts/                            # Operational scripts
│   ├── run_server.ps1                 # Start FastAPI server
│   ├── run_all_experiments.ps1        # Run all 5 experiments
│   ├── run_demo_2org.ps1              # Demo: two-org scenario
│   ├── run_demo_big.ps1              # Demo: large-scale ingestion
│   ├── export_artifacts.ps1           # Export evidence artifacts
│   └── switch_env.ps1                 # Switch between default/test/experiment mode
│
├── experiments/                        # Experiment scripts
│   └── powershell/
│       ├── exp1_clean_commit.ps1      # Experiment 1: Full pipeline to verified root
│       ├── exp2_event_tamper.ps1      # Experiment 2: Direct DB mutation detection
│       ├── exp3_epoch_tamper.ps1      # Experiment 3: Epoch hash corruption detection
│       ├── exp4_multiorg_isolation.ps1 # Experiment 4: Cross-org isolation proof
│       └── exp5_guarded_commit.ps1    # Experiment 5: Policy engine blocking
│
├── CANONICAL_JSON_SPEC.md             # Canonical JSON serialization specification
├── DESIGN_DECISIONS.md                # Architecture rationale document
├── SECURITY.md                        # Security policy and vulnerability disclosure
├── requirements.txt                   # Python dependencies
├── .env                               # Active configuration (generated by switch_env.ps1)
├── .env.default                       # Default mode template (BLOCK_SIZE=1000, DEV_MODE=false)
├── .env.test                          # Test mode template (BLOCK_SIZE=1000, DEV_MODE=true)
├── .env.experiment                    # Experiment mode template (BLOCK_SIZE=2, DEV_MODE=true)
├── .gitignore
├── .gitattributes
├── README.md                          # This file
└── LICENSE                            # MIT License
```

---

## Design Decisions

### Why MMR instead of a simple hash chain?

A Merkle Mountain Range supports **inclusion proofs** — you can prove a single event was in the ledger without replaying the entire history. A simple chain does not. For ~10,000 events, verification requires approximately log₂(n) hash operations (≈14) instead of replaying all 10,000 events.

### Why epoch-based anchoring instead of per-event epochs?

Per-event epochs would create one DB row per event — expensive at scale. Epoch batching at `BLOCK_SIZE=1000` amortizes the cost while maintaining strong tamper detection: any modification within a 1,000-event window is detected when that epoch is next verified.

### Why canonical JSON instead of a binary format?

Human-readable audit trails. A grant reviewer, judge, or regulator can inspect the `canonical_json` field directly and understand what the agent did without specialized tooling.

### Why two-phase commit?

Rejected proposals are as important as accepted ones. Knowing that an agent attempted a dangerous action — and was blocked — is essential context for post-incident forensics.

---

## Citation

If you use LICITRA-MMR in research, please cite:

```bibtex
@misc{nutalapati_licitra_mmr_2026,
  author = {Narendra Kumar Nutalapati},
  title = {LICITRA-MMR: A Merkle Mountain Range Ledger Primitive for Cryptographic Runtime Accountability in Agentic AI Systems},
  year = {2026},
  doi = {10.5281/zenodo.18843032},
  url = {https://github.com/narendrakumarnutalapati/licitra-mmr-core}
}
```

---

## References

- [LICITRA-MMR Technical Report](https://doi.org/10.5281/zenodo.18843032)
- [LICITRA-SENTRY v0.2 Technical Report](https://doi.org/10.5281/zenodo.18860290)
- [LICITRA-SENTRY v0.1 Technical Report](https://doi.org/10.5281/zenodo.18843784)
- [OWASP Top 10 for Agentic Applications (2026)](https://genai.owasp.org/resource/owasp-top-10-for-agentic-applications-for-2026/)

---

## License

[MIT License](LICENSE)

## Author

**Narendra Kumar Nutalapati**
- GitHub: [narendrakumarnutalapati](https://github.com/narendrakumarnutalapati)
- LinkedIn: [narendralicitra](https://linkedin.com/in/narendralicitra)
