# LICITRA-MMR Design Decisions

This document records the key architectural decisions made during the design
of LICITRA-MMR, including the rationale for each choice and the alternatives
that were considered and rejected. It is intended to serve as a reference for
contributors, reviewers, and the arXiv paper that describes this system.

---

## 1. Why Merkle Mountain Range instead of a standard Merkle tree?

**Decision:** Use an MMR (append-only forest of perfect binary trees) rather
than a standard balanced Merkle tree.

**Rationale:**

A standard Merkle tree requires rebalancing on insertion. When a new leaf is
added to a balanced tree, internal node hashes must be recomputed along the
path from the new leaf to the root, and in some implementations the entire
tree must be restructured. This means that inserting a new event modifies
existing nodes — a property that is incompatible with an append-only audit
log, where the integrity guarantee depends on the immutability of committed
records.

An MMR is strictly append-only. New leaves and their parent nodes are added
without modifying any existing node. The 2025 CRYPTO paper by Bonneau, Chen,
Christ, and Karantaidou formally proves that a close variant of the MMR is
essentially optimal among all append-only accumulators with succinct
commitments (ePrint 2025/234). This provides formal justification for the
choice beyond practical convenience.

At the default BLOCK_SIZE of 1,000 events, the MMR produces inclusion proofs
requiring 14 SHA-256 operations — a logarithmic proof path with no
rebalancing overhead.

**Alternatives considered:**

- Standard balanced Merkle tree: rejected due to rebalancing requirement
- Linear hash chain: rejected because it has no inclusion proof capability —
  a verifier must replay the entire chain to verify any single event
- Skip list: rejected due to implementation complexity and lack of formal
  security analysis in the accumulator setting

---

## 2. Why not use Certificate Transparency–style logs?

**Decision:** Use a per-organization epoch-anchored MMR rather than a
CT-style globally auditable log with gossip-based consistency.

**Rationale:**

Certificate Transparency logs solve a different problem: proving that a TLS
certificate exists in a publicly auditable log maintained by multiple
independent operators. The CT trust model requires external log operators,
a gossip protocol for consistency across operators, and a globally shared
namespace. This overhead is appropriate for PKI but is not necessary or
desirable for per-organization agentic AI audit logs.

LICITRA-MMR is designed for a single organization auditing its own agents.
The verifier (an internal auditor, a regulator, or a legal counsel) needs
to verify that the organization's own records were not tampered with after
the fact — not that the records appear in a global public log. The epoch
anchoring chain provides this guarantee without external infrastructure.

**Practical differences:**

- CT requires at least two independent log operators for a certificate to
  be considered logged; LICITRA-MMR has no such requirement
- CT gossip protocol adds latency and operational complexity not justified
  for high-frequency per-org event streams
- CT has no concept of epoch chaining or per-organization namespacing

**Future work:** Multi-party witnessing — where multiple independent
operators each hold a copy of the current epoch hash — is a planned
extension that would bring CT-style trust model benefits without the
full CT infrastructure overhead.

---

## 3. Why not sign epoch roots with Ed25519?

**Decision:** Compute epoch hashes but do not sign them in v0.1. Epoch
signing is planned for v0.2.

**Rationale:**

Signing epoch roots with Ed25519 would strengthen the trust model by
cryptographically binding each epoch to a specific key holder. An external
auditor could then verify not just that the chain is intact, but that a
specific key signed off on each epoch — providing non-repudiation in
addition to tamper-evidence.

This feature was deliberately deferred from v0.1 for one reason: key
management. A signature is only meaningful if the signing key is managed
correctly. Introducing a signing key in an MVP creates several questions
that the v0.1 design intentionally avoids:

- Where is the private key stored? (HSM, KMS, file system?)
- Who has access to the private key?
- What happens if the key is rotated?
- How does a verifier obtain and trust the public key?

Each of these questions has a correct answer, but answering them requires
infrastructure decisions (key storage, rotation policy, public key
distribution) that would expand the scope of v0.1 significantly and
introduce attack surface before the core ledger semantics were validated.

The epoch record schema already reserves a `signature` field for this
purpose. The upgrade path from v0.1 to v0.2 is additive: add a signing
key, populate the `signature` field on epoch finalization, and add
signature verification to the audit path.

---

## 4. Why SHA-256 instead of BLAKE3?

**Decision:** Use SHA-256 (FIPS 180-4) for all hash operations rather than
BLAKE3 or SHA-3.

**Rationale:**

BLAKE3 is faster than SHA-256, especially on long inputs, and is
parallelizable in ways that SHA-256 is not. It has no known weaknesses and
is a well-designed modern hash function. For raw performance, BLAKE3 would
be a reasonable choice.

However, LICITRA-MMR is designed for compliance-oriented deployments of
high-risk AI systems under the EU AI Act and similar frameworks. In this
context, the choice of hash function is subject to regulatory scrutiny.
SHA-256 is:

- FIPS 180-4 compliant
- Referenced in NIST guidance for cryptographic systems
- Accepted by all major compliance frameworks without qualification
- Supported by OpenSSL on all major platforms via Python's `hashlib`

If a compliance auditor or regulator asks "is your hash function approved?",
SHA-256 has a one-word answer. BLAKE3 does not yet appear in FIPS guidance
or NIST-approved algorithm lists.

At the event rates typical of agentic AI systems (hundreds to thousands of
events per second per organization), the performance difference between
SHA-256 and BLAKE3 is negligible — the dominant cost is database I/O, not
hashing. The cryptographic overhead per commit is approximately 3 μs
regardless of which function is used.

**Upgrade path:** BLAKE3 is a reasonable choice for v1.0 if performance
profiling reveals hashing as a bottleneck in high-throughput deployments.
The hash function is isolated in `app/hashing.py` and can be swapped with
minimal changes to the rest of the codebase.

---

## 5. Why not use immudb instead of building a custom ledger?

**Decision:** Build a purpose-built MMR-based ledger rather than using
immudb as the storage layer.

**Rationale:**

immudb is a well-engineered, production-ready tamper-evident database. It
provides Merkle tree-based inclusion proofs, immutable audit logs, and
independent verification. For teams that need only tamper-evident storage,
immudb is a mature and well-supported option.

LICITRA-MMR is not a general-purpose tamper-evident store. It is an
agentic AI governance primitive with specific requirements that immudb
does not address:

**1. MMR structure with epoch anchoring.** immudb uses a Merkle tree over
a linear log, which does not support the epoch chaining model consistent
with regulatory audit requirements. Epoch anchoring creates
bounded verification windows that map cleanly to regulatory audit periods
(monthly, quarterly, annually). immudb has no equivalent concept.

**2. Canonical JSON specification.** Cross-implementation deterministic
verification requires that all implementations produce identical byte
sequences from identical logical payloads. immudb has no versioned
canonical serialization format. LICITRA-MMR's CANONICAL_JSON_SPEC v1.0
provides this guarantee explicitly.

**3. Pre-execution authorization layer.** LICITRA-MMR is the audit layer
of a broader governance stack. The LICITRA-SENTRY control plane adds
pre-execution semantic contracts, agent identity verification, and Chain
of Intent authorization — binding the decision record to a prior
authorization. immudb is a storage system with no concept of
pre-execution governance.

**4. Agentic AI framing and regulatory context.** LICITRA-MMR is
explicitly framed around EU AI Act Article 12, Colorado AI Act, and
OWASP Agentic Top 10. This framing shapes the API design, the evidence
bundle format, and the documentation. immudb is a general-purpose tool
with no regulatory framing.

**The honest version:** if you only need tamper-evident storage, use
immudb. LICITRA-MMR is for teams that need cryptographic accountability
for autonomous AI decision chains specifically, with a governance
architecture designed around that requirement.

---

## 6. Why PostgreSQL instead of SQLite or a dedicated ledger database?

**Decision:** Use PostgreSQL as the storage backend.

**Rationale:**

- PostgreSQL provides row-level locking that prevents race conditions in
  the `_next_seq()` function under concurrent agent workloads
- The `SELECT ... MAX(seq)` pattern used for sequence assignment requires
  serializable isolation that SQLite's WAL mode does not reliably provide
  under concurrent writes
- PostgreSQL is the standard choice for production Python/FastAPI deployments
- SQLite is acceptable for single-threaded testing but not for multi-agent
  concurrent workloads

**Note:** SQLite is used in the test suite for isolation and speed. The
application is tested against PostgreSQL in integration tests.

---

## 7. Why a two-phase commit pipeline (propose + commit) rather than direct insert?

**Decision:** Separate policy evaluation (propose) from cryptographic
commitment (commit) into two distinct phases.

**Rationale:**

A direct insert model would evaluate policy and commit to the MMR in a
single operation. This is simpler but creates an audit gap: rejected
proposals would not be recorded, and the ledger would only reflect
approved actions.

The two-phase model ensures that every agent decision — approved or
rejected — produces an auditable record. Rejected proposals create a
`StagedEvent` record with `status=REJECTED`. If `EMIT_BLOCKED_ACTION`
is enabled, a `blocked_action` audit event is also committed to the MMR,
making the rejection cryptographically tamper-evident alongside approved
actions.

This design is significant for audit purposes: an investigator reviewing
an incident wants to see not just what the agent did, but what it attempted
to do and was blocked from doing. The two-phase pipeline provides this
complete picture.

---

---

## 8. Architectural Non-Goals

The following properties are explicitly outside the scope of LICITRA-MMR.
These are not oversights — they are deliberate boundaries.

**Not a consensus system.** There is one writer (the application server)
and one ledger per organization. Consistency is enforced by database
transaction semantics, not a consensus protocol. The overhead of
consensus is not justified for a single-operator audit log.

**Not a blockchain.** The epoch chain is structurally similar to a
blockchain header chain but is not a blockchain. There is no proof of
work, no proof of stake, no token, no peer-to-peer network, and no
distributed ledger. It is a tamper-evident audit structure.

**Not Byzantine fault tolerant.** The system assumes the database
storage layer faithfully preserves byte-level fidelity of stored values.
It does not protect against a Byzantine storage layer that selectively
serves different values to different readers.

**Not preventing application-layer falsification.** LICITRA-MMR commits
whatever the application layer submits. If an agent or application server
is compromised before the commit pipeline is invoked, the ledger will
faithfully record false data. Pre-execution integrity is the scope of
LICITRA-SENTRY, not LICITRA-MMR. This is the fundamental architectural
boundary between the two components.

**Not availability-protecting.** LICITRA-MMR does not protect against
denial-of-service attacks, database unavailability, or network
partitions. Availability is the responsibility of the deployment
infrastructure.


*Last updated: 2026-02-26*  
*Applies to: LICITRA-MMR v0.1.0-mvp*
