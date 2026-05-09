---
kind: contract
contract_version: "3.0"
status: Archived
superseded_by: review-verdict-v4
related_plugins:
  - codeforge (wrapper, consumer of FIX routing data + Orchestrator self-write post-Sonnet)
  - codeforge-review (lane plugin, producer + synthesizer; final gate write authority transferred to Orchestrator per CFP-61)
related_adrs:
  - ADR-001 (review-agent-unification — lane-agnostic worker)
  - ADR-008 (Inter-plugin Contract Versioning)
  - ADR-010 (Inter-plugin Contract Sibling Sync)
  - ADR-022 (carrier — Sonnet review-verdict decider + consumer scope, in plugin-codeforge wrapper repo) [Deprecated 2026-05-08, CFP-134]
  - ADR-035 (codeforge agent teams Epic architecture — D1 ADR-022 deprecate, in plugin-codeforge wrapper repo)
  - ADR-044 (Phase-scoped sequential team SSOT — review-verdict v4 cutover carrier, CFP-137, in plugin-codeforge wrapper repo)
authors:
  - CFP-61 Phase 1B-1 — review-verdict v2 → v3 BREAKING (Sonnet decider trigger 5 introduction)
  - CFP-135 (2026-05-08) — DEPRECATED PASSTHROUGH annotation (ADR-022 deprecate consequence, sibling-backfill from wrapper)
  - CFP-137 (2026-05-09) — Archived (review-verdict v4 cutover, Sonnet decider 영역 정식 제거; canonical sibling sync from wrapper PR #284)
---

> **ARCHIVED (2026-05-09, CFP-137 / ADR-044)**: 본 contract 가 [review-verdict v4](review-verdict-v4.md) 으로 superseded 됨. v4 가 v3 의 NO-OP passthrough 영역 (Sonnet decider) 정식 제거 + 신규 `worker_dialog_rounds` field 추가. 즉시 cutover (consumer scope 0건). v4 = `pl_recommendation` 자체가 final verdict (PL = decider 책임자 복원). v3 본문은 archive reference 로 보존 — 6 CFP 무사고 후 별도 cleanup CFP 에서 file 삭제 (v2 deprecate 패턴 정합).
>
> **(이전 annotation)** DEPRECATED PASSTHROUGH (2026-05-08, CFP-134 / ADR-035): ADR-022 가 Deprecated 처리되어 본 contract 의 Sonnet decider 5-step 영역 (`decision_state` 의 `pending_sonnet`/`decided`/`decider_timeout`/`decider_suspended`/`review_reopen_requested`/`write_partial`/`write_complete` state, `sonnet_final_status` 필드, `decider_decision_ref` 필드, `write_errors` step enum) 은 **NO-OP** 으로 사용. PL 이 자기 lane synthesis 후 `pl_recommendation` (PASS / FIX / FIX_DISCRETIONARY) 직접 적용 — Sonnet final pick 자동 발화 없음. 사용자 explicit request 시에만 ad-hoc Sonnet invoke. (본 transitional 영역 = CFP-137 wrapper Phase 1 PR merge 시 종료, v4 cutover 적용.)
>
> Architecture decision SSOT = [ADR-035](https://github.com/mclayer/plugin-codeforge/blob/main/docs/adr/ADR-035-codeforge-agent-teams-epic-architecture.md) (Epic CFP-134) + [ADR-044](https://github.com/mclayer/plugin-codeforge/blob/main/docs/adr/ADR-044-phase-scoped-sequential-team.md) (CFP-137 v4 carrier, in plugin-codeforge wrapper repo). 본 canonical annotation 은 wrapper sibling [PR #284](https://github.com/mclayer/plugin-codeforge/pull/284) 의 sibling sync — ADR-010 §단계 절차 정합 (wrapper-first).

# review_verdict v3 — Inter-plugin Contract (CFP-61 Phase 1B-1)

`codeforge-review` plugin → `codeforge` core (Orchestrator) 단방향 schema. v2와 BREAKING — `status` 필드 의미 shift (PL final → Sonnet final), 신규 `decision_state` state machine, `pl_recommendation` (PL advisory) + `sonnet_final_status` (Sonnet binary) split, `decider_decision_ref` link.

**(CFP-135 DEPRECATED PASSTHROUGH 적용 후)**: 본 BREAKING 변경 중 `pl_recommendation` 만 active. 나머지 (`status` 제거 / `sonnet_final_status` / `decider_decision_ref` / `write_errors` / `writes_completed` 의미 재정의) 는 NO-OP — frontmatter 위 deprecation note 참조.

**상위 SSOT 위치**:
- `mclayer/plugin-codeforge-review/docs/inter-plugin-contracts/review-verdict-v3.md`: **canonical** (this file)
- `mclayer/plugin-codeforge/docs/inter-plugin-contracts/review-verdict-v3.md`: sibling reference (canonical 변경 시 sync 의무, ADR-010)
- ADR-022 carrier: `mclayer/plugin-codeforge/docs/adr/ADR-022-sonnet-review-verdict-decider.md`

## 1. v2 → v3 BREAKING 변경 요약

| 영역 | v2.0 (CFP-35 ~ CFP-60) | v3.0 (CFP-61 부터) |
|---|---|---|
| `status` 필드 | PL final (PASS/FIX/FIX_DISCRETIONARY/ESCALATE_PACKET_INCOMPLETE) | **제거** |
| `pl_recommendation` | (없음) | NEW — PL advisory 4 enum |
| `sonnet_final_status` | (없음) | NEW — Sonnet binary (PASS\|FIX) |
| `decision_state` | (없음) | NEW — 8-value state machine |
| `decider_decision_ref` | (없음) | NEW — Sonnet packet link |
| `write_errors` | (없음) | NEW — partial write audit |
| `writes_completed` audit 의미 | PL self-write 결과 | **Orchestrator** self-write 결과 |
| Story §9 / §10 / §12 / GitHub comment / gate label / phase transition write 주체 | PL | **Orchestrator** (post-Sonnet, CFP-61) |

## 2. Schema (verbatim from spec §4.5.1 + §5.1)

```yaml
review_verdict:
  contract_version: "3.0"            # BREAKING marker
  lane: design | code | security
  story_key: <STORY_KEY>
  iteration: <int>
  
  findings:                          # v2 그대로 (배열, severity/category/file/evidence/suggestion)
    - severity: P0 | P1 | P2
      category: <packet category_enum 중 하나>
      file: <path>
      line: <int>
      evidence: <markdown>
      suggestion: <markdown>
  
  pl_recommendation: PASS | FIX | FIX_DISCRETIONARY | ESCALATE_PACKET_INCOMPLETE  # NEW (was status)
  
  # NEW state machine — explicit lifecycle (Codex spec audit P1 #1)
  decision_state: pending_sonnet | decided | blocked_packet_incomplete | decider_timeout | decider_suspended | review_reopen_requested | write_partial | write_complete
  
  sonnet_final_status: PASS | FIX                                                  # required only when decision_state=decided | write_partial | write_complete
  decider_decision_ref:                                                            # required only when decision_state=decided | write_partial | write_complete
    packet_id: <story_key>-<3-digit-seq>
    model: claude-sonnet-4-6
  
  write_errors:                                                                    # NEW — populated when decision_state=write_partial (Codex P1 #5)
    - step: story_section_9 | phase_comment | gate_label_attached | phase_label_transitioned | fix_ledger_append | diagnosis_spawn
      error_class: github_mcp_timeout | edit_conflict | mcp_auth_failure | other
      retry_count: <int>
  
  writes_completed:                  # 의미 재정의 — Orchestrator self-write audit (CFP-61 한정)
    story_section_9: <bool>
    phase_comment: <bool>
    gate_label_attached: <bool>
    phase_label_transitioned: <bool>
    fix_ledger_append: <bool>        # FIX 시 only
    diagnosis_spawn: <bool>          # FIX 시 only
```

## 3. decision_state 의미 (verbatim from spec §4.5.1 transition table)

**`decision_state` 필드 의미** (Codex P1 #1):

| state | 의미 | sonnet_final_status / decider_decision_ref |
|---|---|---|
| `pending_sonnet` | Orchestrator 가 packet 작성, Sonnet 호출 전 | absent |
| `blocked_packet_incomplete` | pl_recommendation=ESCALATE_PACKET_INCOMPLETE, Sonnet 호출 차단 | absent |
| `decider_timeout` | Sonnet 호출 retry 모두 timeout | absent |
| `decider_suspended` | Sonnet quota / auth / runtime denial → user authority | absent |
| `review_reopen_requested` | Sonnet 응답 = packet_requires_review_reopen, ReviewPL 재 spawn 대기 | absent |
| `decided` | Sonnet pick 완료, write 시작 전 | populated |
| `write_partial` | Sonnet pick 완료 + 일부 write 실패 (write_errors 채워짐) | populated |
| `write_complete` | 모든 required write 성공 | populated |

## 4. write_partial → write_complete 전환 (verbatim from spec §4.5.1 transition note)

**`write_partial` → `write_complete` 전환 (Codex Round 2 신규 gap fix)**: user/operator 가 외부 시스템 복구 후 (예: GitHub MCP 재인증, 라벨 부착 수동) Orchestrator 가 다음 spawn 사이클에 본 verdict 의 missing write 재시도 가능. `writes_completed` 의 모든 required field = true 로 갱신되면 `decision_state=write_complete` 로 transition. retry 누적 한도 = 각 sub-step 별 3 회 (initial + 2 retry). 한도 초과 시 user escalation (decision_state=write_partial 잔존 + Story §10 / §12 에 final state mark).

## 5. Sonnet 응답 schema (trigger 5, verbatim from spec §4.5.3)

trigger 5 review-verdict Sonnet 호출 시 응답 (Agent tool with model:sonnet) 은 아래 schema 따름:

```yaml
decision: PASS | FIX | PACKET_REQUIRES_REVIEW_REOPEN
reasoning_summary: <markdown, 1-3 paragraphs>
confidence: high | medium | low
packet_gap_summary: <markdown, optional — required when decision=PACKET_REQUIRES_REVIEW_REOPEN>
```

**Mapping rules (Orchestrator parse)**:

| Sonnet response `decision` | review-verdict `sonnet_final_status` | packet `attempts[].outcome` | review-verdict `decision_state` |
|---|---|---|---|
| `PASS` | `PASS` | `success` | `decided` (then → `write_complete` or `write_partial`) |
| `FIX` | `FIX` | `success` | `decided` (then → `write_complete` or `write_partial`) |
| `PACKET_REQUIRES_REVIEW_REOPEN` | (absent) | `packet_requires_review_reopen` | `review_reopen_requested` |

**Parse failure**: response 가 위 schema 미준수 시 `attempts[].outcome=parse_failure` + 1 회 retry with explicit YAML correction prompt → second failure = `outcome=malformed` + user escalation (review-verdict `decision_state=decider_timeout` 으로 logging — timeout 카테고리에 포함).

## 6. 흐름 개요 (5-step Orchestrator algorithm — verbatim from spec §4.3)

**신규 trigger 5 (review-verdict)** = 5-step algorithm:

```
1. ReviewPL spawn → workers (Claude+Codex parallel) → dedup → review-verdict-v3 packet (no writes)
   ├── findings + pl_recommendation 작성
   ├── decision_state = pending_sonnet (or blocked_packet_incomplete if pl_recommendation=ESCALATE_PACKET_INCOMPLETE)
   └── return to Orchestrator
2. Orchestrator: decision-packet-v2.1 작성 (trigger: review-verdict, review_lane_context populated, findings_hash verified)
3. Orchestrator: Agent tool with model:sonnet 호출 → 응답 parse (§4.5.3 Sonnet 응답 schema)
   ├── decision=PASS|FIX → sonnet_final_status 채움, decision_state=decided, step 4 로 진행
   ├── decision=PACKET_REQUIRES_REVIEW_REOPEN → decision_state=review_reopen_requested, ReviewPL 재 spawn (1 회 한도 per (story_key,lane,iteration))
   └── timeout/malformed (Codex P1 #4) → decision_state=decider_timeout
       └── Story §9 / §10 append 차단. §12 row append (decider_pick=<none>, audit_result=user-escalation, attempts[].outcome=timeout|malformed)
4. Orchestrator self-write (decision_state=decided 일 때만):
   ├── Story §9 append (lane iteration result) — append-only, never rolled back
   ├── GitHub Issue/PR comment ([<lane>-리뷰] / [보안-테스트] prefix) via mcp__github__add_issue_comment
   ├── PASS 시: gate:*-pass label + phase:* 다음 단계 전환 via mcp__github__issue_write
   └── Story §12 Sonnet Decision Log row append
   
   **Partial-write policy (Codex P1 #5)**: 각 sub-step 별 idempotent retry (initial + 2 retry = 3 회 한도, Codex Round 2 gap fix). 실패 시 `writes_completed.<field>=false` + `write_errors[]` populate, decision_state=write_partial. **any required write 가 retry 한도 후에도 false 잔존 시 user escalation** (모든 required 가 아닌 1 건이라도 잔존 시 — Codex Round 2 gap fix wording 명확화). Story §9 + §12 는 append-only — 이미 append 된 내용 rollback 안 함. 외부 복구 후 다음 spawn 사이클에 missing write 재시도 가능 (write_partial → write_complete 전환).
5. FIX 시 (sonnet_final_status=FIX):
   ├── Story §10 FIX Ledger append (decider: claude_sonnet, override marker if pl_recommendation != sonnet_final_status)
   ├── fix-ledger-sync.yml Action mirror (auto)
   ├── DeveloperPL + ArchitectPL parallel diagnosis spawn (CFP-19 R4)
   
   **Spawn-failure policy (Codex P1 #6)**: §10 append 성공 + diagnosis spawn 실패 시 — §10 row 유지 (append-only), §12 append (audit_result=user-escalation, spawn_status=failed), 1 회 retry → second failure = user escalation. spawn 성공할 때까지 §10 row 는 "open FIX with no diagnosis" 상태로 visible.
```

## 7. ESCALATE 처리

decision_state=blocked_packet_incomplete (pl_recommendation=ESCALATE_PACKET_INCOMPLETE) 시:
- Orchestrator 가 Sonnet 호출 차단
- Story §10 / §9 append 차단
- Story §12 row append (`<blocked>` literal placeholder)
- user escalation

## 8. v3 ↔ canonical sync (ADR-010)

본 file = sibling. canonical = `mclayer/plugin-codeforge-review/docs/inter-plugin-contracts/review-verdict-v3.md`. canonical 변경 시 wrapper sibling sync PR 의무. CI lint = `check-inter-plugin-contracts.sh` (wrapper repo).

## 9. v2 deprecate / archive

- v2 status: Active → Archived (CFP-61 머지 직후)
- v2 archive: 6 CFP 무사고 후 (= v3 안정화 확인) — 별도 cleanup CFP에서 file 삭제

## 10. Decider 모델 invariant — Sonnet not reviewer (CFP-61 / ADR-022 §결정 4)

For trigger 5 `review-verdict`, Claude Sonnet (`claude-sonnet-4-6`) is the final decider over ReviewPL-provided review evidence. Sonnet does NOT become a review worker or ReviewPL:

- Sonnet must NOT perform primary file inspection
- Sonnet must NOT generate the review finding set
- Sonnet must NOT alter severity normalization
- Sonnet must NOT replace ReviewPL dedup

Its authority is limited to selecting the final gate outcome (`PASS` | `FIX`) from packet evidence.

**Edge case**: If Sonnet reasoning identifies a potential missing issue in the packet, that item is not a review finding until routed back to ReviewPL via `packet_requires_review_reopen` enum value (per `(story_key, lane, iteration)` 1 회 한도). Orchestrator must not publish Sonnet reasoning content as a review finding directly.

**Trigger 5 contract-fixed options**: option set is contract-fixed as exactly `PASS` and `FIX` (binary). Sonnet must not add, remove, rename, or synthesize options.
