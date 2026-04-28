---
kind: contract
contract_version: "2.0"
status: Active
related_plugins:
  - codeforge (wrapper, consumer of FIX routing data)
  - codeforge-review (lane plugin, producer + self-writer)
related_adrs:
  - ADR-001 (review-agent-unification — lane-agnostic worker)
  - ADR-008 (Inter-plugin Contract Versioning)
authors:
  - CFP-35 ζ arc retrofit (2026-04-29) — first lane self-write 검증
---

# review_verdict v2 — Inter-plugin Contract (CFP-35 ζ arc retrofit)

`codeforge-review` plugin → `codeforge` core (Orchestrator) 단방향 schema. v1과 BREAKING — PL이 **자기 lane writer 역할 직접 수행**, core(DocsAgent) write 위임 제거.

**상위 SSOT 위치**:
- 본 file (codeforge-review repo): canonical schema + example + ESCALATE 처리
- `mclayer/plugin-codeforge/docs/inter-plugin-contracts/review-verdict-v2.md`: sibling reference (sync 의무)
- [`docs/adr/ADR-001-review-agent-unification.md`](../adr/ADR-001-review-agent-unification.md): lane-agnostic 통합 결정

## 1. v1 → v2 BREAKING 변경 요약

| 영역 | v1.0 (CFP-29 ~ CFP-34) | v2.0 (CFP-35부터) |
|---|---|---|
| Story §9 작성 | core(DocsAgent)가 verdict.summary_for_story_section_9 받아서 write | **PL 직접 Edit(docs/stories/<KEY>.md §9)** |
| GitHub Issue/PR comment | core(DocsAgent)가 verdict.summary_for_pr_comment 받아서 phase prefix 적용 + 게시 | **PL 직접 mcp__github__add_issue_comment** |
| gate:* label 부착 (PASS) | core(DocsAgent)가 verdict.next_gate_label 받아서 attach | **PL 직접 mcp__github__issue_write** |
| phase:* 라벨 전환 (PASS) | core(DocsAgent) | **PL 직접** |
| §10 FIX Ledger append | DocsAgent (~CFP-31) → Orchestrator (CFP-32부터) | (변화 없음) Orchestrator 단독 |
| Verdict schema | `summary_for_story_section_9`, `summary_for_pr_comment`, `next_gate_label` 필드 보유 | **위 3 필드 제거** + `writes_completed` audit field 신설 |

## 2. 흐름 개요

```
codeforge core (Orchestrator)
        │
        │ ① review_packet 작성 (lane-specific, contract_version: "1.0" 유지 — packet은 변화 없음)
        ▼
codeforge-review plugin
  └─ <Lane>ReviewPLAgent
        │
        │ ② Orchestrator가 한 메시지에 두 워커 dispatch (Claude ∥ Codex)
        ▼
  ├─ ClaudeReviewAgent
  └─ CodexReviewAgent
        │
        │ ③ 워커 결과 PL에 return
        ▼
  └─ <Lane>ReviewPLAgent dedup + severity 종합
        │
        │ ④ PL self-write (CFP-35 v2 신설):
        │    - Edit(docs/stories/<KEY>.md §9 append)
        │    - mcp__github__add_issue_comment ([<lane>-리뷰] / [보안-테스트] prefix)
        │    - PASS 시: gate:*-pass + phase:*-리뷰 → 다음 phase 라벨 전환
        ▼
        │ ⑤ review_verdict v2 typed output (writes_completed audit)
        ▼
codeforge core (Orchestrator)
        │
        │ ⑥ verdict 처리:
        │    - status=PASS → 다음 lane 진입
        │    - status=FIX → §10 FIX Ledger append (Orchestrator 직접)
        │      → DeveloperPL/ArchitectPL 병렬 진단·판정 (CFP-19 R4)
        │    - status=ESCALATE_PACKET_INCOMPLETE → 사용자 ESCALATE
        ▼
```

## 3. review_verdict v2 schema (PL → Orchestrator)

```yaml
review_verdict:
  contract_version: "2.0"          # 필수 — v2 마커
  lane: design | code | security   # 필수 — packet과 일치
  story_key: <STORY_KEY>           # 필수 — packet과 일치
  iteration: <int>                 # 필수 — Story §10 FIX Ledger 현재 카운터 값

  status: PASS | FIX | FIX_DISCRETIONARY | ESCALATE_PACKET_INCOMPLETE  # 필수

  findings:                         # 필수 — array, 빈 배열 허용
    - severity: P0 | P1 | P2        # 필수 — P3/unclassified는 P2 downgrade 또는 drop
      category: <packet category_enum 중 하나>
      file: <path>                  # 필수 — 비-file finding 시 0
      line: <int>                   # 선택 — 0 허용
      evidence: <markdown>           # 필수 — 위치 인용 + 위반 근거
      suggestion: <markdown>         # 필수 — 수정 방향

  writes_completed:                  # 필수 — PL self-write 결과 audit (v2 신설)
    story_section_9: <bool>         # 필수 — docs/stories/<KEY>.md §9 append 완료
    phase_comment: <bool>           # 필수 — GitHub Issue/PR comment 게시 완료
    gate_label_attached: <bool>     # 필수 — gate:*-pass label 부착 (PASS only)
    phase_label_transitioned: <bool> # 필수 — phase:* 다음 단계로 전환 (PASS only)
```

## 4. ESCALATE 처리

```yaml
review_verdict:
  contract_version: "2.0"
  status: ESCALATE_PACKET_INCOMPLETE
  ...
  writes_completed:                 # 자기 write 단계 일부라도 실패 시 ESCALATE
    story_section_9: false
    phase_comment: false
    gate_label_attached: false
    phase_label_transitioned: false
```

PL self-write 단계 실패 (예: Story file 부재, GitHub MCP timeout) 시:
- Verdict.status = ESCALATE_PACKET_INCOMPLETE
- writes_completed 모든 필드 false
- Orchestrator 가 사용자 ESCALATE → 수동 복구 요청

## 5. v2 → v3 변경 가능성

다음 조건에서 v3 BREAKING 가능:
- writes_completed 필드 schema 확장 (예: 부분 성공 enum 추가)
- ESCALATE 처리 시 retry 정책 도입 (현재 즉시 user 에스컬레이션)
- 새 lane 추가 (예: 4번째 review lane) — lane enum 확장 시 v2.x minor (값 추가는 backward compat)

## 6. v1 deprecate 시점 + 향후 archive

- **v1 status**: Active → Deprecated (CFP-35 머지 직후)
- **v1 archive**: 6 CFP 무사고 후 (= v2 안정화 확인) — 별도 cleanup CFP에서 file 삭제

## 7. 본 contract 시점 동결 ATTRIBUTION

- 동결 일시: 2026-04-29 (CFP-35)
- 협업: Claude (codification) · Codex round 2 (sequencing 권고 — review v2 retrofit이 first lane self-write 검증 단계로 적합)
- Source: `mclayer/plugin-codeforge-review` repo `templates/review-pl-base.md` §5.4-5.5
