# codeforge-review own lint workflow design

**Status**: ready for implementation (handoff from codeforge core CFP-29 Phase 1)
**Date**: 2026-04-28
**Source**: codeforge core PR [#68](https://github.com/mclayer/plugin-codeforge/pull/68) (commit `81a4ad1`) — review subsystem 추출 시 core `.github/workflows/invariant-check.yml`에서 review-specific 단계 2건이 제거됨. 본 repo로 이관해야 정합성 보장 회복.

> 이 spec은 codeforge core 측에서 작성되어 본 repo로 핸드오프된 후속 작업이다. 본 repo Claude 세션에서 곧바로 writing-plans → executing-plans 진행 가능. brainstorming은 결정사항이 이미 확정되어 사실상 spec self-review만 필요.

## Goal

본 repo의 CI에 codeforge core에서 이관된 review-specific 정합성 invariant 2종을 도입한다.

## Background

CFP-29 Phase 1에서 codeforge core의 5 review agent (`{DesignReviewPL, CodeReviewPL, SecurityTestPL, ClaudeReview, CodexReview}Agent.md`) + 공통 base (`templates/review-pl-base.md`) + 3 checklist (`templates/review-checklists/{design,code,security}.md`)가 본 repo로 추출되었다.

core가 보유했던 invariant-check.yml의 9개 단계 중 2개가 **이관 대상 file을 참조**하여 추출 직후 fail 상태였다:

1. **Review category enum parity** (CFP-9 + CFP-13): 3 lane × (SSOT checklist + PL agent + CodexReviewAgent) 카테고리 enum이 동일한지 검증
2. **Severity overrides count + breakdown parity** (CFP-16): 3 lane × (SSOT checklist + PL agent) severity 자동 룰 bullet 개수 + P0/P1 breakdown 동일한지 검증

core PR #68 (commit `9b7e251`)에서 두 단계 통째로 제거하면서 주석으로 "codeforge-review repo 자체 CI에서 enforce해야 함" 명시. 본 spec이 그 후속.

이 두 invariant 없이는 SSOT(checklist md)와 PL agent / Codex agent 간 카테고리 enum / severity rule이 silently drift할 수 있다 (실제 CFP-9/13/16 도입 동기). 본 repo에서 review subsystem이 살아있는 한 동일 위험이 존재.

## Invariants

### Invariant 1: Review category enum parity

**대상 — 3 lane × 3 location**:
- **SSOT**: `templates/review-checklists/<lane>.md` 본문 내 pipe-separated inline code (예: `` `cat-a | cat-b | cat-c` ``)
- **Mirror 1**: `agents/<Lane>PLAgent.md` 본문 내 `category_enum:` YAML list
- **Mirror 2**: `agents/CodexReviewAgent.md` 내 `#### lane=<lane>` 섹션 이후 `category from {a, b, c}` 패턴

**Invariant**: 각 lane에서 3 location의 category list가 **순서까지 동일**.

**왜 필요한가**: 워커(Codex)는 lane별 category enum을 inline set으로 들고 있고 PL은 YAML list로, SSOT 체크리스트는 pipe-separated inline 으로 들고 있어, 한 location만 갱신되면 reviewer가 categorize 시점에 silently 다른 enum 사용 → severity 자동 룰까지 어긋남.

### Invariant 2: Severity overrides count + breakdown parity

**대상 — 3 lane × 2 location**:
- **SSOT**: `templates/review-checklists/<lane>.md`의 `## Severity 자동 룰` 섹션 bullet
- **PL**: `agents/<Lane>PLAgent.md`의 `severity_overrides:` YAML list

**Invariant**:
- bullet 총 개수 동일
- P0 / P1 / Pn breakdown 동일 (예: SSOT P0=3, P1=2면 PL도 P0=3, P1=2)

**string equality는 의도적으로 미적용** — SSOT는 verbose Korean (예: `**X** → P0 강제 (\`category\`)`), PL은 condensed Korean (예: `X → P0`). 작성 시점 의도된 차이. count + severity breakdown만 invariant.

CodexReviewAgent 프롬프트의 severity 영문 요약(`Auto-P0: ADR violation, ...`)은 의도적 영문이라 본 invariant **scope 제외** — 향후 별도 design 필요 시 재검토.

**왜 필요한가**: Severity rule 1개가 SSOT에만 추가되거나 PL에만 추가되면 reviewer가 어느 쪽을 따르냐에 따라 동일 finding의 severity가 달라짐 → P0 자동 차단 누락 또는 false P0.

## File paths in this repo

본 repo에 이미 존재하는 검증 대상 file 7종:

```
templates/review-checklists/design.md
templates/review-checklists/code.md
templates/review-checklists/security.md
agents/DesignReviewPLAgent.md
agents/CodeReviewPLAgent.md
agents/SecurityTestPLAgent.md
agents/CodexReviewAgent.md
```

(ClaudeReviewAgent.md는 본 invariant 대상 아님 — Claude는 lane-agnostic 워커로 category/severity는 packet으로 주입받음)

## Implementation outline

**단일 task — TDD 부적용** (CI workflow는 invariant 자체가 검증 메커니즘이라 별도 unit test 미작성).

신규 file: `.github/workflows/invariant-check.yml`

뼈대:

```yaml
name: invariant-check

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  invariant:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.11"

      - name: Review category enum parity (3 lane × SSOT/PL/Codex)
        run: |
          python3 <<'EOF'
          # [§"Verbatim Python — Invariant 1" 그대로 paste]
          EOF

      - name: Severity overrides count + breakdown parity (3 lane × SSOT/PL)
        run: |
          python3 <<'EOF'
          # [§"Verbatim Python — Invariant 2" 그대로 paste]
          EOF
```

이후:
1. PR open
2. 첫 CI 실행 시 두 단계 모두 **PASS** 확인 (현재 file 상태에서 PASS여야 정상 — drift 없는 baseline)
3. PASS 확인 후 main merge
4. (선택) GitHub Settings > Branches에서 main에 `invariant-check` required status check 등록

## Verbatim Python — Invariant 1

codeforge core commit `9b7e251` 의 삭제 hunk에서 그대로 복사. 파일 경로가 본 repo와 정확히 일치하므로 **수정 없이 그대로 사용**.

```python
"""
3 lane 각각의 review category enum 3 location 정합:
  - SSOT: templates/review-checklists/<lane>.md (pipe-separated inline code)
  - Mirror 1: agents/<Lane>PLAgent.md packet category_enum: YAML list
  - Mirror 2: agents/CodexReviewAgent.md `#### lane=<lane>` 이후 inline {set}

Invariant: 각 lane 3 location 동일 categories + 동일 순서.
"""
import re
import sys
from pathlib import Path

LANES = [
    ("design",   "DesignReviewPLAgent"),
    ("code",     "CodeReviewPLAgent"),
    ("security", "SecurityTestPLAgent"),
]

codex_text = Path("agents/CodexReviewAgent.md").read_text(encoding="utf-8")
all_errors = []

for lane, pl_name in LANES:
    ssot_path = f"templates/review-checklists/{lane}.md"
    pl_path = f"agents/{pl_name}.md"

    # 1. SSOT (pipe-separated inline code)
    ssot_text = Path(ssot_path).read_text(encoding="utf-8")
    ssot_match = re.search(r"`([a-z-]+(?:\s*\|\s*[a-z-]+)+)`", ssot_text)
    if not ssot_match:
        all_errors.append(f"{ssot_path}: pipe-separated category enum 부재")
        continue
    ssot_enum = [s.strip() for s in ssot_match.group(1).split("|")]

    # 2. PL YAML list
    pl_text = Path(pl_path).read_text(encoding="utf-8")
    pl_match = re.search(
        r"category_enum:\s*\n((?:\s*-\s*[a-z-]+\s*\n)+)",
        pl_text,
    )
    if not pl_match:
        all_errors.append(f"{pl_path}: category_enum YAML list 부재")
        continue
    pl_enum = re.findall(r"-\s*([a-z-]+)", pl_match.group(1))

    # 3. Codex lane-anchored set
    codex_match = re.search(
        rf"####\s*lane={lane}.*?category from \{{([^}}]+)\}}",
        codex_text,
        re.DOTALL,
    )
    if not codex_match:
        all_errors.append(
            f"agents/CodexReviewAgent.md: lane={lane} 섹션의 category from {{...}} 패턴 부재"
        )
        continue
    codex_enum = [s.strip() for s in codex_match.group(1).split(",")]

    # 비교 — 3 location list equality (순서 포함)
    if pl_enum != ssot_enum:
        all_errors.append(
            f"[lane={lane}] {pl_path} category_enum ({len(pl_enum)}) ≠ SSOT ({len(ssot_enum)})\n"
            f"  SSOT  : {ssot_enum}\n"
            f"  PL    : {pl_enum}\n"
            f"  diff(only in SSOT): {sorted(set(ssot_enum) - set(pl_enum))}\n"
            f"  diff(only in PL)  : {sorted(set(pl_enum) - set(ssot_enum))}"
        )
    if codex_enum != ssot_enum:
        all_errors.append(
            f"[lane={lane}] CodexReviewAgent.md category set ({len(codex_enum)}) ≠ SSOT ({len(ssot_enum)})\n"
            f"  SSOT  : {ssot_enum}\n"
            f"  Codex : {codex_enum}\n"
            f"  diff(only in SSOT) : {sorted(set(ssot_enum) - set(codex_enum))}\n"
            f"  diff(only in Codex): {sorted(set(codex_enum) - set(ssot_enum))}"
        )

    if pl_enum == ssot_enum and codex_enum == ssot_enum:
        print(f"  ✓ lane={lane}: {len(ssot_enum)} categories x 3 locations")

if all_errors:
    print(f"::error::Review category enum parity 실패 ({len(all_errors)} drift)")
    for e in all_errors:
        for line in e.split("\n"):
            print(f"  {line}")
    sys.exit(1)

print("✓ Review category enum parity: 3 lanes × 3 locations all match")
```

## Verbatim Python — Invariant 2

```python
"""
3 lane 각각의 severity_overrides 정합:
  - SSOT: templates/review-checklists/<lane>.md "## Severity 자동 룰" 섹션 bullet
  - PL: agents/<Lane>PLAgent.md `severity_overrides:` YAML list

Invariant: 각 lane (총 bullet 개수 + P0 개수 + P1 개수) 동일.

Codex 프롬프트는 의도적 영문 요약 (예: "Auto-P0: ADR violation, §8 missing, ...")이라
본 invariant scope 외 — 향후 별도 design 필요 시 재검토.

string equality 미적용 사유: SSOT는 verbose Korean (e.g. "**X** → P0 강제 (`category`)"),
PL은 condensed Korean (e.g. "X → P0"), 작성 시점 의도된 차이. count + breakdown만 invariant.
"""
import re
import sys
from pathlib import Path
from collections import Counter

LANES = [
    ("design",   "DesignReviewPLAgent"),
    ("code",     "CodeReviewPLAgent"),
    ("security", "SecurityTestPLAgent"),
]

SEVERITY_RE = re.compile(r"→\s*P(\d)")

def extract_ssot_severity(path):
    """SSOT의 ## Severity 자동 룰 섹션 bullet 추출 + P0/P1 카운트."""
    text = path.read_text(encoding="utf-8")
    m = re.search(
        r"^## Severity 자동 룰\s*\n(.+?)(?=\n## |\Z)",
        text,
        re.MULTILINE | re.DOTALL,
    )
    if not m:
        return None
    bullets = [
        line for line in m.group(1).split("\n")
        if line.lstrip().startswith("- ")
    ]
    counts = Counter()
    for b in bullets:
        for sev in SEVERITY_RE.findall(b):
            counts[f"P{sev}"] += 1
    return len(bullets), counts

def extract_pl_severity(path):
    """PL의 severity_overrides: YAML list 추출 + P0/P1 카운트."""
    text = path.read_text(encoding="utf-8")
    m = re.search(
        r"severity_overrides:\s*\n((?:\s*-\s*\".+?\"\s*\n)+)",
        text,
    )
    if not m:
        return None
    lines = [
        line for line in m.group(1).split("\n")
        if line.lstrip().startswith("- ")
    ]
    counts = Counter()
    for line in lines:
        for sev in SEVERITY_RE.findall(line):
            counts[f"P{sev}"] += 1
    return len(lines), counts

all_errors = []

for lane, pl_name in LANES:
    ssot_path = Path(f"templates/review-checklists/{lane}.md")
    pl_path = Path(f"agents/{pl_name}.md")

    ssot_result = extract_ssot_severity(ssot_path)
    if ssot_result is None:
        all_errors.append(f"{ssot_path}: '## Severity 자동 룰' 섹션 또는 bullet 부재")
        continue
    ssot_total, ssot_counts = ssot_result

    pl_result = extract_pl_severity(pl_path)
    if pl_result is None:
        all_errors.append(f"{pl_path}: severity_overrides YAML list 부재")
        continue
    pl_total, pl_counts = pl_result

    if ssot_total != pl_total:
        all_errors.append(
            f"[lane={lane}] bullet count 불일치 — SSOT={ssot_total}, PL={pl_total}"
        )
    for sev in sorted(set(ssot_counts) | set(pl_counts)):
        if ssot_counts[sev] != pl_counts[sev]:
            all_errors.append(
                f"[lane={lane}] {sev} count 불일치 — "
                f"SSOT={ssot_counts[sev]}, PL={pl_counts[sev]}"
            )

    if ssot_total == pl_total and all(
        ssot_counts[s] == pl_counts[s]
        for s in set(ssot_counts) | set(pl_counts)
    ):
        breakdown = ", ".join(f"{s}={ssot_counts[s]}" for s in sorted(ssot_counts))
        print(f"  ✓ lane={lane}: {ssot_total} bullets ({breakdown})")

if all_errors:
    print(f"::error::Severity overrides parity 실패 ({len(all_errors)} drift)")
    for e in all_errors:
        print(f"  - {e}")
    sys.exit(1)

print("✓ Severity overrides count + breakdown parity: 3 lanes × SSOT/PL match")
```

## Out of scope (defer to future)

- **Inter-plugin contract validation lint** (review_verdict v1 / review_packet v1 schema 위반 자동 검출): bilateral 작업이라 codeforge core 측 후속(CFP-30+)과 같이 spec 분할 필요. 본 spec은 carryover만 포함.
- **추가 invariant 신규 발의**: 본 repo 자체 운영 후 drift 패턴 발견 시 별도 spec.
- **Branch protection 등록**: GitHub Settings 작업이라 코드 변경 없음. 본 spec 머지 후 사용자가 수동 등록.

## Handoff instructions for receiving Claude session

본 repo에서 Claude Code 세션 개시 후:

1. **Spec self-review** (5분): 본 spec을 읽고 placeholder/오자/논리 모순 검사. brainstorming skill 정식 invocation은 spec이 이미 결정 상태라 사실상 skip.
2. **writing-plans skill** invoke → 단일 task plan 생성 (workflow file 생성 + commit + PR open + 첫 CI green 확인). TDD step 부적용 (CI workflow의 본질이 invariant test이므로 별도 unit test 무의미).
3. **executing-plans** 또는 **subagent-driven-development**로 구현.
4. PR open → 첫 CI 실행 시 두 단계 모두 PASS 확인. 만약 FAIL이면 file content drift 발견 — drift 자체가 본 spec의 detection 목적이므로 fix하고 PASS로 만들어 머지.

## Acceptance criteria

- [ ] `.github/workflows/invariant-check.yml` 생성
- [ ] Invariant 1 (category enum parity) step PASS
- [ ] Invariant 2 (severity overrides parity) step PASS
- [ ] PR open 시 GitHub Actions에서 위 step들 자동 실행
- [ ] README 또는 CHANGELOG에 본 작업 1줄 기록 (예: `v0.2.0 - own invariant-check workflow (carryover from codeforge core CFP-29 추출)`)

## References

- codeforge core PR [#68](https://github.com/mclayer/plugin-codeforge/pull/68) (CFP-29 Phase 1 추출 본 PR — 본 spec carryover의 origin)
- codeforge core commit `9b7e251` (invariant-check.yml 삭제 hunk — 본 spec verbatim Python의 출처)
- codeforge core CFP-9 / CFP-13 / CFP-16 (각 invariant 도입 history)
- codeforge core PR [#37](https://github.com/mclayer/plugin-codeforge/pull/37) (CFP-9 origin) / [#45](https://github.com/mclayer/plugin-codeforge/pull/45) (CFP-13) / [#48](https://github.com/mclayer/plugin-codeforge/pull/48) (CFP-16)
