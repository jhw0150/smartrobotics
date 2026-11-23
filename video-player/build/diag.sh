#!/usr/bin/env bash
# 임시 진단: 어떤 설정이 재생 종료를 막는지 좁힌다.
cd "$(dirname "$0")/.."
MPV=dist/mpv/mpv.com
CONF=dist/app/portable_config
mkdir -p dist/smoke
SRC="av://lavfi:testsrc=duration=1:size=320x240:rate=30"
H=(--vo=null --ao=null --force-window=no --idle=no --keep-open=no --save-position-on-quit=no --hwdec=no)
t() {
  local name=$1; shift
  timeout -k 3 15 "$MPV" "$@" --log-file="dist/smoke/diag-$name.log" --msg-level=all=warn "$SRC" < /dev/null > "dist/smoke/diag-$name.out" 2>&1
  echo "[$name] exit=$?"
  head -5 "dist/smoke/diag-$name.out" | sed 's/^/    out: /'
}
"$MPV" --version < /dev/null | head -3
t plain        --no-config --vo=null --ao=null
t plain-all    --no-config "${H[@]}"
t conf-noscr   --config-dir="$CONF" "${H[@]}" --load-scripts=no
t conf-noosd   --config-dir="$CONF" "${H[@]}" --load-scripts=no --title=x
t conf-full    --config-dir="$CONF" "${H[@]}"
t conf-noauto  --config-dir="$CONF" "${H[@]}" --script-opts=uosc-autoload=no
echo "--- conf-full 로그 (반복 줄 제외, 끝 60줄)"
grep -v 'video EOF' dist/smoke/diag-conf-full.log | tail -60 | cut -c1-200
echo "--- plain 로그 (반복 줄 제외, 끝 25줄)"
grep -v 'video EOF' dist/smoke/diag-plain.log | tail -25 | cut -c1-200
