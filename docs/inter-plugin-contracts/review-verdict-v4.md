---
kind: contract
contract_version: "4.2"
status: Active
related_plugins:
  - codeforge (wrapper, consumer of FIX routing data + Orchestrator self-write)
  - codeforge-review (lane plugin, producer + synthesizer + final pl_recommendation author)
related_adrs:
  - ADR-001  # review-agent-unification — lane-agnostic worker
  - ADR-008  # Inter-plugin Contract Versioning (MAJOR/MINOR bump)
  - ADR-010  # Inter-plugin Contract Sibling Sync (canonical/sibling 관계)
  - ADR-022  # Deprecated by ADR-035 — Sonnet decider 영역 본 v4 에서 정식 제거
  - ADR-035  # codeforge agent teams Epic architecture (D2 implementation level)
  - ADR-044  # Phase-scoped sequential team SSOT (본 v4 carrier)
  - ADR-059  # debate-protocol-v1 — anchor_id field 가 stable identifier 로 의존 (CFP-391)
  - ADR-065  # ArchitectAgent Phase 1 mechanical self-check — mechanical_self_check_passed field (CFP-438)
authors:
  - CFP-137 (2026-05-09) — review-verdict v3 → v4 MAJOR bump (Sonnet decider 영역 정식 제거 + worker_dialog_rounds 추가)
  - CFP-391 (2026-05-11) — findings[].anchor_id optional field 추가 (debate-protocol-v1 stable identifier SSOT 정합, FIX-1)
  - CFP-391 (2026-05-11) — v4.0 → v4.1 MINOR bump (anchor_id field 추가 = ADR-008 §결정 2 "새 선택 필드 추가" MINOR bump 정합, F-003 follow-up)
  - CFP-438 (2026-05-13) — v4.1 → v4.2 MINOR bump (mechanical_self_check_passed optional bool field 추가, ADR-065)
amendment_log:
  - version: "4.2"
    date: 2026-05-13
    cfp: CFP-438
    type: MINOR
    summary: "mechanical_self_check_passed optional bool field 추가 — ADR-065 ArchitectAgent Phase 1 7-item mechanical sync self-check 결과 explicit marker. true = 모두 PASS 또는 NA, false = FIX 의무 (ArchitectAgent re-spawn). 적용 lane: design lane only (code/security lane = optional, omit 가능). ADR-008 §결정 2 \"새 선택 필드 추가\" = MINOR bump 정합. Runtime impact 없음 (기존 v4.1 consumer 가 본 필드 무시 가능)."
  - version: "4.1"
    date: 2026-05-11
    cfp: CFP-391
    type: MINOR
    summary: "findings[].anchor_id optional field 추가 — debate-protocol-v1 stable identifier 의존. ADR-008 §결정 2 \"새 선택 필드 추가\" = MINOR bump 정합. Runtime impact 없음 (ADR-008 §결정 4 v.x compat 룰 정합)."
  - version: "4.0"
    date: 2026-05-09
    cfp: CFP-137
    type: MAJOR
    summary: "v3 → v4 BREAKING — Sonnet decider 영역 (decision_state 8-value enum / sonnet_final_status / decider_decision_ref / write_errors step Sonnet semantics / 5-step Orchestrator algorithm) 정식 제거. PL pl_recommendation 자체가 final verdict. worker_dialog_rounds 추가."
---

# review_verdict v4 — Inter-plugin Contract (CFP-137 / ADR-044)

`codeforge-review` plugin → `codeforge` core (Orchestrator) 단방향 schema. v3와 BREAKING — Sonnet decider 영역 (`decision_state` 8-value enum / `sonnet_final_status` / `decider_decision_ref` / `write_errors` step Sonnet semantics / 5-step Orchestrator algorithm) 정식 제거. PL `pl_recommendation` 자체가 final verdict (PASS / FIX / FIX_DISCRETIONARY / ESCALATE_PACKET_INCOMPLETE).

신규 field `worker_dialog_rounds` 추가 — Adversarial debate (5 권장 패턴 — ADR-044 §결정 5) measurable verification.

**상위 SSOT 위치**:
- `mclayer/plugin-codeforge-review/docs/inter-plugin-contracts/review-verdict-v4.md`: **canonical** (sibling sync follow-up PR — wrapper Phase 1 PR merge 후 ADR-010 §단계 절차 정합)
- 본 file (codeforge wrapper repo): sibling reference (CFP-137 wrapper Phase 1 PR 시 신설)
- ADR-044 carrier: `docs/adr/ADR-044-phase-scoped-sequential-team.md`

## 1. v3 → v4 BREAKING 변경 요약

| 영역 | v3.0 (CFP-61 ~ CFP-134) | v4.0 (CFP-137 부터) |
|---|---|---|
| `decision_state` 8-value enum | `pending_sonnet` / `decided` / `blocked_packet_incomplete` / `decider_timeout` / `decider_suspended` / `review_reopen_requested` / `write_partial` / `write_complete` (NO-OP passthrough since CFP-134) | **제거** (단순화 — PL synthesis → Orchestrator self-write 단일 path) |
| `sonnet_final_status` | NEW (NO-OP passthrough since CFP-134) | **제거** |
| `decider_decision_ref` | NEW (NO-OP passthrough since CFP-134) | **제거** |
| `write_errors[].step` Sonnet semantics | `fix_ledger_append` / `diagnosis_spawn` 의 `decider:claude_sonnet` semantics | step enum 유지하되 Sonnet semantics 제거 — Orchestrator self-write retry only |
| 5-step Orchestrator algorithm | Sonnet 호출 step 3 포함 | **4-step 단순화** (step 3 제거, PL pl_recommendation 직접 적용) |
| `worker_dialog_rounds` | (없음) | **NEW** — Adversarial debate SendMessage round count (ADR-044 §결정 5) |
| `pl_recommendation` final authority | PL advisory + Sonnet final pick override | **PL pl_recommendation 자체가 final verdict** |
| Sonnet override marker (Story §10 FIX Ledger row) | `decider: claude_sonnet, override_marker if pl_recommendation != sonnet_final_status` | **제거** — PL recommendation 단일 source |

## 2. Schema (v4 verbatim)

```yaml
review_verdict:
  contract_version: "4.0"            # BREAKING marker
  lane: design | code | security
  story_key: <STORY_KEY>
  iteration: <int>
  
  findings:                          # v3 그대로 (배열, severity/category/file/evidence/suggestion) + anchor_id NEW
    - severity: P0 | P1 | P2
      category: <packet category_enum 중 하나>
      file: <path>
      line: <int>
      evidence: <markdown>
      suggestion: <markdown>
      anchor_id: <string>            # NEW (optional) — finding 의 stable identifier
                                     # 형식: `<file>:<line>` (예: `src/foo.py:42`)
                                     #     또는 `§<section-ref>` (예: `§7.4`)
                                     #     또는 wrapper-defined hash (e.g., sha1(file+line+evidence)[:12])
                                     # 용도: debate-protocol-v1 (ADR-059 §결정 2/4) 이 stable identifier 로 의존
                                     #       — Codex worker counter-arg 가 동일 finding 을 anchor_id 로 reference
                                     # Producer 가 채움 (PL synthesis 시점). 미제공 시 PL 이 hash 로 auto-generate 가능
                                     # 동일 (story_key, lane, iteration) 안에서 unique 권장 (debate cross-ref 정합성)
  
  pl_recommendation: PASS | FIX | FIX_DISCRETIONARY | ESCALATE_PACKET_INCOMPLETE  # v3 유지, 단 final verdict 책무 단독
  
  mechanical_self_check_passed: <bool>  # NEW v4.2 (optional) — ADR-065 / CFP-438
                                         # ArchitectAgent Phase 1 7-item mechanical sync self-check 결과
                                         # true = 모두 PASS 또는 NA
                                         # false = FIX 의무 (ArchitectAgent re-spawn)
                                         # 적용 lane: design lane only (code/security lane = optional, omit 가능)
                                         # 미제공 시 (v4.1 producer) → Orchestrator 는 무시 (backward-compat)
                                         # 7 항목: label-registry sync / doc-locations regen / workflow self-app /
                                         #         link target Phase 분배 / MANIFEST.yaml 갱신 / section-ownership row /
                                         #         doc-locations row
  
  worker_dialog_rounds: <int>        # NEW — Adversarial debate SendMessage round count
                                     # 0 = no Codex worker (default subagent context 또는 user_request_only 미요청)
                                     # >= 1 = SendMessage round 발화 횟수
                                     # >= 2 권장 (ADR-044 §결정 5 Adversarial measurable verification)
  
  write_errors:                      # v3 유지하되 Sonnet semantics 제거 — Orchestrator self-write retry only
    - step: story_section_9 | phase_comment | gate_label_attached | phase_label_transitioned | fix_ledger_append | diagnosis_spawn
      error_class: github_mcp_timeout | edit_conflict | mcp_auth_failure | other
      retry_count: <int>             # initial + max 2 retry = 3 attempts (v3 §4 partial-write policy 정합)
  
  writes_completed:                  # 의미 v3 와 동일 — Orchestrator self-write audit
    story_section_9: <bool>
    phase_comment: <bool>
    gate_label_attached: <bool>
    phase_label_transitioned: <bool>
    fix_ledger_append: <bool>        # FIX 시 only
    diagnosis_spawn: <bool>          # FIX 시 only
```

## 3. 4-step Orchestrator algorithm (v3 의 5-step → 4-step 단순화)

```
1. ReviewPL spawn → workers (Claude worker default + Codex worker on user_request) → dedup → review-verdict-v4 packet (no writes)
   ├── findings + pl_recommendation 작성
   ├── worker_dialog_rounds 채움 (Adversarial debate SendMessage round count)
   ├── mechanical_self_check_passed 채움 (design lane only — ArchitectPLAgent 가 ArchitectAgent §5.5 self-check 결과 forward, ADR-065 / CFP-438)
   └── return to Orchestrator

2. Orchestrator self-write (pl_recommendation = PASS | FIX | FIX_DISCRETIONARY 일 때만, ESCALATE_PACKET_INCOMPLETE 시 차단):
   ├── Story §9 append (lane iteration result) — append-only, never rolled back
   ├── GitHub Issue/PR comment (lane-specific prefix per comment-prefix-registry-v1) via mcp__github__add_issue_comment
   ├── PASS 시: gate:*-pass label + phase:* 다음 단계 전환 via mcp__github__issue_write
   └── (Story §12 Sonnet Decision Log row append — v4 에서 obsoleted, write 없음)

   **Partial-write policy (v3 §4 verbatim 차용)**: 각 sub-step 별 idempotent retry (initial + 2 retry = 3 회 한도). 실패 시 `writes_completed.<field>=false` + `write_errors[]` populate. **any required write 가 retry 한도 후에도 false 잔존 시 user escalation** (모든 required 가 아닌 1 건이라도 잔존 시). Story §9 는 append-only — 이미 append 된 내용 rollback 안 함. 외부 복구 후 다음 spawn 사이클에 missing write 재시도 가능.

3. FIX 시 (pl_recommendation=FIX):
   ├── Story §10 FIX Ledger append (decider field 제거 — PL recommendation 단일 source)
   ├── fix-ledger-sync.yml Action mirror (auto)
   └── DeveloperPL + ArchitectPL parallel diagnosis spawn (CFP-19 R4)

   **Spawn-failure policy (v3 §4 verbatim 차용)**: §10 append 성공 + diagnosis spawn 실패 시 — §10 row 유지 (append-only), 1 회 retry → second failure = user escalation. spawn 성공할 때까지 §10 row 는 "open FIX with no diagnosis" 상태로 visible.

4. ESCALATE 처리 (pl_recommendation=ESCALATE_PACKET_INCOMPLETE):
   ├── Orchestrator self-write 차단 (§9 / §10 / GitHub state 모두 차단)
   ├── ReviewPL 재 spawn (1 회 한도 per (story_key, lane, iteration))
   └── 한도 초과 시 user escalation
```

## 4. v3 → v4 migration 가이드

본 v4 는 wrapper Phase 1 PR (CFP-137 Wave 2) merge 시점 즉시 cutover. consumer scope 0건 (mctrader debut audit 까지) 으로 backward compat 면제. ADR-044 §결정 4 정합.

### 수신자 (Orchestrator + Lane PL) 갱신 항목

1. **Sonnet 호출 경로 제거** — Orchestrator 가 ReviewPL packet 수령 후 Sonnet Agent tool 호출 step skip. `pl_recommendation` 직접 적용.
2. **`decision_state` 처리 코드 제거** — 8-value enum 분기 무용. PL packet 의 pl_recommendation = `PASS` / `FIX` / `FIX_DISCRETIONARY` / `ESCALATE_PACKET_INCOMPLETE` 4-value 분기로 단순화.
3. **`sonnet_final_status` / `decider_decision_ref` field 참조 제거** — Story §10 FIX Ledger row 의 `decider:` column 자체 제거 (PL recommendation 단일 source).
4. **`worker_dialog_rounds` field 채움 의무** — review lane PL 이 SendMessage round count tracking → packet 작성 시 채움. Codex worker 미발화 시 (default subagent context 또는 user_request_only 미요청) `worker_dialog_rounds: 0`.
5. **5-step → 4-step algorithm 적용** — playbook §3.1 본문 갱신 (step 3 제거).

### Producer (codeforge-review plugin) 갱신 항목

1. PL synthesis template (`templates/review-pl-base.md`) 갱신 — packet 작성 시 v4 schema 따름.
2. `worker_dialog_rounds` field 채움 logic 추가 — SendMessage round count tracking.
3. canonical (codeforge-review plugin) review-verdict-v4.md 신설 + v3 status flip.
4. ADR-010 sibling sync follow-up PR 의무 — wrapper sibling 본 file 와 동기 verbatim.

### Story §10 FIX Ledger schema 영향

기존 v3 schema `| decider | override_marker |` column = v4 에서 제거 (PL recommendation 단일 source). 본 cleanup 은 별도 follow-up CFP — Story §10 schema 자체 SSOT = wrapper CLAUDE.md 의 "FIX Ledger §10 schema" 4 SSOT 예외 (ADR-012 §3) — wrapper Phase 1 PR scope 안에서 column 제거 추후 검토.

**v4 Phase 1 PR 시점 schema 정합**: 기존 v3 column (`decider`) 잔존 시 PL synthesis 가 `decider: <none>` 또는 absent 로 채움. cleanup 의무는 follow-up CFP scope.

## 5. ESCALATE 처리

pl_recommendation=ESCALATE_PACKET_INCOMPLETE 시:
- Orchestrator self-write 차단 (Story §9 / §10 / GitHub state 모두 차단)
- ReviewPL 재 spawn (1 회 한도 per (story_key, lane, iteration))
- 한도 초과 시 user escalation

## 6. v4 ↔ canonical sync (ADR-010)

본 file = sibling. canonical = `mclayer/plugin-codeforge-review/docs/inter-plugin-contracts/review-verdict-v4.md` (CFP-137 sibling sync follow-up PR 시 신설). canonical 변경 시 wrapper sibling sync PR 의무. CI lint = `check-inter-plugin-contracts.sh` (wrapper repo).

**Wrapper-first 절차 (ADR-010 §4 + Story §5.5 B1 default 채택)**:
1. 본 wrapper Phase 1 PR (CFP-137) merge — 본 file (sibling) 신설 + v3 sibling status flip.
2. canonical (codeforge-review plugin) sibling sync follow-up PR — verbatim mirror.
3. canonical merge 후 본 wrapper sibling 의 frontmatter `canonical_repo` 갱신 (annotation only — 내용 동일).

## 7. v3 deprecate / archive

- v3 status (wrapper sibling): Active → Archived (CFP-137 wrapper Phase 1 PR merge 시점)
- v3 archive: 6 CFP 무사고 후 (= v4 안정화 확인) — 별도 cleanup CFP에서 file 삭제 (v2 deprecate 패턴 정합)

## 8. v4 invariant — PL = decider 책임자 복원

ADR-022 Deprecated 후 (CFP-134 / ADR-035) Sonnet decider 자동 발동 무효 — PL `pl_recommendation` 자체가 final verdict. v4 가 본 invariant 를 schema level 에서 정식 codify.

- PL은 lane synthesis 후 findings + pl_recommendation 작성
- Orchestrator 는 pl_recommendation 직접 적용 (decision_state 무용, Sonnet 호출 무용)
- 사용자 explicit request 시에만 ad-hoc Sonnet 호출 가능 — codeforge orchestration 외 (memory `feedback_sonnet_decider_user_only.md` 정합)

**Edge case**: PL 이 packet 의 finding 분류 misjudgment 시 — packet 의 pl_recommendation 자체가 final 이므로 Sonnet override 채널 부재. mitigation = (a) 사용자 ad-hoc Sonnet 호출 요청 (codeforge 외 conversation), (b) FIX iteration 시 본 PL 재 spawn (Story file FIX Ledger 정합).

## 9. CONSUMER scope 영향 분석

- **mctrader (debut audit)**: 0건 — 본 v4 cutover 전까지 mctrader Story 자체 미진행 (mctrader debut audit 후 적용).
- **다른 consumer (가설)**: 본 cutover 시점에 v3 사용 중인 consumer 존재 가능성 0 — codeforge family agent 는 wrapper Orchestrator 만 review-verdict 수신. consumer Orchestrator 가 v3 직접 parsing 하는 사례 0건.
- **Backward compat 면제 근거**: ADR-008 §SemVer MAJOR bump rule + consumer scope 0 — 즉시 cutover 가능. Story §5.5 R3 default 채택.

## 10. Adversarial debate measurable verification (ADR-044 §결정 5)

`worker_dialog_rounds` field 가 5 권장 패턴 (Anthropic agent design pattern) Adversarial 영역 measurable signal:

- **0**: Codex worker 미발화 (default subagent context env=0 또는 dispatch_mode=user_request_only 미요청 시)
- **>= 1**: SendMessage round 발화 — Adversarial 진행
- **>= 2 권장**: 의미있는 debate cycle (Claude initial → Codex counter → Claude final, 또는 deeper rounds)

**Phase 2 PR scope (CFP-137 e2e fixture)**:
- review-verdict v4 schema lint — `worker_dialog_rounds` field 정합 검증
- `worker_dialog_rounds >= 2` 시 review-verdict packet 의 finding evidence 에 round-by-round narrative 포함 검증 (subjective fixture)

## 11. ArchitectAgent Phase 1 mechanical self-check (v4.2 — ADR-065 / CFP-438)

`mechanical_self_check_passed` optional bool field 가 ArchitectAgent Phase 1 산출물 commit 직전 7-item mechanical sync self-check 결과 explicit marker:

| # | 항목 | 검증 방법 |
|---|---|---|
| 1 | `label-registry-v2.md` 변경 시 `scripts/bootstrap-labels.sh` sync 동반 | `bash scripts/check-labels-bootstrap-strict.sh` PASS |
| 2 | `doc-locations.yaml` 변경 시 `bash scripts/check-doc-locations.sh --regen` 실행 | regenerate 후 `doc-location-registry.md` mirror diff 0 |
| 3 | 신규 `templates/github-workflows/*.yml` 시 `.github/workflows/` self-app copy 동반 | `diff -q templates/github-workflows/X.yml .github/workflows/X.yml` exit 0 (byte-identical) |
| 4 | CLAUDE.md / docs/** 내 link target 이 Phase 1 분배인지 확인 | Phase 2 file 참조 시 dangling — markdown internal link lint PASS |
| 5 | `docs/inter-plugin-contracts/MANIFEST.yaml` registries 블록 갱신 필요성 확인 | 신규 registry 도입 시 row append, `check-inter-plugin-contracts.sh` PASS |
| 6 | `docs/parallel-work/section-ownership.yaml` 정책 필요 시 row append | 동시 편집 영향 받는 신규 section 도입 시 row append |
| 7 | `docs/doc-locations.yaml` 신규 doc type row 필요성 확인 | 신규 doc type 도입 시 row append, `check-doc-locations.sh` PASS |

**Producer 책무 (ArchitectPLAgent)**:

- ArchitectAgent `§5.5 Phase 1 commit-time self-check` (ADR-065 / CFP-438) 통과 후 7 항목 결과 수령
- packet `mechanical_self_check_passed` 채움 (true = 모두 PASS 또는 NA, false = 1+ FAIL)
- false 시 `pl_recommendation: FIX` + `findings[]` 에 mechanical 누락 항목 each row append (severity P1, category `mechanical_sync_required`)

**Consumer 책무 (Orchestrator)**:

- false 수신 시: Story §10 FIX Ledger row append (Orchestrator monopoly, fix-event-v1 contract) → ArchitectPLAgent re-spawn 의뢰 → PL 이 ArchitectAgent re-spawn 명령
- true 수신 시: 정상 lane 진행 (mechanical 영역 PASS 신호로 채택)
- 미제공 (v4.1 producer) 수신 시: 무시 — backward-compat, 본 영역 lint 없음으로 간주

**적용 lane**:

- **design lane** (필수) — ArchitectPLAgent verdict packet 의 의무 필드
- **code lane / security lane** (optional) — code/security review 가 mechanical sync 외 영역만 다루므로 omit 가능

**marketplace 영역 분리**:

본 self-check 는 non-marketplace 영역만 (ADR-065 §결정 5). marketplace mirrored field (`name` / `version` / `description` / `author`) atomic invariant = ADR-063 SSOT (3-file: plugin.json / CHANGELOG.md / marketplace.json). cross-ref only — packet 의 mechanical_self_check_passed 는 marketplace 영역과 무관.
