# Own invariant-check workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Carry over codeforge core의 review-specific invariant 2종(category enum parity / severity overrides parity)을 본 repo CI에 own workflow로 도입한다.

**Architecture:** 신규 GitHub Actions workflow 1개(`.github/workflows/invariant-check.yml`) + spec verbatim Python 2 step. SSOT(체크리스트 md)와 mirror(PL agent / CodexReviewAgent md) 간 silent drift를 push/PR 시점에 fail-fast로 잡는다. TDD 부적용 — workflow 자체가 검증 메커니즘.

**Tech Stack:** GitHub Actions (`ubuntu-latest`), Python 3.11 (stdlib only — `re`, `pathlib`, `collections.Counter`).

---

## File Structure

| 파일 | 책임 | 액션 |
|---|---|---|
| `.github/workflows/invariant-check.yml` | 2개 invariant Python 스크립트를 CI 단계로 실행 | Create |
| `CHANGELOG.md` | 본 작업 1줄 기록 (acceptance criteria) | Modify (Unreleased 섹션 추가) |
| `docs/superpowers/specs/2026-04-28-own-lint-workflow-design.md` | spec SSOT (Verbatim Python 출처) | Read-only reference |

Spec [docs/superpowers/specs/2026-04-28-own-lint-workflow-design.md](../specs/2026-04-28-own-lint-workflow-design.md) §"Verbatim Python — Invariant 1" / §"Verbatim Python — Invariant 2"이 본 plan의 코드 SSOT. 본 plan은 paste만 하고 코드 수정 금지.

---

### Task 1: Spec self-review + local dry-run baseline 확인

**Goal:** 두 verbatim Python을 워크플로우에 박기 전, 현재 repo 상태에서 둘 다 PASS인지 로컬에서 확인 (drift 없는 baseline). PR 첫 CI 실행에서 surprise 방지.

**Files:**
- Read-only: `docs/superpowers/specs/2026-04-28-own-lint-workflow-design.md`
- Read-only (검증 대상): `templates/review-checklists/{design,code,security}.md`, `agents/{Design,Code,Security}{Review,Test}PLAgent.md`, `agents/CodexReviewAgent.md`

- [ ] **Step 1: Spec self-review (5분 skim)**

[docs/superpowers/specs/2026-04-28-own-lint-workflow-design.md](../specs/2026-04-28-own-lint-workflow-design.md)를 읽고 placeholder/오자/논리 모순만 검사. 의심 항목 발견 시 stop하고 사용자 확인. 의심 없으면 Step 2로.

- [ ] **Step 2: Invariant 1 verbatim Python 로컬 실행**

repo root에서 다음 명령. 본 plan은 spec §"Verbatim Python — Invariant 1" 블록을 그대로 인라이닝:

```bash
cd /c/workspace/mclayer/plugin-codeforge-review && python3 <<'EOF'
"""3 lane 각각의 review category enum 3 location 정합 검증."""
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

    ssot_text = Path(ssot_path).read_text(encoding="utf-8")
    ssot_match = re.search(r"`([a-z-]+(?:\s*\|\s*[a-z-]+)+)`", ssot_text)
    if not ssot_match:
        all_errors.append(f"{ssot_path}: pipe-separated category enum 부재")
        continue
    ssot_enum = [s.strip() for s in ssot_match.group(1).split("|")]

    pl_text = Path(pl_path).read_text(encoding="utf-8")
    pl_match = re.search(
        r"category_enum:\s*\n((?:\s*-\s*[a-z-]+\s*\n)+)",
        pl_text,
    )
    if not pl_match:
        all_errors.append(f"{pl_path}: category_enum YAML list 부재")
        continue
    pl_enum = re.findall(r"-\s*([a-z-]+)", pl_match.group(1))

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
EOF
```

**Expected output (PASS baseline):**
```
  ✓ lane=design: N categories x 3 locations
  ✓ lane=code: N categories x 3 locations
  ✓ lane=security: N categories x 3 locations
✓ Review category enum parity: 3 lanes × 3 locations all match
```

(N은 실제 카테고리 개수 — design/code/security 각각 다름.) Exit code 0.

**FAIL 시 처리**: drift detected. 어느 location이 SSOT인지 사용자 확인 필요 — workflow 도입 전에 fix해야 baseline 확보.

- [ ] **Step 3: Invariant 2 verbatim Python 로컬 실행**

```bash
cd /c/workspace/mclayer/plugin-codeforge-review && python3 <<'EOF'
"""3 lane 각각의 severity_overrides 정합 검증 (count + P0/P1 breakdown)."""
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
EOF
```

**Expected output (PASS baseline):**
```
  ✓ lane=design: N bullets (P0=X, P1=Y)
  ✓ lane=code: N bullets (P0=X, P1=Y)
  ✓ lane=security: N bullets (P0=X, P1=Y)
✓ Severity overrides count + breakdown parity: 3 lanes × SSOT/PL match
```

Exit code 0. FAIL 시 위 Step 2와 동일 — drift 어느 쪽 SSOT인지 사용자 확인.

- [ ] **Step 4: 두 dry-run 모두 PASS면 Task 2 진행 / FAIL이면 stop**

PASS 결과 기록 (이후 commit 메시지 baseline 확인용으로 카테고리 개수 / bullet 개수 필요할 수 있음).

---

### Task 2: 워크플로우 파일 생성

**Goal:** Spec 뼈대 그대로 `.github/workflows/invariant-check.yml` 생성. 두 verbatim Python을 heredoc step에 그대로 paste.

**Files:**
- Create: `.github/workflows/invariant-check.yml`

- [ ] **Step 1: 디렉토리 준비**

```bash
mkdir -p c:/workspace/mclayer/plugin-codeforge-review/.github/workflows && ls c:/workspace/mclayer/plugin-codeforge-review/.github/workflows/
```

Expected: 빈 디렉토리.

- [ ] **Step 2: workflow 파일 생성 (Write tool)**

`c:/workspace/mclayer/plugin-codeforge-review/.github/workflows/invariant-check.yml` 에 다음 정확한 content:

````yaml
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
          """3 lane 각각의 review category enum 3 location 정합 검증."""
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

              ssot_text = Path(ssot_path).read_text(encoding="utf-8")
              ssot_match = re.search(r"`([a-z-]+(?:\s*\|\s*[a-z-]+)+)`", ssot_text)
              if not ssot_match:
                  all_errors.append(f"{ssot_path}: pipe-separated category enum 부재")
                  continue
              ssot_enum = [s.strip() for s in ssot_match.group(1).split("|")]

              pl_text = Path(pl_path).read_text(encoding="utf-8")
              pl_match = re.search(
                  r"category_enum:\s*\n((?:\s*-\s*[a-z-]+\s*\n)+)",
                  pl_text,
              )
              if not pl_match:
                  all_errors.append(f"{pl_path}: category_enum YAML list 부재")
                  continue
              pl_enum = re.findall(r"-\s*([a-z-]+)", pl_match.group(1))

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
          EOF

      - name: Severity overrides count + breakdown parity (3 lane × SSOT/PL)
        run: |
          python3 <<'EOF'
          """3 lane 각각의 severity_overrides 정합 검증."""
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
          EOF
````

**중요: heredoc 내부 Python은 GitHub Actions `run:` 블록에서 6-space 들여쓰기**된다 (action step indent). `<<'EOF'` 가 single-quoted라 `$VAR` interpolation 없음 → 안전. 닫는 `EOF`는 들여쓰기 그대로 유지(좌측 정렬 X — `run: |` 안의 일관 들여쓰기 따름).

- [ ] **Step 3: YAML 파싱 검증**

```bash
cd /c/workspace/mclayer/plugin-codeforge-review && python3 -c "import yaml; d = yaml.safe_load(open('.github/workflows/invariant-check.yml', encoding='utf-8')); print('YAML OK,', len(d['jobs']['invariant']['steps']), 'steps')"
```

Expected output: `YAML OK, 4 steps` (checkout + setup-python + invariant-1 + invariant-2)

FAIL 시 indentation 또는 heredoc 닫는 `EOF` 위치 점검.

- [ ] **Step 4: workflow의 두 단계 로컬 simulation**

GitHub Actions에서 `run: |` 블록은 bash로 실행되므로 로컬에서도 동일 동작. step 단위로 raw command 추출해 실행:

```bash
cd /c/workspace/mclayer/plugin-codeforge-review && python3 -c "
import yaml
d = yaml.safe_load(open('.github/workflows/invariant-check.yml', encoding='utf-8'))
for step in d['jobs']['invariant']['steps']:
    if 'run' in step:
        print('===', step['name'], '===')
        print(step['run'])
"
```

이 출력에서 두 Python heredoc 내용이 그대로 나오는지 육안 확인. 이미 Task 1에서 동일 코드를 dry-run했으므로 추가 실행 불필요.

---

### Task 3: CHANGELOG 업데이트

**Goal:** Acceptance criteria의 마지막 항목 충족.

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: 현재 CHANGELOG 상단 확인**

```bash
cd /c/workspace/mclayer/plugin-codeforge-review && head -10 CHANGELOG.md
```

Expected: 현재 첫 entry가 `## [0.1.0] - 2026-04-28`. 본 작업은 v0.1.0 이후 unreleased.

- [ ] **Step 2: Unreleased 섹션 추가 (Edit tool)**

`CHANGELOG.md` 의 `버전 체계: ...` 라인 뒤, `## [0.1.0]` 이전에 다음 블록 삽입.

old_string (Edit의 anchor):
```
버전 체계: [Semantic Versioning 2.0.0](https://semver.org/lang/ko/). v1.0 이전은 minor bump도 breaking 가능.

## [0.1.0] - 2026-04-28
```

new_string:
```
버전 체계: [Semantic Versioning 2.0.0](https://semver.org/lang/ko/). v1.0 이전은 minor bump도 breaking 가능.

## [Unreleased]

### Added

- `.github/workflows/invariant-check.yml` — own invariant-check workflow (carryover from codeforge core CFP-29 Phase 1 추출). Review category enum parity (3 lane × SSOT/PL/Codex) + Severity overrides count + breakdown parity (3 lane × SSOT/PL) 검증.

## [0.1.0] - 2026-04-28
```

---

### Task 4: 브랜치 + commit + push + PR open + CI 확인

**Goal:** Spec acceptance criteria 4번 (PR open 시 GHA 자동 실행) + CI green baseline 확인.

**Files:**
- 변경 없음 (이미 만든 파일을 stage/commit)

- [ ] **Step 1: 브랜치 분기**

```bash
cd /c/workspace/mclayer/plugin-codeforge-review && git status && git checkout -b feat/own-invariant-check-workflow
```

Expected: untracked `.github/workflows/invariant-check.yml`, modified `CHANGELOG.md`, modified or untracked `docs/superpowers/plans/2026-04-28-own-invariant-check-workflow.md`. 브랜치 전환 OK.

- [ ] **Step 2: 변경 stage + 진단**

```bash
cd /c/workspace/mclayer/plugin-codeforge-review && git add .github/workflows/invariant-check.yml CHANGELOG.md docs/superpowers/plans/2026-04-28-own-invariant-check-workflow.md && git status && git diff --cached --stat
```

Expected: 3 files staged. plan 파일은 commit에 포함시켜 trace 보존.

- [ ] **Step 3: commit 생성**

```bash
cd /c/workspace/mclayer/plugin-codeforge-review && git commit -m "$(cat <<'EOF'
feat: own invariant-check workflow (carryover from codeforge core)

CFP-29 Phase 1 추출 시 codeforge core invariant-check.yml에서 제거된
review-specific 단계 2종을 본 repo로 이관. SSOT(체크리스트 md)와 mirror
(PL agent / Codex agent) 간 silent drift를 push/PR 시점에 fail-fast.

- Review category enum parity (3 lane × SSOT/PL/Codex)
- Severity overrides count + breakdown parity (3 lane × SSOT/PL)

Verbatim Python 출처: codeforge core commit 9b7e251 삭제 hunk.
Spec: docs/superpowers/specs/2026-04-28-own-lint-workflow-design.md

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

Expected: commit 성공. SHA 기록.

- [ ] **Step 4: push + PR open**

```bash
cd /c/workspace/mclayer/plugin-codeforge-review && git push -u origin feat/own-invariant-check-workflow && gh pr create --title "feat: own invariant-check workflow (carryover from codeforge core)" --body "$(cat <<'EOF'
## Summary

- codeforge core CFP-29 Phase 1 추출 시 제거된 review-specific invariant 2종을 본 repo CI로 이관
- Review category enum parity (3 lane × SSOT/PL/Codex)
- Severity overrides count + breakdown parity (3 lane × SSOT/PL)

Spec: [docs/superpowers/specs/2026-04-28-own-lint-workflow-design.md](docs/superpowers/specs/2026-04-28-own-lint-workflow-design.md)

## Test plan

- [ ] PR open 후 GHA invariant-check workflow 자동 실행
- [ ] Review category enum parity step PASS
- [ ] Severity overrides parity step PASS
- [ ] (선택) main에 invariant-check required status check 등록 — 별도 GitHub Settings 작업

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Expected: PR URL 출력. 기록.

- [ ] **Step 5: 첫 CI 실행 결과 확인**

```bash
cd /c/workspace/mclayer/plugin-codeforge-review && sleep 30 && gh pr checks
```

Expected (PASS 시):
```
invariant / invariant   pass   ...
```

FAIL 시: `gh run view --log-failed` 로 어느 lane에서 drift가 났는지 확인 → fix push.

- [ ] **Step 6: PR 링크를 사용자에게 보고**

PR URL 출력하고 마무리. main merge 및 branch protection 등록은 사용자 결정 (spec §"Out of scope" 명시).

---

## Acceptance criteria (spec §"Acceptance criteria" 그대로)

- [ ] `.github/workflows/invariant-check.yml` 생성
- [ ] Invariant 1 (category enum parity) step PASS
- [ ] Invariant 2 (severity overrides parity) step PASS
- [ ] PR open 시 GitHub Actions에서 위 step들 자동 실행
- [ ] CHANGELOG.md에 본 작업 1줄 기록

## Self-review checklist (writer)

- ✅ Spec 모든 acceptance 항목이 task로 매핑됨
- ✅ Placeholder 없음 — 모든 Python 코드 verbatim
- ✅ 파일 경로 모두 절대 path 또는 repo-root-relative
- ✅ Expected output 명시 (PASS 형식 / FAIL 시 처리)
- ✅ Type/method 일관성 — 단일 파일이라 N/A
