# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 본 repo의 정체

`codeforge-review` Claude Code plugin. **실행 코드 없음** — 전부 markdown(agents/templates) + 2개 shell hook. 빌드/린트/테스트 step 없음.

**단독 동작 불가**: [`codeforge@mclayer`](https://github.com/mclayer/plugin-codeforge) core plugin (>= 0.17.0) 의존. core의 Orchestrator agent가 본 plugin의 PL agent에 review_packet을 주입하고, [`review_verdict v1`](https://github.com/mclayer/plugin-codeforge/blob/main/docs/inter-plugin-contracts/review-verdict-v1.md) contract로 결과 수령. core 미설치 시 [overlay/hooks/session-start-deps-check.sh](overlay/hooks/session-start-deps-check.sh)가 fail-fast.

추출 컨텍스트: codeforge core v0.16.0 (commit `1e75442`)에서 Phase 1 분리. 자세한 사항 [docs/adr/ADR-001-extracted-from-codeforge.md](docs/adr/ADR-001-extracted-from-codeforge.md).

## Architecture — PL + Worker 패턴

```
Orchestrator(core)
  └─ DesignReviewPL  | CodeReviewPL | SecurityTestPL   ← lane 진입 시 1개 스폰
       ↓ review_packet 주입
       └─ ClaudeReviewAgent ∥ CodexReviewAgent          ← 한 메시지에 병렬 dispatch
```

- **3 PL agent** (`agents/{Design,Code,SecurityTest}ReviewPLAgent.md`) — 각 lane의 packet builder + verdict 종합. 워커 결과를 dedup → severity 종합 → PASS/FIX/ESCALATE 반환. **Write/Edit 권한 없음** (코드·docs 직접 수정 금지).
- **2 worker agent** (`agents/{Claude,Codex}ReviewAgent.md`) — lane-agnostic. PL이 packet으로 도메인(checklist · scope · category enum · severity override) 주입. **둘 다 필수 peer** — Claude/Codex 단독 fallback 허용 안 함.
- **공통 base** [templates/review-pl-base.md](templates/review-pl-base.md) — 3 PL이 공유하는 severity 종합·dedup·noise 분류·보고 형식·escalation·FIX Ledger·워커 의존성 SSOT. 각 PL md는 lane-specific 4가지(checklist packet · FIX 카운터 정책 · 검증 스코프 · 다음 게이트)만 본문에 명시.
- **3 lane checklist** (`templates/review-checklists/{design,code,security}.md`) — 각 lane의 항목·자동 P0 룰. PL이 packet의 `checklist_path`로 워커에 전달.

## Drift-avoidance discipline (수정 시 반드시 지킬 것)

본 repo는 SSOT 분리를 명시적으로 강제. **공통 로직을 PL md에 다시 인라이닝하지 말 것** — 항상 base 템플릿 참조:

- severity 종합·dedup·보고 형식 변경 → [templates/review-pl-base.md](templates/review-pl-base.md) 만 수정
- packet schema 변경 → 동 파일 §2만 수정 (워커 md에서 schema 자체를 재인용 금지 — `ClaudeReviewAgent.md` / `CodexReviewAgent.md`의 `## 입력` 섹션이 base §2를 가리키게 유지)
- mechanical_category fast-path 분류 → base §3 SSOT, 각 lane checklist md는 참조만 (재정의 금지)
- 원인 판정(설계 vs 구현) decision table → core repo의 `CLAUDE.md` "원인 판정 decision table" 섹션 SSOT — `CodeReviewPLAgent.md` / `SecurityTestPLAgent.md`에서 inline 발췌 금지

## Inter-plugin contract — review_verdict v1

PL이 Orchestrator에 반환하는 typed schema. SSOT는 codeforge core repo의 `docs/inter-plugin-contracts/review-verdict-v1.md` — 본 plugin은 contract 준수만 한다.

- v1.x backward-compat: 새 선택 필드 추가만 가능 (양쪽 plugin 무관)
- v2.0 BREAKING: 양쪽 plugin 동시 bump + ADR 신설 (core [ADR-008](https://github.com/mclayer/plugin-codeforge/blob/main/docs/adr/ADR-008-inter-plugin-contract-versioning.md))

PL이 lifecycle write(Story §9 / Issue 코멘트 / gate 라벨)를 직접 수행 금지 — 모두 core/DocsAgent 책임.

## Versioning 룰

`codeforge-review` 자체 version은 codeforge core version과 **독립**. v1 contract 호환되는 한 자유롭게 bump. 호환 매트릭스는 [README.md](README.md) "Versioning" 섹션 SSOT — 새 release마다 갱신.

## Hook chain

- `SessionStart` → [overlay/hooks/session-start-deps-check.sh](overlay/hooks/session-start-deps-check.sh) → core 설치 verify → [overlay/hooks/regen-agents.sh](overlay/hooks/regen-agents.sh) 체인 실행
- `regen-agents.sh`는 core의 `overlay/hooks/merge.py`를 재사용해 `agents/*.md`를 `.claude/agents/`로 머지 출력 (consumer overlay `.claude/_overlay/agents/<name>.md` 있으면 적용). **core merge.py 미발견 시 fail** — sibling discovery 안 함, 본 plugin의 `agents/`만 iterate.

hook 수정 시 core merge.py 인터페이스 호환성 깨지지 않도록 주의 (cross-repo coordination — ADR-001 §부정/Trade-off).

## Worker 호출 규약 (편집 시 침해 금지)

- **Packet 누락 = 즉시 `ESCALATE_PACKET_INCOMPLETE` 반환** — 워커가 generic fallback 절대 금지 ([ADR-001](docs/adr/ADR-001-extracted-from-codeforge.md) §결정 4번 패턴). PL/워커 md 수정 시 이 의미를 우회하는 fallback 경로 추가 금지.
- 워커는 서로 보고 미참조 — 독립 peer로 병렬 수행. 교차 검증은 호출 PL 책임.
- 워커는 **직접 다른 subagent 스폰 불가** — Orchestrator가 한 메시지에 두 워커를 dispatch (재귀 spawn 플랫폼 제약).
- **WebSearch/WebFetch는 `lane=security`만** 사용 가능 — design/code lane에서는 외부 fetch 금지 (repo 내부 문서·코드만 근거).
- `lane=security` PL은 워커 spawn 전 GitHub native 1차 layer(Dependabot/CodeQL/Secret Scanning/Push Protection) fetch 의무 — packet에 inline 첨부.

## 자주 보는 함정

- agent md frontmatter의 `permissions.deny`(`Edit(src/**)` 등) 은 review plugin 전체 정책 — 새 PL/worker 추가 시 동일 deny 룩 유지.
- 본 repo에는 `docs/adr/ADR-001-review-agent-unification.md` 가 **없다** — 그건 codeforge core repo의 ADR. 본 repo의 ADR-001은 [docs/adr/ADR-001-extracted-from-codeforge.md](docs/adr/ADR-001-extracted-from-codeforge.md) (추출 사실 ADR). agent md에서 `../docs/adr/ADR-001-review-agent-unification.md` 링크는 core repo로의 외부 참조 — 깨진 링크 아님 (의도적).
