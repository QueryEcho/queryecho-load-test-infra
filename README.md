# QueryEcho Load Test Infrastructure

QueryEcho Java SDK, Spring SDK 및 Collector의 동시 부하와 수집 정확도를 검증하기 위한 독립 AWS 인프라 프로젝트다.
QueryEcho 애플리케이션 소스와 분리해 Terraform 상태, AWS 권한, 비용 및 인프라 변경 이력을 별도로 관리한다.

## 저장소 경계

```text
QueryEcho/                       SDK + Collector + Dashboard
db-test/                         Spring 부하 대상 애플리케이션
java-load-test-app/              순수 Java 부하 대상 애플리케이션
queryecho-load-test-infra/       이 저장소: AWS 인프라 + Lambda 부하 발생기
```

애플리케이션 저장소의 CI가 Docker 이미지를 ECR에 올리고, 이 저장소는 이미지 태그를 입력받아 배포한다.
Terraform은 이미지를 빌드하지 않으며 `terraform apply`만으로 부하 테스트를 시작하지 않는다.

## 구성

```text
runner -> Lambda workers -> internal target ALB
                           ├─ Spring app -> RDS MySQL
                           └─ Java app   -> RDS MySQL

Spring/Java SDK -> internal Collector ALB -> QueryEcho -> RDS PostgreSQL
Lambda result   -> S3
ECS/Lambda/RDS  -> CloudWatch
```

기본 구성은 외부에서 직접 접근할 수 없는 내부 ALB를 사용한다. 대시보드 접근은 VPN, SSM 포트 포워딩용 중계 인스턴스,
또는 조직의 기존 사설 접속 경로를 별도로 연결해야 한다.

## 디렉터리

```text
infra/bootstrap/                 Terraform 상태 버킷 생성
infra/environments/loadtest/     실제 loadtest 환경 조립
infra/modules/network/           VPC, Subnet, NAT, Security Group
infra/modules/registry/          ECR
infra/modules/databases/         RDS MySQL, PostgreSQL
infra/modules/applications/      ECS, ALB, Task Definition, Secrets
infra/modules/load-generator/    Lambda, 결과 S3
infra/modules/observability/     CloudWatch Dashboard
lambda/worker.py                 동시 HTTP 요청 작업자
runner/run_test.py               여러 Lambda 작업자 실행 및 결과 취합
scenarios/                       재현 가능한 테스트 입력
```

## 준비 사항

- AWS CLI 인증
- Terraform 1.10 이상
- Python 3.11 이상 및 `boto3`
- Spring/Java/QueryEcho Docker 이미지
- 비용이 발생하는 리소스: NAT Gateway, ALB 2개, ECS, RDS 2개

전체 진행 순서와 비용 발생 시점은 [`DEPLOYMENT_CHECKLIST.md`](DEPLOYMENT_CHECKLIST.md)를 먼저 확인한다.
로컬 이미지 빌드는 다음 스크립트를 사용한다.

```powershell
.\scripts\Build-Images.ps1 -Tag "20260919-01"
```

AWS 인증과 도구 상태는 리소스를 생성하기 전에 검사한다.

```powershell
.\scripts\Test-AwsPrerequisites.ps1 -Profile "queryecho-loadtest-new"
```

로컬 전용 `terraform.tfvars`에는 AWS 프로필과 배포 계정 ID를 함께 기록한다.
Provider의 `allowed_account_ids`가 다른 계정에 대한 실수로 인한 배포를 거부한다.

## 1. 상태 버킷 생성

```powershell
cd infra/bootstrap
terraform init
terraform apply -var="project_name=queryecho-loadtest"
```

출력된 버킷 이름을 `infra/environments/loadtest/backend.hcl`에 기록한다.

```hcl
bucket       = "출력된-버킷"
key          = "queryecho/loadtest/terraform.tfstate"
region       = "ap-northeast-2"
use_lockfile = true
encrypt      = true
```

## 2. 환경 변수 파일 준비

```powershell
cd ..\environments\loadtest
Copy-Item backend.hcl.example backend.hcl
Copy-Item terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars`에 AWS 리전, 이미지 태그와 ECS 개수를 입력한다. ECR이 비어 있는 첫 적용에서는
`spring_desired_count`, `java_desired_count`, `collector_desired_count`를 0으로 두고 저장소부터 만든다.
이미지를 Push한 다음 1로 올려 다시 적용한다.

세 이미지는 모두 첫 적용에서 생성된 전용 ECR 저장소에 Push한다. 태그가 변경 불가능하도록 설정되어 있으므로
`latest` 대신 Git 커밋 SHA처럼 매번 고유한 태그를 사용한다.

## 3. 배포

```powershell
terraform init -backend-config=backend.hcl
terraform fmt -recursive
terraform validate
terraform plan -out=loadtest.tfplan
terraform apply loadtest.tfplan
```

## 4. 부하 실행

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r ..\..\..\runner\requirements.txt

python ..\..\..\runner\run_test.py `
  --function-name <terraform output lambda_function_name> `
  --profile queryecho-loadtest-new `
  --scenario ..\..\..\scenarios\transaction.json `
  --workers 10
```

각 작업자는 결과를 S3에 저장한다. 실행 전 요청 1건으로 SQL 실행과 Collector 저장을 검증한 뒤 동시성을 단계적으로 높인다.

시나리오의 `requestIntervalMs`는 각 실행 레인의 요청 시작 간격을 제한한다. 현재 시나리오는
`requestIntervalMs: 1000`이므로 레인 하나가 초당 최대 1개 요청을 시작한다. 따라서 일반 시나리오의
대략적인 요청 속도 상한은 `workers × concurrency` RPS이며, 실제 처리량은 응답시간에 따라 더 낮을 수 있다.

첫 검증은 30초, 동시성 1인 smoke 시나리오로 시작한다.

```powershell
python runner\run_test.py `
  --function-name <terraform output lambda_function_name> `
  --profile queryecho-loadtest-new `
  --scenario scenarios\smoke-spring.json `
  --workers 1

python runner\run_test.py `
  --function-name <terraform output lambda_function_name> `
  --profile queryecho-loadtest-new `
  --scenario scenarios\smoke-java.json `
  --workers 1
```

smoke 결과와 QueryEcho 수집 결과가 일치하면 `java-standalone.json`,
`java-transaction.json`, `java-mixed.json` 또는 기존 Spring 시나리오의 작업자 수를 단계적으로 높인다.

## 안전 원칙

- 운영 DB나 운영 Collector를 대상으로 실행하지 않는다.
- 테스트 환경의 ECS 자동 확장은 기본적으로 끈다.
- RDS와 ALB는 사설 네트워크에 둔다.
- 비밀번호와 수집 API 키는 Secrets Manager에 저장한다.
- 상태 파일에도 민감한 메타데이터가 포함될 수 있으므로 상태 버킷 접근을 제한한다.
- 테스트가 끝나면 `terraform destroy`로 비용 발생 리소스를 제거한다.
