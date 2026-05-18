'use strict';

const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');

const PORT = parseInt(process.env.PORT || '3000', 10);
const TOKEN = process.env.GITHUB_TOKEN || '';

const UPSTREAM = {
  '/api/repos': 'https://api.github.com/user/repos?sort=pushed&direction=desc&per_page=30&type=owner',
  '/api/stars': 'https://api.github.com/users/linearza/starred?per_page=12&sort=created',
};

const GH_HEADERS = {
  Accept: 'application/vnd.github+json',
  'X-GitHub-Api-Version': '2022-11-28',
  'User-Agent': 'linear.co.za-dev',
};
if (TOKEN) GH_HEADERS.Authorization = `Bearer ${TOKEN}`;
else console.warn('Warning: GITHUB_TOKEN not set — only public repos will appear, rate limits apply');

const cache = Object.create(null);
const TTL_MS = 5 * 60 * 1000;

function ghFetch(url, cb) {
  const now = Date.now();
  const hit = cache[url];
  if (hit && now - hit.at < TTL_MS) return cb(null, hit.body);
  https.get(url, { headers: GH_HEADERS }, (ghRes) => {
    const chunks = [];
    ghRes.on('data', (c) => chunks.push(c));
    ghRes.on('end', () => {
      const body = Buffer.concat(chunks);
      if (ghRes.statusCode === 200) cache[url] = { at: now, body };
      cb(ghRes.statusCode === 200 ? null : new Error(`GitHub ${ghRes.statusCode}`), body);
    });
  }).on('error', cb);
}

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css':  'text/css; charset=utf-8',
  '.js':   'text/javascript; charset=utf-8',
  '.svg':  'image/svg+xml',
  '.ico':  'image/x-icon',
  '.txt':  'text/plain; charset=utf-8',
};

const ROOT = __dirname;

http.createServer((req, res) => {
  const urlPath = req.url.split('?')[0];

  // API routes
  const upstream = UPSTREAM[urlPath];
  if (upstream) {
    ghFetch(upstream, (err, body) => {
      if (err) {
        res.writeHead(502, { 'Content-Type': 'application/json' });
        res.end('{"error":"upstream error"}');
        return;
      }
      res.writeHead(200, {
        'Content-Type': 'application/json',
        'Cache-Control': 'no-store',
      });
      res.end(body);
    });
    return;
  }

  // Static files
  let filePath = path.join(ROOT, urlPath === '/' ? 'index.html' : urlPath);
  fs.stat(filePath, (err, stat) => {
    if (err || !stat.isFile()) {
      res.writeHead(404);
      res.end('Not found');
      return;
    }
    const ext = path.extname(filePath);
    res.writeHead(200, { 'Content-Type': MIME[ext] || 'application/octet-stream' });
    fs.createReadStream(filePath).pipe(res);
  });
}).listen(PORT, '127.0.0.1', () => {
  console.log(`dev server → http://localhost:${PORT}`);
  if (!TOKEN) console.log('  set GITHUB_TOKEN=ghp_... to include private repos');
});
