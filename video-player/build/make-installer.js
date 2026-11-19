// dist/win-unpacked 폴더를 NSIS 설치 파일 하나로 묶는다.
// makensis는 PATH에서 찾고, 없으면 electron-builder가 내려받아 둔 것을 쓴다.
const { spawnSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const root = path.join(__dirname, '..');
const { version } = require(path.join(root, 'package.json'));
const appDir = path.join(root, 'dist', 'win-unpacked');
const outFile = path.join(root, 'dist', `VideoPlayer-Setup-${version}.exe`);

if (!fs.existsSync(path.join(appDir, 'SmartVideoPlayer.exe'))) {
  console.error('dist/win-unpacked 가 없습니다. 먼저 "npm run pack"을 실행하세요.');
  process.exit(1);
}

function findCached() {
  const base = path.join(process.env.ELECTRON_BUILDER_CACHE || path.join(os.homedir(), '.cache', 'electron-builder'), 'nsis-3.0.4.1');
  if (!fs.existsSync(base)) return null;
  for (const dir of fs.readdirSync(base)) {
    const nsisDir = path.join(base, dir);
    const bin = process.platform === 'win32'
      ? path.join(nsisDir, 'Bin', 'makensis.exe')
      : path.join(nsisDir, process.platform === 'darwin' ? 'mac' : 'linux', 'makensis');
    if (fs.existsSync(bin)) return { bin, nsisDir };
  }
  return null;
}

const cached = findCached();
const bin = cached ? cached.bin : 'makensis';
const env = { ...process.env };
if (cached) env.NSISDIR = cached.nsisDir;

const D = process.platform === 'win32' ? '/D' : '-D';
const flag = f => (process.platform === 'win32' ? '/' : '-') + f;
const r = spawnSync(bin, [
  flag('V2'), flag('INPUTCHARSET'), 'UTF8',
  `${D}APP_DIR=${appDir}`, `${D}OUT_FILE=${outFile}`, `${D}APP_VERSION=${version}`,
  path.join(__dirname, 'installer.nsi'),
], { stdio: 'inherit', env });

if (r.error || r.status !== 0) {
  console.error(r.error ? `makensis 실행 실패: ${r.error.message}` : `makensis 종료 코드 ${r.status}`);
  process.exit(1);
}
console.log(`설치 파일: ${outFile} (${(fs.statSync(outFile).size / 1048576).toFixed(1)} MB)`);
