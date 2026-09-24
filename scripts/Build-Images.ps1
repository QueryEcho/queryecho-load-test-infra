param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9_.-]+$')]
    [string]$Tag
)

$ErrorActionPreference = "Stop"
$infraRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $infraRoot

$images = @(
    @{ Name = "queryecho-spring-target:$Tag"; Context = Join-Path $workspaceRoot "db-test" },
    @{ Name = "queryecho-java-target:$Tag"; Context = Join-Path $workspaceRoot "java-load-test-app" },
    @{ Name = "queryecho-collector:$Tag"; Context = Join-Path $workspaceRoot "QueryEcho" }
)

foreach ($image in $images) {
    Write-Host "Building $($image.Name) from $($image.Context)"
    docker build --tag $image.Name $image.Context
    if ($LASTEXITCODE -ne 0) {
        throw "Docker 이미지 빌드 실패: $($image.Name)"
    }
}

$imageNames = $images | ForEach-Object { $_.Name }
docker image inspect $imageNames --format '{{.RepoTags}} {{.Size}}'
if ($LASTEXITCODE -ne 0) {
    throw "빌드된 Docker 이미지 확인에 실패했습니다."
}
