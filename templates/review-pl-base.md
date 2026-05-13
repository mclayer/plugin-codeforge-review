# Review/Test PL 공통 base 템플릿

3개 리뷰 레인 PL(`DesignReviewPLAgent` · `CodeReviewPLAgent` · `SecurityTestPLAgent`)이 공유하는 **severity 종합 · dedup · noise 분류 · 보고 형식 · escalation 절차**의 SSOT. 각 PL md는 본 템플릿을 참조하고 lane-specific 4가지(체크리스트 packet · FIX 카운터 정책 · 검증 스코프 · 다음 게이트 라벨)만 본문에 명시한다.

ADR 근거: [ADR-001](../docs/adr/ADR-001-review-agent-unification.md).

---

## 1. 공통 포지션

- **상위**: Orchestrator
- **하위**: ClaudeReviewAgent, CodexReviewAgent (워커 2종 통합 — [ADR-001](../docs/adr/ADR-001-review-agent-unification.md))
- **호출 시점**: 각 레인 진입 직후 Orchestrator 스폰. PL은 워커 packet만 작성·검증해 Orchestrator에 return — **워커 spawn은 Orchestrator가 한 메시지에 두 워커(Claude ∥ Codex)를 dispatch** (서브에이전트 재귀 spawn 금지 platform 제약 정합, [CFP-19 R3](../docs/superpowers/specs/2026-04-27-cfp-19-orchestration-parallelization.md))
- **평행 PL**: 다른 2개 리뷰 PL — 동일 종합 로직 공유, lane-specific 4가지만 다름

---

## 2. 워커 packet 구성 (PL → Orchestrator → Worker)

PL은 lane 진입 시 다음 필드를 채운 packet을 워커에 주입한다. **필수 필드 누락 시 워커가 ESCALATE 신호(`ESCALATE_PACKET_INCOMPLETE`) 반환 — generic fallback 금지**.

### 공통 필드 (모든 lane)

```yaml
review_packet:
  contract_version: "1.0"                                       # 필수 — review_verdict v1 contract enforcement
  lane: design | code | security                               # 필수
  checklist_path: templates/review-checklists/{design,code,security}.md  # 필수
  scope_globs:                                                  # 필수
    - <file glob list>     # 예: ["docs/change-plans/**", "docs/stories/<KEY>.md"]
  category_enum:                                                # 필수
    - <category list>      # 예: ["adr-mismatch", "design-quality", ...]
  severity_overrides:        # 선택 — lane-specific 자동 P0 룰
    - rule: "ADR violation" → P0
    - rule: "credential hardcode" → P0
  story_key: <STORY_KEY>     # 필수 — Story file 참조용
  related_adrs:              # 선택 — 정합성 교차 입력
    - docs/adr/ADR-NNN-<slug>.md
```

### lane-specific 확장 필드

**`lane=security` 추가 필수 필드** — SecurityTestPL이 1차 layer fetch 결과를 packet에 inline 첨부:

```yaml
  first_layer_findings:                                          # security lane 필수
    dependabot:    [<Dependabot alerts list (gh api repos/*/dependabot/alerts)>]
    codeql:        [<CodeQL findings (gh api repos/*/code-scanning/alerts)>]
    secret_scan:   [<Secret Scanning alerts>]
    push_protection: [<Push Protection bypassed events, optional>]
```

워커는 1차 layer가 이미 보고한 finding은 skip하고 **high-level 분석(trust boundary·auth model)에 집중**. `lane=design` / `lane=code` 는 이 필드 없음.

**lane별 packet 필수 필드 매트릭스**:

| 필드 | design | code | security |
|------|:------:|:----:|:--------:|
| contract_version | ✅ | ✅ | ✅ |
| lane | ✅ | ✅ | ✅ |
| checklist_path | ✅ | ✅ | ✅ |
| scope_globs | ✅ | ✅ | ✅ |
| category_enum | ✅ | ✅ | ✅ |
| story_key | ✅ | ✅ | ✅ |
| severity_overrides | ◯ | ◯ | ◯ |
| related_adrs | ◯ | ◯ | ◯ |
| **first_layer_findings** | — | — | ✅ |

---

## 3. Severity 종합 규칙

### Dedup

- 같은 location(파일·라인·섹션·ADR) + 동일 category finding은 1건 병합
- severity는 두 리뷰 중 **높은 쪽 채택**

### Worker verdict → review_verdict.pl_recommendation 변환

워커는 `verdict: PASS | ISSUES | NO_SHIP | ESCALATE_PACKET_INCOMPLETE` 4종으로 보고 ([ClaudeReviewAgent §보고 형식](../agents/ClaudeReviewAgent.md), [CodexReviewAgent §정규화 보고 스키마](../agents/CodexReviewAgent.md)). PL은 dedup·severity 종합 후 양 워커 결과를 다음 표로 contract pl_recommendation으로 변환:

| 양 워커 종합 (dedup 후 P0/P1 카운트 기준) | review_verdict.pl_recommendation |
|---|---|
| 두 워커 중 1건 이상 `ESCALATE_PACKET_INCOMPLETE` | `ESCALATE_PACKET_INCOMPLETE` (PL advisory — Orchestrator가 Sonnet 호출 차단 후 user escalation) |
| 두 워커 모두 `PASS` (또는 `ISSUES` with P0=0, P1=0) | `PASS` |
| `NO_SHIP` 1건 이상 (즉 P0 ≥ 1) | `FIX` |
| `ISSUES` + P0=0, P1 ≥ 2 | `FIX` |
| `ISSUES` + P0=0, P1 = 1 | `FIX_DISCRETIONARY` (PL 재량 — 근거 포함 Orchestrator 전달) |
| FIX 카운터 lane 한도 초과 | `FIX` 결정 후 PL이 별도 ESCALATE 신호 추가 (lane md FIX 카운터 정책 SSOT) |

본 표가 contract `review_verdict.pl_recommendation` enum과 워커 verdict enum 사이의 유일한 매핑 SSOT. 워커 verdict enum 추가/변경 시 본 표도 동시 갱신 의무.

**v3 advisory 의미**: 위 `pl_recommendation` 값은 모두 **advisory** — PL 최종 판정이 아님. Sonnet이 `sonnet_final_status` (PASS|FIX) 를 최종 결정한다 (trigger 5, ADR-022 §결정 4). PASS/FIX/FIX_DISCRETIONARY/ESCALATE_PACKET_INCOMPLETE = Orchestrator + Sonnet 판단을 위한 PL evidence 제공.

### 종합 판정

| 조건 | 판정 |
|------|------|
| P0 ≥ 1건 | **FIX (최우선)** |
| P1 ≥ 2건 | **FIX** |
| P1 = 1건 | **FIX 재량** (근거 포함 Orchestrator 전달) |
| P2만 | **PASS** |
| FIX 카운터 한도 초과 | **ESCALATE** (한도는 lane-specific) |

### Mechanical fast-path 분류 (R11)

PL이 verdict packet에 **`mechanical_category`** 필드를 추가해 다음 자격을 1차 분류한다. Orchestrator가 fast-path 적용 여부 최종 판정.

| `mechanical_category` 후보 | 자격 조건 |
|---------|----------|
| `typo` | 단일 파일 typo·문법 수정 |
| `broken-link` | markdown link 1건 깨짐 (path/anchor) |
| `minor-naming` | 단일 함수/변수 rename, 의미 보존 |
| `comment-only` | 코멘트·docstring 수정만 |
| `none` | 위 4종 미해당 (정상 cycle) |

**Fast-path 자격 = `mechanical_category != none` AND (severity = P2 OR (severity = P1 AND 파일 수 = 1))**.

자격 충족 시 Orchestrator는 DeveloperPL 1차 진단 → ArchitectPL 판정 cycle을 skip하고 직접 fix commit + same-iteration internal verify (다음 Iter 행 안 매김). 분류 잘못이면 다음 review iteration이 P0/P1 발견 → 정상 cycle 회복 (Iter 행 append).

분류 책임자: 각 ReviewPL이 verdict 산출 시 1차 분류. SSOT는 본 절. 각 lane checklist md (`templates/review-checklists/{design,code,security}.md`)는 본 절 참조만 (재정의 금지).

### P3 / unclassified severity 처리

워커는 P3·unclassified를 emit ([ClaudeReviewAgent §분류 규칙](../agents/ClaudeReviewAgent.md), [CodexReviewAgent §변환 규칙](../agents/CodexReviewAgent.md))하지만 contract `review_verdict.findings[].severity`는 `P0|P1|P2`만 허용 (v3 §3). PL이 verdict로 변환 시:

- `P3` → `P2`로 downgrade 후 `review_verdict.findings[]`에 emit
- `unclassified` → 워커 보고 원문에서 추가 근거 추출 시도. 추출 가능하면 `P2`, 불가능하면 `findings[]`에서 drop

본 변환은 PL 의무 — 미적용 시 core가 contract enum 위반으로 verdict 거부.

### Noise 분류

- 본 PL 1차 `valid/noise` 분류
- ArchitectPLAgent가 noise 재배정 가능 — GitHub Issue 코멘트 의무 기록 (Orchestrator 경유 DocsAgent)
- 재배정 기록 형식: `[리뷰 종합] <PL이름> → ArchitectPLAgent reclassify: <이유>`

### Container security severity rule (CFP-128 / ADR-033, SecurityTest lane only)

`infra_strategy: docker_first` consumer 의 SecurityTest lane 한정. 본 rule 은 1차 layer 자동 도구 (trivy / hadolint) 결과의 contract `findings[].severity` 매핑 SSOT — `category: dependency-cve` (trivy CVE) 또는 `category: config` (hadolint Dockerfile / trivy misconfig) 로 emit.

| 도구 결과 | severity | 비고 |
|---|:---:|---|
| trivy CRITICAL CVE | **P0** | no-pass · immediate FIX |
| trivy HIGH CVE | **P1** | FIX with mitigation plan |
| trivy MEDIUM / LOW CVE | advisory (P2) | no FIX gate · 단 design 시점 검토 권고 |
| trivy misconfig (CRITICAL) | **P0** | Dockerfile · k8s manifest critical misconfig |
| trivy misconfig (HIGH) | **P1** | best-practice 위반 |
| hadolint error | **P0** | Dockerfile syntax 결함 (build fail) |
| hadolint warning | **P1** | best practice 위반 (mitigation 가능) |
| hadolint info | advisory (P2) | no FIX gate |

**Mitigation 정책**:
- trivy `--ignore-unfixed: true` (default) — base image CVE 변동 의존 noise 회피. fixed-version 가용 CVE 만 gate.
- hadolint `failure-threshold: warning` — info-level pass.

본 rule 은 SecurityTest lane 만 적용. DesignReview / CodeReview lane finding 에는 영향 없음 (SecurityArch / SecurityTest 분담 — wrapper [CLAUDE.md](https://github.com/mclayer/plugin-codeforge/blob/main/CLAUDE.md) "Design / Code / Security 리뷰 책임 매트릭스" SSOT).

ADR 근거: [ADR-033](https://github.com/mclayer/plugin-codeforge/blob/main/docs/adr/ADR-033-docker-first-infra-engineering.md) §결정 4. SecurityTestPLAgent 1차 layer fetch 의무 = [`agents/SecurityTestPLAgent.md`](../agents/SecurityTestPLAgent.md) §"1차 layer fetch 의무".

### Adversarial debate (debate-protocol-v1) — CFP-391 / ADR-059

DesignReview lane 만 자동 발동 (Story 1 scope). Codex worker 가 활성된 상태에서 두 worker review-verdict-v4 packet 수신 후 PL 이 divergence detection 알고리즘 수행 → criteria match 시 debate-protocol-v1 Round dispatch.

본 sub-section 4종 SOP (§3.0~§3.3) 는 DesignReviewPLAgent 의 verdict 합성 알고리즘 일부. CodeReview / SecurityTest lane 은 deferred CFP-C (Codex 활성 후 향후 도입).

#### §3.0 Divergence detection

DesignReviewPL 이 두 워커 review-verdict-v4 packet 수령 후 다음 알고리즘으로 divergence 감지:

```
for anchor_id in union(claude_findings[*].anchor_id, codex_findings[*].anchor_id):
    claude_f = find(claude_findings, anchor_id) or None
    codex_f  = find(codex_findings,  anchor_id) or None

    # Case 1: 한쪽만 발화
    if claude_f and not codex_f:
        divergence_type = "recommendation"  # silent = PASS, 발화 = FIX/FIX_DISCRETIONARY
    elif codex_f and not claude_f:
        divergence_type = "recommendation"  # silent = PASS, 발화 = FIX/FIX_DISCRETIONARY
    # Case 2: 양측 발화 — severity 또는 recommendation 비교
    elif claude_f.severity != codex_f.severity:
        divergence_type = "severity"
    elif claude_f.recommendation != codex_f.recommendation:
        divergence_type = "recommendation"
    else:
        divergence_type = None  # aligned, debate 미발동
```

`criteria: [severity_mismatch, recommendation_mismatch]` (team-spec-design-review.yaml `divergence_detection.criteria`) 정합. anchor 수집은 review-verdict-v4 `findings[].anchor_id` field SSOT.

#### §3.0.5 dispatch_mode 결정 (debate-protocol-v1 v1.1 — CFP-533 / ADR-059 Amendment 1)

divergence detection 결과 `divergence_detected: true` 시 PL 이 다음 branch logic 으로 dispatch_mode 결정 — Phase 1 verdict 생성 직전, Round 0 dispatch 발동 전 단계:

```
1. consumer / user ad-hoc explicit request 감지 시:
   → dispatch_mode = "user_request_only"
   → trigger schema 작성 후 사용자 dialog 통해 manual dispatch
2. divergence anchor 들의 file path 추출 + severity 추출:
   a. single_file_scope = (len(set(anchor.file for anchor in divergence_anchors)) == 1)
   b. severity_capped = all(anchor.severity in {P1, P2} for anchor in divergence_anchors)
3. (a) AND (b) 모두 True:
   → dispatch_mode = "mechanical_fast_path_inline"
   → debate Round 0 dispatch 안 함
   → PL inline 판정 (양 worker finding 의 reasoning trail 검토 후 final verdict 결정)
   → transcript Story §9 append 면제 (debate 미발동)
   → §10 FIX Ledger row append 의무 보존 (resolution column 에 PL inline reasoning verbose 기록)
   → debate_artifact_ref = null
4. (a) OR (b) 미충족 (multi-file 또는 P0 critical):
   → dispatch_mode = "auto_on_divergence" (표준 multi-round debate)
   → §3.1 Debate dispatch 진입 (Round 0 init)
```

**우선순위 룰**: `auto_on_divergence > mechanical_fast_path_inline > user_request_only`. 두 mode 동시 활성 가능 영역 (예: explicit user request + auto-divergence detection) 시 더 강한 쪽 effective.

**조건 모호 시 fallback**: single-file 경계 또는 severity 경계 모호 시 `auto_on_divergence` 채택 (안전 방향 — false negative 회피 우선).

**review-verdict-v4 packet 의 dispatch_mode 필드**: PL 이 Phase 1 verdict packet 작성 시 `trigger.dispatch_mode` 채움 (v1.1 required). `mechanical_fast_path_inline` 채택 시 packet 의 `worker_dialog_rounds: 0` + `findings[]` PL inline judgment 결과 반영.

**FIX 통합 (mechanical_fast_path_inline 시)**: §3.3 Transcript 영속화 절차 면제. 대신 §10 FIX Ledger row 의 resolution column 에 PL inline reasoning verbose 기록 의무 — audit trail 보존 forcing function. ArchitectPLAgent re-spawn 시 §10 row 의 root_cause + resolution column 만으로 redesign context 충족 (debate transcript 부재 인지).

ADR cross-ref:
- ADR-059 §결정 6 (Amendment 1, CFP-533) — protocol-level dispatch_mode SSOT
- ADR-044 §결정 2 Amendment 1 — team-spec layer dispatch_mode (별 layer)
- debate-protocol-v1 v1.1 §3.9 — dispatch_mode 결정 알고리즘 SSOT

#### §3.1 Debate dispatch

divergence detection 결과 1개 이상 anchor 에서 divergence_type != None 시 debate-protocol-v1 Round 0 init:

- **Round 0** (init): trigger schema 작성 + 양 worker initial_position 추출 + topic_anchor 원문 캡처
- **Round 1 ~ N** (max 5):
  - 매 라운드 입력 최상단 topic_anchor prepend 의무 (drift forcing function)
  - 매 라운드 system_prompt_appendix verbatim 재주입 (anti-sycophancy directive)
  - 양 worker output 수신 후 PL 이 `remaining_disagreements` non-empty 검증 + `position_change: true` 시 `position_change_reason` 검증 (invalid → 재발화 요청 1회 한정, EC-3 / EC-4)
- **min 3 force_continue**: `remaining_disagreements` 비어있고 `dialog_rounds_count < 3` 시 PL 이 adversarial_prompt 재주입 후 Round 추가 (EC-2)
- **max 5 escalation**: `dialog_rounds_count == 5` 도달 + 미합의 시 PL 이 escalation_packet 으로 AskUserQuestion 발화 (§3.5 정합)

영속화: 매 라운드 output 은 PL 이 in-memory transcript 누적. final verdict 결정 후 termination block 작성 + Story §9 inline append (§3.3 정합).

#### §3.2 Anchor 재발 검사

DesignReview lane 진입 직전 (Round 0 dispatch 전) PL 이 Story §9 scan 으로 anchor_id 재발 검출:

```
count = grep -c '^### Debate transcript: <anchor_id>\s*$' docs/stories/<KEY>.md
if count >= 2:
  termination.method = "anchor_recurrence"
  → AskUserQuestion escalation (debate Round 진입 없이 즉시)
```

`>= 2` 시 PL 이 정리한 packet:
- (a) topic_anchor 원문
- (b) 이전 debate 최종 verdict + 양측 마지막 라운드 입장
- (c) ArchitectAgent 가 적용한 redesign 요지
- (d) 재발 finding 의 새 context (의미적으로 같은 쟁점인지 PL 판단 근거)
- (e) 사용자 중재 옵션 제시

**EC-7**: ArchitectAgent 수정 후 동일 `anchor_id` 가 발화되었으나 PL 이 명확히 다른 쟁점으로 판단 시 `anchor_recurrence_count` 증가 안 함. 모호 시 사용자 escalation 우선 (안전 방향).

ADR 근거: [ADR-059](https://github.com/mclayer/plugin-codeforge/blob/main/docs/adr/ADR-059-debate-protocol-v1.md) §결정 4.

#### §3.3 Transcript 영속화

debate verdict 가 `FIX` 또는 `FIX_DISCRETIONARY` 시 다음 흐름 강제:

1. **Story §9 inline append**: section header format `### Debate transcript: <anchor_id>` (Story §9 하위 sub-section). schema = trigger / rounds / termination 3 block (debate-protocol-v1 §2 정합)
   - writer = DesignReviewPL via Orchestrator self-write delegate (ADR-039 Amendment 정합)
   - 독립 파일 신설 금지 — `doc-locations.yaml` 신규 doc_type 추가 불필요
2. **§10 FIX Ledger row append** — Orchestrator self-write (fix-event-v1 1.1 contract):
   - `debate_artifact_ref` 필드 = `#debate-transcript-<anchor_id>` (Story §9 section anchor link)
3. **ArchitectPLAgent re-spawn** — prompt 에 debate transcript 명시적 주입 (verbatim, 요약 금지)
4. **ArchitectAgent re-run instruction**: "양측 입장의 reasoning trail 을 반영해 redesign 하라. transcript 의 양보 / 반박 / 미해결 disagreement 를 모두 검토 후 새 change-plan / ADR 작성."
5. DesignReview re-entry (FIX-N+1) — Story §10 FIX Ledger 카운터 정합

`check-doc-section-schema.sh` (wrapper repo) 가 Story §9 의 `### Debate transcript: ` prefix sub-section 인식 + 내부 schema 검증 (anchor_id non-empty + trigger/rounds/termination 3 block + rounds 최소 1 entry).

### 4-invariant boundary completeness flag (ADR-068 §결정 2 dual-binding)

DesignReview 와 CodeReview PL 이 `findings[].type: "boundary-completeness"` (review-verdict-v4 v4.3) 로 I-1~I-4 위반을 flag 하는 공통 check table.

| Invariant | DesignReview check | CodeReview check |
|---|---|---|
| I-1 API contract semantic completeness | ArchitectAgent §3/§7 docstring template 누락 시 finding | impl docstring ↔ Story §7 enum/state semantics 매핑 검증 |
| I-2 Cross-module propagation completeness | status enum mapping 표 누락 시 finding | caller (호출 site) 의 enum 분기 처리 누락 시 finding |
| I-3 Guard placement intent | invariant guard 위치 (unconditional/conditional) ADR 본문 명시 누락 시 finding | impl assertion / pre-condition 위치 ADR 명시와 mismatch 시 finding |
| I-4 Wording SSOT | Story §3/§7 enum identifier ↔ ADR 본문 wording desync 시 finding | impl enum identifier ↔ Story §7 wording desync 시 finding |

Violation finding type: `boundary-completeness` (review-verdict-v4 v4.3 `findings[].type` literal).

**적용 원칙**:
- DesignReview = 설계 문서 감사 관점 (§3/§7 기술 방식 완결성 검증)
- CodeReview = 구현 cross-validate 관점 (impl ↔ 설계 wording / 분기 정합성 검증)
- Severity default = P1 (boundary-completeness 위반이 구현 오류로 전파될 시 P0 가능)
- ADR-068 §결정 2: ArchitectAgent 는 `boundary_completeness_self_check_passed: bool` emit (verdict packet), DesignReview/CodeReview PL 은 findings[] 로 cross-validate — 양 채널이 dual-binding 을 구성

### I-5 Dimensional empirical grounding (Amendment 1 — CFP-528, 2026-05-13)

**I-5 (Dimensional empirical grounding)**: §3 / §7 의 quantitative parameter (10 dimension enum: latency / scale / cardinality / throughput / cost / accuracy / lifecycle / volume / rate / count) 마다 `[empirical-source: <ref>]` 또는 `[empirical-source: TBD]` annotation 부재 시 finding emit (severity P1, category `dimensional_empirical_gap`, type `"dimensional-empirical-gap"`). Verification format: empirical-source-annotation.

**Trigger 4종 (anti-pattern entry condition)**:
- empirical-absent default (#319 RETRO-MCT-104 carrier)
- synthetic guess
- industry-assumption transplant
- legacy inertia

**Mitigation 4종**:
- empirical-first
- TBD 박제 (annotation 보존, 후속 측정 채움 carrier)
- range-bound
- dimensional checklist

**Justification (annotation 면제)**: well-defined SLA / standardized protocol RFC / vendor doc explicit guarantee.

**Exemption (trivial decision)**: SLA / quantitative metric 무관 — Story §1 명시 선언 의무.

**CodeReviewPL Tier C cross-validate (I-5)**: impl level 의 hardcoded numeric value 가 ADR / Story 의 empirical-source annotation 과 mismatch 시 finding emit (예: ADR 에 `200ms [empirical-source: wiretap]` 박제했는데 impl 에 `30s` hardcode → finding).

**적용 원칙**:
- DesignReview Tier B (design-review-time) = §3 / §7 quantitative parameter annotation 누락 / mitigation 미적용 detect
- CodeReview Tier C (code-review-time) = impl ↔ ADR / Story empirical-source 정합성 cross-validate
- Severity default = P1 (empirical-source 누락이 SLA 위반 / accuracy regression 으로 전파 시 P0 가능)
- ADR-068 §결정 2 Amendment 1: ArchitectAgent 는 `dimensional_empirical_self_check_passed: bool` emit (verdict packet, review-verdict-v4 v4.4), DesignReview / CodeReview PL 은 `findings[].type: "dimensional-empirical-gap"` 로 cross-validate — boundary-completeness dual-binding 과 동일 패턴

---

## 4. FIX 카운터 SSOT

- **카운터 SSOT** = `docs/stories/<KEY>.md` §10 "FIX Ledger" (GitHub Issue 라벨 `fix:<레인>-retry`는 보조 지표)
- PL이 FIX 판정 시 `pl_recommendation=FIX` 반환만 — §10 FIX Ledger append 는 codeforge core Orchestrator 단독 책임 (CFP-32 monopoly · `fix-event-v1` contract)
- §10 commit → `fix-ledger-sync.yml` Action이 자동 (1) Issue comment `[FIX #N]` mirror, (2) `fix:<레인>-retry` 라벨 부착
- "현재 사이클" count = §10 RESET 마커 이후 iteration 합산

레인별 한도는 각 PL md에서 명시.

---

## 5. 보고 형식

### Verdict-return 우선 원칙 (R2)

PL은 severity 종합 후 **즉시 Orchestrator에 verdict return** (PASS / FIX / ESCALATE 결정). DocsAgent를 통한 영속 기록(GitHub Issue 코멘트·Story file §9)은 **Orchestrator가 다음 lane spawn을 트리거한 직후 background drain**으로 처리.

- ✅ 허용: PL → Orchestrator (verdict) → Orchestrator → 다음 lane spawn ∥ DocsAgent (background, mode: background)
- ❌ 금지: PL이 DocsAgent save 완료 대기 후 verdict return — save가 다음 lane 게이트가 되면 안 됨

이 분기는 평균 1-2분 단축 ([CFP-19 R2](../docs/superpowers/specs/2026-04-27-cfp-19-orchestration-parallelization.md)).

### PASS

```
✅ <레인> 리뷰 PASS — 다음 단계 진입 승인
- Claude: 이슈 없음 (또는 P2 N건 / P3 N건, 비차단)
- Codex: 이슈 없음 (또는 P2 N건 / P3 N건, 비차단)
다음 단계: <레인별 다음 게이트>
```

### FIX

```
🔧 <레인> 리뷰 FIX — Iteration {i}/{max or ∞}
- Claude 이슈: {P0/P1 summary}
- Codex 이슈: {P0/P1 summary}
- 교차 일치: {양 리뷰어 동시 지적}
- 1차 원인 가정: {구현 / 설계} (해당 시 — 코드/보안 lane만)
- 수정 방향: {ArchitectPLAgent 또는 DeveloperPL 전달용 초안}
다음 단계: <레인별 escalation 경로>
```

### ESCALATE

```
⚠️ <레인> 리뷰 ESCALATE
- 상태: FIX {max}회 후에도 blocking severity 지속
- 요약: {원인 및 남은 이슈}
- 이전 시도: {iteration별 수정 내용 요약 — Story file §10 인용}
- 권장: 사용자 지시 대기
```

### 5.4 Typed verdict 출력 (contract-required v3.0 — CFP-61부터)

§5.1-5.3의 PASS/FIX/ESCALATE 한글 블록은 사람용 보고. **CFP-61부터** PL 출력은 **evidence + advisory recommendation만** — final gate decision은 Orchestrator post-Sonnet self-write 영역. v3 contract surface ([review-verdict-v3.md §3](../docs/inter-plugin-contracts/review-verdict-v3.md) SSOT).

**v2 → v3 BREAKING 변경 (CFP-61, ADR-022)**:
- PL의 `status` 필드 **제거** → `pl_recommendation` (advisory only) 신설
- Sonnet 최종 결정 = `sonnet_final_status` **신설** (Orchestrator populate)
- `decision_state` **신설** — PL 단계에서 `pending_sonnet` 또는 `blocked_packet_incomplete`
- Story §9 / GitHub comment / gate label / phase transition self-write = **Orchestrator이 Sonnet 호출 후 처리** (PL 아님)
- `writes_completed` **유지** — 의미 변경 (PL self-write 결과 → **Orchestrator** self-write audit). PL이 이 필드를 populate하는 것이 아니라 Orchestrator가 자체 write 감사 결과를 기록.

**PL-produced 필드 vs Orchestrator-populated 필드 (CFP-61 / ADR-022 §결정 4)**:

PL이 작성하는 필드 (review evidence + advisory):
- `contract_version`, `lane`, `story_key`, `iteration`
- `findings[]` (전체 배열)
- `pl_recommendation` (advisory — PASS | FIX | FIX_DISCRETIONARY | ESCALATE_PACKET_INCOMPLETE)
- `decision_state` (PL 단계에서 `pending_sonnet` 또는 `blocked_packet_incomplete` 만)

Orchestrator가 Sonnet 호출 후 populate하는 필드:
- `sonnet_final_status` (PASS | FIX — Sonnet binary 결정)
- `decider_decision_ref` (object — packet_id + model)
- `decision_state` (Sonnet 응답에 따라 `decided` | `review_reopen_requested` | `decider_timeout` | `write_partial` | `write_complete` 로 갱신)
- `write_errors[]` (write 실패 시 populate)
- `writes_completed` (모든 6개 sub-field — Orchestrator self-write 감사)

```yaml
review_verdict:
  contract_version: "3.0"          # 필수 — v3부터 PL output = evidence + recommendation, Sonnet decides
  lane: design | code | security   # 필수 — packet과 일치
  story_key: <STORY_KEY>           # 필수 — packet과 일치
  iteration: <int>                 # 필수 — Story §10 FIX Ledger 현재 카운터 값

  pl_recommendation: PASS | FIX | FIX_DISCRETIONARY | ESCALATE_PACKET_INCOMPLETE  # 필수 — advisory, PL 판정 (§3 Worker verdict 변환표 적용)
  decision_state: pending_sonnet | blocked_packet_incomplete  # 필수 — PL stage에서 둘 중 하나

  findings:                         # 필수 — array, 빈 배열 허용 (FIX 라우팅 input — Orchestrator/ArchitectPL 소비)
    - severity: P0 | P1 | P2        # 필수 — P3/unclassified는 §3 규정에 따라 P2 downgrade 또는 drop
      category: <packet category_enum 중 하나>
      file: <path>                  # 필수 — 비-file finding 시 0
      line: <int>                   # 선택 — 0 허용
      evidence: <markdown>           # 필수 — 위치 인용 + 위반 근거
      suggestion: <markdown>         # 필수 — 수정 방향 (코드 patch 아님)

  # Orchestrator populate 후속 필드 (v3부터, PL은 수정 금지):
  sonnet_final_status: PASS | FIX   # Orchestrator populate (Sonnet 결정) — Story §9·GitHub·gate·phase는 이 값 기반
  decider_decision_ref:              # Orchestrator populate — decision-packet-v2.1 reference (CFP-61 / ADR-022)
    packet_id: <story_key>-<3-digit-seq>
    model: claude-sonnet-4-6
  decision_state: decided | review_reopen_requested | decider_timeout | decider_suspended | write_partial | write_complete  # Orchestrator 갱신
  write_errors:                      # Orchestrator populate — decision_state=write_partial 시
    - step: story_section_9 | phase_comment | gate_label_attached | phase_label_transitioned | fix_ledger_append | diagnosis_spawn
      error_class: github_mcp_timeout | edit_conflict | mcp_auth_failure | other
      retry_count: <int>
  writes_completed:                  # Orchestrator self-write audit (CFP-61 — 의미 재정의, PL responsibility 아님)
    story_section_9: <bool>
    phase_comment: <bool>
    gate_label_attached: <bool>
    phase_label_transitioned: <bool>
    fix_ledger_append: <bool>        # FIX 시 only
    diagnosis_spawn: <bool>          # FIX 시 only
```

`mechanical_category` 필드는 본 contract에 정의되지 않음 — plugin 내부 §3 fast-path 분류용 필드로만 PL → Orchestrator 사이드채널.

### 5.5 Self-write 절차 (CFP-61 v3부터 Orchestrator 책임)

v3부터 **PL은 verdict emit만 수행** (evidence + pl_recommendation + decision_state). Story §9 append / GitHub comment / gate label / phase transition은 **Orchestrator이 Sonnet 호출 직후 처리** — PL의 책임이 아님.

**CFP-35 v2 (PL self-write)와 v3 (Orchestrator self-write) 비교**:

| 영역 | v2 (CFP-35) | v3 (CFP-61) |
|------|:---:|:---:|
| Story §9 append | PL write | Orchestrator write |
| GitHub phase comment | PL write | Orchestrator write |
| gate label + phase transition | PL write (PASS only) | Orchestrator write (Sonnet final_status 기반) |
| verdict contract return 타이밍 | PL이 4개 task 완료 후 | PL이 evidence 정리하자마자 |
| writes_completed 필드 | PL self-write 결과 (v2) | **Orchestrator** self-write 감사 (v3 — 의미 재정의, 제거 아님) |

PL의 output boundary (CFP-61 ADR-022):
- ✅ `pl_recommendation` (advisory)
- ✅ `findings[]` (evidence)
- ✅ `decision_state` (pending_sonnet or blocked_packet_incomplete)
- ❌ `sonnet_final_status`, `decider_decision_ref` (Orchestrator populate, PL 수정 금지) — decision-packet-v2.1 reference (CFP-61 / ADR-022)
- ❌ `writes_completed`, `write_errors[]` (Orchestrator self-write 감사 필드, PL 수정 금지)
- ❌ Story §9, GitHub comment, gate label, phase — Orchestrator 책임

**Lane → gate label / next phase 매핑 (Orchestrator이 Sonnet 호출 후 적용)**:
- `lane=design` + `sonnet_final_status=PASS` → `gate:design-review-pass` + `phase:설계-리뷰` → `phase:구현`
- `lane=code` + `sonnet_final_status=PASS` → 게이트 라벨 없음 + `phase:구현-리뷰` → `phase:구현-테스트`
- `lane=security` + `sonnet_final_status=PASS` → `gate:security-test-pass` + `phase:보안-테스트` → (Story 완료, Phase 2 PR mergeable)
- Any lane + `sonnet_final_status=FIX` → gate 라벨·phase 전환 안 함 (회귀 경로: ArchitectPL 또는 DeveloperPL)

---

## 6. Escalation 경로 (FIX 트리거 시)

**수평 호출 금지** — ArchitectPLAgent / DeveloperPL / 다른 PL 직접 호출 금지. 모든 회귀 요청은 Orchestrator 경유.

### 설계 lane (DesignReviewPL)

```
FIX → Orchestrator → ArchitectPLAgent 회귀 → ArchitectAgent 재스폰 의뢰 → Change Plan 갱신 → 설계 리뷰 재실행
```

### 코드/보안 lane (CodeReviewPL · SecurityTestPL)

```
FIX → Orchestrator → DeveloperPLAgent 1차 원인 진단 → ArchitectPLAgent 최종 판정
  ├── 설계 원인 판정: Change Plan 갱신 → Phase 1 follow-up PR → 설계 리뷰부터 재실행
  └── 구현 원인 판정: Phase 2 PR commit append → 해당 lane 재실행
```

원인 판정 decision table은 [CLAUDE.md](../CLAUDE.md) "원인 판정 decision table" 섹션 SSOT.

---

## 7. 이력 영속화 (Story file §9.x)

레인 iteration 종료 시 결과 요약을 Story file §9의 lane별 블록에 누적. v3 contract (CFP-61+)부터는 **Orchestrator이 Sonnet 결정 후 append** (PL 책임 아님 — §5.5 참조). 각 lane plugin 의 CLAUDE.md `Self-write 책임` 표 + codeforge wrapper [CLAUDE.md](https://github.com/mclayer/plugin-codeforge/blob/main/CLAUDE.md) `오케스트레이션 규칙` 참조. 섹션 매핑은 각 PL md에서 명시.

---

## 8. 공통 제약

- **Write/Edit 없음** — 코드·문서 직접 수정 금지
- **수평 호출 금지** — 다른 PL·ArchitectPLAgent·DeveloperPL 직접 호출 금지, Orchestrator 경유
- **다른 lane 판정 관여 금지** — 각 lane 별도 PL이 판정
- **직접 subagent 스폰 불가** — Orchestrator가 워커 병렬 스폰 대행

---

## 9. 활용 플러그인/스킬 (공통)

- `superpowers:systematic-debugging` — FIX 판정 후 수정 방향 초안 시 "symptom 패치 금지" 원칙
- `superpowers:verification-before-completion` — PASS 판정 전 evidence 확인

---

## 10. 워커 의존성 (공통)

- **ClaudeReviewAgent**: 외부 의존성 없어 **항상 필수**
- **CodexReviewAgent**: Codex 플러그인 필수. 미설치 시 해당 lane **진입 불가** — Orchestrator가 설치 안내 후 중단. `SKIPPED` 허용 안 함

워커 상세는 [`agents/ClaudeReviewAgent.md`](../agents/ClaudeReviewAgent.md) · [`agents/CodexReviewAgent.md`](../agents/CodexReviewAgent.md) 참조.

---

## 11. 문서화 표준

GitHub Issue/PR/docs write 책임 분담은 각 lane plugin 의 CLAUDE.md `Self-write 책임` 표 + codeforge wrapper [CLAUDE.md](https://github.com/mclayer/plugin-codeforge/blob/main/CLAUDE.md) `오케스트레이션 규칙` 참조. v3 contract (CFP-61+) 에서는 PL이 evidence + recommendation만 제공, Orchestrator이 Sonnet 호출 후 영속화 — 상세는 §5.5 Self-write 절차.

---

## 12. 버전 이력

| Version | Date | Story | 주요 변경 |
|---------|------|-------|----------|
| v1.0 | CFP-35 | — | Initial typed contract (PL self-write) |
| v2.0 | CFP-35 | — | §5.4: `contract_version: 2.0`, `status: PASS\|FIX\|FIX_DISCRETIONARY`, `writes_completed` 신설 |
| v3.0 | 2026-05-02 | CFP-61 | §5.4: `pl_recommendation` (advisory only) + `decision_state`, Orchestrator post-Sonnet self-write 영역 정의, `writes_completed` 의미 재정의 (PL→Orchestrator self-write audit), `decider_decision_ref` object 신설 (decision-packet-v2.1 / ADR-022) |
| v3.1 | 2026-05-07 | CFP-128 | §3: Container security severity rule append (SecurityTest lane only) — trivy CRITICAL/HIGH/mid + hadolint error/warning/info. ADR-033 §결정 4 sibling sync. |
