param(
  [Parameter(Mandatory = $true)]
  [string]$DeviceId,
  [string]$Python = "python",
  [string]$Flutter = "flutter",
  [switch]$SkipBackend,
  [switch]$SkipMobile,
  [string]$TestTarget = "integration_test"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$localEnv = Join-Path $PSScriptRoot "env.local.ps1"
if (Test-Path -LiteralPath $localEnv) {
  . $localEnv
}

$required = @(
  "E2E_API_BASE_URL",
  "E2E_SUPABASE_URL",
  "E2E_SUPABASE_PUBLISHABLE_KEY",
  "E2E_EMAIL",
  "E2E_PASSWORD"
)
foreach ($name in $required) {
  if (-not [System.Environment]::GetEnvironmentVariable($name)) {
    throw "Falta la variable de entorno $name"
  }
}

$apiBaseUrl = [System.Environment]::GetEnvironmentVariable("E2E_API_BASE_URL")
$supabaseUrl = [System.Environment]::GetEnvironmentVariable("E2E_SUPABASE_URL")
$supabaseKey = [System.Environment]::GetEnvironmentVariable("E2E_SUPABASE_PUBLISHABLE_KEY")
$email = [System.Environment]::GetEnvironmentVariable("E2E_EMAIL")
$password = [System.Environment]::GetEnvironmentVariable("E2E_PASSWORD")
$redirect = [System.Environment]::GetEnvironmentVariable("E2E_AUTH_REDIRECT_URL")
if (-not $redirect) {
  $redirect = "app.nerilum://auth-callback"
}
$verification = [System.Environment]::GetEnvironmentVariable("E2E_VERIFICATION_API_BASE_URL")
if (-not $verification) {
  $verification = $apiBaseUrl
}

if (-not $SkipBackend) {
  & $Python -m pytest "$root\back\e2e" -q
  if ($LASTEXITCODE -ne 0) {
    throw "E2E backend falló con código $LASTEXITCODE"
  }
}

$mobileExitCode = 0
$screenshotHostDir = Join-Path $root "e2e\screenshots"
if (-not $SkipMobile) {
  $adbCommand = Get-Command adb -ErrorAction SilentlyContinue
  $adbPath = if ($adbCommand) { $adbCommand.Source } else { Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe" }
  if (-not (Test-Path -LiteralPath $adbPath)) {
    throw "No se encontró adb en PATH ni en $adbPath"
  }
  New-Item -ItemType Directory -Force -Path $screenshotHostDir | Out-Null
  Get-ChildItem -LiteralPath $screenshotHostDir -Filter *.png -ErrorAction SilentlyContinue | Remove-Item -Force
  Get-ChildItem -LiteralPath $screenshotHostDir -Filter ui_*.xml -ErrorAction SilentlyContinue | Remove-Item -Force
  $marker = Join-Path $screenshotHostDir ".running"
  Set-Content -LiteralPath $marker -Value "1"
  $captureJob = Start-Job -ScriptBlock {
    param($adb, $device, $dir, $markerPath)
    function Save-AdbOutput {
      param($arguments, $path)
      $psi = [System.Diagnostics.ProcessStartInfo]::new()
      $psi.FileName = $adb
      $psi.Arguments = $arguments
      $psi.RedirectStandardOutput = $true
      $psi.UseShellExecute = $false
      $psi.CreateNoWindow = $true
      $process = [System.Diagnostics.Process]::Start($psi)
      $stream = [System.IO.File]::Create($path)
      try {
        $process.StandardOutput.BaseStream.CopyTo($stream)
      }
      finally {
        $stream.Dispose()
        $process.WaitForExit()
      }
    }
    while (Test-Path -LiteralPath $markerPath) {
      $stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
      $shotPath = Join-Path $dir ("shot_$stamp.png")
      $uiPath = Join-Path $dir ("ui_$stamp.xml")
      try {
        Save-AdbOutput "-s $device exec-out screencap -p" $shotPath
      }
      catch {
        Remove-Item -LiteralPath $shotPath -Force -ErrorAction SilentlyContinue
      }
      try {
        Save-AdbOutput "-s $device exec-out uiautomator dump /dev/tty" $uiPath
      }
      catch {
        Remove-Item -LiteralPath $uiPath -Force -ErrorAction SilentlyContinue
      }
      Start-Sleep -Milliseconds 1500
    }
  } -ArgumentList $adbPath, $DeviceId, $screenshotHostDir, $marker

  $defines = @(
    "--dart-define=AUTH_MODE=supabase",
    "--dart-define=SUPABASE_URL=$supabaseUrl",
    "--dart-define=SUPABASE_PUBLISHABLE_KEY=$supabaseKey",
    "--dart-define=AUTH_REDIRECT_URL=$redirect",
    "--dart-define=API_BASE_URL=$apiBaseUrl",
    "--dart-define=E2E_VERIFICATION_API_BASE_URL=$verification",
    "--dart-define=E2E_EMAIL=$email",
    "--dart-define=E2E_PASSWORD=$password"
  )
  $optional = @(
    "E2E_DISPLAY_NAME",
    "E2E_IMAGE_ASSET",
    "E2E_SECOND_EMAIL",
    "E2E_SECOND_PASSWORD"
  )
  foreach ($name in $optional) {
    $value = [System.Environment]::GetEnvironmentVariable($name)
    if ($value) {
      $defines += "--dart-define=$name=$value"
    }
  }
  Push-Location "$root\frontend"
  try {
    & $Flutter test $TestTarget -d $DeviceId @defines
    $mobileExitCode = $LASTEXITCODE
  }
  finally {
    Pop-Location
  }
  Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
  Wait-Job $captureJob | Out-Null
  Receive-Job $captureJob | Out-Null
  Remove-Job $captureJob -Force
  if ($mobileExitCode -ne 0) {
    throw "E2E móvil falló con código $mobileExitCode"
  }
}
