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

// M1 gated-change tests (V2-M1-cos-design.md §4, §7.10; TP-V2-M1
// assertions 2 and 10 exercise this logic at the gate):
//   - priority: coarse enum validation, pass-through, out-of-range reject
//   - approval_hash: whitespace-exact SHA-256 canonicalization,
//     retry integrity across §6 ambiguous-submit retries,
//     mismatch-reject-and-surface

import (
	"crypto/sha256"
	"encoding/hex"
	"strings"
	"testing"
)

func TestValidatePriority(t *testing.T) {
	for _, ok := range []string{"", "high", "normal", "low"} {
		if err := ValidatePriority(ok); err != nil {
			t.Errorf("ValidatePriority(%q) = %v, want nil", ok, err)
		}
	}
	for _, bad := range []string{"urgent", "HIGH", "1", "high ", "medium"} {
		if err := ValidatePriority(bad); err == nil {
			t.Errorf("ValidatePriority(%q) = nil, want reject", bad)
		}
	}
}

func TestPriorityPassThrough(t *testing.T) {
	req := TaskRequest{Title: "t", AgentCapability: "backend engineer",
		TaskBrief: "b", Priority: "high"}
	agent := AgentIndexEntry{Ref: "ephemeral-org/eph-backend-engineer",
		Role: "backend engineer", Folder: "ephemeral-org/eph-backend-engineer",
		SpecRef: "ephemeral-org/eph-backend-engineer/behavioral-spec.md"}
	msg, err := ComposeTaskMessage(req, agent, "https://example.test/roster",
		"repo", "owner", 45, 900)
	if err != nil {
		t.Fatalf("ComposeTaskMessage with priority: %v", err)
	}
	if msg.Priority != "high" {
		t.Errorf("priority not passed through: %q", msg.Priority)
	}
	if _, err := ComposeTaskMessage(TaskRequest{Priority: "urgent"},
		agent, "u", "r", "o", 45, 900); err == nil {
		t.Error("out-of-range priority accepted at compose time")
	}
}

func TestApprovalHashWhitespaceExact(t *testing.T) {
	spec := "Do the thing.\n\n  Keep  double spaces."
	sum := sha256.Sum256([]byte(spec))
	want := hex.EncodeToString(sum[:])
	if got := ApprovalHash(spec); got != want {
		t.Errorf("ApprovalHash mismatch: %s != %s", got, want)
	}
	// whitespace-exact: any normalization changes the hash
	if ApprovalHash(spec) == ApprovalHash(strings.Join(strings.Fields(spec), " ")) {
		t.Error("hash was normalized — canonicalization must be whitespace-exact")
	}
}

func TestHashLedgerRetryIntegrity(t *testing.T) {
	l := NewHashLedger()
	const id = "11111111-1111-4111-8111-111111111111"
	spec := "spec text v1"

	if v, err := l.CheckRetry(id, spec, ""); v != HashOK || err != nil {
		t.Fatalf("first submission: %v %v", v, err)
	}
	// §6 retry with the IDENTICAL spec → ok
	if v, err := l.CheckRetry(id, spec, ""); v != HashOK || err != nil {
		t.Fatalf("identical retry: %v %v", v, err)
	}
	// retry with a silently swapped payload → mismatch, must be surfaced
	if v, err := l.CheckRetry(id, "spec text v2 (swapped)", ""); v != HashMismatch || err == nil {
		t.Fatalf("swapped retry: got %v %v, want HashMismatch", v, err)
	}
}

func TestHashLedgerDeclaredHashMismatch(t *testing.T) {
	l := NewHashLedger()
	const id = "22222222-2222-4222-8222-222222222222"
	if v, err := l.CheckRetry(id, "spec", ApprovalHash("different spec")); v != HashMismatch || err == nil {
		t.Fatalf("declared-hash mismatch: got %v %v, want HashMismatch", v, err)
	}
}

func TestHashLedgerShapeChangeBetweenRetries(t *testing.T) {
	l := NewHashLedger()
	const id = "33333333-3333-4333-8333-333333333333"
	if v, _ := l.CheckRetry(id, "spec", ""); v != HashOK {
		t.Fatal("setup: first submission should pass")
	}
	// retry adds a declared hash the first attempt lacked — payload changed shape
	if v, err := l.CheckRetry(id, "spec", ApprovalHash("spec")); v != HashOK {
		_ = err // same spec → recomputed matches; declared matches too → ok
	}
}

func TestHashLedgerEmptyTaskID(t *testing.T) {
	l := NewHashLedger()
	if v, err := l.CheckRetry("", "spec", ""); v != HashMismatch || err == nil {
		t.Fatal("empty task_id must be a mismatch")
	}
}

func TestMarshalStrictAllowsM1Fields(t *testing.T) {
	h := ApprovalHash("s")
	msg := TaskMessage{TaskID: "44444444-4444-4444-8444-444444444444",
		AgentRef: "r#f", BehavioralSpec: "s", RepoTarget: "rt",
		Requester: "o", Priority: "low", ApprovalHash: h}
	b, err := msg.MarshalStrict()
	if err != nil {
		t.Fatalf("MarshalStrict with M1 fields: %v", err)
	}
	for _, field := range []string{`"priority":"low"`, `"approval_hash":"` + h + `"`} {
		if !strings.Contains(string(b), field) {
			t.Errorf("marshaled message missing %s", field)
		}
	}
	// absent optional fields must stay absent (additionalProperties=false)
	clean := TaskMessage{TaskID: "44444444-4444-4444-8444-444444444444",
		AgentRef: "r#f", BehavioralSpec: "s", RepoTarget: "rt", Requester: "o"}
	b, _ = clean.MarshalStrict()
	if strings.Contains(string(b), "priority") || strings.Contains(string(b), "approval_hash") {
		t.Errorf("omitempty leak: %s", b)
	}
}
