from datetime import datetime, timezone
from sqlalchemy import (
    BigInteger, Column, Float, Index, Integer, String,
    Text, UniqueConstraint, DateTime, Enum as SAEnum,
)
import enum
from app.database import Base


class StagedStatus(str, enum.Enum):
    PENDING  = "PENDING"
    APPROVED = "APPROVED"
    REJECTED = "REJECTED"


class StagedEvent(Base):
    __tablename__ = "staged_events"

    id              = Column(Integer, primary_key=True, autoincrement=True)
    org_id          = Column(String(128), nullable=False, index=True)
    agent_id        = Column(String(128), nullable=False)
    proposed_json   = Column(Text, nullable=False)
    status          = Column(SAEnum(StagedStatus), nullable=False, default=StagedStatus.PENDING)
    decision_reason = Column(Text, nullable=True)
    risk_score      = Column(Float, nullable=True)
    policy_version  = Column(String(32), nullable=False)
    created_at      = Column(DateTime(timezone=True), nullable=False,
                             default=lambda: datetime.now(timezone.utc))


class Event(Base):
    __tablename__ = "events"

    id             = Column(Integer, primary_key=True, autoincrement=True)
    org_id         = Column(String(128), nullable=False, index=True)
    event_id       = Column(String(128), nullable=False)
    seq            = Column(BigInteger, nullable=False)
    canonical_json = Column(Text, nullable=False)
    leaf_hash      = Column(String(64), nullable=False)
    epoch_id       = Column(Integer, nullable=False)
    created_at     = Column(DateTime(timezone=True), nullable=False,
                            default=lambda: datetime.now(timezone.utc))

    __table_args__ = (
        UniqueConstraint("org_id", "event_id", name="uq_events_org_event"),
        UniqueConstraint("org_id", "seq",      name="uq_events_org_seq"),
        Index("ix_events_org_epoch", "org_id", "epoch_id"),
    )


class Epoch(Base):
    __tablename__ = "epochs"

    id              = Column(Integer, primary_key=True, autoincrement=True)
    org_id          = Column(String(128), nullable=False, index=True)
    epoch_id        = Column(Integer, nullable=False)
    start_seq       = Column(BigInteger, nullable=False)
    end_seq         = Column(BigInteger, nullable=False)
    mmr_root        = Column(String(64), nullable=False)
    prev_epoch_hash = Column(String(64), nullable=False)
    epoch_hash      = Column(String(64), nullable=False)
    event_count     = Column(Integer, nullable=False)
    created_at      = Column(DateTime(timezone=True), nullable=False,
                             default=lambda: datetime.now(timezone.utc))

    __table_args__ = (
        UniqueConstraint("org_id", "epoch_id", name="uq_epochs_org_epoch"),
    )


class MmrNode(Base):
    __tablename__ = "mmr_nodes"

    id        = Column(Integer, primary_key=True, autoincrement=True)
    org_id    = Column(String(128), nullable=False)
    epoch_id  = Column(Integer, nullable=False)
    position  = Column(Integer, nullable=False)
    node_hash = Column(String(64), nullable=False)

    __table_args__ = (
        UniqueConstraint("org_id", "epoch_id", "position", name="uq_mmr_nodes"),
        Index("ix_mmr_nodes_org_epoch", "org_id", "epoch_id"),
    )
