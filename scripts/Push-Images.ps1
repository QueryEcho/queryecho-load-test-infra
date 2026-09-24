param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9_.-]+$')]
    [string]$Tag,

    [string]$Profile = "queryecho-loadtest",
    [string]$Region = "ap-northeast-2"
)

$ErrorActionPreference = "Stop"
$infraRoot = Split-Path -Parent $PSScriptRoot
$environmentPath = Join-Path $infraRoot "infra\environments\loadtest"
$terraform = "C:\springdb\tools\terraform\terraform.exe"

$repositories = & $terraform -chdir=$environmentPath output -json ecr_repository_urls | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
    throw "Terraform output에서 ECR URL을 읽지 못했습니다. 기반 인프라를 먼저 적용하세요."
}

$springRepository = $repositories.'spring-target'
$javaRepository = $repositories.'java-target'
$collectorRepository = $repositories.collector
$registry = ($springRepository -split '/')[0]

$password = aws ecr get-login-password --profile $Profile --region $Region
if ($LASTEXITCODE -ne 0) {
    throw "ECR 로그인 토큰 발급에 실패했습니다."
}
$password | docker login --username AWS --password-stdin $registry
if ($LASTEXITCODE -ne 0) {
    throw "ECR 로그인에 실패했습니다."
}

$images = @(
    @{ Local = "queryecho-spring-target:$Tag"; Remote = "${springRepository}:$Tag" },
    @{ Local = "queryecho-java-target:$Tag"; Remote = "${javaRepository}:$Tag" },
    @{ Local = "queryecho-collector:$Tag"; Remote = "${collectorRepository}:$Tag" }
)

foreach ($image in $images) {
    docker tag $image.Local $image.Remote
    docker push $image.Remote
    if ($LASTEXITCODE -ne 0) {
        throw "ECR Push 실패: $($image.Remote)"
    }
}

$images.Remote

