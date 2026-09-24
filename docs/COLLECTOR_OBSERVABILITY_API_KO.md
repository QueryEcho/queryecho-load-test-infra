# QueryEcho Collector 관측 API 확장 및 부하 테스트 가이드

## 1. 확장 목적

기존 부하 테스트에서는 타깃 애플리케이션의 HTTP 요청 성공 여부와 Collector의 오류 로그만 확인할 수 있었다.

예를 들어 타깃 API 요청이 모두 `200 OK`여도 Collector 내부에서는 다음과 같은 문제가 발생할 수 있다.

```text
pool size = 4
active threads = 4
queued tasks = 1000
TaskRejectedException
Collector responded 503
Dropped metric events
```

이 로그만으로는 다음 중 어느 부분이 병목인지 구분하기 어렵다.

- Collector가 이벤트를 받는 속도가 너무 빠른가?
- 비동기 Worker가 부족한가?
- 큐가 계속 쌓이고 있는가?
- PostgreSQL 저장이 느린가?
- SDK 단계에서 이미 이벤트가 유실되었는가?

이를 구분하기 위해 기존 `GET /api/v1/metrics/collection-health` API에 Collector 내부 처리량과 지연시간 지표를 추가했다.

## 2. 전체 처리 흐름

```text
Spring/Java 타깃 API 요청
        ↓
QueryEcho SDK가 쿼리·트랜잭션 이벤트 생성
        ↓
SDK 내부 버퍼 및 HTTP 배치 전송
        ↓
Collector Ingest API 수신
        ↓
비동기 Executor 큐 적재
        ↓
Worker가 이벤트 처리
        ↓
PostgreSQL 저장
```

확장한 API는 위 흐름을 다음과 같이 나누어 측정한다.

```text
수신량 → 접수량 → 큐 대기시간 → Worker 실행 → DB 저장시간 → 저장 성공/실패
```

## 3. API 정보

### 기본 요청

```http
GET /api/v1/metrics/collection-health
```

### 특정 애플리케이션만 조회

```http
GET /api/v1/metrics/collection-health?environment=loadtest&appName=db-test
```

`environment`, `appName`은 선택 조건이다. 값을 생략하면 Collector가 알고 있는 전체 인스턴스를 합산한다.

현재 AWS 구성에서 Collector ALB는 내부용이므로 로컬 PC에서 주소를 직접 호출할 수 없다. 같은 VPC에 있는 리소스를 통하거나 ECS Exec으로 Collector 컨테이너 내부에서 호출해야 한다.

## 4. 추가한 주요 지표

### Collector 누적 카운터

| 필드 | 의미 | 해석 |
|---|---|---|
| `collectorReceivedTotal` | Ingest API가 받은 이벤트 수 | Collector 입구에 실제로 도착한 양 |
| `collectorAcceptedTotal` | 비동기 처리 큐에 접수된 이벤트 수 | Worker가 처리하기로 받아들인 양 |
| `collectorPersistedTotal` | PostgreSQL에 새로 저장된 이벤트 수 | 최종 저장 성공량 |
| `collectorRejectedTotal` | 큐 포화나 요청 크기 초과로 거절된 이벤트 수 | 0보다 크면 Collector 처리 용량 초과 |
| `collectorPersistenceFailedTotal` | DB 저장 중 실패한 이벤트 수 | DB 연결·SQL·트랜잭션 문제 가능성 |
| `collectorInFlight` | 접수됐지만 아직 저장 결과가 확정되지 않은 이벤트 수 | 계속 증가하면 처리 속도가 유입 속도를 따라가지 못함 |

`collectorInFlight`는 다음 개념으로 계산한다.

```text
accepted - persisted - duplicate - persistenceFailed
```

음수가 되지 않도록 최소값을 0으로 제한한다.

### Executor 상태

`executor` 객체는 Collector 비동기 처리기의 현재 상태다.

| 필드 | 의미 |
|---|---|
| `queueSize` | 현재 대기 중인 작업 수 |
| `queueCapacity` | 큐의 최대 크기. 현재 설정은 1,000 |
| `queueUtilizationPercent` | 큐 사용률 |
| `activeWorkers` | 지금 작업을 수행 중인 Worker 수 |
| `currentWorkers` | 현재 생성된 Worker 수 |
| `maxWorkers` | 생성 가능한 최대 Worker 수. 현재 설정은 4 |
| `completedTasks` | 완료된 비동기 작업 누적 수 |

현재 Executor 설정은 다음과 같다.

```text
corePoolSize = 2
maxPoolSize = 4
queueCapacity = 1000
```

### 큐 대기시간

`queueWait`는 이벤트가 Executor에 제출된 시점부터 Worker가 실제 실행을 시작할 때까지 걸린 시간이다.

| 필드 | 의미 |
|---|---|
| `count` | 측정 표본 수 |
| `averageMs` | 평균 큐 대기시간 |
| `p50Ms` | 절반의 작업이 이 시간 이내에 실행됨 |
| `p95Ms` | 95%의 작업이 이 시간 이내에 실행됨 |
| `p99Ms` | 99%의 작업이 이 시간 이내에 실행됨 |
| `maxMs` | 최대 큐 대기시간 |

`queueSize`가 순간적으로 0이어도 `queueWait.p95Ms` 또는 `p99Ms`가 높다면, 테스트 중간에 큐 적체가 있었다는 의미다.

### DB 저장시간

`persistence.query`와 `persistence.transaction`은 각각 쿼리 이벤트와 트랜잭션 이벤트의 PostgreSQL 저장시간을 나타낸다.

```json
{
  "persistence": {
    "query": {
      "count": 0,
      "averageMs": 0.0,
      "p50Ms": 0.0,
      "p95Ms": 0.0,
      "p99Ms": 0.0,
      "maxMs": 0.0
    },
    "transaction": {
      "count": 0,
      "averageMs": 0.0,
      "p50Ms": 0.0,
      "p95Ms": 0.0,
      "p99Ms": 0.0,
      "maxMs": 0.0
    }
  }
}
```

저장시간은 짧은데 큐 대기시간만 증가하면 Worker 수나 Worker에서 수행하는 전체 로직을 의심할 수 있다. 저장시간도 함께 증가하면 PostgreSQL, 커넥션 풀, 인덱스 또는 트랜잭션 비용을 우선 확인한다.

### SDK 및 인스턴스별 지표

`instances`에는 `appName + environment + instanceId` 단위의 상태가 들어간다.

주요 필드는 다음과 같다.

- SDK: `capturedTotal`, `enqueuedTotal`, `sentTotal`, `droppedTotal`
- SDK Drop 원인: `droppedBufferTotal`, `droppedSerializationTotal`, `droppedTransportTotal`
- SDK 버퍼: `queueSize`, `queueCapacity`
- Collector: 수신·접수·저장·중복·거절·저장 실패·처리 중 카운터
- 상태: `HEALTHY`, `DEGRADED`, `DISCONNECTED`, `NO_SDK_REPORT`

## 5. 코드 변경 구조

### `AsyncConfig`

- 익명 기본 실행기 대신 `collectorTaskExecutor`라는 전용 Bean을 사용한다.
- `core=2`, `max=4`, `queue=1000`으로 제한한다.
- `TaskDecorator`를 연결해 각 작업의 큐 대기시간을 측정한다.
- 실행기 자체를 Telemetry 서비스에 연결해 큐 크기와 Worker 수를 조회한다.

### `MetricIngestController`

- 인증을 통과한 이벤트를 `received`로 기록한다.
- 비동기 큐에 정상 제출된 이벤트를 `accepted`로 기록한다.
- 큐가 포화되면 실패한 현재 이벤트뿐 아니라 아직 제출하지 못한 배치의 나머지도 `rejected`로 기록한다.
- 한 요청이 5,000개를 초과하면 전체를 명시적으로 거절하고 카운터에 반영한다.

### `QueryMetricListener`, `TxMetricListener`

- DB 저장 직전에 `System.nanoTime()`으로 측정을 시작한다.
- 성공 또는 실패와 관계없이 `finally`에서 저장 소요시간을 기록한다.
- 쿼리 저장시간과 트랜잭션 저장시간을 분리한다.

### `CollectionTelemetryService`

- 동시 요청에서도 안전하도록 `AtomicLong`, `LongAdder`, `ConcurrentHashMap`을 사용한다.
- 큐 대기시간과 DB 저장시간은 고정 구간 히스토그램으로 기록한다.
- 모든 원본 시간을 메모리에 저장하지 않기 때문에 테스트가 길어져도 측정용 메모리가 계속 증가하지 않는다.
- p50, p95, p99는 원본 표본의 정밀 계산값이 아니라 각 히스토그램 구간의 상한값이다.

## 6. 로컬 WSL 준비

ECS Exec을 사용하려면 WSL에 AWS Session Manager Plugin이 필요하다.

### 설치 여부 확인

```bash
session-manager-plugin --version
```

명령을 찾을 수 없다면 다음 순서로 설치한다.

```bash
tmp_dir=$(mktemp -d)
cd "$tmp_dir"

curl -fsSLo session-manager-plugin.deb \
  https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb

sudo dpkg -i session-manager-plugin.deb

session-manager-plugin --version
```

## 7. AWS Collector API 조회 명령

저장소 위치는 어디여도 되지만 AWS 프로필과 리전이 정확해야 한다.

```bash
export AWS_PROFILE=queryecho-loadtest-new
export AWS_REGION=ap-northeast-2
export ECS_CLUSTER=queryecho-loadtest-loadtest-cluster
export COLLECTOR_SERVICE=queryecho-loadtest-loadtest-collector
```

실행 중인 Collector 태스크 ARN을 가져온다.

```bash
COLLECTOR_TASK=$(aws ecs list-tasks \
  --cluster "$ECS_CLUSTER" \
  --service-name "$COLLECTOR_SERVICE" \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --query 'taskArns[0]' \
  --output text)

echo "$COLLECTOR_TASK"
```

Collector 컨테이너 내부에서 관측 API를 호출한다.

```bash
aws ecs execute-command \
  --cluster "$ECS_CLUSTER" \
  --task "$COLLECTOR_TASK" \
  --container queryecho \
  --interactive \
  --command "wget -qO- http://127.0.0.1:8080/api/v1/metrics/collection-health" \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION"
```

특정 앱만 보고 싶다면 URL을 다음처럼 바꾼다.

```text
http://127.0.0.1:8080/api/v1/metrics/collection-health?environment=loadtest&appName=db-test
```

## 8. 부하 테스트에서 사용하는 방법

### 1단계: 테스트 전 기준값 저장

부하를 넣기 전에 API를 호출해 다음 값을 기록한다.

- `collectorReceivedTotal`
- `collectorPersistedTotal`
- `collectorRejectedTotal`
- `collectorInFlight`
- `executor.queueSize`
- `executor.completedTasks`
- `queueWait.p95Ms`, `queueWait.p99Ms`
- `persistence.query.p95Ms`, `persistence.transaction.p95Ms`

### 2단계: 부하 실행

Spring 5 RPS 예시다.

```bash
cd /mnt/c/springdb/queryecho-load-test-infra
source .venv/bin/activate

python runner/run_test.py \
  --function-name queryecho-loadtest-loadtest-worker \
  --profile queryecho-loadtest-new \
  --scenario scenarios/mixed.json \
  --workers 1 \
  | tee local-results/spring-rps-5-observed.json
```

현재 시나리오는 Worker 하나당 `concurrency=5`, `requestIntervalMs=1000`이므로 목표 상한은 약 5 RPS다.

| Workers | 목표 상한 |
|---:|---:|
| 1 | 약 5 RPS |
| 2 | 약 10 RPS |
| 4 | 약 20 RPS |
| 5 | 약 25 RPS |
| 10 | 약 50 RPS |

### 3단계: 테스트 직후 지표 재조회

동일한 ECS Exec 명령으로 API를 다시 호출한다. 누적값은 `테스트 후 - 테스트 전`으로 계산한다.

```text
이번 테스트 수신량 = after.collectorReceivedTotal - before.collectorReceivedTotal
이번 테스트 저장량 = after.collectorPersistedTotal - before.collectorPersistedTotal
이번 테스트 거절량 = after.collectorRejectedTotal - before.collectorRejectedTotal
```

## 9. 결과 판단 기준

| 관측 결과 | 판단 |
|---|---|
| `queueSize`와 `collectorInFlight`가 증가 후 다시 0에 가까워짐 | 순간 Burst는 있었지만 회복 가능 |
| 테스트가 계속될수록 `queueSize`와 `collectorInFlight`가 증가 | 지속 처리량 한계 초과 |
| `activeWorkers == maxWorkers`이고 큐 사용률 증가 | Worker 처리 용량 부족 가능성 |
| `queueWait.p95/p99` 증가, DB 저장시간은 안정적 | Executor/처리 로직 병목 가능성 |
| DB 저장 `p95/p99`도 함께 증가 | PostgreSQL·커넥션 풀·SQL 병목 가능성 |
| `collectorRejectedTotal > 0` | Collector가 이벤트를 실제 거절함 |
| `sdkDroppedTotal > 0` 또는 인스턴스 `droppedTotal > 0` | SDK 측 데이터 유실 발생 |
| 타깃 HTTP 100% 성공, Collector 거절 발생 | 비즈니스 API는 정상이나 모니터링 데이터는 유실된 상태 |

## 10. 주의사항

- 이 지표는 Collector 프로세스 메모리에 누적되므로 컨테이너가 재시작되면 0으로 초기화된다.
- ECS 태스크가 여러 개면 각 태스크 메모리의 지표가 서로 자동 합산되지 않는다. 현재 Collector 1개 기준 테스트에는 문제가 없다.
- 부하 테스트 결과의 HTTP 성공률은 타깃 API 성공률이다. Collector의 수집 성공률과 동일하지 않다.
- 현재 배치 일부가 큐에 접수된 뒤 나머지가 거절되면 Collector는 `503`을 반환한다. SDK는 배치 전체를 전송 실패로 판단할 수 있으므로 부분 접수의 정확한 재시도 정책은 별도 개선 대상이다.
- 이 API 확장의 목적은 바로 Worker 수나 큐 크기를 늘리는 것이 아니라, 병목 위치를 수치로 확인한 뒤 필요한 부분만 조정하는 것이다.

## 11. `TargetNotConnectedException` 해결

다음 오류는 Session Manager Plugin 설치 오류가 아니라 ECS 태스크가 AWS Exec 메시지 채널에 연결하지 못한 상태다.

```text
TargetNotConnectedException: The execute command failed. TargetNotConnected
```

ECS 서비스에 `enable_execute_command = true`를 설정하는 것만으로는 충분하지 않다. 컨테이너가 사용하는 **Task Role**에도 다음 권한이 필요하다.

```text
ssmmessages:CreateControlChannel
ssmmessages:CreateDataChannel
ssmmessages:OpenControlChannel
ssmmessages:OpenDataChannel
```

이 저장소의 `infra/modules/applications/main.tf`에는 위 네 권한만 허용하는 `allow-ecs-exec-channels` 인라인 정책을 추가했다.

권한 적용 후에는 이미 실행 중인 태스크를 새 태스크로 교체해야 한다. 기존 태스크는 시작 시점에 Exec 채널 연결에 실패했기 때문에 정책만 추가해도 자동 복구되지 않을 수 있다.

```bash
aws ecs update-service \
  --cluster queryecho-loadtest-loadtest-cluster \
  --service queryecho-loadtest-loadtest-collector \
  --force-new-deployment \
  --profile queryecho-loadtest-new \
  --region ap-northeast-2

aws ecs wait services-stable \
  --cluster queryecho-loadtest-loadtest-cluster \
  --services queryecho-loadtest-loadtest-collector \
  --profile queryecho-loadtest-new \
  --region ap-northeast-2
```

또한 채팅이나 문서에서 명령어를 복사할 때 URL을 다음과 같은 Markdown 링크 문법으로 입력하면 안 된다.

```text
[http://127.0.0.1:8080/...](http://127.0.0.1:8080/...)
```

터미널에는 다음처럼 순수 URL만 입력한다.

```text
http://127.0.0.1:8080/api/v1/metrics/collection-health
```
