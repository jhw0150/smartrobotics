#!/usr/bin/env bash
# 재생 엔진(mpv)과 화면 조작부(uosc)를 내려받아 dist/app 에 설치할 폴더를 만든다.
# 필요한 도구: gh(GH_TOKEN 설정), 7z. GitHub Actions의 Windows 러너에서 실행한다.
set -euo pipefail
cd "$(dirname "$0")/.."

MPV_REPO=shinchiro/mpv-winbuild-cmake
UOSC_REPO=tomasklaen/uosc

rm -rf dist
mkdir -p dist/dl dist/app

# 일반 x86-64용 mpv 빌드를 고른다 (v3 빌드는 구형 CPU에서 실행되지 않는다).
assets=$(gh release view --repo "$MPV_REPO" --json assets --jq '.assets[].name')
mpv_asset=$(echo "$assets" | grep -E '^mpv-x86_64-[0-9]{8}-git-[0-9a-f]+\.7z$' | head -1)
if [ -z "$mpv_asset" ]; then
  echo "mpv 빌드를 찾지 못했습니다. 릴리스 파일 목록:" >&2
  echo "$assets" >&2
  exit 1
fi
echo "mpv: $mpv_asset"
gh release download --repo "$MPV_REPO" --pattern "$mpv_asset" --dir dist/dl
gh release download --repo "$UOSC_REPO" --pattern 'uosc.zip' --dir dist/dl

7z x -y -bso0 -odist/mpv "dist/dl/$mpv_asset"
cp dist/mpv/mpv.exe dist/app/SmartVideoPlayer.exe
# 일부 그래픽 드라이버에서 필요한 셰이더 컴파일러
if [ -f dist/mpv/d3dcompiler_43.dll ]; then cp dist/mpv/d3dcompiler_43.dll dist/app/; fi

cp -r config/portable_config dist/app/
7z x -y -bso0 -odist/app/portable_config dist/dl/uosc.zip
test -f dist/app/portable_config/scripts/uosc/main.lua

echo "$mpv_asset" > dist/app/portable_config/engine-version.txt
ls -la dist/app dist/app/portable_config
