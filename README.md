# codeforge-review

[`codeforge`](https://github.com/mclayer/plugin-codeforge) core의 lane-agnostic review subsystem 추출 plugin. 3 review PL (Design / Code / Security) + 2 worker (Claude / Codex) + 공통 base + 3 lane checklist 보유.

[ADR-001](https://github.com/mclayer/plugin-codeforge/blob/main/docs/adr/ADR-001-review-agent-unification.md) 통합 결정 + [CFP-29](https://github.com/mclayer/plugin-codeforge/blob/main/docs/superpowers/specs/2026-04-28-cfp-29-codeforge-review-extraction-design.md) Phase 1 추출 결과.

## Dependencies

**필수**: [`codeforge@mclayer`](https://github.com/mclayer/plugin-codeforge) (>= 0.17.0). 단독 동작 불가 — codeforge core가 review_packet을 주입하고 review_verdict v1 contract로 결과 수령.

본 plugin의 SessionStart hook이 codeforge core 설치 여부 verify. 미설치 시 fail-fast + install 안내.

## 설치

```jsonc
// ~/.claude/settings.json
{
  "extraKnownMarketplaces": {
    "mclayer": { "source": { "source": "github", "repo": "mclayer/marketplace" } }
  },
  "enabledPlugins": {
    "codeforge@mclayer": true,
    "codeforge-review@mclayer": true
  }
}
```

또는 CLI:

```
/plugins install codeforge@mclayer
/plugins install codeforge-review@mclayer
```

## 구조

```
agents/
  DesignReviewPLAgent.md    # lane=design packet 빌더 + dedup + verdict 종합
  CodeReviewPLAgent.md      # lane=code
  SecurityTestPLAgent.md    # lane=security + 1차 layer fetch (Dependabot/CodeQL/Secret/Push Protection)
  ClaudeReviewAgent.md      # lane-agnostic worker (Claude 네이티브)
  CodexReviewAgent.md       # lane-agnostic worker (Codex GPT-5 wrapper)

templates/
  review-pl-base.md         # 3 PL 공통 base — severity 종합 / dedup / 보고 형식 / escalation SSOT
  review-checklists/
    design.md
    code.md
    security.md

overlay/hooks/
  session-start-deps-check.sh  # codeforge core 설치 verify
  regen-agents.sh              # 자기 agents 재생성 (core merge.py 재사용)
```

## Inter-plugin Contract — review_verdict v1

PL이 워커 결과 종합 후 codeforge core (Orchestrator) 에 반환하는 typed schema. **review plugin은 직접 write 안 함** — Story §9 / GitHub PR comment / gate label 등 lifecycle write는 모두 core/DocsAgent 책임.

상세 schema: codeforge core repo의 [`docs/inter-plugin-contracts/review-verdict-v1.md`](https://github.com/mclayer/plugin-codeforge/blob/main/docs/inter-plugin-contracts/review-verdict-v1.md). 본 plugin이 그 contract version v1을 준수.

향후 contract 변경 시:
- v1.x backward-compat: 새 선택 필드 추가만 가능 (양쪽 plugin 무관)
- v2.0 BREAKING: 양쪽 plugin 동시 bump + ADR 신설

상세는 codeforge core [ADR-008](https://github.com/mclayer/plugin-codeforge/blob/main/docs/adr/ADR-008-inter-plugin-contract-versioning.md) (Inter-plugin Contract Versioning).

## Versioning

`codeforge-review` 자체 version은 codeforge core version과 **독립**. review packet/verdict contract version v1과 호환되는 이상 자유롭게 bump 가능.

| codeforge-review | codeforge core compat |
|---|---|
| v0.1.x | >= 0.17.0 |
| v1.x (조건부 향후) | >= 0.17.0 (v1 contract 유지 시) |

## License / Author

codeforge core와 동일 (Josh / mclayer).
