# Changelog

`codeforge-review` plugin 릴리스 이력.

버전 체계: [Semantic Versioning 2.0.0](https://semver.org/lang/ko/). v1.0 이전은 minor bump도 breaking 가능.

## [0.3.0] - 2026-04-29

### Changed

Bundle 1 contract alignment — Codex 협업 gap review에서 확인된 review_verdict v1 contract와 PL/worker md 사이 silent drift 5건 해소 (review-only):

- `templates/review-pl-base.md` §2 — packet에 `contract_version: "1.0"` 필수 필드 추가 + lane×field 매트릭스 행 추가 (gap #3)
- `templates/review-pl-base.md` §3 — Worker verdict (`PASS|ISSUES|NO_SHIP|ESCALATE_PACKET_INCOMPLETE`) → review_verdict.status (`PASS|FIX|FIX_DISCRETIONARY`) 변환표 신설 (gap #1)
- `templates/review-pl-base.md` §3 — P3/unclassified severity 처리 규정 신설 (P3 → P2 downgrade, unclassified → drop or P2) (gap #5)
- `templates/review-pl-base.md` §5.4 — typed verdict YAML 출력 블록 신설 (contract-required 8 필드 명시) (gap #2)
- `agents/{Claude,Codex}ReviewAgent.md` — packet 검증에 `contract_version` 추가; lane=security `first_layer_findings` 부재 시 `ESCALATE_PACKET_INCOMPLETE`로 일관 (이전: 비차단 결손 표기) (gap #7, gap #3)
- `agents/{Design,Code,SecurityTest}ReviewPLAgent.md` — packet 예시에 `contract_version: "1.0"` 첫 줄 추가 (gap #3)
- `.github/workflows/invariant-check.yml` — 신규 step "Packet contract_version presence" 추가 (3 PL × YAML)

### Why

review_verdict v1 contract는 codeforge core SSOT지만 review plugin 측 PL/worker md가 contract 8 필드 중 일부를 silently 누락 emit하거나 enum 불일치를 노출. Codex 협업 gap review에서 7건 P1 drift 확인 — 본 v0.3.0이 review-only 5건 처리. 나머지 cross-repo coordination 2건(`mechanical_category` schema 추가, `next_gate_label` 자기모순 해소)은 별도 PR (Bundle 2).

### Compatibility

`codeforge core` >= 0.17.0 호환 그대로 유지 — contract version v1.0 위반 없음 (오히려 v1.0 enforcement 강화).

상세 plan: [`docs/superpowers/plans/2026-04-29-bundle-1-contract-alignment.md`](docs/superpowers/plans/2026-04-29-bundle-1-contract-alignment.md).

## [0.2.0] - 2026-04-28

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
