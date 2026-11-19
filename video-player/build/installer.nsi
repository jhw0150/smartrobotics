; 동영상 플레이어 설치 프로그램 (사용자 계정 단위 설치, 관리자 권한 불필요)
Unicode true
SetCompressor /SOLID lzma
RequestExecutionLevel user

!include "MUI2.nsh"
!include "FileFunc.nsh"

!define APP_NAME "동영상 플레이어"
!define APP_ID "SmartVideoPlayer"
!define APP_EXE "SmartVideoPlayer.exe"
!define PROGID "SmartRobotics.VideoPlayer"
!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}"
!define CAP_KEY "Software\${APP_ID}\Capabilities"

Name "${APP_NAME}"
OutFile "${OUT_FILE}"
InstallDir "$LOCALAPPDATA\Programs\${APP_ID}"
InstallDirRegKey HKCU "Software\${APP_ID}" "InstallDir"

!define MUI_FINISHPAGE_RUN "$INSTDIR\${APP_EXE}"
!define MUI_FINISHPAGE_RUN_TEXT "${APP_NAME} 실행"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "Korean"

; 확장자 하나를 이 플레이어에 연결한다. 기존 연결은 지울 때 되돌릴 수 있게 따로 적어 둔다.
!macro Assoc EXT
  ReadRegStr $0 HKCU "Software\Classes\.${EXT}" ""
  StrCmp $0 "${PROGID}" +2
    WriteRegStr HKCU "Software\Classes\.${EXT}" "${APP_ID}_backup" "$0"
  WriteRegStr HKCU "Software\Classes\.${EXT}" "" "${PROGID}"
  WriteRegStr HKCU "Software\Classes\.${EXT}\OpenWithProgids" "${PROGID}" ""
  WriteRegStr HKCU "${CAP_KEY}\FileAssociations" ".${EXT}" "${PROGID}"
  WriteRegStr HKCU "Software\Classes\Applications\${APP_EXE}\SupportedTypes" ".${EXT}" ""
!macroend

!macro UnAssoc EXT
  ReadRegStr $0 HKCU "Software\Classes\.${EXT}" ""
  StrCmp $0 "${PROGID}" 0 +4
    ReadRegStr $1 HKCU "Software\Classes\.${EXT}" "${APP_ID}_backup"
    WriteRegStr HKCU "Software\Classes\.${EXT}" "" "$1"
    Goto +1
  DeleteRegValue HKCU "Software\Classes\.${EXT}" "${APP_ID}_backup"
  DeleteRegValue HKCU "Software\Classes\.${EXT}\OpenWithProgids" "${PROGID}"
!macroend

!macro ForEachExt MACRO
  !insertmacro ${MACRO} "mp4"
  !insertmacro ${MACRO} "m4v"
  !insertmacro ${MACRO} "mkv"
  !insertmacro ${MACRO} "webm"
  !insertmacro ${MACRO} "mov"
  !insertmacro ${MACRO} "avi"
  !insertmacro ${MACRO} "wmv"
  !insertmacro ${MACRO} "asf"
  !insertmacro ${MACRO} "flv"
  !insertmacro ${MACRO} "f4v"
  !insertmacro ${MACRO} "ts"
  !insertmacro ${MACRO} "mts"
  !insertmacro ${MACRO} "m2ts"
  !insertmacro ${MACRO} "mpg"
  !insertmacro ${MACRO} "mpeg"
  !insertmacro ${MACRO} "vob"
  !insertmacro ${MACRO} "3gp"
  !insertmacro ${MACRO} "3g2"
  !insertmacro ${MACRO} "rm"
  !insertmacro ${MACRO} "rmvb"
  !insertmacro ${MACRO} "divx"
  !insertmacro ${MACRO} "ogv"
  !insertmacro ${MACRO} "ogm"
!macroend

Section "Install"
  SetOutPath "$INSTDIR"
  File /r "${APP_DIR}/*.*"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  WriteRegStr HKCU "Software\${APP_ID}" "InstallDir" "$INSTDIR"

  CreateShortcut "$SMPROGRAMS\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}"
  CreateShortcut "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}"

  ; 파일 형식(ProgID)과 여는 명령
  WriteRegStr HKCU "Software\Classes\${PROGID}" "" "동영상 파일"
  WriteRegStr HKCU "Software\Classes\${PROGID}\DefaultIcon" "" "$INSTDIR\${APP_EXE},0"
  WriteRegStr HKCU "Software\Classes\${PROGID}\shell\open\command" "" '"$INSTDIR\${APP_EXE}" "%1"'
  WriteRegStr HKCU "Software\Classes\Applications\${APP_EXE}" "FriendlyAppName" "${APP_NAME}"
  WriteRegStr HKCU "Software\Classes\Applications\${APP_EXE}\shell\open\command" "" '"$INSTDIR\${APP_EXE}" "%1"'

  ; Windows 설정의 "기본 앱" 목록에 나타나게 한다.
  WriteRegStr HKCU "${CAP_KEY}" "ApplicationName" "${APP_NAME}"
  WriteRegStr HKCU "${CAP_KEY}" "ApplicationDescription" "모든 형식을 재생하는 동영상 플레이어"
  WriteRegStr HKCU "Software\RegisteredApplications" "${APP_ID}" "${CAP_KEY}"

  !insertmacro ForEachExt Assoc

  ; 프로그램 추가/제거 항목
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayName" "${APP_NAME}"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKCU "${UNINST_KEY}" "Publisher" "smartrobotics"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayIcon" "$INSTDIR\${APP_EXE},0"
  WriteRegStr HKCU "${UNINST_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINST_KEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoRepair" 1
  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  IntFmt $0 "0x%08X" $0
  WriteRegDWORD HKCU "${UNINST_KEY}" "EstimatedSize" "$0"

  ; 탐색기에 연결이 바뀌었음을 알린다 (SHCNE_ASSOCCHANGED).
  System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'
SectionEnd

Section "Uninstall"
  !insertmacro ForEachExt UnAssoc
  DeleteRegKey HKCU "Software\Classes\${PROGID}"
  DeleteRegKey HKCU "Software\Classes\Applications\${APP_EXE}"
  DeleteRegValue HKCU "Software\RegisteredApplications" "${APP_ID}"
  DeleteRegKey HKCU "Software\${APP_ID}"
  DeleteRegKey HKCU "${UNINST_KEY}"

  Delete "$SMPROGRAMS\${APP_NAME}.lnk"
  Delete "$DESKTOP\${APP_NAME}.lnk"
  RMDir /r "$INSTDIR"

  System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'
SectionEnd
