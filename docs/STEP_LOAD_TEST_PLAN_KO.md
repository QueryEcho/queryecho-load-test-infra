# QueryEcho 단계별 부하 테스트 계획

## 1. 테스트 목적

외부 애플리케이션에 적용된 QueryEcho SDK가 동시 부하 상황에서도 다음 기능을 정상적으로 수행하는지 확인한다.

- Spring SDK와 순수 Java SDK가 쿼리·트랜잭션을 정상 수집하는지
- 타깃 애플리케이션의 DB 커넥션 풀이 언제부터 대기 또는 고갈되는지
- Collector가 수집 이벤트를 얼마나 안정적으로 저장하는지
- 부하가 증가할 때 이벤트 누락과 API 지연이 어떻게 변하는지

## 2. 테스트 전 확인

- Terraform 리소스 배포 완료
- Spring, Java, Collector ECS 서비스가 각각 1개씩 실행 중
- ALB Target Group 상태가 `healthy`
- RDS MySQL과 PostgreSQL 상태가 `available`
- Spring/Java 요청 1건이 성공하고 QueryEcho에 수집되는지 확인
- 테스트 대상이 운영 환경이 아닌지 확인

## 3. 동시 부하 단계

일반 시나리오의 `concurrency`는 5이고 `requestIntervalMs`는 1,000ms다. 레인 하나가 초당 최대 1개 요청을 시작하므로 요청 속도 상한은 대략 `workers × 5` RPS다. 실제 처리량은 응답시간에 따라 더 낮을 수 있다.

| 단계 | 시나리오 | Workers | 목표 요청 속도 상한 | 확인 목적 |
|---|---|---:|---:|---|
| 0 | `smoke-spring.json` / `smoke-java.json` | 1 | 약 1 RPS | 전체 연결과 수집 경로 확인 |
| 1 | `mixed.json` / `java-mixed.json` | 1 | 약 5 RPS | 정상 상태 기준값 측정 |
| 2 | 동일 | 2 | 약 10 RPS | Collector 처리량 변화 확인 |
| 3 | 동일 | 5 | 약 25 RPS | 응답 지연과 수집 큐 증가 확인 |
| 4 | 동일 | 10 | 약 50 RPS | timeout, 오류, 이벤트 누락 확인 |

각 단계가 끝난 후 결과를 확인하고 다음 단계로 올라간다. Spring과 Java는 처음에는 동시에 실행하지 말고 각각 따로 테스트한다.

## 4. 실행 예시

아래 명령은 저장소 최상위 디렉터리에서 실행한다.

```bash
source .venv/bin/activate

python runner/run_test.py \
  --function-name <Lambda 함수 이름> \
  --profile queryecho-loadtest-new \
  --scenario scenarios/smoke-spring.json \
  --workers 1
```

Smoke 테스트 성공 후 `mixed.json`의 workers를 단계적으로 높인다.

```bash
python runner/run_test.py \
  --function-name <Lambda 함수 이름> \
  --profile queryecho-loadtest-new \
  --scenario scenarios/mixed.json \
  --workers 1
```

이후 `--workers`를 `2 → 5 → 10` 순서로 변경한다. 순수 Java는 시나리오만 `scenarios/java-mixed.json`으로 바꾼다.

## 5. 단계마다 기록할 항목

| 구분 | 기록 항목 |
|---|---|
| 부하 결과 | 총 요청 수, 성공 수, 실패 수, timeout 수 |
| 응답 성능 | 평균, p95, p99, 최대 응답시간 |
| 타깃 앱 | HTTP 5xx, HikariCP timeout, CPU, 메모리 |
| MySQL | DatabaseConnections, CPU, FreeableMemory |
| SDK | captured, sent, dropped, queue size |
| Collector | HTTP 오류, 비동기 큐 포화, 저장 오류 |
| PostgreSQL | DatabaseConnections, CPU, 저장된 이벤트 수 |

수집 성공률은 다음과 같이 계산한다.

```text
수집 성공률(%) = Collector에 저장된 이벤트 수 / SDK가 캡처한 이벤트 수 × 100
```

## 6. 중단 기준

다음 현상이 나타나면 부하를 더 올리지 않고 해당 단계의 로그와 지표부터 확인한다.

- API timeout 또는 HTTP 5xx가 지속적으로 증가함
- Spring에서 8초 DB 커넥션 획득 timeout이 발생함
- SDK `dropped` 값이 증가함
- Collector가 5xx를 반환하거나 이벤트 저장 오류가 발생함
- ECS 태스크가 재시작되거나 메모리 부족으로 종료됨
- RDS CPU 또는 커넥션 수가 한계에 근접함

## 7. 커넥션 문제가 잘 드러나지 않을 때

현재 SQL은 실행 시간이 짧아 커넥션이 빠르게 반환된다. 동시 요청 50에서도 문제가 재현되지 않으면 다음 단계로 테스트 전용 `connection-hold` API를 추가한다.

```text
트랜잭션 시작 → DB 커넥션 획득 → 일정 시간 점유 → 커밋
```

예를 들어 커넥션을 3초 동안 점유하면 풀 대기와 timeout을 더 명확하게 재현할 수 있다. RPS 제한 테스트는 Collector 처리량을 확인하고, 커넥션 점유 테스트는 DB 풀 경합을 확인하는 별도 실험으로 구분한다.

## 8. 테스트 종료

- Lambda/S3 결과와 CloudWatch 지표 보관
- Spring/Java/Collector 로그 보관
- 단계별 수집 성공률과 최초 오류 발생 지점 기록
- 테스트가 끝나면 `terraform destroy`로 비용 발생 리소스 제거
