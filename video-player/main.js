const { app, BrowserWindow, ipcMain, Menu } = require('electron');
const path = require('path');
const fs = require('fs');
const http = require('http');
const crypto = require('crypto');
const { spawn } = require('child_process');
const { pathToFileURL } = require('url');

const MEDIA = /\.(mp4|m4v|mkv|webm|mov|avi|wmv|asf|flv|f4v|ts|mts|m2ts|mpg|mpeg|vob|3gp|3g2|rm|rmvb|divx|ogv|ogm|mp3|m4a|aac|wav|flac|ogg|opus|wma|ac3|dts)$/i;
const SUB_EXTS = ['.srt', '.vtt', '.ko.srt', '.ko.vtt', '.kor.srt'];

// 내장 엔진(Chromium)이 직접 재생할 수 있는 조합. 그 밖의 형식은 FFmpeg로 실시간 변환한다.
const DIRECT_CONTAINERS = /\.(mp4|m4v|mov|mkv|webm|ogv|mp3|m4a|wav|flac|ogg|opus|aac)$/i;
// hevc는 그래픽카드가 지원할 때만 풀리므로 일단 시도하고, 안 되면 화면 쪽에서 다음 단계로 넘긴다.
const DIRECT_VIDEO = new Set(['h264', 'hevc', 'vp8', 'vp9', 'av1', 'theora']);
const DIRECT_AUDIO = new Set(['aac', 'mp3', 'opus', 'vorbis', 'flac']);
const TEXT_SUBS = new Set(['subrip', 'ass', 'ssa', 'webvtt', 'mov_text', 'text']);

const FFMPEG = app.isPackaged
  ? path.join(process.resourcesPath, 'ffmpeg', 'ffmpeg.exe')
  : (process.platform === 'win32' ? path.join(__dirname, 'vendor', 'ffmpeg', 'ffmpeg.exe') : 'ffmpeg');

let win = null;
let pending = [];
let server = null;
let port = 0;
const token = crypto.randomBytes(16).toString('hex');
/** @type {Map<number, {file:string, info:object}>} */
const registry = new Map();
let nextId = 1;

// 한국어 자막은 UTF-8이 아닌 CP949(EUC-KR)로 저장된 경우가 많다.
function decodeText(buf) {
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(buf);
  } catch {
    return new TextDecoder('euc-kr').decode(buf);
  }
}

function findSubtitle(file) {
  const base = file.slice(0, -path.extname(file).length);
  for (const ext of SUB_EXTS) {
    const p = base + ext;
    try {
      if (fs.statSync(p).isFile()) return { name: path.basename(p), text: decodeText(fs.readFileSync(p)) };
    } catch {}
  }
  return null;
}

// `ffmpeg -i`의 출력에서 길이와 스트림 코덱을 읽는다 (ffprobe를 따로 싣지 않기 위함).
function probe(file) {
  return new Promise(resolve => {
    const info = { ok: false, duration: 0, video: null, pixfmt: '', audio: null, textSub: false };
    let err = '';
    let p;
    try {
      p = spawn(FFMPEG, ['-hide_banner', '-i', file], { windowsHide: true });
    } catch { return resolve(info); }
    p.stderr.on('data', d => { if (err.length < 200000) err += d; });
    p.on('error', () => resolve(info));
    p.on('close', () => {
      const d = /Duration: (\d+):(\d+):(\d+(?:\.\d+)?)/.exec(err);
      if (d) info.duration = d[1] * 3600 + d[2] * 60 + Number(d[3]);
      for (const line of err.split('\n')) {
        const m = /Stream #\d+:\d+.*?: (Video|Audio|Subtitle): (\w+)(.*)/.exec(line);
        if (!m) continue;
        if (m[1] === 'Video' && !info.video && !/attached pic/.test(line)) {
          info.video = m[2];
          info.pixfmt = (/, (yuv\w+|gbr\w+|nv\w+|p0\w+)/.exec(m[3]) || [])[1] || '';
        } else if (m[1] === 'Audio' && !info.audio) info.audio = m[2];
        else if (m[1] === 'Subtitle' && TEXT_SUBS.has(m[2])) info.textSub = true;
      }
      info.ok = Boolean(info.video || info.audio);
      resolve(info);
    });
  });
}

// 영상을 다시 인코딩하지 않고 그대로 옮겨 담을 수 있는가 (음성만 변환).
const canCopyVideo = info =>
  (info.video === 'h264' && /^yuvj?420p$/.test(info.pixfmt)) || info.video === 'hevc';

// 재생 단계: 0 직접 재생, 1 영상 그대로 + 음성만 변환, 2 그래픽카드 인코딩, 3 CPU 인코딩.
// 화면 쪽에서 재생에 실패하면 한 단계씩 올린다.
function startLevel(file, info) {
  if (!info.ok) return 0; // FFmpeg도 못 읽으면 변환할 방법이 없으니 그대로 시도한다.
  const videoOk = !info.video || (DIRECT_VIDEO.has(info.video) &&
    (info.video !== 'h264' || /^yuvj?420p$/.test(info.pixfmt))); // 10비트 H.264 등은 제외
  const audioOk = !info.audio || DIRECT_AUDIO.has(info.audio) || /^pcm_/.test(info.audio);
  if (DIRECT_CONTAINERS.test(file) && videoOk && audioOk) return 0;
  return info.video && canCopyVideo(info) ? 1 : 2;
}

// 쓸 수 있는 그래픽카드 인코더를 한 번만 찾아 둔다 (NVIDIA, Intel, AMD 순).
const HW_ENCODERS = {
  h264_nvenc: ['-c:v', 'h264_nvenc', '-preset', 'p4', '-rc', 'vbr', '-cq', '23', '-b:v', '0', '-pix_fmt', 'yuv420p'],
  h264_qsv: ['-c:v', 'h264_qsv', '-preset', 'veryfast', '-global_quality', '23', '-pix_fmt', 'nv12'],
  h264_amf: ['-c:v', 'h264_amf', '-quality', 'speed', '-rc', 'cqp', '-qp_i', '22', '-qp_p', '24', '-pix_fmt', 'nv12'],
};
let hwEncoder; // Promise<string|null>
function detectHwEncoder() {
  if (hwEncoder) return hwEncoder;
  const tryOne = name => new Promise(resolve => {
    let p;
    try {
      p = spawn(FFMPEG, ['-hide_banner', '-loglevel', 'error', '-f', 'lavfi', '-i', 'color=s=640x360:r=30:d=0.2',
        ...HW_ENCODERS[name], '-f', 'null', '-'], { windowsHide: true, stdio: 'ignore' });
    } catch { return resolve(false); }
    const timer = setTimeout(() => p.kill(), 8000);
    p.on('error', () => { clearTimeout(timer); resolve(false); });
    p.on('close', code => { clearTimeout(timer); resolve(code === 0); });
  });
  hwEncoder = (async () => {
    for (const name of Object.keys(HW_ENCODERS)) if (await tryOne(name)) return name;
    return null;
  })();
  return hwEncoder;
}

async function describe(file) {
  const info = await probe(file);
  const id = nextId++;
  registry.set(id, { file, info });
  return {
    id,
    name: path.basename(file),
    url: pathToFileURL(file).href,
    streamBase: `http://127.0.0.1:${port}/stream/${token}/${id}`,
    level: startLevel(file, info),
    canStream: info.ok,
    canCopy: Boolean(info.video) && canCopyVideo(info),
    hasVideo: Boolean(info.video),
    duration: info.duration,
    hasTextSub: info.textSub,
    sub: findSubtitle(file),
  };
}

async function describeAll(paths) {
  const out = [];
  for (const p of paths) {
    if (typeof p !== 'string' || !MEDIA.test(p)) continue;
    try { if (fs.statSync(p).isFile()) out.push(await describe(p)); } catch {}
  }
  return out;
}

const mediaFromArgv = (argv, cwd) =>
  describeAll(argv.filter(a => !a.startsWith('-')).map(a => path.resolve(cwd, a)));

// 변환 스트림 서버: 탐색할 때마다 해당 위치(ss)부터 다시 변환해 조각난 MP4로 내보낸다.
function startServer() {
  return new Promise(resolve => {
    server = http.createServer(async (req, res) => {
      const u = new URL(req.url, 'http://127.0.0.1');
      const m = /^\/stream\/([0-9a-f]+)\/(\d+)$/.exec(u.pathname);
      const entry = m && m[1] === token ? registry.get(Number(m[2])) : null;
      if (!entry) { res.writeHead(404); res.end(); return; }
      const ss = Math.max(Number(u.searchParams.get('ss')) || 0, 0);
      const { file, info } = entry;
      const mode = u.searchParams.get('mode');
      const args = ['-hide_banner', '-loglevel', 'error'];
      if (mode !== 'copy') args.push('-hwaccel', 'auto'); // 풀기(디코딩)도 가능하면 그래픽카드로
      args.push('-ss', String(ss), '-i', file, '-map', '0:v:0?', '-map', '0:a:0?', '-sn', '-dn');
      const hw = mode === 'hw' ? await detectHwEncoder() : null;
      if (mode === 'copy' && canCopyVideo(info)) {
        args.push('-c:v', 'copy');
        if (info.video === 'hevc') args.push('-tag:v', 'hvc1');
      } else if (hw) {
        args.push(...HW_ENCODERS[hw], '-g', '60', '-vf', 'scale=trunc(iw/2)*2:trunc(ih/2)*2');
      } else {
        // CPU 인코딩은 끊기지 않도록 가장 가벼운 설정을 쓰고, 4K는 1080p로 줄인다.
        args.push('-c:v', 'libx264', '-preset', 'superfast', '-tune', 'zerolatency', '-crf', '23',
          '-pix_fmt', 'yuv420p', '-g', '60',
          '-vf', "scale='min(1920,trunc(iw/2)*2)':-2");
      }
      args.push('-c:a', 'aac', '-b:a', '192k', '-ac', '2',
        '-movflags', 'frag_keyframe+empty_moov+default_base_moof', '-f', 'mp4', 'pipe:1');
      const ff = spawn(FFMPEG, args, { windowsHide: true, stdio: ['ignore', 'pipe', 'ignore'] });
      res.writeHead(200, { 'Content-Type': 'video/mp4', 'Cache-Control': 'no-store', 'Access-Control-Allow-Origin': '*' });
      ff.stdout.pipe(res);
      ff.on('error', () => res.destroy());
      res.on('close', () => ff.kill());
    });
    server.listen(0, '127.0.0.1', () => { port = server.address().port; resolve(); });
  });
}

// 파일 안에 들어 있는 첫 번째 글자 자막을 WebVTT로 꺼낸다.
function embeddedSubtitle(id) {
  const entry = registry.get(id);
  if (!entry || !entry.info.textSub) return null;
  return new Promise(resolve => {
    const chunks = [];
    const ff = spawn(FFMPEG, ['-hide_banner', '-loglevel', 'error', '-i', entry.file,
      '-map', '0:s:0', '-f', 'webvtt', 'pipe:1'], { windowsHide: true, stdio: ['ignore', 'pipe', 'ignore'] });
    ff.stdout.on('data', d => chunks.push(d));
    ff.on('error', () => resolve(null));
    ff.on('close', code => {
      const text = Buffer.concat(chunks).toString('utf8');
      resolve(code === 0 && text.includes('-->') ? { name: '내장 자막', text } : null);
    });
  });
}

function createWindow() {
  win = new BrowserWindow({
    width: 1280,
    height: 760,
    minWidth: 480,
    minHeight: 320,
    backgroundColor: '#0f1114',
    autoHideMenuBar: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });
  win.loadFile(path.join(__dirname, 'index.html'));
  win.on('closed', () => { win = null; });
}

if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  const initialArgv = process.argv.slice(app.isPackaged ? 1 : 2);
  const initialCwd = process.cwd();

  // 플레이어가 이미 떠 있을 때 다른 파일을 더블클릭하면 기존 창에서 연다.
  app.on('second-instance', async (_e, argv, cwd) => {
    if (!win) return;
    if (win.isMinimized()) win.restore();
    win.focus();
    const files = await mediaFromArgv(argv.slice(1), cwd);
    if (files.length && win) win.webContents.send('open-files', files);
  });

  ipcMain.handle('initial-files', () => {
    const files = pending;
    pending = [];
    return files;
  });
  ipcMain.handle('describe', (_e, paths) => describeAll(Array.isArray(paths) ? paths : []));
  ipcMain.handle('hw-encoder', () => detectHwEncoder());
  ipcMain.handle('embedded-sub', (_e, id) => embeddedSubtitle(Number(id)));

  app.whenReady().then(async () => {
    Menu.setApplicationMenu(null);
    await startServer();
    detectHwEncoder();
    pending = await mediaFromArgv(initialArgv, initialCwd);
    createWindow();
  });

  app.on('window-all-closed', () => app.quit());
}
