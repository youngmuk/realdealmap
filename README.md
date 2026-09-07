# realdealmap-data

RealDealMap의 데이터 파이프라인과 갱신 트리거. 국토교통부 실거래가 Open API에서 자료를 수집해
정규화·좌표 결합 후 Cloudflare R2에 불변 청크로 배포한다.

설계 근거는 `Doc/기술검토서.html`(rev.2), 작업 단위는 `Doc/jobs/작업계획.html`을 참조한다.

## 구성

| 경로 | 역할 |
| --- | --- |
| `packages/shared` | 시군구 카탈로그, 공통 타입 |
| `packages/ingest` | 국토부 수집 · 정규화 · 청크 생성 · R2 업로드 |
| `packages/geocode` | 주소→좌표 사전 구축 |
| `packages/worker` | 갱신 트리거 Worker + 지역 Durable Object |
| `.github/workflows` | 수집 워크플로 (dispatch · schedule) |

## 시군구 카탈로그

실거래가 API는 시군구 5자리 코드(`LAWD_CD`)와 계약년월(`DEAL_YMD`)로 조회한다.
그 코드 목록을 행정표준코드관리시스템의 법정동코드 전체자료에서 생성한다.

```bash
npm run regions        # 내려받기 + 생성
```

생성물:

- `packages/shared/data/regions.json` — 시군구 레벨 269건, 그중 **조회 대상 256건**
- `packages/shared/data/legacy-codes.json` — 폐지 코드 → 현행 코드 매핑 92건

원본(`packages/shared/raw/`)은 커밋하지 않는다. 생성물만 커밋한다.

### 조회 대상이 256건인 이유

시군구 레벨 항목은 269건이지만, 일반구를 둔 시 13곳(수원·성남·안양·부천·안산·고양·용인·화성·
청주·천안·포항·창원·전주)은 그 자체로도 코드를 가진다. 하위 구와 중복 조회가 되므로
`queryable: false`로 표시해 조회 대상에서 제외한다.

### 주의: 행정구역 개편이 진행 중이다

- **광주광역시(29)와 전라남도(46)가 폐지되고 전남광주통합특별시(12)로 통합**되었다.
- 부천시(2024)·화성시(2025)에 일반구가 신설되었다.
- 강원도(42)→강원특별자치도(51), 전라북도(45)→전북특별자치도(52) 코드도 바뀌었다.

**국토부 실거래가 API가 과거 계약월에 대해 신·구 코드 중 무엇을 받는지는 확인되지 않았다.**
작업계획 T1.1에서 실호출로 검증한 뒤 조회 코드 결정 로직을 확정한다. 그 전까지
`legacy-codes.json`을 폴백 후보로 보존한다.

## 보안

서비스키·R2 자격증명·카카오 REST 키는 **GitHub Secrets에만** 둔다. 이 저장소는 public이다.

- 워크플로 로그에 요청 URL 전체를 출력하지 않는다(`serviceKey`가 쿼리스트링에 들어간다).
- R2 토큰은 대상 버킷 하나로 범위를 제한하고 Object Read and Write만 부여한다.
- 카카오 REST 키는 **헤더로만** 나간다. URL 쿼리에 실으면 로그·프록시에 그대로 남는다.

필요한 Secrets:

| 이름 | 쓰는 곳 |
| --- | --- |
| `DATA_GO_KR_SERVICE_KEY` | 국토부 실거래가 호출 |
| `R2_ACCOUNT_ID` · `R2_ACCESS_KEY_ID` · `R2_SECRET_ACCESS_KEY` · `R2_BUCKET` | R2 업로드 |
| `KAKAO_REST_API_KEY` | 주소→좌표 변환 (`geocode-queue`, `refresh-region`) |
| `CALLBACK_SECRET` | Worker 완료 알림 |
