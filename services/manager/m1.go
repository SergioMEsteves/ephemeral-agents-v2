// Copyright 2026 A&R Visual Development Inc (arvisdev)
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package main

// M1 manager changes (V2-M1-cos-design.md §4, individually gated):
//
// 1. The `priority` field (OQ1/OQ4, lands WITH M1): coarse enum
//    high|normal|low, additive-optional in message-v1. The manager
//    validates and passes it through; out-of-range values are REJECTED
//    and the declared value is surfaced to the operator log (the broker
//    applies its own x-max-priority semantics — the manager never talks
//    to the broker directly; D8).
//
// 2. Approval-hash verification (TP-V2-M1 assertion 10, tamper-evidence
//    not tamper-prevention): the submitted package may carry
//    `approval_hash` — SHA-256 over the UTF-8 behavioral_spec,
//    whitespace-exact (canonicalization fixed here, not configurable).
//    At M1 the manager enforces exactly two checks:
//      - retry integrity: the same task_id must carry an IDENTICAL spec
//        hash across the §6 ambiguous-submit retries — the payload
//        cannot be silently swapped between attempts;
//      - mismatch-reject-and-surface: a non-matching payload is rejected
//        and reported to the owner, never silently accepted.
//    The honest limit (§7.10): the CoS supplies both spec and hash, so
//    the hash cannot prove the spec matches what the owner approved —
//    it is tamper-evidence for post-hoc audit. The gateway-side
//    approval-registration change (owner-sourced pin) is a later,
//    separately-gated milestone.

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"sync"
)

// PriorityEnum is the OQ1 coarse priority encoding (manager rejects
// out-of-range values; the declared value is logged, never coerced).
var PriorityEnum = map[string]bool{
	"high":   true,
	"normal": true,
	"low":    true,
}

// ValidatePriority returns an error for any value outside the coarse
// enum. Empty is valid (the field is additive-optional).
func ValidatePriority(p string) error {
	if p == "" || PriorityEnum[p] {
		return nil
	}
	return fmt.Errorf("priority %q outside the coarse enum (high|normal|low) — reject", p)
}

// ApprovalHash computes the message-v1 `approval_hash`: SHA-256 over the
// UTF-8 bytes of the behavioral_spec, whitespace-exact. The
// canonicalization is fixed: no trimming, no normalization, no JSON
// re-encoding — byte-for-byte what the approval covered.
func ApprovalHash(behavioralSpec string) string {
	sum := sha256.Sum256([]byte(behavioralSpec))
	return hex.EncodeToString(sum[:])
}

// HashVerdict is the outcome of a ledger check.
type HashVerdict int

const (
	HashOK HashVerdict = iota // accepted; recorded
	HashMismatch              // retry integrity violated — reject and surface
)

// HashLedger records the first-seen approval_hash per task_id and enforces
// retry integrity across the §6 ambiguous-submit retries. Concurrency-safe
// (the manager serves the API and the response consumer concurrently).
type HashLedger struct {
	mu     sync.Mutex
	byTask map[string]string
}

func NewHashLedger() *HashLedger {
	return &HashLedger{byTask: make(map[string]string)}
}

// CheckRetry verifies a submission's hash against the ledger:
//
//   - first sight of a task_id with a non-empty hash → record, HashOK.
//   - repeat task_id (a §6 retry) → the recomputed hash must equal the
//     recorded one (identical spec across attempts); a difference is a
//     HashMismatch: the caller must reject and surface to the owner.
//   - a task_id whose first submission carried no hash but a retry does
//     (or vice versa) is also a mismatch — the payload changed shape
//     between attempts, which is exactly what retry integrity forbids.
//
// The empty-spec + empty-hash case for a brand-new task_id is the V1
// behavior (no approval_hash present) and is HashOK — the hash is
// additive-optional in message-v1.
func (l *HashLedger) CheckRetry(taskID, behavioralSpec, declaredHash string) (HashVerdict, error) {
	if taskID == "" {
		return HashMismatch, fmt.Errorf("retry-integrity check on empty task_id — reject")
	}
	recomputed := ApprovalHash(behavioralSpec)
	if declaredHash != "" && declaredHash != recomputed {
		return HashMismatch, fmt.Errorf(
			"declared approval_hash does not match the spec for task %s: declared %s, computed %s — REJECT and surface to owner",
			taskID, declaredHash, recomputed)
	}
	l.mu.Lock()
	defer l.mu.Unlock()
	seen, exists := l.byTask[taskID]
	if !exists {
		l.byTask[taskID] = recomputed
		return HashOK, nil
	}
	if seen != recomputed {
		return HashMismatch, fmt.Errorf(
			"approval_hash retry-integrity violation for task %s: recorded %s, this attempt %s — payload swapped between retries; REJECT and surface to owner",
			taskID, seen, recomputed)
	}
	if declaredHash != "" && declaredHash != recomputed {
		return HashMismatch, fmt.Errorf(
			"declared approval_hash does not match the spec for task %s: declared %s, computed %s — REJECT and surface to owner",
			taskID, declaredHash, recomputed)
	}
	return HashOK, nil
}
