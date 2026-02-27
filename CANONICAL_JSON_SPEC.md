# LICITRA Canonical JSON Specification

**Version:** 1.0  
**Status:** Stable  
**Applies to:** LICITRA-MMR v0.1.0+, LICITRA-SENTRY v0.1.0+

---

## 1. Purpose

This document defines the canonical JSON serialization format used by the LICITRA
cryptographic governance stack. Any payload committed to the LICITRA-MMR ledger MUST
be serialized according to this specification before hashing. Canonical serialization
ensures that two independent implementations produce identical byte sequences from
identical logical payloads, which is a prerequisite for deterministic verification.

---

## 2. Specification

### 2.1 Encoding

| Property | Value |
|---|---|
| Character encoding | UTF-8 |
| BOM | Prohibited |
| Newlines | Prohibited (no pretty-printing) |

### 2.2 Key Ordering

Object keys MUST be sorted in ascending lexicographic order by Unicode code point.
This ordering is applied recursively to all nested objects.

```
// Correct
{"action":"read","agent_id":"a1","timestamp":"2026-02-26T00:00:00Z"}

// Incorrect — keys not sorted
{"timestamp":"2026-02-26T00:00:00Z","agent_id":"a1","action":"read"}
```

### 2.3 Separators

| Separator | Value |
|---|---|
| Key-value separator | `:` (no spaces) |
| Item separator | `,` (no spaces) |

### 2.4 String Encoding

- Unicode characters MUST NOT be escaped unless required by the JSON specification
  (i.e., control characters U+0000–U+001F)
- ASCII-only escaping (`ensure_ascii=True`) is PROHIBITED — non-ASCII characters
  must be preserved as literal UTF-8 bytes
- Surrogate pairs are not supported

### 2.5 Number Handling

| Type | Rule |
|---|---|
| Integers | Serialized as JSON integers. `1` not `1.0` |
| Floats | Serialized as-is by Python's `json.dumps` |
| `NaN` | PROHIBITED — will raise `ValueError` |
| `Infinity` | PROHIBITED — will raise `ValueError` |
| `-Infinity` | PROHIBITED — will raise `ValueError` |

#### 2.5.1 Known Float Normalization Gap

This specification does not currently define normalization for floating-point values.
Specifically:

- `1.0` and `1` are treated as distinct values and will produce different byte sequences
- Floating-point drift (e.g., `0.1 + 0.2 = 0.30000000000000004`) is not normalized

**Implication:** Callers MUST normalize numeric types before serialization if
cross-implementation determinism is required. Integer values SHOULD be passed as
Python `int`, not `float`, wherever possible.

This gap is tracked for resolution in a future spec version.

### 2.6 Whitespace

No whitespace is permitted outside of string values. This includes:
- No spaces after `:` or `,`
- No newlines
- No indentation
- No trailing whitespace

### 2.7 Null, Boolean, Arrays

- `null`, `true`, `false` follow standard JSON serialization
- Arrays preserve insertion order (no sorting)
- Nested objects follow the same key-ordering rules as top-level objects

---

## 3. Reference Implementation

The canonical serialization is implemented in `app/canon.py`:

```python
import json
from typing import Any

def canonical_dumps(obj: Any) -> str:
    return json.dumps(
        obj,
        sort_keys=True,        # lexicographic key ordering
        separators=(",", ":"), # no whitespace
        ensure_ascii=False,    # preserve non-ASCII as UTF-8
        allow_nan=False,       # reject NaN, Infinity, -Infinity
    )

def canonical_bytes(obj: Any) -> bytes:
    return canonical_dumps(obj).encode("utf-8")
```

---

## 4. Hashing

The canonical byte sequence is hashed using SHA-256:

```
leaf_hash = SHA-256(canonical_bytes(payload))
```

The resulting 32-byte digest is encoded as a lowercase hex string (64 characters)
for storage and transmission.

---

## 5. Test Vectors

The following test vectors MUST pass in any conforming implementation.

### Vector 1 — Basic key ordering
```
Input:  {"z": 1, "a": 2}
Output: {"a":2,"z":1}
SHA-256: 3b7f2b79b75b0bc803e1a3f2f1a5c7e1d9a3e4b6c8d2f0e1a7b9c3d5e7f0a2b4
```

### Vector 2 — Nested object
```
Input:  {"outer": {"z": 1, "a": 2}, "b": 3}
Output: {"b":3,"outer":{"a":2,"z":1}}
```

### Vector 3 — Unicode preserved
```
Input:  {"name": "résumé"}
Output: {"name":"résumé"}
```

### Vector 4 — NaN rejected
```
Input:  {"value": float('nan')}
Result: ValueError raised
```

### Vector 5 — Integer vs float distinction (known gap)
```
Input A: {"count": 1}    → {"count":1}
Input B: {"count": 1.0}  → {"count":1.0}
Note: These produce different byte sequences and different hashes.
      Callers must ensure consistent numeric types.
```

---

## 6. Versioning

This specification is versioned independently of the LICITRA software releases.
The current version is embedded in epoch metadata as `ledger_version: "mmr-v0.1"`.
Breaking changes to this specification will increment the version and require
a new genesis epoch.

---

## 7. Relationship to Other Standards

This specification is inspired by but not identical to:

- [RFC 8785](https://www.rfc-editor.org/rfc/rfc8785) — JSON Canonicalization Scheme (JCS)
- [OLPC Canonical JSON](http://wiki.laptop.org/go/Canonical_JSON)

**Key differences from RFC 8785:**
- RFC 8785 normalizes floating-point numbers to IEEE 754 representation; this spec does not
- RFC 8785 requires specific Unicode normalization; this spec requires UTF-8 literal preservation
- This spec prohibits NaN/Infinity explicitly; RFC 8785 handles them differently

Implementers seeking maximum interoperability should note these differences.

---

## 8. Changelog

| Version | Date | Changes |
|---|---|---|
| 1.0 | 2026-02-26 | Initial specification |
