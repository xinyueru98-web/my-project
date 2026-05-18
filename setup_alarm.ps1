if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "このスクリプトは管理者権限で実行する必要があります。"
    Write-Warning "PowerShellを「管理者として実行」して、再度実行してください。"
    Return
}

$targetFolder = "C:\Users\no1be\Downloads\手探り\目覚まし"
if (-not (Test-Path -Path $targetFolder)) {
    New-Item -ItemType Directory -Path $targetFolder -Force | Out-Null
}

$lockOffFile = Join-Path $targetFolder "Lock_OFF_Volume50.ps1"
$playLiveFile = Join-Path $targetFolder "CheckAndPlayLive.ps1"
$lockOnFile = Join-Path $targetFolder "Lock_ON.ps1"

# Create Lock_OFF_Volume50.ps1
$lockOffContent = @'
powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_NONE CONSOLELOCK 0
powercfg /SETDCVALUEINDEX SCHEME_CURRENT SUB_NONE CONSOLELOCK 0
powercfg /S SCHEME_CURRENT

Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;
[Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAudioEndpointVolume {
  int f(); int g(); int h(); int i();
  int SetMasterVolumeLevelScalar(float fLevel, System.Guid pguidEventContext);
  int j(); int k(); int l(); int m();
  int GetMasterVolumeLevelScalar(out float pfLevel);
  int n(); int o(); int p(); int q();
  int SetMute([MarshalAs(UnmanagedType.Bool)] bool bMute, System.Guid pguidEventContext);
  int GetMute(out bool pbMute);
}
[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDevice {
  int Activate(ref System.Guid id, int clsCtx, int activationParams, out IAudioEndpointVolume aev);
}
[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDeviceEnumerator {
  int f();
  int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice endpoint);
}
[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumeratorComObject { }
public class Audio {
  public static void SetVolume(float level) {
    IMMDeviceEnumerator enumerator = (IMMDeviceEnumerator)new MMDeviceEnumeratorComObject();
    IMMDevice dev;
    enumerator.GetDefaultAudioEndpoint(0, 1, out dev);
    IAudioEndpointVolume epv;
    System.Guid epvid = typeof(IAudioEndpointVolume).GUID;
    dev.Activate(ref epvid, 23, 0, out epv);
    epv.SetMasterVolumeLevelScalar(level, System.Guid.Empty);
    epv.SetMute(false, System.Guid.Empty);
  }
}
"@
[Audio]::SetVolume(0.5f)
'@
Set-Content -Path $lockOffFile -Value $lockOffContent -Encoding UTF8


# Create CheckAndPlayLive.ps1
$playLiveContent = @'
$url = "https://www.youtube.com/@ichikagoyou/live"
$maxRetries = 15
$retryIntervalSec = 60

# Find Default Browser
$browserPath = ""
$progId = (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice" -Name "ProgId" -ErrorAction SilentlyContinue).ProgId
if ($progId) {
    $browserCmd = (Get-ItemProperty -Path "HKCR:\$progId\shell\open\command" -ErrorAction SilentlyContinue).'(default)'
    if ($browserCmd) {
        $browserPath = $browserCmd -split '"' | Where-Object { $_ -match '\.exe$' } | Select-Object -First 1
        if (-not $browserPath) {
            $browserPath = ($browserCmd -split ' ')[0]
        }
    }
}
if (-not $browserPath -or !(Test-Path $browserPath)) {
    $browserPath = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
}

# Check Live status loop
for ($i = 0; $i -lt $maxRetries; $i++) {
    try {
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -UserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -TimeoutSec 15 -ErrorAction Stop
        $html = $response.Content
        if ($html -match '"isLive":true' -or $html -match 'isLiveBroadcast" ?: ?true' -or $html -match 'hqdefault_live.jpg') {
            # It's live!
            Start-Process -FilePath $browserPath -ArgumentList "--autoplay-policy=no-user-gesture-required", $url
            Return
        }
    } catch {
        # Network error or timeout, will retry
    }

    # Not live or error, wait for next minute
    Start-Sleep -Seconds $retryIntervalSec
}

# If it reaches here, 15 minutes passed and still not live. Stops silently.
'@
Set-Content -Path $playLiveFile -Value $playLiveContent -Encoding UTF8


# Create Lock_ON.ps1
$lockOnContent = @'
powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_NONE CONSOLELOCK 1
powercfg /SETDCVALUEINDEX SCHEME_CURRENT SUB_NONE CONSOLELOCK 1
powercfg /S SCHEME_CURRENT
'@
Set-Content -Path $lockOnFile -Value $lockOnContent -Encoding UTF8


# Define generic task actions
$psPath = "powershell.exe"
$actionLockOff = New-ScheduledTaskAction -Execute $psPath -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$lockOffFile`""
$actionPlay = New-ScheduledTaskAction -Execute $psPath -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$playLiveFile`""
$actionLockOn = New-ScheduledTaskAction -Execute $psPath -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$lockOnFile`""

# Define Triggers
$triggerLockOff = New-ScheduledTaskTrigger -Daily -At 4:55am
$triggerPlay = New-ScheduledTaskTrigger -Daily -At 5:00am
$triggerLockOn = New-ScheduledTaskTrigger -Daily -At 5:20am

# Define Settings (Play needs WakeToRun)
$settingsDefault = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 2)
$settingsWake = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 2) -WakeToRun

# Register Tasks
Register-ScheduledTask -TaskName "LiveAlarm_LockOff" -Action $actionLockOff -Trigger $triggerLockOff -Settings $settingsWake -User "SYSTEM" -RunLevel Highest -Force | Out-Null
Register-ScheduledTask -TaskName "LiveAlarm_Play" -Action $actionPlay -Trigger $triggerPlay -Settings $settingsWake -User $env:USERNAME -RunLevel Highest -Force | Out-Null
Register-ScheduledTask -TaskName "LiveAlarm_LockOn" -Action $actionLockOn -Trigger $triggerLockOn -Settings $settingsDefault -User "SYSTEM" -RunLevel Highest -Force | Out-Null

Write-Host "設定が完了しました！" -ForegroundColor Green
Write-Host "以下のタスクが登録されました:"
Write-Host " - 4:55 : 音量を50%に変更し、スリープ復帰時のパスワードを解除します。"
Write-Host " - 5:00 : YouTubeをチェックし、ライブが始まっていれば既定のブラウザで開きます（最大15分間待機）。"
Write-Host " - 5:20 : スリープ復帰時のパスワードを再度有効化します。"
Write-Host "※ 作成されたスクリプトは $targetFolder に保存されています。"
