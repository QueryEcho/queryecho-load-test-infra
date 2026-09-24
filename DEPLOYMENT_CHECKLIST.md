# AWS 부하 테스트 배포 체크리스트

이 문서는 AWS에 실제 비용이 발생하기 전후의 작업을 구분한다.

## A. 로컬 준비 — AWS 변경 및 비용 없음

- [x] Terraform 실행 파일 설치 및 체크섬 검증
- [x] Terraform `fmt` 및 `validate`
- [x] Spring 대상 앱 Dockerfile 작성
- [x] 순수 Java 대상 앱 Dockerfile 작성
- [x] QueryEcho Collector Dockerfile 확인
- [x] Docker 이미지 3개 로컬 빌드 성공 (`20260919-01`)
- [x] AWS CLI 프로파일 인증 성공 (`queryecho-loadtest-new`)
- [x] 배포 대상 계정 ID와 서울 리전 확인

## B. Terraform 상태 저장소 생성 — AWS 변경 시작

생성 리소스: Terraform 상태용 S3 버킷. 비용은 매우 작지만 AWS 리소스가 실제로 생성된다.

- [x] `infra/bootstrap`에서 `terraform plan` 검토 (5 add, 0 change, 0 destroy)
- [ ] 사용자 승인 후 `terraform apply`
- [ ] 출력된 버킷 이름으로 `backend.hcl` 작성

## C. 기반 인프라 생성 — 시간당 비용 발생 시작

ECS desired count가 0이어도 다음 리소스가 생성되어 과금된다.

- NAT Gateway 1개와 Elastic IP 1개
- Application Load Balancer 2개
- RDS MySQL `db.t4g.small` 1개
- RDS PostgreSQL `db.t4g.small` 1개
- VPC, Subnet, Security Group, ECR, S3, Secrets Manager, CloudWatch

- [ ] `terraform.tfvars`의 세 desired count를 0으로 설정
- [ ] `terraform plan`의 생성·변경·삭제 수량 확인
- [ ] 사용자 승인 후 첫 `terraform apply`
- [ ] 생성된 ECR URL 확인

## D. 이미지 Push 및 ECS 실행

- [ ] 고유 이미지 태그 결정(예: Git 커밋 SHA 또는 날짜-시각)
- [ ] Spring, Java, Collector 이미지를 ECR에 Push
- [ ] `terraform.tfvars`의 이미지 태그를 Push한 태그로 변경
- [ ] 세 desired count를 1로 변경
- [ ] 두 번째 `terraform plan` 검토
- [ ] 사용자 승인 후 두 번째 `terraform apply`
- [ ] ECS 서비스 3개가 stable 상태인지 확인
- [ ] ALB Target Group 헬스체크가 모두 healthy인지 확인

## E. 단계적 부하 테스트

- [ ] Lambda는 계정의 unreserved concurrency를 사용하며 `--workers`를 1 → 5 → 10 순서로 제한
- [ ] 작업자 1개로 smoke test
- [ ] QueryEcho에서 1개 단독 쿼리, COMMIT 3개, ROLLBACK 3개 확인
- [ ] 작업자 5개
- [ ] 작업자 10개
- [ ] 필요할 때만 20개 이상으로 증가
- [ ] CloudWatch에서 오류율, P95/P99, ECS CPU/메모리, RDS 부하 확인
- [ ] S3 결과 파일 확인

## F. 비용 중단

- [ ] 결과를 내려받거나 기록
- [ ] `terraform destroy` 계획 검토
- [ ] 사용자 승인 후 `terraform destroy`
- [ ] NAT Gateway, ALB 2개, RDS 2개, ECS 서비스가 삭제됐는지 AWS 콘솔에서 확인
- [ ] 필요 없으면 bootstrap 상태 버킷과 ECR 이미지도 정리
