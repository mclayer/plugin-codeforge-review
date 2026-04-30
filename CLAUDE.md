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

## Drift-avoidance discipline (수정 시 반드시 지키세)

본 repo는 SSOT 분리를 명시적으로 강제. **공통 로직을 PL md에 다시 인라이닝하지 말 것** — 항상 base 템플릿 참조.

## Inter-plugin contract — review_verdict v1

PL이 Orchestrator에 반환하는 typed schema. SSOT는 codeforge core repo의 `docs/inter-plugin-contracts/review-verdict-v1.md` — 본 plugin은 contract 준수만 한다.

## Versioning 룰

`codeforge-review` 자체 version은 codeforge core version과 **독립**. v1 contract 호환되는 한 자유롭게 bump.

## Hook chain

- `SessionStart` → [overlay/hooks/session-start-deps-check.sh](overlay/hooks/session-start-deps-check.sh) → core 설치 verify → [overlay/hooks/regen-agents.sh](overlay/hooks/regen-agents.sh) 체인 실행
- `regen-agents.sh`는 core의 `overlay/hooks/merge.py`를 재사용해 `agents/*.md`를 `.claude/agents/`로 머지 출력.

## Worker 호출 규약 (편집 시 침해 금지)

- **Packet 누락 = 즉시 `ESCALATE_PACKET_INCOMPLETE` 반환**
- 워커는 서로 보고 미참조 — 독립 peer로 병렬 수행
- 워커는 **직접 다른 subagent 스폰 불가**
- **WebSearch/WebFetch는 `lane=security`만** 사용 가능
- `lane=security` PL은 워커 spawn 전 GitHub native 1차 layer fetch 의무

## Dogfood policy (CFP-45)

본 plugin repo 는 runtime SSOT 만 보유. dogfood artifacts (specs/plans/retros/stories/change-plans) 는 [`mclayer/codeforge-internal-docs`](https://github.com/mclayer/codeforge-internal-docs) 단일 monorepo SSOT. 본 plugin 폴더는 `codeforge-internal-docs/review/`. 상세 정책 + Story workflow 흐름은 wrapper [CLAUDE.md](https://github.com/mclayer/plugin-codeforge/blob/main/CLAUDE.md) canonical SSOT 참조 + [ADR-013](https://github.com/mclayer/plugin-codeforge/blob/main/docs/adr/ADR-013-codeforge-family-dogfood-out-policy.md) (PR-I 머지 후 Adopted).

Plugin repo 측 GitHub Issue 와 internal-docs 측 Story file 의 binding:
- Issue body frontmatter: `story_uri: <internal-docs URL>`
- Story file frontmatter: `story_issues: [{repo: "mclayer/plugin-codeforge-review", number: <N>}]`
- `.github/workflows/phase-gate-mergeable.yml` (본 repo) 가 cross-repo Story fetch via GitHub App
