#!/usr/bin/env bash
# 설치할 폴더(dist/app)가 실제 Windows에서 동작하는지 확인한다.
#  1) 설정 파일과 uosc 스크립트가 오류 없이 읽히는지
#  2) 여러 코덱의 시험 영상을 만들어 끝까지 재생되는지
set -uo pipefail
cd "$(dirname "$0")/.."

MPV=dist/mpv/mpv.com          # 콘솔 출력이 되는 실행 파일 (엔진은 dist/app 것과 같다)
# 멈춘 경우에도 시험이 끝나도록 실행마다 제한 시간을 둔다 (종료 코드 124 = 시간 초과).
run() { timeout -k 5 "$1" "$MPV" "${@:2}" < /dev/null; }
CONF=dist/app/portable_config
OUT=dist/smoke
mkdir -p "$OUT"
fail=0

# 화면과 소리 장치가 없는 러너에서도 돌도록 출력만 끈다. 디코딩은 실제로 수행된다.
# uosc의 autoload는 재생이 끝나도 창을 열어 두므로(keep-open) 시험에서는 끈다.
HEADLESS=(--vo=null --ao=null --force-window=no --idle=no --keep-open=no --save-position-on-quit=no --hwdec=no
  --script-opts=uosc-autoload=no)

echo "== 1. 설정과 스크립트 읽기"
run 60 --config-dir="$CONF" "${HEADLESS[@]}" --log-file="$OUT/config.log" --msg-level=all=warn \
  "av://lavfi:testsrc=duration=1:size=320x240:rate=30" > "$OUT/config.out" 2>&1
code=$?
cat "$OUT/config.out"
if [ $code -ne 0 ]; then echo "FAIL: 종료 코드 $code"; fail=1; echo "--- 로그 끝부분"; tail -40 "$OUT/config.log"; fi
if grep -Ei 'error|unknown option|could not|failed|invalid' "$OUT/config.out"; then
  echo "FAIL: 설정 또는 스크립트 경고/오류"; fail=1
fi
if ! grep -q 'uosc' "$OUT/config.log"; then echo "FAIL: uosc 스크립트가 로드되지 않음"; fail=1; fi

echo "== 2. 코덱별 재생"
SRC="av://lavfi:testsrc=duration=2:size=320x240:rate=30[out0];sine=frequency=440:duration=2[out1]"
# 이름 | 영상 인코더 | 음성 인코더
cases=(
  "hevc_ac3.mkv|libx265|ac3"
  "h264_aac.mp4|libx264|aac"
  "mpeg4_mp3.avi|mpeg4|libmp3lame"
  "wmv2_wma.wmv|wmv2|wmav2"
  "vp9_opus.webm|libvpx-vp9|libopus"
  "mpeg2_mp2.mpg|mpeg2video|mp2"
  "av1_flac.mkv|libsvtav1|flac"
)
for c in "${cases[@]}"; do
  IFS='|' read -r name vc ac <<< "$c"
  f="$OUT/$name"
  echo "-- $name"
  if ! run 90 --no-config "$SRC" --o="$f" --ovc="$vc" --oac="$ac" --msg-level=all=error > "$OUT/$name.enc" 2>&1 || [ ! -s "$f" ]; then
    echo "SKIP $name (시험 영상을 만들지 못함)"; sed 's/^/    /' "$OUT/$name.enc" | head -5
    continue
  fi
  run 60 --config-dir="$CONF" "${HEADLESS[@]}" --msg-level=all=warn "$f" > "$OUT/$name.play" 2>&1
  code=$?
  if [ $code -ne 0 ] || grep -Ei 'error|failed|could not' "$OUT/$name.play" > /dev/null; then
    echo "FAIL $name (종료 코드 $code)"; sed 's/^/    /' "$OUT/$name.play" | head -10; fail=1
  else
    echo "OK   $name"
  fi
done

echo "== 3. CP949 한글 자막"
printf '1\n00:00:00,000 --> 00:00:02,000\n\xc7\xd1\xb1\xdb \xc0\xda\xb8\xb7\n' > "$OUT/h264_aac.srt"
run 60 --config-dir="$CONF" "${HEADLESS[@]}" --msg-level=all=warn,cplayer=v "$OUT/h264_aac.mp4" > "$OUT/sub.play" 2>&1
code=$?
cat "$OUT/sub.play"
if [ $code -ne 0 ] || grep -Ei 'error|failed|invalid' "$OUT/sub.play" > /dev/null; then echo "FAIL 자막 (종료 코드 $code)"; fail=1
elif ! grep -q 'h264_aac.srt' "$OUT/sub.play"; then echo "FAIL 자막 파일이 로드되지 않음"; fail=1
else echo "OK   자막 파일 자동 로드"; fi

exit $fail
