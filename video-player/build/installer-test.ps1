# 설치 파일을 실제로 설치해 보고 파일 연결과 제거까지 확인한다 (GitHub Actions Windows 러너용).
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$setup = Get-ChildItem "$root\dist\VideoPlayer-Setup-*.exe" | Select-Object -First 1
$dir = "$env:LOCALAPPDATA\Programs\SmartVideoPlayer"
$exe = "$dir\SmartVideoPlayer.exe"
$failed = $false
function Check($ok, $what) {
  if ($ok) { Write-Host "OK   $what" } else { Write-Host "FAIL $what"; $script:failed = $true }
}
function RegValue($key, $name) {
  try { (Get-ItemProperty -Path "Registry::HKEY_CURRENT_USER\$key" -ErrorAction Stop).$name } catch { $null }
}

Write-Host "== 설치: $($setup.Name)"
$p = Start-Process -FilePath $setup.FullName -ArgumentList '/S' -Wait -PassThru
Check ($p.ExitCode -eq 0) "설치 프로그램 종료 코드 0"
Check (Test-Path $exe) "실행 파일 설치됨"
Check (Test-Path "$dir\portable_config\scripts\uosc\main.lua") "화면 조작부 설치됨"
Check (Test-Path "$dir\Uninstall.exe") "제거 프로그램 설치됨"
Check (Test-Path "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\동영상 플레이어.lnk") "시작 메뉴 바로가기"
$cmd = RegValue 'Software\Classes\SmartRobotics.VideoPlayer\shell\open\command' '(default)'
Check ($cmd -eq "`"$exe`" `"%1`"") "여는 명령 등록: $cmd"
foreach ($ext in 'mp4', 'mkv', 'avi', 'wmv', 'ts') {
  Check ((RegValue "Software\Classes\.$ext" '(default)') -eq 'SmartRobotics.VideoPlayer') ".$ext 파일 연결"
}
Check ((RegValue 'Software\Microsoft\Windows\CurrentVersion\Uninstall\SmartVideoPlayer' 'DisplayName') -eq '동영상 플레이어') "프로그램 추가/제거 등록"

Write-Host "== 설치된 플레이어로 재생"
$clip = "$root\dist\smoke\hevc_ac3.mkv"
$p = Start-Process -FilePath $exe -Wait -PassThru -ArgumentList @("`"$clip`"", '--vo=null', '--ao=null',
  '--force-window=no', '--idle=no', '--keep-open=no', '--save-position-on-quit=no', '--hwdec=no')
Check ($p.ExitCode -eq 0) "HEVC+AC3 영상 재생 후 정상 종료"

Write-Host "== 제거"
$p = Start-Process -FilePath "$dir\Uninstall.exe" -ArgumentList '/S', "_?=$dir" -Wait -PassThru
Check ($p.ExitCode -eq 0) "제거 프로그램 종료 코드 0"
Check (-not (Test-Path $exe)) "실행 파일 삭제됨"
Check ($null -eq (RegValue 'Software\Classes\SmartRobotics.VideoPlayer\shell\open\command' '(default)')) "여는 명령 삭제됨"
Check ((RegValue 'Software\Classes\.mkv' '(default)') -ne 'SmartRobotics.VideoPlayer') ".mkv 파일 연결 해제됨"

if ($failed) { exit 1 }
