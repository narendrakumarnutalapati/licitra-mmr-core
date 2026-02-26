# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| v0.1.x (current) | ✅ Active |

---

## Reporting a Vulnerability

If you discover a security vulnerability in LICITRA-MMR, please **do not open a public GitHub issue**. Public disclosure before a fix is available could put users at risk.

### How to report

Email: **narendrakumarnutalapati@gmail.com**  
Subject line: `[SECURITY] LICITRA-MMR — <brief description>`

Please include:
- A description of the vulnerability
- The component affected (`app/mmr.py`, `app/pipeline.py`, `app/policy.py`, etc.)
- Steps to reproduce
- Potential impact (what an attacker could do)
- Your suggested fix, if any

### What to expect

| Timeline | Action |
|----------|--------|
| Within 48 hours | Acknowledgement of your report |
| Within 7 days | Initial assessment and severity classification |
| Within 30 days | Fix developed and tested |
| Within 45 days | Patched release published and CVE filed if applicable |

You will be credited in the release notes unless you request otherwise.

---

## Scope

The following are **in scope** for security reports:

- **Cryptographic integrity bypass** — any method that allows a tampered event or epoch to pass verification
- **Policy engine bypass** — any method that allows a REJECTED proposal to be committed
- **Per-org isolation breach** — any method that allows one org's data to affect another org's MMR state
- **Authentication/authorization flaws** — in DEV_MODE endpoint protection
- **SQL injection or ORM bypass** — in any endpoint
- **Denial of service** — via malformed payloads that crash the service
- **Evidence bundle integrity** — any method that produces a bundle with a valid `bundle_sha256` despite tampered content

The following are **out of scope**:

- Vulnerabilities in third-party dependencies (report those upstream)
- Issues that require physical access to the database server
- Social engineering
- DEV_MODE endpoints behaving as designed (they are intentionally destructive)

---

## Cryptographic Design

LICITRA-MMR makes the following explicit cryptographic commitments. A report demonstrating that any of these can be violated without detection is considered **critical severity**:

1. **Leaf integrity** — modifying `canonical_json` after commit changes `leaf_hash`, which is detected on next `GET /verify/{org_id}`
2. **MMR root integrity** — modifying any MMR node changes the root, which is recomputed and compared on verification
3. **Epoch hash chain** — modifying any epoch's `epoch_hash` breaks the chain from that epoch forward
4. **Cross-org isolation** — events, MMR nodes, and epochs are partitioned by `org_id` at the DB level; no query crosses org boundaries

---

## Security Architecture Notes

- All hashing uses **SHA-256** via Python's `hashlib` — no custom cryptography
- Canonical JSON serialization uses **sorted keys + no whitespace** — deterministic across all inputs
- The genesis epoch uses `prev_epoch_hash = "00" * 32` as a well-known sentinel
- `DEV_MODE=true` enables destructive endpoints (`/tamper`, `/dev/reset`) — **never run with DEV_MODE=true in production**
- Database credentials are loaded from environment variables via `.env` — never hardcoded

---

## Disclosure Policy

We follow **coordinated disclosure**:

1. Reporter submits privately
2. We confirm and assess within 48 hours
3. We develop and test a fix
4. We publish the fix and credit the reporter
5. Reporter may publish their findings after the fix is live

We will not pursue legal action against researchers who follow this policy in good faith.
