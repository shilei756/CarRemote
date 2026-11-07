'use strict';
// 长安控车 · 独立网站后台（零依赖，只用 Node 内置模块）
//
// 启动：  node server.js            或  ./start.sh
// 配置：  PORT=8787 ADMIN_PASSWORD=你的密码 UPSTREAM=https://后端域名 node server.js
//
// 能力：
//   1. 仅站主可登录（ADMIN_PASSWORD），登录后拿到内存 token；
//   2. 发布系统公告 -> App 启动 / 下拉「系统公告」时读取 GET /api/notice；
//   3. 通用反向代理 /api/upstream -> 网页版 /admin/* 权限接口，服务端转发绕过浏览器 CORS，
//      因此「网页后台限制某人」与「App 内白名单管理」操作的是同一套数据，双向联动；
//   4. 公告数据落本地 data/announcements.json，重启不丢。

const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const PORT = Number(process.env.PORT || 8787);
const PASSWORD = process.env.ADMIN_PASSWORD || 'admin888';
const UPSTREAM = (process.env.UPSTREAM || 'https://a9db267525c1cf6b2.app.workbuddy.host')
  .replace(/\/+$/, '');
const DATA_DIR = path.join(__dirname, 'data');
const NOTICE_FILE = path.join(DATA_DIR, 'announcements.json');
const PUBLIC_DIR = path.join(__dirname, 'public');

const tokens = new Set();

function readNotices() {
  try {
    const list = JSON.parse(fs.readFileSync(NOTICE_FILE, 'utf8'));
    return Array.isArray(list) ? list : [];
  } catch (e) {
    return [];
  }
}

function writeNotices(list) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
  fs.writeFileSync(NOTICE_FILE, JSON.stringify(list, null, 2), 'utf8');
}

function send(res, code, obj) {
  const body = JSON.stringify(obj === undefined ? {} : obj);
  res.writeHead(code, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
    'Cache-Control': 'no-store',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type, X-Admin-Token',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS'
  });
  res.end(body);
}

function sendHtml(res, html) {
  res.writeHead(200, {
    'Content-Type': 'text/html; charset=utf-8',
    'Cache-Control': 'no-store'
  });
  res.end(html);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let buf = '';
    req.on('data', (c) => {
      buf += c;
      if (buf.length > 1024 * 1024) req.destroy();
    });
    req.on('end', () => {
      try { resolve(buf ? JSON.parse(buf) : {}); } catch (e) { reject(e); }
    });
    req.on('error', reject);
  });
}

function isAuthed(req) {
  return tokens.has(String(req.headers['x-admin-token'] || ''));
}

/** 服务端转发到网页版后端，浏览器不受 CORS 限制 */
function upstreamPost(targetPath, payload) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify(payload || {});
    let u;
    try { u = new URL(UPSTREAM + targetPath); } catch (e) { reject(e); return; }
    const mod = u.protocol === 'https:' ? https : http;
    const r = mod.request({
      hostname: u.hostname,
      port: u.port || (u.protocol === 'https:' ? 443 : 80),
      path: u.pathname + u.search,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body)
      },
      timeout: 15000
    }, (resp) => {
      let data = '';
      resp.on('data', (c) => { data += c; });
      resp.on('end', () => {
        try { resolve({ status: resp.statusCode, data: JSON.parse(data) }); }
        catch (e) { resolve({ status: resp.statusCode, data: { raw: data.slice(0, 800) } }); }
      });
    });
    r.on('timeout', () => r.destroy(new Error('上游请求超时')));
    r.on('error', reject);
    r.write(body);
    r.end();
  });
}

const server = http.createServer(async (req, res) => {
  try {
    const u = new URL(req.url, 'http://localhost');
    const p = u.pathname;

    if (req.method === 'OPTIONS') { send(res, 204, {}); return; }

    if (p === '/' || p === '/index.html') {
      const html = fs.readFileSync(path.join(PUBLIC_DIR, 'index.html'), 'utf8');
      sendHtml(res, html);
      return;
    }

    if (p === '/api/login' && req.method === 'POST') {
      const b = await readBody(req);
      if (String(b.password || '') !== PASSWORD) {
        send(res, 401, { ok: false, message: '后台密码错误' });
        return;
      }
      const token = crypto.randomBytes(24).toString('hex');
      tokens.add(token);
      send(res, 200, { ok: true, token });
      return;
    }

    if (p === '/api/logout' && req.method === 'POST') {
      tokens.delete(String(req.headers['x-admin-token'] || ''));
      send(res, 200, { ok: true });
      return;
    }

    if (p === '/api/me') {
      send(res, 200, { ok: isAuthed(req), upstream: UPSTREAM });
      return;
    }

    // App 公开读取最新公告；无公告时返回空对象，App 端静默跳过
    if (p === '/api/notice' && req.method === 'GET') {
      const list = readNotices();
      const latest = list.length ? list[list.length - 1] : null;
      send(res, 200, latest || { id: '', title: '', body: '', date: '', level: 'info' });
      return;
    }

    if (p === '/api/notice' && req.method === 'POST') {
      if (!isAuthed(req)) { send(res, 401, { ok: false, message: '未登录' }); return; }
      const b = await readBody(req);
      if (!b.title || !b.body) {
        send(res, 400, { ok: false, message: '标题和正文不能为空' });
        return;
      }
      const list = readNotices();
      const notice = {
        id: 'n' + Date.now(),
        title: String(b.title).slice(0, 120),
        body: String(b.body).slice(0, 5000),
        date: new Date().toLocaleString('zh-CN', { hour12: false }),
        level: b.level === 'warning' ? 'warning' : 'info'
      };
      list.push(notice);
      writeNotices(list.slice(-100));
      send(res, 200, { ok: true, notice });
      return;
    }

    if (p === '/api/notices' && req.method === 'GET') {
      if (!isAuthed(req)) { send(res, 401, { ok: false, message: '未登录' }); return; }
      send(res, 200, { items: readNotices().slice().reverse() });
      return;
    }

    // 通用代理：只放行网页版管理接口，避免被当成开放代理
    if (p === '/api/upstream' && req.method === 'POST') {
      if (!isAuthed(req)) { send(res, 401, { ok: false, message: '未登录' }); return; }
      const b = await readBody(req);
      const target = String(b.path || '');
      if (!target.startsWith('/admin/') && !target.startsWith('/api/auth/')) {
        send(res, 400, { ok: false, message: '不允许的后端路径' });
        return;
      }
      const out = await upstreamPost(target, b.payload || {});
      send(res, 200, out);
      return;
    }

    send(res, 404, { ok: false, message: 'Not found' });
  } catch (e) {
    send(res, 500, { ok: false, message: String((e && e.message) || e) });
  }
});

server.listen(PORT, () => {
  console.log('==============================================');
  console.log(' 长安控车 · 网站后台已启动');
  console.log(' 本机访问 : http://localhost:' + PORT);
  console.log(' 后台密码 : ' + (process.env.ADMIN_PASSWORD ? '（由环境变量设置）' : 'admin888（建议用 ADMIN_PASSWORD 修改）'));
  console.log(' 网页后端 : ' + UPSTREAM);
  console.log(' App 侧请把「我的 → 网站后台」地址填为此服务地址');
  console.log('==============================================');
});
