# Design Review 체크리스트 (lane=design)

DesignReviewPLAgent가 ClaudeReviewAgent / CodexReviewAgent에 packet으로 주입하는 설계 리뷰 체크리스트. 두 워커가 **공통 입력**으로 사용. SSOT 분리는 [ADR-001](../../docs/adr/ADR-001-review-agent-unification.md) 결정.

CFP-46 / [ADR-014](../../docs/adr/ADR-014-operational-risk-ssot-distribution.md) 반영 — §7.4 운영 리스크 (DR / cancel-on-disconnect / clock sync / rate limit / env isolation, OperationalRiskArchitectAgent 산출물) + §11.6 Idempotency CONDITIONAL invariant 신설. §7 numbering shift: 기존 §7.4 민감 데이터 → §7.5, §7.5 위협↔완화 → §7.6, §7.6 N/A → §7.7.

## 리뷰 대상 (scope_globs)

- `docs/change-plans/<slug>.md` (Change Plan 본문)
- `docs/stories/<KEY>.md` §1-7 (컨텍스트·Change Plan 요약·RefactorAgent 분석)
- `docs/stories/<KEY>.md` §3 관련 ADR (정합성 교차 입력)
- `docs/adr/ADR-*.md` (위 §3에서 언급된 ADR 본문)
- Change Plan §8 Test Contract

## Category enum (출력 분류)

`adr-mismatch | design-completeness | mapper-refactor-balance | implementability | test-contract | section-missing | security-design | data-migration | api-compatibility | observability | slo-missing`

## Severity 자동 룰

- **ADR violation** → P0 강제 (`adr-mismatch`)
- **§8 Test Contract 누락** → P0 강제 (`section-missing` 또는 `test-contract`)
- **§3 도입할 설계 / §4 API 계약 / §5 변경 계획 / §6 리팩터링 선행 누락** → P0 강제 (`section-missing`)
- **§7 보안 설계 누락** → P0 강제 (`security-design`)
- **§7.4 운영 리스크 누락 / N/A 사유 부재** → P0 강제 (`security-design`) — CFP-46 / ADR-014 결정 #4
- **§7.7 N/A 사유 부재** → P0 강제 (`security-design`)
- **Architect 통합 판정에서 SecurityArch 위협-완화 매핑 미반영** → P0 강제 (`security-design`)
- **§11 데이터 마이그레이션 누락** → P0 강제 (`data-migration`)
- **§11.6 Idempotency 누락 / N/A 사유 부재** → P0 강제 (`data-migration`) — CFP-46 / ADR-014 결정 #4
- **§11.7 N/A 사유 부재** → P0 강제 (`data-migration`)
- **Architect 통합 판정에서 DataMigrationArch 마이그레이션 안전성 매핑 미반영** → P0 강제 (`data-migration`)
- **API breaking change에 versioning 전략 부재** → P0 강제 (`api-compatibility`) — 공개 API·SLA 대상만, 내부 도구는 P1
- **외부 입력 컴포넌트에 관측성 결정 부재** → P0 강제 (`observability`) — boundary 컴포넌트만, 내부 함수는 P1
- **공개 API · SLA 대상 서비스에 SLO 부재** → P0 강제 (`slo-missing`) — 내부 도구는 P1
- **API 변경 시 deprecation timeline 미정의** → P1 (`api-compatibility`)
- **신규 컴포넌트 metric 종류 미명시** → P1 (`observability`)
- **SLO 목표 측정 방법 부재** → P1 (`slo-missing`)

## 체크리스트 (5축)

### 1. Change Plan 완결성 (`design-completeness`, `section-missing`)

- 필수 섹션 존재: 목적 · 현재 구조 분석 · 도입할 설계 · API 계약 · 변경 계획(파일 단위) · 리팩토링 선행 · 테스트 계획(§8 Test Contract 포함) · 분기 · ADR 여부
- "0 컨텍스트 개발자 전제" 구체성 — 파일·인터페이스·시그니처·이름·타입 확정 여부
- 모호한 표현(고려·검토·필요시) 식별 — Dev가 재량 없이 실행할 수 있는 수준인가

### 2. ADR 정합성 (`adr-mismatch`, P0 고정)

- Story file §3에 나열된 관련 ADR을 **명시적으로 fetch**하여 Change Plan 결정과 대조
- ADR 결정 위반 발견 시 **P0 severity 강제**
- 설계 의도가 ADR 변경이라면 "신규 ADR 필요" P0 지적 (신규 ADR 없이 기존 ADR 변경 금지 — [`templates/adr.md`](../adr.md) §파일 메타)

### 3. CodebaseMapper ↔ RefactorAgent 균형 (`mapper-refactor-balance`)

- Mapper의 변호 근거가 합리적 반박 없이 일축됐는지 점검
- Refactor 제안이 요건 범위를 초과해 과잉 리팩터링으로 흐르는지 점검
- 두 관점 충돌이 Change Plan §2(현재 구조) / §3(도입할 설계)에 명시적으로 기록됐는지

### 4. 구현 가능성 (`implementability`)

- Dev가 재량 없이 실행 가능한 구체성
- 모호한 네이밍·시그니처·타입 식별 → P1
- API 계약 불완전성 (요청/응답 스키마·에러 코드·비동기 약속) → P0 또는 P1

### 5. Test Contract 타당성 (`test-contract`)

- 커버리지 계획·경계 조건·invariant·성능 baseline 기준 명시
- Change Plan 범위 대비 커버리지 공백 식별
- 성능 baseline §8.3 프로토콜 (mean 10% 악화 기준 측정 절차) 명시 여부

## §7 보안 설계 감사 (SecurityArchitectAgent + OperationalRiskArchitectAgent 산출물 통합 결과 검증)

### §7.1 Trust boundary
- [ ] 외부 입력 진입점이 모두 식별되었는가
- [ ] 신뢰 경계가 명시되었는가
- [ ] 각 boundary 검증 책임이 명시되었는가

### §7.2 Threat model
- [ ] STRIDE-LITE 표가 작성되었는가
- [ ] 변경 영향 컴포넌트별로 6 STRIDE 카테고리가 검토되었는가

### §7.3 Auth/Authz
- [ ] 인증 방식이 명시되고 결정 근거가 제시되었는가
- [ ] 권한 모델이 명시되고 결정 근거가 제시되었는가
- [ ] 세션 lifecycle이 정의되었는가 (해당 시)

### §7.4 운영 리스크 (CFP-46 / ADR-014)

OperationalRiskArchitectAgent 산출물 검증. 5 sub-items 모두 작성 또는 N/A + 사유 1줄 (10자+) 의무.

#### §7.4.1 DR (Disaster Recovery)
- [ ] Runbook (장애 대응 절차)이 명시되었는가
- [ ] Failover 경로 (primary 실패 시 secondary 전환)가 정의되었는가
- [ ] 재시작 후 상태 복원 (in-flight 작업 / 큐 / 세션) 정책이 명시되었는가
- [ ] N/A 시 사유 1줄 (10자+) 명시

#### §7.4.2 Cancel-on-disconnect
- [ ] Stream 끊김 감지 메커니즘이 명시되었는가 (heartbeat / read deadline / TCP keepalive)
- [ ] 끊김 발생 시 자동 작업 취소 정책이 명시되었는가 (in-flight order / long-running job / pending side-effect)
- [ ] 재진입 정책 (재연결 시 중복 / 재시도 / dedup) 이 명시되었는가
- [ ] N/A 시 사유 1줄 (10자+) 명시 — stream/connection 의존 없음 명시

#### §7.4.3 Clock sync (CONDITIONAL)
- [ ] Time-window 의존 (timestamp 검증 / TTL / nonce window / replay 방지) 여부 식별
- [ ] 의존 시 NTP / recvWindow / clock skew 허용치가 명시되었는가
- [ ] N/A 시 사유 1줄 (10자+) 명시 — time-window 의존 없음 명시

#### §7.4.4 Rate limit / quota
- [ ] 외부 시스템 (거래소·API·DB) 별 weight / quota / IP ban 임계가 식별되었는가
- [ ] Throttling / backoff / circuit breaker 정책이 명시되었는가
- [ ] Quota 초과 시 fallback (대체 endpoint / queue / drop) 이 명시되었는가
- [ ] N/A 시 사유 1줄 (10자+) 명시

#### §7.4.5 Env isolation
- [ ] Staging / production 시크릿 분리 정책이 명시되었는가
- [ ] 런타임 (DB / 외부 endpoint / API key) 분리가 명시되었는가
- [ ] 승인 게이트 (production 배포 사전 승인 / canary / rollback 트리거) 가 정의되었는가
- [ ] N/A 시 사유 1줄 (10자+) 명시

### §7.5 민감 데이터
- [ ] 데이터 분류표가 작성되었는가
- [ ] 데이터 흐름이 추적 가능한가
- [ ] log/error 노출 금지 항목이 명시되었는가

### §7.6 위협↔완화
- [ ] 식별 위협별 설계 단계 완화책이 매핑되었는가
- [ ] 미완화 위협에 수용 사유가 명시되었는가

### §7.7 N/A 처리
- [ ] N/A 명시 시 사유가 명확하게 제시되었는가 (사유 부재 시 P0 차단)

### Severity 자동 룰
- §7 보안 설계 섹션 부재 → **P0**
- §7.4 운영 리스크 누락 또는 5 sub-items N/A 사유 부재 → **P0** (CFP-46 / ADR-014 결정 #4)
- §7.7 N/A 사유 부재 → **P0**
- Architect 통합 판정에서 SecurityArch 위협-완화 매핑 미반영 → **P0**
- §7.2 STRIDE 표 컴포넌트 일부만 채워짐 → **P1**
- §7.3 결정 근거 부재 → **P1**
- §7.5 log 노출 금지 항목 누락 → **P1**

## §11 데이터 마이그레이션 감사 (DataMigrationArchitectAgent 산출물 통합 결과 검증)

### §11.1 Schema 변경 영향
- [ ] 변경 대상 테이블/컬렉션/인덱스/뷰 + 변경 유형 (ADD/MODIFY/DROP) 모두 식별되었는가
- [ ] 기존 데이터 행/문서 수 추정 + impact 분석 (테이블 크기·트래픽·의존 service)이 명시되었는가
- [ ] FK / unique / check constraint 영향이 분석되었는가

### §11.2 Migration 전략
- [ ] 마이그레이션 방식이 결정되었고 결정 근거가 제시되었는가 (online / offline / blue-green / dual-write / expand-contract / shadow table)
- [ ] Lock 시간 추정 + downtime 허용 여부가 명시되었는가
- [ ] Backward / forward compatibility (구버전 코드↔새 schema 양방향)가 검토되었는가
- [ ] Migration 도구가 결정되었는가 (consumer 환경 정합)

### §11.3 Rollback 경로
- [ ] 실패 시 rollback 스크립트/절차가 정의되었는가
- [ ] Rollback이 데이터 손실 동반하는 지점이 명시되었는가
- [ ] Point of no return 지점이 명시되었는가
- [ ] Rollback 검증 절차 (staging 시뮬레이션)가 명시되었는가

### §11.4 Data integrity invariant
- [ ] Migration 전후 불변식이 정의되었는가 (row count / FK / NULL / unique 등)
- [ ] 검증 쿼리·체크포인트 (pre-check / post-check)가 명시되었는가
- [ ] 불일치 감지 시 alert / halt 정책이 명시되었는가

### §11.5 Backfill / 기존 데이터 처리
- [ ] Default value 정책이 명시되었는가 (nullable vs NOT NULL with default)
- [ ] Backfill 배치 전략 (chunk size / throttle / lock 회피 / replication lag)이 정의되었는가
- [ ] 진행률 모니터링 + resume 가능성이 검토되었는가

### §11.6 Idempotency invariant (CONDITIONAL) (CFP-46 / ADR-014)

DataMigrationArchitectAgent primary + OperationalRiskArchitectAgent consult 산출물 검증.

#### 적용 조건 (다음 중 하나라도 해당 시 invariant 작성 의무)
- 재시도 (retry) 가능 작업
- 외부 side effect (외부 API 호출 / 메시지 발행 / 결제 / 거래)
- 장기 워크플로우 (multi-step / saga / async pipeline)
- Migration script (재실행 가능 vs 1회성)

#### 작성 의무 (적용 조건 충족 시)
- [ ] Idempotency key 정의가 명시되었는가 (request_id / business_key / dedup token)
- [ ] 중복 호출 / 재실행 시 결과 동일성 (state 변화 / side effect / 응답) 보장 메커니즘이 명시되었는가
- [ ] Key 저장·조회 정책 (TTL / dedup table / Redis SET) 이 명시되었는가
- [ ] Migration script 의 경우 재실행 안전성 (CREATE IF NOT EXISTS / idempotent UPSERT) 이 명시되었는가

#### N/A 처리 (적용 조건 미충족 시)
- [ ] N/A 명시 + 사유 1줄 (10자+) — "재시도 없음", "side effect 없는 read-only 변경" 등 구체적 사유

### §11.7 N/A 처리
- [ ] N/A 명시 시 사유가 명확하게 제시되었는가 (사유 부재 시 P0 차단)

### Severity 자동 룰
- §11 데이터 마이그레이션 섹션 부재 → **P0**
- §11.6 Idempotency 누락 또는 N/A 사유 부재 → **P0** (CFP-46 / ADR-014 결정 #4)
- §11.7 N/A 사유 부재 → **P0**
- Architect 통합 판정에서 DataMigrationArch 마이그레이션 안전성 매핑 미반영 → **P0**
- §11.2 Migration 전략 결정 근거 부재 → **P1**
- §11.3 Point of no return 지점 미명시 → **P1**
- §11.4 invariant 검증 쿼리 누락 → **P1**

## §4 API 호환 감사 (Codex audit #5, [CFP-22 spec](../../docs/superpowers/specs/2026-04-28-cfp-22-design-checklist-expansion.md))

### API 변경 식별
- [ ] API 변경(route / schema / response code / status code) 영향이 §4 API 계약 또는 §5 변경 계획에 명시되었는가
- [ ] Breaking 여부 분류 (additive / breaking / internal-only)가 명시되었는가

### Backward / Forward compatibility
- [ ] Breaking change 시 versioning 전략이 결정되었는가 (URL prefix / Accept header / OpenAPI version / GraphQL schema)
- [ ] Deprecation timeline이 정의되었는가 (sunset notice / parallel run / migration window)
- [ ] Consumer 영향 분석 (alpha/beta consumer 식별 + 통보 채널)이 명시되었는가

### Severity 자동 룰
- API breaking change에 versioning 전략 부재 → **P0** (공개 API·SLA 대상만)
- API 변경 시 deprecation timeline 미정의 → **P1**
- API 변경 없는 Story → N/A 명시 + 사유 1줄

## §3·§4 관측성 감사 (Codex audit #4, [CFP-22 spec](../../docs/superpowers/specs/2026-04-28-cfp-22-design-checklist-expansion.md))

### 관측성 결정
- [ ] 신규/변경 컴포넌트의 log level + 구조화 형식 (JSON / plain) 결정이 명시되었는가
- [ ] 신규 컴포넌트의 metric 종류 (counter / gauge / histogram + 라벨 차원)가 명시되었는가
- [ ] 신규 외부 호출의 trace span 결정이 명시되었는가

### 핵심 이벤트 emit
- [ ] 핵심 비즈니스 이벤트 emit 지점이 명시되었는가 (예: 결제 완료 / 인증 실패 / 외부 호출 실패)
- [ ] error response의 trace ID·correlation ID 전파 정책이 명시되었는가

### 민감 데이터 redact
- [ ] log·metric·trace의 민감 데이터 redact 정책이 명시되었는가 (SecurityArch §7.5와 cross-ref)
- [ ] PII / 금융 / 헬스 데이터가 외부 시스템(log aggregator / APM)에 전송되지 않음을 검증했는가

### Severity 자동 룰
- 외부 입력 컴포넌트에 관측성 결정 부재 → **P0** (boundary 컴포넌트만)
- 신규 컴포넌트 metric 종류 미명시 → **P1**
- 민감 데이터 redact 정책 부재 → **P1** (SecurityArch §7.5와 동시 P1)
- 내부 함수·docs-only Story → N/A 명시 + 사유 1줄

## §3 SLO 감사 (Codex audit #6, [CFP-22 spec](../../docs/superpowers/specs/2026-04-28-cfp-22-design-checklist-expansion.md))

### SLO 목표 정의
- [ ] 가용성 목표 (예: 99.9%)가 정의되었는가
- [ ] 지연 목표 (p50·p95·p99 latency)가 정의되었는가
- [ ] Throughput 목표 (rps / 동시 connection)가 정의되었는가

### 측정·검증 방법
- [ ] SLO 측정 방법이 명시되었는가 (synthetic monitoring / 실 트래픽 sampling / SLO calculator)
- [ ] Error budget 정책이 정의되었는가 (소진 시 release 정지 / 우선순위 조정)

### §8.3 성능 baseline와의 관계
- [ ] §8.3 성능 baseline (mean 10% 회귀 차단)와 SLO가 별개임을 인지하고 둘 다 정의되었는가 (baseline = 회귀 감지, SLO = 운영 목표)

### Severity 자동 룰
- 공개 API · SLA 대상 서비스에 SLO 부재 → **P0**
- SLO 목표 측정 방법 부재 → **P1**
- 내부 도구·plugin meta Story → N/A 명시 + 사유 1줄

## 다음 게이트 (PASS 시)

- DocsAgent가 `gate:design-review-pass` 라벨 부착
- Phase 1 PR mergeable → merge → 구현 lane 진입
- Story file §9.1 "설계 리뷰 Iteration N" 누적

## Consumer overlay 확장

Consumer는 `.claude/_overlay/templates/review-checklists/design.md`에 도메인 특화 체크 항목을 추가할 수 있다. SessionStart hook이 base + overlay merge.
