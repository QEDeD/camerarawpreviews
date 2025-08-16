Param(
  [string]$Name = $(if ($env:NC_NAME) { $env:NC_NAME } else { 'nc-dev' }),
  [string]$Image = $(if ($env:NC_IMAGE) { $env:NC_IMAGE } else { 'nextcloud:31-apache' }),
  [string]$AppId = 'camerarawpreviews'
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

$AppPath = (Get-Location).Path

# Create dedicated volume for test assets (container-only)
$volName = "$Name-assets"
$existingVolumes = docker volume ls --format '{{.Name}}' | ForEach-Object { $_.Trim() }
if (-not ($existingVolumes -contains $volName)) {
  docker volume create $volName | Out-Null
}

# Start container if not existing
$existing = docker ps -a --format '{{.Names}}' | ForEach-Object { $_.Trim() }
if (-not ($existing -contains $Name)) {
  Write-Output "Starting new Nextcloud container $Name ..."
  docker run -d --name $Name -p 8080:80 `
    -e NEXTCLOUD_ADMIN_USER=admin -e NEXTCLOUD_ADMIN_PASSWORD=admin `
    -e INSIDE_NC_CONTAINER=1 `
    -v "$AppPath:/var/www/html/custom_apps/$AppId" `
    -v "$volName:/var/www/html/custom_apps/$AppId/tests/assets/cache" `
    $Image | Out-Null
} else {
  Write-Output "Container $Name already exists. Starting..."
  docker start $Name | Out-Null
}

# Wait for Nextcloud initial setup to complete (status.php installed=true)
Write-Output 'Waiting for Nextcloud to complete initial setup (up to 120s)...'
$ready = $false
for ($i = 0; $i -lt 120; $i++) {
  try {
    $resp = Invoke-WebRequest -UseBasicParsing -Uri 'http://localhost:8080/status.php' -TimeoutSec 5
    if ($resp.StatusCode -eq 200 -and ($resp.Content -match '"installed"\s*:\s*true')) { $ready = $true; break }
  } catch { }
  Start-Sleep -Seconds 1
}
if ($ready) { Write-Output 'Nextcloud is ready.' } else { Write-Warning 'Nextcloud did not report ready within timeout; continuing anyway.' }

# Install phpunit9 inside container if missing
$hasPhpunit = (docker exec $Name bash -lc 'command -v phpunit9 >/dev/null 2>&1 && echo yes || echo no' 2>$null).Trim()
if ($hasPhpunit -ne 'yes') {
  Write-Output 'Installing phpunit9 inside container...'
  docker exec $Name bash -lc 'curl -Ls https://phar.phpunit.de/phpunit-9.phar -o /usr/local/bin/phpunit9 && chmod +x /usr/local/bin/phpunit9' | Out-Null
}

# Enable app (idempotent)
try { docker exec -u www-data $Name php occ app:enable $AppId | Out-Null } catch { }

# Ensure Imagick + TIFF support
Write-Output 'Ensuring Imagick + TIFF support inside container...'
$null = docker exec $Name bash -lc @'
set -e
NEED_IMAGICK=0
php -r "exit((int)!extension_loaded(\"imagick\"));" || NEED_IMAGICK=1
if [ "$NEED_IMAGICK" -eq 1 ]; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y >/dev/null 2>&1 || true
  apt-get install -y --no-install-recommends php-imagick imagemagick >/dev/null 2>&1 || true
  phpenmod imagick >/dev/null 2>&1 || true
fi
if php -r "exit((int)!extension_loaded('imagick'));"; then
  if php -r "exit((int)(count(\\Imagick::queryformats('TIFF'))>0));"; then
    echo "Imagick TIFF support: OK"
  else
    echo "WARNING: Imagick TIFF not supported (TIFF tests may skip)" >&2
  fi
else
  echo "WARNING: Imagick extension not available (some tests may skip)" >&2
fi
service apache2 reload >/dev/null 2>&1 || apachectl -k graceful >/dev/null 2>&1 || true
'@

Write-Host "" -ForegroundColor DarkGray
Write-Host @"
Nextcloud container running at: http://localhost:8080
Admin login: admin / admin
Mounted app path: /var/www/html/custom_apps/$AppId
Assets cache (container volume): $volName mounted at /var/www/html/custom_apps/$AppId/tests/assets/cache
To tail logs: docker logs -f $Name
Container name: $Name
Image: $Image
Tip: .\scripts\integration-smoke.ps1 -Name $Name
"@
