import hashlib
from typing import Union


def sha256_bytes(data: bytes) -> bytes:
    return hashlib.sha256(data).digest()


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def hash_leaf(canonical_json_bytes: bytes) -> str:
    return sha256_hex(canonical_json_bytes)


def hash_node(left_hex: str, right_hex: str) -> str:
    left  = bytes.fromhex(left_hex)
    right = bytes.fromhex(right_hex)
    return sha256_hex(left + right)


def hash_epoch(prev_epoch_hash_hex: str, mmr_root_hex: str, metadata_bytes: bytes) -> str:
    prev     = bytes.fromhex(prev_epoch_hash_hex)
    root     = bytes.fromhex(mmr_root_hex)
    meta     = sha256_bytes(metadata_bytes)
    return sha256_hex(prev + root + meta)
