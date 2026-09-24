param(
    [string]$Profile = "queryecho-loadtest",
    [string]$Region = "ap-northeast-2"
)

$ErrorActionPreference = "Stop"
$terraform = "C:\springdb\tools\terraform\terraform.exe"

if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    throw "AWS CLI가 설치되어 있지 않습니다."
}
if (-not (Test-Path -LiteralPath $terraform)) {
    throw "Terraform을 찾을 수 없습니다: $terraform"
}
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker CLI가 설치되어 있지 않습니다."
}

$identity = aws sts get-caller-identity --profile $Profile --output json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
    throw "AWS 프로파일 인증에 실패했습니다: $Profile"
}

$configuredRegion = aws configure get region --profile $Profile
if ($configuredRegion -ne $Region) {
    throw "AWS 프로파일 리전이 $Region 이 아닙니다. 현재 값: $configuredRegion"
}

$dockerVersion = docker version --format '{{.Server.Version}}'
if ($LASTEXITCODE -ne 0) {
    throw "Docker 엔진에 연결할 수 없습니다."
}

[PSCustomObject]@{
    AccountId        = $identity.Account
    PrincipalArn     = $identity.Arn
    Region           = $configuredRegion
    TerraformVersion = (& $terraform version -json | ConvertFrom-Json).terraform_version
    DockerVersion    = $dockerVersion
}

