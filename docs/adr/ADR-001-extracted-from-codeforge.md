---
adr_number: 001
title: codeforge core 에서 review subsystem 추출 — codeforge-review plugin 신설
status: Accepted
category: Architecture
date: 2026-04-28
related_files:
  - .claude-plugin/plugin.json
  - agents/*.md (5 review agents)
  - templates/review-pl-base.md
  - templates/review-checklists/{design,code,security}.md
  - overlay/hooks/{session-start-deps-check,regen-agents}.sh
related_stories:
  - CFP-25 (parent design — staged ε strategy)
  - CFP-29 (Phase 1 implementation)
---

# ADR-001: codeforge core 에서 review subsystem 추출 — codeforge-review plugin 신설

## 상태

`Accepted` (2026-04-28)

## 컨텍스트

[`mclayer/plugin-codeforge`](https://github.com/mclayer/plugin-codeforge) (codeforge core)는 24 core agent + 7 lane structure를 monolithic plugin으로 운영. 매 design 변경 (예: CFP-21 DataMigrationArchitect 6번째 deputy 추가)이 9+ file 동시 갱신을 강제 — revision 비용 高.

CFP-25 design spec ([Claude Opus 4.7 + Codex GPT-5.4 4 라운드 협업 결과](https://github.com/mclayer/plugin-codeforge/blob/main/docs/superpowers/specs/2026-04-28-docsagent-scope-reduction-and-review-extraction-design.md))이 "staged ε" strategy 합의: 같은 role-shape의 agent family를 plugin 경계로 분리. 본 추출이 Phase 1 strategic payoff.

전제 (CFP-26 Phase 0a · CFP-27 Phase 0b 머지 완료):
- DocsAgent scope 축소 — single-author docs는 owner agent direct write
- 4 owner doc path schema enforcement 시작 (warning 모드)

## 결정

본 plugin (`codeforge-review`)을 codeforge core repo에서 분리된 별도 `mclayer/plugin-codeforge-review` repo로 신설한다. 추출 대상:

- 5 review agents: `DesignReviewPLAgent` · `CodeReviewPLAgent` · `SecurityTestPLAgent` · `ClaudeReviewAgent` · `CodexReviewAgent`
- 공통 base: `templates/review-pl-base.md` (severity 종합 / dedup / 보고 형식 / escalation SSOT)
- 3 lane checklist: `templates/review-checklists/{design,code,security}.md`

본 plugin은 codeforge core 의존 — 단독 동작 불가. SessionStart hook이 core 설치 verify.

Inter-plugin contract `review_verdict v1` 은 codeforge core repo의 `docs/inter-plugin-contracts/review-verdict-v1.md` SSOT. 본 plugin이 v1 contract 준수.

## 결과

### 긍정

- codeforge core가 review subsystem 변경에서 분리 — revision 비용 ↓
- review plugin이 자체 cadence로 발전 가능 (예: 새 lane checklist 추가 시 core bump 불필요)
- ADR-001 (codeforge core, "Review/Test 워커 통합 — Claude/Codex 2종") 결정이 plugin 경계로 보존 — physical separation
- consumer 입장에서 review plugin 비활성화 옵션 가능 (강제 아님)

### 부정 / Trade-off

- consumer가 두 plugin 모두 설치 의무 — install 절차 복잡화
- cross-repo coordination 필요 (codeforge core ↔ codeforge-review version 호환성)
- contract drift 위험 — ADR-008 (codeforge core, "Inter-plugin Contract Versioning")이 enforcement 룰 정의
- git history 분리 — 본 repo는 fresh start (codeforge core SHA `1e75442a9cb3f0004cf75cd8e0b152745cba532a` attribution만 보존)

### 영향

- codeforge core: v0.17.0 BREAKING (5 agent + base + 3 checklist 삭제)
- consumer: install 추가 + SessionStart hook 새로 trigger
- marketplace: 2 plugin entry (`codeforge` + `codeforge-review`)

## 다이어그램

```
Before (codeforge core monolith — v0.16.0):
  codeforge plugin
   └── 24 agents (review 5 포함) + templates + overlay

After (CFP-29 Phase 1 — v0.17.0):
  codeforge plugin                    codeforge-review plugin (신설)
   ├── 19 agents                       ├── 5 review agents
   ├── templates (review 3 빠짐)       ├── templates/review-pl-base.md
   └── docs/inter-plugin-contracts/    └── templates/review-checklists/
        review-verdict-v1.md (SSOT)
   
   Inter-plugin contract: review_verdict v1
   (codeforge core 가 SSOT, codeforge-review 가 준수)
```

## 관련 파일

- 본 repo: `agents/`, `templates/`, `overlay/hooks/`, `.claude-plugin/plugin.json`
- codeforge core: `docs/inter-plugin-contracts/review-verdict-v1.md`, `docs/adr/ADR-008-inter-plugin-contract-versioning.md`, `CLAUDE.md` "## Inter-plugin Contract" 섹션
- mclayer/marketplace: `.claude-plugin/marketplace.json` plugins[] 에 `codeforge-review` entry
