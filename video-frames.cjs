'use strict';

const { spawn } = require('node:child_process');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { pathToFileURL } = require('node:url');

async function getBrowser() {
  const roots = [process.env.ProgramFiles, process.env['ProgramFiles(x86)'], process.env.LOCALAPPDATA].filter(Boolean);
  for (const suffix of ['Google/Chrome/Application/chrome.exe', 'Microsoft/Edge/Application/msedge.exe']) {
    for (const root of roots) {
      const candidate = path.join(root, suffix);
      try {
        await fs.access(candidate);
        return candidate;
      } catch (error) {
        if (error.code !== 'ENOENT') throw error;
      }
    }
  }
  throw new Error('Chrome or Edge is required.');
}

const douyinHosts = new Set(['douyin.com', 'www.douyin.com', 'v.douyin.com', 'm.douyin.com', 'jingxuan.douyin.com', 'www.iesdouyin.com', 'open.douyin.com']);

async function getDouyinPlayer(source) {
  let url = new URL(source);
  const signal = AbortSignal.timeout(8000);
  for (let hop = 0; hop < 6; hop++) {
    if (url.protocol !== 'https:' || url.port || url.username || url.password || !douyinHosts.has(url.hostname)) break;
    const candidate = url.pathname.match(/\/(?:video|share\/video)\/(\d+)(?:\/|$)/)?.[1] ||
      url.searchParams.get('modal_id') || (url.pathname === '/player/video' ? url.searchParams.get('vid') : '');
    if (/^\d{10,25}$/.test(candidate || '')) {
      return new URL('https://open.douyin.com/player/video?autoplay=1&vid=' + candidate).href;
    }
    const response = await fetch(url, { redirect: 'manual', signal });
    const location = response.headers.get('location');
    await response.body?.cancel();
    if (response.status < 300 || response.status >= 400 || !location) break;
    url = new URL(location, url);
  }
  throw new Error('Could not resolve a public Douyin video ID.');
}

async function extract(source, remote) {
  const browserPath = await getBrowser();
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'prompt-sprite-'));
  const html = path.join(directory, 'frame.html');
  let browser;
  let timeout;
  try {
    let url = source;
    if (!remote) {
      const videoUrl = pathToFileURL(path.resolve(source)).href.replaceAll('&', '&amp;').replaceAll('"', '&quot;');
      await fs.writeFile(html, '<!doctype html><video muted preload="auto" src="' + videoUrl + '"></video>');
      url = pathToFileURL(html).href;
    }
    browser = spawn(browserPath, [
      '--headless=new', '--disable-extensions', '--no-first-run', '--disable-background-networking',
      ...(remote ? ['--window-size=1100,1050'] : ['--allow-file-access-from-files']),
      '--user-data-dir=' + path.join(directory, 'profile'),
      '--remote-debugging-pipe', 'about:blank'
    ], { windowsHide: true, stdio: ['ignore', 'ignore', 'ignore', 'pipe', 'pipe'] });
    const pending = new Map();
    let nextId = 0;
    let buffer = '';
    browser.stdio[4].setEncoding('utf8');
    browser.stdio[4].on('data', chunk => {
      buffer += chunk;
      let end;
      while ((end = buffer.indexOf('\0')) >= 0) {
        const message = JSON.parse(buffer.slice(0, end));
        buffer = buffer.slice(end + 1);
        if (!pending.has(message.id)) continue;
        const { resolve, reject } = pending.get(message.id);
        pending.delete(message.id);
        if (message.error) reject(new Error(message.error.message));
        else resolve(message.result);
      }
    });
    const send = (method, params = {}, sessionId) => new Promise((resolve, reject) => {
      const id = ++nextId;
      pending.set(id, { resolve, reject });
      browser.stdio[3].write(JSON.stringify({ id, method, params, sessionId }) + '\0');
    });
    const fail = new Promise((_, reject) => {
      timeout = setTimeout(() => reject(new Error('Video decoding timed out.')), 35000);
      browser.once('error', reject);
      browser.once('exit', () => reject(new Error('Browser closed while reading the video.')));
      browser.stdio[3].once('error', reject);
    });
    const capture = async () => {
      const { targetId } = await send('Target.createTarget', { url: 'about:blank' });
      const { sessionId } = await send('Target.attachToTarget', { targetId, flatten: true });
      const navigation = await send('Page.navigate', { url }, sessionId);
      if (navigation.errorText) throw new Error(navigation.errorText);
      if (remote) {
        const evaluate = async (expression) => {
          const response = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true }, sessionId);
          if (response.exceptionDetails) throw new Error('The public video player could not render a frame.');
          return response.result?.value;
        };
        let duration;
        for (let attempt = 0; attempt < 35; attempt++) {
          duration = await evaluate(`(() => {
            const v = document.querySelector('video');
            if (!v || v.mediaKeys) return 0;
            v.muted = true;
            if (v.readyState < 2) { if (v.paused) void v.play().catch(() => {}); return 0; }
            if (!v.videoWidth || !Number.isFinite(v.duration)) return 0;
            v.pause();
            return v.duration;
          })()`).catch(() => 0);
          if (duration > 0) break;
          await new Promise(resolve => setTimeout(resolve, 280));
        }
        if (!(duration > 0)) throw new Error('The public video player did not load playable media.');
        const frames = [];
        for (const fraction of [.08, .24, .43, .62, .79, .92]) {
          const time = duration * fraction;
          const frame = await evaluate(`(async () => {
            const v = document.querySelector('video');
            const time = ${JSON.stringify(time)};
            if (!v || v.mediaKeys || !v.videoWidth) return;
            if (Math.abs(v.currentTime - time) > .04) {
              const seeked = new Promise(resolve => {
                const timeout = setTimeout(() => resolve(false), 2200);
                v.addEventListener('seeked', () => { clearTimeout(timeout); resolve(true); }, {once:true});
              });
              v.currentTime = time;
              if (!await seeked) return;
            }
            if (v.readyState < 2 || Math.abs(v.currentTime - time) > .65) return;
            try {
              const ratio = Math.min(1, 1100 / Math.max(v.videoWidth,v.videoHeight));
              const canvas = document.createElement('canvas');
              canvas.width = Math.max(1, Math.round(v.videoWidth * ratio));
              canvas.height = Math.max(1, Math.round(v.videoHeight * ratio));
              canvas.getContext('2d', {alpha:false}).drawImage(v,0,0,canvas.width,canvas.height);
              return { url: canvas.toDataURL('image/jpeg', .83) };
            } catch (error) {
              if (error.name !== 'SecurityError') throw error;
              const rect = v.getBoundingClientRect();
              const scale = Math.min(rect.width/v.videoWidth, rect.height/v.videoHeight);
              const w = Math.min(rect.width,v.videoWidth*scale), h = Math.min(rect.height,v.videoHeight*scale);
              const x = Math.max(0,rect.left+(rect.width-w)/2), y = Math.max(0,rect.top+(rect.height-h)/2);
              const width = Math.min(w,innerWidth-x), height = Math.min(h,innerHeight-y);
              if (width < 80 || height < 80) return;
              const element = document.elementFromPoint(x+width/2,y+height/2);
              if (element !== v) return;
              return { clip: {x,y,width,height,scale:1} };
            }
          })()`);
          let frameUrl = frame?.url;
          if (frame?.clip) {
            const shot = await send('Page.captureScreenshot', {format:'jpeg', quality:80, captureBeyondViewport:false, clip:frame.clip}, sessionId);
            if (shot.data) frameUrl = 'data:image/jpeg;base64,' + shot.data;
          }
          if (frameUrl?.startsWith('data:image/jpeg;base64,')) frames.push({Time:Math.round(time*10)/10, Url:frameUrl});
        }
        if (frames.length < 2) throw new Error('The public video player yielded too few frames.');
        return frames;
      }
      for (let attempt = 0; attempt < 50; attempt++) {
        const ready = await send('Runtime.evaluate', { expression: "Boolean(document.querySelector('video'))", returnByValue: true }, sessionId).catch(() => null);
        if (ready?.result?.value) break;
        await new Promise(resolve => setTimeout(resolve, 100));
      }
      const result = await send('Runtime.evaluate', {
        expression: `(async () => {
          if (document.readyState === 'loading') await new Promise(resolve => document.addEventListener('DOMContentLoaded', resolve, {once:true}));
          const video = document.querySelector('video');
          if (!video || video.error) throw new Error('The video cannot be decoded.');
          if (video.readyState < 2) await new Promise((resolve, reject) => {
            video.addEventListener('loadeddata', resolve, {once:true});
            video.addEventListener('error', reject, {once:true});
          });
          if (!video.videoWidth || !Number.isFinite(video.duration) || video.duration <= 0) throw new Error('No usable video frames.');
          const canvas = document.createElement('canvas');
          const ratio = Math.min(1, 1100 / Math.max(video.videoWidth, video.videoHeight));
          canvas.width = Math.max(1, Math.round(video.videoWidth * ratio));
          canvas.height = Math.max(1, Math.round(video.videoHeight * ratio));
          const ctx = canvas.getContext('2d', {alpha:false});
          const frames = [];
          for (const fraction of [.08, .24, .43, .62, .79, .92]) {
            const time = video.duration * fraction;
            const seek = new Promise(resolve => video.addEventListener('seeked', resolve, {once:true}));
            video.currentTime = time;
            await seek;
            ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
            frames.push({Time: Math.round(time * 10) / 10, Url: canvas.toDataURL('image/jpeg', .83)});
          }
          return frames;
        })()`,
        awaitPromise: true,
        returnByValue: true
      }, sessionId);
      if (result.exceptionDetails || !result.result?.value?.length) throw new Error('Could not decode the video.');
      return result.result.value;
    };
    return await Promise.race([capture(), fail]);
  } finally {
    clearTimeout(timeout);
    if (browser && browser.exitCode === null && browser.pid) {
      const exited = new Promise(resolve => browser.once('exit', resolve));
      browser.kill();
      let fallback;
      await Promise.race([exited, new Promise(resolve => { fallback = setTimeout(resolve, 1600); })]);
      clearTimeout(fallback);
    }
    await fs.rm(directory, { recursive: true, force: true, maxRetries: 3, retryDelay: 250 }).catch(() => {});
  }
}

if (require.main === module) {
  const [input, link] = process.argv.slice(2);
  const operation = input === '--douyin' && link
    ? getDouyinPlayer(link).then(url => extract(url, true))
    : input ? extract(input, false) : Promise.reject(new Error('Expected a local video path or a Douyin link.'));
  operation.then(frames => process.stdout.write(JSON.stringify(frames))).catch(error => {
    console.error(error.message);
    process.exitCode = 1;
  });
}

module.exports = { extract, getDouyinPlayer };
