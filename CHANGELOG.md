# Changelog

`codeforge-review` plugin 릴리스 이력.

버전 체계: [Semantic Versioning 2.0.0](https://semver.org/lang/ko/). v1.0 이전은 minor bump도 breaking 가능.

## [Unreleased]

### Added

- `.github/workflows/invariant-check.yml` — own invariant-check workflow (carryover from codeforge core CFP-29 Phase 1 추출). Review category enum parity (3 lane × SSOT/PL/Codex) + Severity overrides count + breakdown parity (3 lane × SSOT/PL) 검증.

## [0.1.0] - 2026-04-28

### Initial extract from codeforge core

[`mclayer/plugin-codeforge`](https://github.com/mclayer/plugin-codeforge) v0.16.0 (commit `1e75442a9cb3f0004cf75cd8e0b152745cba532a`)에서 lane-agnostic review subsystem 추출.

### Added (initial)

- `agents/DesignReviewPLAgent.md` (codeforge core 에서 이동)
- `agents/CodeReviewPLAgent.md` (이동)
- `agents/SecurityTestPLAgent.md` (이동)
- `agents/ClaudeReviewAgent.md` (이동, lane-agnostic worker)
- `agents/CodexReviewAgent.md` (이동, lane-agnostic worker)
- `templates/review-pl-base.md` (이동, 3 PL 공통 base SSOT)
- `templates/review-checklists/design.md` (이동)
- `templates/review-checklists/code.md` (이동)
- `templates/review-checklists/security.md` (이동)
- `overlay/hooks/session-start-deps-check.sh` (NEW — codeforge core 설치 verify)
- `overlay/hooks/regen-agents.sh` (NEW — codeforge core merge.py 재사용 패턴)
- `docs/adr/ADR-001-extracted-from-codeforge.md` (NEW — 추출 사실 + verdict v1 contract 동결 시점)
- `README.md` + `CHANGELOG.md`

### Why

CFP-25 Phase 1 strategic payoff. codeforge core revision 비용 절감 + ADR-001 lane-agnostic worker 통합을 plugin 경계로 보존. 상세는 codeforge core repo의 [CFP-29 design spec](https://github.com/mclayer/plugin-codeforge/blob/main/docs/superpowers/specs/2026-04-28-cfp-29-codeforge-review-extraction-design.md).

### Migration (from codeforge core monolith)

기존 codeforge consumer는 codeforge >= 0.17.0 + codeforge-review >= 0.1.0 두 plugin 모두 install 의무. 자세한 사항: codeforge core [migration-guide v0.16 → v0.17](https://github.com/mclayer/plugin-codeforge/blob/main/docs/migration-guide.md) 섹션.
