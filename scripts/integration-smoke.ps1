Param(
  [string]$Name = $(if ($env:NC_NAME) { $env:NC_NAME } else { 'nc-dev' }),
  [string]$Workdir = '/var/www/html/custom_apps/camerarawpreviews'
)

$ErrorActionPreference = 'Stop'

function Test-CommandExists {
  param([Parameter(Mandatory)][string]$Name)
  $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

if (-not (Test-CommandExists docker)) {
  if (-not (Test-CommandExists podman)) {
    Write-Error 'No container runtime available (docker/podman). Install Docker Desktop and retry.'
  } else {
    Write-Output 'Using podman in place of docker.'
    Set-Alias docker podman -Scope Local
  }
}

# Verify container is running
$cid = (docker ps --format '{{.ID}} {{.Names}}' | Select-String -Pattern "\b$Name$" | ForEach-Object { $_.ToString().Split(' ')[0] })
if (-not $cid) { Write-Error "Nextcloud container '$Name' not running. Run scripts/run-nextcloud-container.ps1 first." }

# Ensure phpunit9 inside container
$hasPhpunit = (docker exec $Name bash -lc 'command -v phpunit9 >/dev/null 2>&1 && echo yes || echo no' 2>$null).Trim()
if ($hasPhpunit -ne 'yes') {
  Write-Output 'Installing phpunit9 inside container...'
  docker exec $Name bash -lc 'curl -Ls https://phar.phpunit.de/phpunit-9.phar -o /usr/local/bin/phpunit9 && chmod +x /usr/local/bin/phpunit9' | Out-Null
}

# Run EnvSanityTest only
$exitCode = 0
try {
  docker exec --workdir $Workdir --user www-data $Name phpunit9 --bootstrap tests/bootstrap.php tests/integration/EnvSanityTest.php
} catch {
  $exitCode = 1
}
exit $exitCode
