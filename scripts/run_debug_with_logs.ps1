param(
  [string]$PackageName = '',
  [int]$DeviceLogLimit = 5,
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$FlutterArgs
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Resolve-Path (Join-Path $scriptDir '..')
$runtimeRoot = Join-Path $projectRoot 'runtime_logs'
$hostDir = Join-Path $runtimeRoot 'host'
$deviceDir = Join-Path $runtimeRoot 'device'

New-Item -ItemType Directory -Path $hostDir -Force | Out-Null
New-Item -ItemType Directory -Path $deviceDir -Force | Out-Null

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$flutterLogPath = Join-Path $hostDir "flutter_run_$timestamp.log"
$adbLogPath = Join-Path $hostDir "adb_logcat_$timestamp.log"
$notesLogPath = Join-Path $hostDir "device_pull_$timestamp.log"

function Write-Note {
  param([string]$Message)
  $line = "[{0}] {1}" -f ((Get-Date).ToString('o')), $Message
  $line | Tee-Object -FilePath $notesLogPath -Append | Out-Null
}

function Resolve-PackageName {
  param([string]$Preferred)
  if ($Preferred -and $Preferred.Trim().Length -gt 0) {
    return $Preferred.Trim()
  }

  $adb = Get-Command adb -ErrorAction SilentlyContinue
  if (-not $adb) {
    return $null
  }

  $packages = & adb shell pm list packages 2>$null
  if ($LASTEXITCODE -ne 0 -or -not $packages) {
    return $null
  }

  $candidates = @()
  foreach ($line in $packages) {
    if ($line -match '^package:(.+)$') {
      $pkg = $Matches[1].Trim()
      if ($pkg -like 'com.chatify.app*') {
        $candidates += $pkg
      }
    }
  }

  if ($candidates.Count -eq 0) {
    return $null
  }
  if ($candidates -contains 'com.chatify.app.dev') {
    return 'com.chatify.app.dev'
  }
  if ($candidates -contains 'com.chatify.app') {
    return 'com.chatify.app'
  }
  return $candidates[0]
}

function Pull-DeviceSessionLogs {
  param(
    [string]$ResolvedPackage,
    [int]$Limit
  )

  if (-not $ResolvedPackage) {
    Write-Note 'Package name was not resolved. Skipped pulling device logs.'
    return
  }

  $adb = Get-Command adb -ErrorAction SilentlyContinue
  if (-not $adb) {
    Write-Note 'adb was not found in PATH. Skipped pulling device logs.'
    return
  }

  $deviceLogDir = "/data/user/0/$ResolvedPackage/app_flutter/chatify_debug_logs"
  $listResult = & adb shell "run-as $ResolvedPackage ls -1t $deviceLogDir/debug_session_*.log" 2>&1
  if ($LASTEXITCODE -ne 0) {
    Write-Note "Could not list device session logs for package $ResolvedPackage. adb output: $($listResult -join ' ')"
    return
  }

  $paths = @()
  foreach ($line in $listResult) {
    $trimmed = "$line".Trim()
    if (-not $trimmed) {
      continue
    }
    if ($trimmed.StartsWith('run-as:') -or $trimmed.StartsWith('ls:')) {
      continue
    }
    if ($trimmed.Contains('No such file')) {
      continue
    }
    $paths += $trimmed
  }

  if ($paths.Count -eq 0) {
    Write-Note "No debug_session_*.log files found inside $deviceLogDir."
    return
  }

  $count = [Math]::Min($Limit, $paths.Count)
  for ($i = 0; $i -lt $count; $i++) {
    $remotePath = $paths[$i]
    $fileName = [System.IO.Path]::GetFileName($remotePath)
    if ([string]::IsNullOrWhiteSpace($fileName)) {
      continue
    }

    $localPath = Join-Path $deviceDir $fileName
    $content = & adb shell "run-as $ResolvedPackage cat $remotePath" 2>&1
    if ($LASTEXITCODE -ne 0) {
      Write-Note "Failed to read $remotePath. adb output: $($content -join ' ')"
      continue
    }
    Set-Content -Path $localPath -Value $content -Encoding utf8
    Write-Note "Pulled $remotePath -> $localPath"
  }
}

Write-Note "Debug log capture started (PackageName='$PackageName', DeviceLogLimit=$DeviceLogLimit)"

$adbProcess = $null
$adbAvailable = (Get-Command adb -ErrorAction SilentlyContinue) -ne $null
if ($adbAvailable) {
  try {
    & adb logcat -c | Out-Null
  } catch {
    Write-Note "Failed to clear adb logcat buffer: $($_.Exception.Message)"
  }
  try {
    $adbProcess = Start-Process -FilePath 'adb' -ArgumentList @('logcat', '-v', 'threadtime') -NoNewWindow -PassThru -RedirectStandardOutput $adbLogPath -RedirectStandardError $adbLogPath
    Write-Host "adb logcat -> $adbLogPath"
  } catch {
    Write-Note "Failed to start adb logcat capture: $($_.Exception.Message)"
  }
} else {
  Write-Note 'adb was not found in PATH. Host logcat capture skipped.'
}

$flutterRunArgs = @('run')
if ($FlutterArgs -and $FlutterArgs.Count -gt 0) {
  $flutterRunArgs += $FlutterArgs
}

$supabaseDefineFile = Join-Path $projectRoot 'supabase.env.json'
$hasDefineFromFileArg = $flutterRunArgs -match '^--dart-define-from-file='
if ((Test-Path $supabaseDefineFile) -and -not $hasDefineFromFileArg) {
  $flutterRunArgs += "--dart-define-from-file=$supabaseDefineFile"
  Write-Note "Using Supabase defines from $supabaseDefineFile"
}

Write-Host "flutter run output -> $flutterLogPath"
Write-Host "Running: flutter $($flutterRunArgs -join ' ')"

try {
  & flutter @flutterRunArgs 2>&1 | Tee-Object -FilePath $flutterLogPath
} finally {
  if ($adbProcess -and -not $adbProcess.HasExited) {
    try {
      Stop-Process -Id $adbProcess.Id -Force -ErrorAction SilentlyContinue
    } catch {
      Write-Note "Failed to stop adb logcat capture: $($_.Exception.Message)"
    }
  }

  $resolvedPackage = Resolve-PackageName -Preferred $PackageName
  Pull-DeviceSessionLogs -ResolvedPackage $resolvedPackage -Limit $DeviceLogLimit
  Write-Note "Debug log capture finished. Host logs: $hostDir | Device logs: $deviceDir"

  Write-Host "Host logs directory:   $hostDir"
  Write-Host "Device logs directory: $deviceDir"
}
