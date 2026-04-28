# Bundle 1 — Contract Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Codex 협업 gap review에서 확인된 review_verdict v1 contract와 PL/worker md 사이 silent drift 5건(#1,#2,#3,#5,#7) 해소. cross-repo coordination 불필요한 review-plugin 단독 수정.

**Architecture:** Markdown 편집만 — 1 base template + 3 PL agent + 2 worker agent + 1 CI workflow + CHANGELOG. 신규 source code 0줄. 검증은 기존 `.github/workflows/invariant-check.yml`에 신규 invariant 1건 추가 + 사람 reading. cross-repo `mechanical_category` 추가는 본 PR 범위 외(Bundle 2).

**Tech Stack:** Markdown, GitHub Actions (Python 3.11 정규식), bash hooks 미변경.

---

## File Map

- Modify: [`templates/review-pl-base.md`](../../../templates/review-pl-base.md)
  - §2 packet schema — `contract_version: "1.0"` 필수 필드 추가 + lane×field 매트릭스 행 추가
  - §3 — Worker verdict → contract status 변환표 신설 + P3/unclassified 처리 규정
  - §5 — §5.4 "Typed verdict 출력" 신설 (contract-required 8 필드 YAML 템플릿)
- Modify: [`agents/ClaudeReviewAgent.md`](../../../agents/ClaudeReviewAgent.md)
  - "Packet 누락 검증" §1에 `contract_version` 추가
  - "Failure Mode 처리" 표 + lane=security 입력 검증에서 `first_layer_findings` 부재 시 `ESCALATE_PACKET_INCOMPLETE`로 통일 (현재: 비차단 결손 표기)
- Modify: [`agents/CodexReviewAgent.md`](../../../agents/CodexReviewAgent.md) — 위와 동일한 2건
- Modify: [`agents/DesignReviewPLAgent.md`](../../../agents/DesignReviewPLAgent.md) — 워커 packet YAML 예시에 `contract_version: "1.0"` 첫 줄 추가
- Modify: [`agents/CodeReviewPLAgent.md`](../../../agents/CodeReviewPLAgent.md) — 동일
- Modify: [`agents/SecurityTestPLAgent.md`](../../../agents/SecurityTestPLAgent.md) — 동일
- Modify: [`.github/workflows/invariant-check.yml`](../../../.github/workflows/invariant-check.yml) — 새 step "Packet contract_version presence" 추가
- Modify: [`CHANGELOG.md`](../../../CHANGELOG.md) — `[0.3.0] - 2026-04-29` 엔트리

---

## Tasks

### Task 0: Baseline & branch

**Files:** none (workspace 준비만)

- [ ] **Step 0.1: Verify clean working tree on `main`**

```bash
git status
```

Expected: `nothing to commit, working tree clean` — branch on `main`.

- [ ] **Step 0.2: Run existing invariant-check.yml locally to establish green baseline**

```bash
python3 -c "$(awk '/^      - name: Review category enum parity/,/^      - name: Severity overrides/' .github/workflows/invariant-check.yml | sed -n "/python3 <<'EOF'/,/^EOF/p" | sed '1d;$d')"
python3 -c "$(awk '/^      - name: Severity overrides count/,/^$/' .github/workflows/invariant-check.yml | sed -n "/python3 <<'EOF'/,/^EOF/p" | sed '1d;$d')"
```

Expected: 둘 다 `✓ ... all match` 메시지로 통과. 둘 중 하나라도 실패 시 사용자에게 보고하고 plan 중단 — drift 발견은 별도 hotfix가 필요.

(이 명령은 어색하면 다음 더 직접적인 우회 사용:)

```bash
# Invariant 1 standalone runner
mkdir -p .claude-work/plan-bundle-1
sed -n '/Verbatim Python — Invariant 1/,/Verbatim Python — Invariant 2/p' docs/superpowers/specs/2026-04-28-own-lint-workflow-design.md \
  | sed -n '/^```python$/,/^```$/p' | sed '1d;$d' > .claude-work/plan-bundle-1/inv1.py
python3 .claude-work/plan-bundle-1/inv1.py
```

- [ ] **Step 0.3: Create feature branch**

```bash
git checkout -b feat/bundle-1-contract-alignment
```

Expected: `Switched to a new branch 'feat/bundle-1-contract-alignment'`.

---

### Task 1: contract_version end-to-end (TDD via new invariant)

**Files:**
- Modify: `.github/workflows/invariant-check.yml` (add step)
- Modify: `templates/review-pl-base.md` (§2)
- Modify: `agents/DesignReviewPLAgent.md` (packet 예시)
- Modify: `agents/CodeReviewPLAgent.md` (packet 예시)
- Modify: `agents/SecurityTestPLAgent.md` (packet 예시)
- Modify: `agents/ClaudeReviewAgent.md` (packet 검증)
- Modify: `agents/CodexReviewAgent.md` (packet 검증)

#### TDD 사이클

- [ ] **Step 1.1: Write failing invariant — append new step to `.github/workflows/invariant-check.yml`**

기존 두 step 다음에 다음 step을 추가 (들여쓰기 정확히 맞춤 — 현재 file의 step 패턴 그대로):

```yaml
      - name: Packet contract_version presence (3 PL × packet YAML)
        run: |
          python3 <<'EOF'
          """
          3 PL md의 review_packet: YAML 블록에 `contract_version: "1.0"` 필수.
          review_verdict v1 contract (codeforge core SSOT) 준수 enforcement.
          """
          import re
          import sys
          from pathlib import Path

          PL_FILES = [
              "agents/DesignReviewPLAgent.md",
              "agents/CodeReviewPLAgent.md",
              "agents/SecurityTestPLAgent.md",
          ]
          errors = []
          for path in PL_FILES:
              text = Path(path).read_text(encoding="utf-8")
              # review_packet: 블록 추출 (다음 yaml 코드 블록 끝 ``` 까지)
              m = re.search(
                  r"```ya?ml\s*\nreview_packet:[\s\S]*?\n```",
                  text,
              )
              if not m:
                  errors.append(f"{path}: review_packet YAML 블록 부재")
                  continue
              if not re.search(
                  r'^\s*contract_version:\s*"1\.0"\s*$',
                  m.group(0),
                  re.MULTILINE,
              ):
                  errors.append(
                      f'{path}: review_packet에 contract_version: "1.0" 부재'
                  )
          if errors:
              print(
                  f"::error::Packet contract_version invariant 실패 ({len(errors)} drift)"
              )
              for e in errors:
                  print(f"  - {e}")
              sys.exit(1)
          print("✓ Packet contract_version: \"1.0\" present in all 3 PL packets")
          EOF
```

- [ ] **Step 1.2: Run new invariant locally → expect FAIL**

```bash
sed -n '/Packet contract_version presence/,/^$/p' .github/workflows/invariant-check.yml \
  | sed -n "/python3 <<'EOF'/,/^          EOF$/p" | sed '1d;$d' \
  | sed 's/^          //' > .claude-work/plan-bundle-1/inv-cv.py
python3 .claude-work/plan-bundle-1/inv-cv.py
```

Expected: `::error::Packet contract_version invariant 실패 (3 drift)` — 모든 PL이 contract_version 누락.

- [ ] **Step 1.3: Update `templates/review-pl-base.md` §2 — declare contract_version required**

§2 "공통 필드 (모든 lane)" 코드 블록에서 `lane:` 줄 **앞에** 다음 줄 삽입:

```yaml
  contract_version: "1.0"                                       # 필수 — review_verdict v1 contract enforcement
```

§2 "lane별 packet 필수 필드 매트릭스" 표에 새 첫 데이터 행 추가:

```markdown
| contract_version | ✅ | ✅ | ✅ |
```

- [ ] **Step 1.4: Add `contract_version` to 3 PL packet YAML examples**

세 PL md의 `review_packet:` 블록에서 `lane:` 줄 **앞에** 다음 줄 삽입 (각 file 한 곳):

[agents/DesignReviewPLAgent.md](../../../agents/DesignReviewPLAgent.md) §"워커 packet 작성":
```yaml
  contract_version: "1.0"
```

[agents/CodeReviewPLAgent.md](../../../agents/CodeReviewPLAgent.md) §"워커 packet 작성": 동일.

[agents/SecurityTestPLAgent.md](../../../agents/SecurityTestPLAgent.md) §"워커 packet 작성": 동일.

- [ ] **Step 1.5: Add `contract_version` validation to two workers**

[agents/ClaudeReviewAgent.md](../../../agents/ClaudeReviewAgent.md) §"입력: review packet" → "Packet 누락 검증" 1번 항목을 다음으로 교체:

```markdown
1. **공통 필수 필드**: `contract_version` (== `"1.0"`) · `lane` · `checklist_path` · `scope_globs` · `category_enum` 존재. `contract_version` 누락 또는 `"1.0"`이 아닌 값 → 즉시 `ESCALATE_PACKET_INCOMPLETE` (review_verdict v1 contract enforcement, [ADR-008](https://github.com/mclayer/plugin-codeforge/blob/main/docs/adr/ADR-008-inter-plugin-contract-versioning.md))
```

[agents/CodexReviewAgent.md](../../../agents/CodexReviewAgent.md) §"입력: review packet" → "Packet 누락 검증" 1번 항목: 동일 교체.

- [ ] **Step 1.6: Re-run invariant → expect PASS**

```bash
python3 .claude-work/plan-bundle-1/inv-cv.py
```

Expected: `✓ Packet contract_version: "1.0" present in all 3 PL packets`.

- [ ] **Step 1.7: Re-run all 3 invariants (existing 2 + new 1) → expect ALL PASS**

```bash
python3 .claude-work/plan-bundle-1/inv1.py
python3 .claude-work/plan-bundle-1/inv-cv.py
# Invariant 2 (severity parity) — file 접근만 하므로 다음 단순 cmd로 충분
python3 -c "
import re, sys
from pathlib import Path
from collections import Counter
LANES=[('design','DesignReviewPLAgent'),('code','CodeReviewPLAgent'),('security','SecurityTestPLAgent')]
SEV=re.compile(r'→\s*P(\d)')
errs=[]
for lane,pl in LANES:
    s=Path(f'templates/review-checklists/{lane}.md').read_text(encoding='utf-8')
    p=Path(f'agents/{pl}.md').read_text(encoding='utf-8')
    sm=re.search(r'^## Severity 자동 룰\s*\n(.+?)(?=\n## |\Z)',s,re.MULTILINE|re.DOTALL)
    pm=re.search(r'severity_overrides:\s*\n((?:\s*-\s*\".+?\"\s*\n)+)',p)
    sb=[l for l in sm.group(1).split('\n') if l.lstrip().startswith('- ')]
    pb=[l for l in pm.group(1).split('\n') if l.lstrip().startswith('- ')]
    sc=Counter(); pc=Counter()
    for b in sb:
        for v in SEV.findall(b): sc[f'P{v}']+=1
    for b in pb:
        for v in SEV.findall(b): pc[f'P{v}']+=1
    if len(sb)!=len(pb) or sc!=pc:
        errs.append(f'{lane}: SSOT={len(sb)}/{dict(sc)} vs PL={len(pb)}/{dict(pc)}')
if errs:
    [print(e) for e in errs]; sys.exit(1)
print('✓ severity parity 3 lanes')
"
```

Expected: 3건 모두 `✓` 메시지.

- [ ] **Step 1.8: Commit**

```bash
git add .github/workflows/invariant-check.yml templates/review-pl-base.md agents/{Design,Code,SecurityTest}ReviewPLAgent.md agents/{Claude,Codex}ReviewAgent.md
git commit -m "$(cat <<'EOF'
feat: enforce packet contract_version "1.0" (gap #3)

review_verdict v1 contract requires contract_version on packet
(codeforge core docs/inter-plugin-contracts/review-verdict-v1.md L47-50)
but base packet schema and worker validation omitted it. Silent drift
risk if either side rolls forward without the other.

- templates/review-pl-base.md §2: declare contract_version required + matrix row
- agents/{Design,Code,SecurityTest}ReviewPLAgent.md: add to packet YAML examples
- agents/{Claude,Codex}ReviewAgent.md: add to packet 누락 검증 #1 → ESCALATE_PACKET_INCOMPLETE if absent
- .github/workflows/invariant-check.yml: new "Packet contract_version presence" step (3 PL × YAML block)

Refs: gap #3 from 2026-04-29 codex 협업 review.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Worker verdict → contract status 변환표 (gap #1)

**Files:**
- Modify: `templates/review-pl-base.md` (§3)

이 task는 invariant로 검증할 게 별로 없는 **prose 추가**. 사람 reading + base 변경 후 PL md가 base를 cross-ref하는 link 점검만.

- [ ] **Step 2.1: Edit `templates/review-pl-base.md` §3 — insert subsection before `### Mechanical fast-path 분류 (R11)`**

§3 "Severity 종합 규칙" 안에서 `### Dedup` 다음, `### 종합 판정` 앞에 신규 subsection 삽입:

```markdown
### Worker verdict → review_verdict.status 변환

워커는 `verdict: PASS | ISSUES | NO_SHIP | ESCALATE_PACKET_INCOMPLETE` 4종으로 보고 ([ClaudeReviewAgent §보고 형식](../agents/ClaudeReviewAgent.md), [CodexReviewAgent §정규화 보고 스키마](../agents/CodexReviewAgent.md)). PL은 dedup·severity 종합 후 양 워커 결과를 다음 표로 contract status로 변환:

| 양 워커 종합 (dedup 후 P0/P1 카운트 기준) | review_verdict.status |
|---|---|
| 두 워커 중 1건 이상 `ESCALATE_PACKET_INCOMPLETE` | (PL은 status 반환 안 함 — packet 정정 후 워커 재 dispatch 의뢰) |
| 두 워커 모두 `PASS` (또는 `ISSUES` with P0=0,P1=0) | `PASS` |
| `NO_SHIP` 1건 이상 (즉 P0 ≥ 1) | `FIX` |
| `ISSUES` + P0=0, P1 ≥ 2 | `FIX` |
| `ISSUES` + P0=0, P1 = 1 | `FIX_DISCRETIONARY` (PL 재량 — 근거 포함 Orchestrator 전달) |
| FIX 카운터 lane 한도 초과 | `FIX` 결정 후 PL이 별도 ESCALATE 신호 추가 (lane md FIX 카운터 정책 SSOT) |

본 표가 contract `review_verdict.status` enum과 워커 verdict enum 사이의 유일한 매핑 SSOT. 워커 verdict enum 추가/변경 시 본 표도 동시 갱신 의무.
```

- [ ] **Step 2.2: Verify by reading**

```bash
grep -n "Worker verdict → review_verdict.status 변환" templates/review-pl-base.md
grep -n "ESCALATE_PACKET_INCOMPLETE" templates/review-pl-base.md
```

Expected: 첫 grep 1건 hit (§3 안), 두 번째 ≥ 2건 hit.

- [ ] **Step 2.3: Commit**

```bash
git add templates/review-pl-base.md
git commit -m "$(cat <<'EOF'
docs: add worker verdict → contract status mapping table (gap #1)

Worker enum {PASS, ISSUES, NO_SHIP, ESCALATE_PACKET_INCOMPLETE} differs
from review_verdict v1 status enum {PASS, FIX, FIX_DISCRETIONARY}. Base
§3 had only severity-aggregation rule, no explicit translation table.
Drift-prone if either enum evolves.

templates/review-pl-base.md §3: new "Worker verdict → review_verdict.status 변환"
subsection with explicit mapping table.

Refs: gap #1 from 2026-04-29 codex 협업 review.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: P3 / unclassified severity 처리 규정 (gap #5)

**Files:**
- Modify: `templates/review-pl-base.md` (§3)

- [ ] **Step 3.1: Edit `templates/review-pl-base.md` §3 — insert subsection right before `### Noise 분류`**

```markdown
### P3 / unclassified severity 처리

워커는 P3·unclassified를 emit ([ClaudeReviewAgent §분류 규칙](../agents/ClaudeReviewAgent.md), [CodexReviewAgent §변환 규칙](../agents/CodexReviewAgent.md))하지만 contract `review_verdict.findings[].severity`는 `P0|P1|P2`만 허용 ([review-verdict-v1 §3](https://github.com/mclayer/plugin-codeforge/blob/main/docs/inter-plugin-contracts/review-verdict-v1.md#L91-L92)). PL이 verdict로 변환 시:

- `P3` → `P2`로 downgrade 후 `review_verdict.findings[]`에 emit
- `unclassified` → 워커 보고 원문에서 추가 근거 추출 시도. 추출 가능하면 `P2`, 불가능하면 `findings[]`에서 drop하고 `summary_for_story_section_9`에 1줄 ("워커 unclassified N건 drop") 기록

본 변환은 PL 의무 — 미적용 시 core가 contract enum 위반으로 verdict 거부.
```

- [ ] **Step 3.2: Verify by reading**

```bash
grep -n "P3 / unclassified severity 처리" templates/review-pl-base.md
```

Expected: 1건 hit.

- [ ] **Step 3.3: Commit**

```bash
git add templates/review-pl-base.md
git commit -m "$(cat <<'EOF'
docs: P3/unclassified severity downgrade rule (gap #5)

Workers emit P3 + unclassified in their normalized output, but contract
review_verdict.findings[].severity is constrained to P0|P1|P2. Without
explicit conversion rule PL would silently emit out-of-enum values that
core would reject.

templates/review-pl-base.md §3: new "P3 / unclassified severity 처리"
subsection — P3→P2 downgrade, unclassified→P2 with evidence else drop.

Refs: gap #5 from 2026-04-29 codex 협업 review.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Typed verdict YAML 출력 블록 §5.4 (gap #2)

**Files:**
- Modify: `templates/review-pl-base.md` (§5)

이 task는 contract roundtrip 정합성에서 가장 중요한 변경. PL이 사람용 한글 PASS/FIX/ESCALATE 블록과 별개로 typed YAML을 동시 emit해야 core가 처리 가능.

- [ ] **Step 4.1: Edit `templates/review-pl-base.md` §5 — append subsection §5.4**

§5의 마지막 subsection (`### ESCALATE` 코드 블록) 다음, `## 6. Escalation 경로 (FIX 트리거 시)` 앞에 추가:

```markdown
### 5.4 Typed verdict 출력 (contract-required)

§5.1-5.3의 PASS/FIX/ESCALATE 한글 블록은 사람용 보고 (Orchestrator 콘솔·Story §9.x append). **추가로** 아래 YAML을 동시 emit — 이것이 review_verdict v1 contract surface ([review-verdict-v1 §3](https://github.com/mclayer/plugin-codeforge/blob/main/docs/inter-plugin-contracts/review-verdict-v1.md#L75-L111) SSOT). 둘 중 하나라도 누락 시 core가 verdict 거부 + ESCALATE.

```yaml
review_verdict:
  contract_version: "1.0"          # 필수 — packet contract_version과 일치
  lane: design | code | security   # 필수 — packet과 일치
  story_key: <STORY_KEY>           # 필수 — packet과 일치
  iteration: <int>                 # 필수 — Story §10 FIX Ledger 현재 카운터 값

  status: PASS | FIX | FIX_DISCRETIONARY  # 필수 — §3 Worker verdict 변환표 적용

  findings:                         # 필수 — array, 빈 배열 허용
    - severity: P0 | P1 | P2        # 필수 — P3/unclassified는 §3 규정에 따라 P2 downgrade 또는 drop
      category: <packet category_enum 중 하나>
      file: <path>                  # 필수 — 비-file finding 시 0
      line: <int>                   # 선택 — 0 허용
      evidence: <markdown>           # 필수 — 위치 인용 + 위반 근거
      suggestion: <markdown>         # 필수 — 수정 방향 (코드 patch 아님)

  summary_for_story_section_9: |    # 필수 — core(DocsAgent)가 Story §9 append
    <PL 종합 보고 — finding count + 결정 근거 + iteration 추세>

  summary_for_pr_comment: |         # 필수 — core(DocsAgent)가 phase prefix 적용해 PR comment 게시
    <≤30 줄 요약 — 상세는 §9 참조 링크>

  next_gate_label:                  # 필수 — null 허용
    # status=PASS + lane=design   → gate:design-review-pass
    # status=PASS + lane=security → gate:security-test-pass
    # status=PASS + lane=code     → null (구현 리뷰 PASS 라벨 부재 — 다음 lane 트리거만)
    # status=FIX | FIX_DISCRETIONARY → null
```

`mechanical_category` 필드는 본 v1.0 contract에 정의되지 않음 — 본 plugin 내부 §3 fast-path 분류용 필드로만 PL → Orchestrator 사이드채널. core repo가 v1.1로 schema에 추가하기 전까지 contract surface 외 (Bundle 2 작업 — gap #4).
```

- [ ] **Step 4.2: Verify by reading**

```bash
grep -n "5.4 Typed verdict 출력" templates/review-pl-base.md
grep -n "summary_for_story_section_9" templates/review-pl-base.md
grep -n "summary_for_pr_comment" templates/review-pl-base.md
grep -n "next_gate_label" templates/review-pl-base.md
```

Expected: 첫 grep 1건, 나머지 각 ≥ 1건 hit.

- [ ] **Step 4.3: Commit**

```bash
git add templates/review-pl-base.md
git commit -m "$(cat <<'EOF'
feat: add §5.4 typed verdict YAML output block (gap #2)

review_verdict v1 contract requires 8 fields (contract_version, lane,
story_key, iteration, status, findings[], summary_for_story_section_9,
summary_for_pr_comment, next_gate_label) but base §5 only described the
human-readable Korean PASS/FIX/ESCALATE blocks. PL emit of contract
schema was implicit. Without §5.4 PL output silently misses required
fields and core rejects the verdict.

templates/review-pl-base.md §5.4: typed verdict YAML template + per-field
guidance + next_gate_label decision rules + mechanical_category note
(deferred to Bundle 2 cross-repo coordination).

Refs: gap #2 from 2026-04-29 codex 협업 review.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: first_layer_findings 부재 시 동작 통일 (gap #7)

**Files:**
- Modify: `agents/ClaudeReviewAgent.md` (3 곳)
- Modify: `agents/CodexReviewAgent.md` (3 곳)

현재: 두 워커가 lane=security에서 first_layer 부재 시 비차단 (보고 첫 줄에 `first-layer-input-missing` 명시)으로 동작 — SecurityTestPL의 fetch 의무 위반 시 silently 약한 보안 lane이 됨. ADR-001 §결정 4번 ("Packet 누락 = 즉시 ESCALATE") 정신과 불일치. 양 워커를 strict하게 통일.

- [ ] **Step 5.1: Edit `agents/ClaudeReviewAgent.md` — strict ESCALATE in 3 locations**

**위치 1**: §"입력: review packet" → "Packet 누락 검증" → "lane-conditional 추가 검증" → `lane=security` 항목을 다음으로 교체:

```markdown
   - `lane=security`: packet은 1차 layer 결과(Dependabot · CodeQL · Secret Scanning · Push Protection)를 inline 포함 + `scope_globs`에 의존성 매니페스트 ≥ 1 포함. 둘 중 하나라도 부재 시 즉시 `ESCALATE_PACKET_INCOMPLETE` (ADR-001 §결정 4번 invariant policing — fetch 책임은 SecurityTestPL 소유, 워커 비차단 fallback은 silently 약한 보안 lane을 만들 수 있음)
```

**위치 2**: §"Failure Mode 처리" 표에서 `보안 lane 1차 layer 결과 inline 부재` 행을 다음으로 교체:

```markdown
| 보안 lane 1차 layer 결과 inline 부재 또는 의존성 매니페스트 0건 | `ESCALATE_PACKET_INCOMPLETE` 반환 (SecurityTestPL fetch 의무 위반 — silently 약화 방지) |
```

**위치 3**: §"보고 형식" → "분류 규칙 (공통)"의 `verdict: ESCALATE_PACKET_INCOMPLETE` 항목 본문은 그대로 유지하되, 같은 페이지 §"보고 형식" 본 코드 블록 위 `[Claude Review 정규화]` 주석 영역에서 만약 옛 `first-layer-input-missing` 멘션이 보이면 제거 (현재 file v0.2.0 기준 해당 멘션은 §입력에만 있으므로 추가 작업 불필요 — Step 5.1 위치 1이 cover).

**검증**:
```bash
grep -n "first-layer-input-missing" agents/ClaudeReviewAgent.md
```
Expected: 0건 hit (모든 mention이 strict ESCALATE 룰로 교체됨).

- [ ] **Step 5.2: Edit `agents/CodexReviewAgent.md` — apply same 2 edits**

위치 1, 위치 2를 동일하게 (Codex md의 §입력 / §변환 규칙 / §정규화 보고 위치는 다르지만 텍스트 패턴은 같음). Codex md에 위치 3은 없음.

**검증**:
```bash
grep -n "first-layer-input-missing" agents/CodexReviewAgent.md
```
Expected: 0건 hit.

- [ ] **Step 5.3: Verify SecurityTestPLAgent.md still requires PL fetch (no change there)**

```bash
grep -n "1차 layer fetch 의무" agents/SecurityTestPLAgent.md
```
Expected: ≥ 1건 hit — PL의 fetch 의무는 변경 없이 유지 (워커는 더 strict, PL 책임은 그대로).

- [ ] **Step 5.4: Commit**

```bash
git add agents/ClaudeReviewAgent.md agents/CodexReviewAgent.md
git commit -m "$(cat <<'EOF'
fix: unify first_layer_findings missing → ESCALATE_PACKET_INCOMPLETE (gap #7)

Workers previously documented "비차단 결손 표기" for missing
first_layer_findings (Claude L50,L117 / Codex L59), conflicting with
SecurityTestPL §"1차 layer fetch 의무" strictness and ADR-001 §결정 4번
("Packet 누락 = 즉시 ESCALATE"). Without strict worker behavior, a PL
fetch bug could silently produce a weakened security lane review.

agents/{Claude,Codex}ReviewAgent.md: §입력 lane=security validation +
§Failure Mode handler now both ESCALATE_PACKET_INCOMPLETE on missing
1차 layer or zero dependency manifest. PL fetch contract unchanged.

Refs: gap #7 from 2026-04-29 codex 협업 review.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: CHANGELOG v0.3.0 + final verification

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `.claude-plugin/plugin.json` (version bump)

- [ ] **Step 6.1: Update `.claude-plugin/plugin.json` version → 0.3.0**

`"version": "0.2.0"` → `"version": "0.3.0"`. 다른 필드 변경 금지.

- [ ] **Step 6.2: Prepend new entry to `CHANGELOG.md`**

`## [0.2.0]` 앞에 다음 엔트리 추가:

```markdown
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

```

- [ ] **Step 6.3: Run all 3 invariants locally → expect ALL PASS**

```bash
python3 .claude-work/plan-bundle-1/inv1.py
python3 .claude-work/plan-bundle-1/inv-cv.py
python3 -c "
import re, sys
from pathlib import Path
from collections import Counter
LANES=[('design','DesignReviewPLAgent'),('code','CodeReviewPLAgent'),('security','SecurityTestPLAgent')]
SEV=re.compile(r'→\s*P(\d)')
errs=[]
for lane,pl in LANES:
    s=Path(f'templates/review-checklists/{lane}.md').read_text(encoding='utf-8')
    p=Path(f'agents/{pl}.md').read_text(encoding='utf-8')
    sm=re.search(r'^## Severity 자동 룰\s*\n(.+?)(?=\n## |\Z)',s,re.MULTILINE|re.DOTALL)
    pm=re.search(r'severity_overrides:\s*\n((?:\s*-\s*\".+?\"\s*\n)+)',p)
    sb=[l for l in sm.group(1).split('\n') if l.lstrip().startswith('- ')]
    pb=[l for l in pm.group(1).split('\n') if l.lstrip().startswith('- ')]
    sc=Counter(); pc=Counter()
    for b in sb:
        for v in SEV.findall(b): sc[f'P{v}']+=1
    for b in pb:
        for v in SEV.findall(b): pc[f'P{v}']+=1
    if len(sb)!=len(pb) or sc!=pc:
        errs.append(f'{lane}: SSOT={len(sb)}/{dict(sc)} vs PL={len(pb)}/{dict(pc)}')
if errs: [print(e) for e in errs]; sys.exit(1)
print('✓ severity parity 3 lanes')
"
```

Expected: 3건 모두 `✓` 메시지.

- [ ] **Step 6.4: Verify no `first-layer-input-missing` references remain**

```bash
grep -rn "first-layer-input-missing" agents/ templates/
```

Expected: 0건 hit.

- [ ] **Step 6.5: Commit**

```bash
git add CHANGELOG.md .claude-plugin/plugin.json
git commit -m "$(cat <<'EOF'
chore: release v0.3.0 — Bundle 1 contract alignment

Bumps version + CHANGELOG entry covering 5 gap fixes from 2026-04-29
codex 협업 gap review (review-only). Cross-repo coordination items
(gap #4 mechanical_category, gap #6 next_gate_label) deferred to
Bundle 2.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Push branch + open PR (USER CONFIRMATION REQUIRED)

이 task는 remote 영향 — 사용자에게 확인 후 진행.

- [ ] **Step 7.1: Confirm with user before pushing**

사용자에게 "feat/bundle-1-contract-alignment 브랜치 push + PR 열까요?"라고 물어보고 승인 받기. 거부 시 plan은 여기서 종료.

- [ ] **Step 7.2: Push branch**

```bash
git push -u origin feat/bundle-1-contract-alignment
```

- [ ] **Step 7.3: Open PR**

```bash
gh pr create --title "feat: Bundle 1 contract alignment — review_verdict v1 drift 5건 해소" --body "$(cat <<'EOF'
## Summary

- review_verdict v1 contract와 PL/worker md 사이 silent drift 5건 해소 (Codex 협업 gap review 결과)
- review-only 변경 — codeforge core 미수정 (cross-repo gap #4, #6는 Bundle 2)
- `.github/workflows/invariant-check.yml`에 contract_version 신규 invariant 추가

해결 gap (자세한 사항은 [plan doc](docs/superpowers/plans/2026-04-29-bundle-1-contract-alignment.md)):

| # | 변경 |
|---|---|
| 1 | Worker verdict ↔ contract status 변환표 신설 |
| 2 | PL typed verdict YAML 출력 블록 §5.4 신설 |
| 3 | packet `contract_version: "1.0"` 필수화 + invariant 추가 |
| 5 | P3/unclassified severity downgrade 규정 |
| 7 | first_layer_findings 부재 시 ESCALATE_PACKET_INCOMPLETE 통일 |

## Test plan

- [x] 기존 invariant-check 2건 (category enum parity / severity overrides parity) 로컬 PASS
- [x] 신규 invariant (Packet contract_version presence) 로컬 PASS
- [x] `grep -rn "first-layer-input-missing"` → 0건
- [ ] CI invariant-check workflow PASS (push 후 자동 실행 확인)
- [ ] PR self-review — 6 commit이 각 gap에 1:1 매핑

## Compatibility

- `codeforge` core >= 0.17.0 호환 유지
- review_verdict contract v1.0 미변경 — v1 enforcement 강화만

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 7.4: Wait for CI green + report PR URL to user**

```bash
gh pr view --json url,statusCheckRollup
```

CI fail 시 fix → re-push → 재 PASS까지. main으로 머지는 사용자 결정.

---

## Self-Review Checklist (이 plan 작성자 자체 점검 — execution 전에 실행)

**Spec coverage** — gap #1, #2, #3, #5, #7 5건 모두 task에 1:1 매핑 (Task 2, 4, 1, 3, 5). Bundle 1 범위와 일치.

**Placeholder scan** — 검색 키워드 `TBD|TODO|implement later|fill in details|Add appropriate|Similar to`: 본 plan 본문에 0건. 모든 step에 실행 가능한 명령 또는 정확한 markdown patch 명시.

**Type consistency** — 7 task 사이 사용된 식별자 점검:
- `contract_version` (Task 1): YAML 필드명, `"1.0"` string literal — 7 file 동일 사용 ✓
- `ESCALATE_PACKET_INCOMPLETE` (Task 1, 5): worker verdict 상수 — base §3 변환표 + 두 워커 md 모두 동일 ✓
- `review_verdict.status` enum `PASS|FIX|FIX_DISCRETIONARY` (Task 2, 4): contract SSOT와 일치 ✓
- `mechanical_category`: Task 4 §5.4 본문에서 "v1.0 contract에 정의되지 않음" 정확히 명시 (Bundle 2 대상으로 deferral) ✓
- branch name `feat/bundle-1-contract-alignment`: Task 0, 7 동일 ✓

**Risk scan** — destructive command 0건. 모든 git operation은 새 branch 위에서. push는 Task 7.2에서 사용자 승인 후. force push / branch delete 없음.
