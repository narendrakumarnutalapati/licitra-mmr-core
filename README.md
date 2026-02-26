# LICITRA-MMR

**Cryptographic runtime integrity layer for agentic AI systems.**

Every action an AI agent takes is committed to a tamper-evident ledger using a Merkle Mountain Range (MMR) — a structure borrowed from Bitcoin's Mimblewimble protocol. Any retroactive modification to any event, at any point in history, is cryptographically detectable.

[![Tests](https://img.shields.io/badge/tests-11%2F11%20passing-brightgreen)](./tests)
[![Python](https://img.shields.io/badge/python-3.12-blue)](https://python.org)
[![License](https://img.shields.io/badge/license-MIT-green)](./LICENSE)

---

## The Problem

Agentic AI systems act autonomously — browsing the web, writing code, calling APIs, managing files. There is currently no standard mechanism to prove, after the fact, that an agent did exactly what it claims to have done, and nothing more. Log files can be deleted. Databases can be edited. Timestamps can be forged.

LICITRA-MMR makes tampering **cryptographically detectable**, not just policy-prohibited.

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

Every 1,000 events (configurable via `BLOCK_SIZE`), the MMR is sealed into an **epoch**:

```
epoch_hash = SHA256(prev_epoch_hash || mmr_root || canonical_metadata)
```

Epochs chain together like blockchain blocks. Modifying epoch N breaks the hash of epoch N+1, N+2, and every subsequent epoch. The genesis epoch uses `prev_epoch_hash = "00" * 32`.

### 4. 2-Phase Commit Pipeline

No event enters the ledger without passing a policy check:

```
POST /agent/propose   →  policy engine evaluates risk
                      →  APPROVED or REJECTED (both recorded)
POST /agent/commit    →  only APPROVED proposals can be committed
```

Rejected proposals are retained in the staged events table — a permanent audit trail of what was attempted and why it was blocked.

### 5. Per-Org Isolation

Each organization has a completely independent MMR, epoch chain, and event sequence. Tampering with one org's ledger has zero effect on any other org's cryptographic state.

---

## Architecture

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

---

## API Reference

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET`  | `/health` | Service health + DB check |
| `POST` | `/agent/propose` | Submit action for policy evaluation |
| `POST` | `/agent/commit/{staged_id}` | Commit an APPROVED proposal |
| `GET`  | `/verify/{org_id}` | Full cryptographic verification |
| `GET`  | `/evidence/{org_id}` | JSON evidence bundle with self-checksum |
| `GET`  | `/evidence/{org_id}/pdf` | PDF evidence bundle for audit/legal |
| `GET`  | `/proof/{org_id}/{event_id}` | MMR inclusion proof for a single event |

**DEV_MODE only:**

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/tamper/{org_id}/{event_id}` | Corrupt a leaf (for experiment demos) |
| `POST` | `/tamper-epoch/{org_id}/{epoch_id}` | Corrupt an epoch hash |
| `POST` | `/dev/reset/{org_id}` | Wipe all data for an org |

---

## Quickstart

### Prerequisites

- Python 3.12
- PostgreSQL 16
- Windows (PowerShell) or Linux/macOS

### Setup

```powershell
git clone https://github.com/narendrakumarnutalapati/licitra-mmr-core
cd licitra-mmr-core

python -m venv .venv
.\.venv\Scripts\Activate.ps1          # Windows
# source .venv/bin/activate           # Linux/macOS

pip install -r requirements.txt
```

### Configure

Create `.env` in the project root:

```env
DATABASE_URL=postgresql://postgres:password@localhost:5432/licitra_mmr
DEV_MODE=true
BLOCK_SIZE=1000
```

### Run

```powershell
.\run_server.ps1
```

Or directly:

```powershell
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

Server starts at `http://localhost:8000`. API docs at `http://localhost:8000/docs`.

---

## Test Suite

11 independent test suites. Each is a standalone reproducible artifact.

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

| Suite | What it validates |
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

Five reproducible experiments demonstrate the system's cryptographic guarantees end-to-end.

```powershell
.\run_all_experiments.ps1
```

| Experiment | Demonstrates |
|------------|-------------|
| exp1 — Clean Commit | Full pipeline from proposal to verified MMR root |
| exp2 — Event Tamper | Direct DB mutation detected by leaf integrity check |
| exp3 — Epoch Tamper | Epoch hash corruption detected by chain verification |
| exp4 — Multi-Org Isolation | Two orgs, one tampered — the other unaffected |
| exp5 — Guarded Commit | Policy engine blocking high-risk actions |

---

## Evidence Bundles

Every org can produce a cryptographically signed evidence bundle:

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

To verify: hash the leaf, walk the proof path, compare to mmr_root. If they match, the event was in the ledger at the time the epoch was sealed.

---

## Project Layout

```
licitra-mmr-core/
├── app/
│   ├── main.py          # FastAPI app, router registration
│   ├── models.py        # SQLAlchemy ORM: Event, Epoch, MmrNode, StagedEvent
│   ├── mmr.py           # MMR append, proof generation, root computation
│   ├── canon.py         # Canonical JSON serialization
│   ├── hashing.py       # SHA-256 leaf and epoch hash functions
│   ├── pipeline.py      # 2-phase commit pipeline
│   ├── policy.py        # Policy engine: hard rules + risk scorer
│   ├── verify.py        # Full chain verification
│   ├── evidence.py      # JSON + PDF evidence bundle generation
│   └── config.py        # BLOCK_SIZE, GENESIS_HASH, LEDGER_VERSION
├── tests/
│   ├── _common.ps1      # Shared helpers: Invoke-Api, Commit-N, Pass/Fail
│   ├── t01_health.ps1
│   ├── t02_guarded_commit.ps1
│   ├── t03_canonicalization.ps1
│   ├── t04_mmr_epoch.ps1
│   ├── t05_verification.ps1
│   ├── t06_inclusion_proofs.ps1
│   ├── t07_evidence_bundle.ps1
│   ├── t08_multiorg_isolation.ps1
│   ├── t09_devmode.ps1
│   ├── t10_determinism.ps1
│   ├── t11_powershell_scripts.ps1
│   └── run_all_tests.ps1
├── exp1_clean_commit.ps1
├── exp2_event_tamper.ps1
├── exp3_epoch_tamper.ps1
├── exp4_multiorg_isolation.ps1
├── exp5_guarded_commit.ps1
├── run_all_experiments.ps1
├── run_demo_2org.ps1
├── run_demo_big.ps1
├── run_server.ps1
└── export_artifacts.ps1
```

---

## Design Decisions

**Why MMR instead of a simple hash chain?**
A Merkle Mountain Range supports *inclusion proofs* — you can prove a single event was in the ledger without replaying the entire history. A simple chain does not.

**Why epoch-based anchoring instead of per-event epochs?**
Per-event epochs would create one DB row per event — expensive at scale. Epoch batching at BLOCK_SIZE=1000 amortizes the cost while maintaining strong tamper detection: any modification within a 1,000-event window is detected when that epoch is next verified.

**Why canonical JSON instead of a binary format?**
Human-readable audit trails. A grant reviewer, judge, or regulator can inspect the canonical_json field directly and understand what the agent did without specialized tooling.

**Why 2-phase commit?**
Rejected proposals are as important as accepted ones. Knowing that an agent *attempted* a dangerous action — and was blocked — is essential context for post-incident forensics.

---

## License

MIT
