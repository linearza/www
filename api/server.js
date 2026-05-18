'use strict';

const http = require('http');
const https = require('https');

const PORT = parseInt(process.env.PORT || '47291', 10);
const TOKEN = process.env.GITHUB_TOKEN || '';

const UPSTREAM = {
  '/repos': 'https://api.github.com/user/repos?sort=pushed&direction=desc&per_page=30&type=owner',
  '/stars': 'https://api.github.com/users/linearza/starred?per_page=12&sort=created',
};

const GH_HEADERS = {
  Accept: 'application/vnd.github+json',
  'X-GitHub-Api-Version': '2022-11-28',
  'User-Agent': 'linear.co.za',
};
if (TOKEN) GH_HEADERS.Authorization = `Bearer ${TOKEN}`;

// 5-minute in-memory cache
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
      cb(ghRes.statusCode === 200 ? null : new Error(String(ghRes.statusCode)), body);
    });
  }).on('error', cb);
}

http.createServer((req, res) => {
  const path = req.url.split('?')[0];
  const upstream = UPSTREAM[path];

  if (!upstream) {
    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end('{"error":"not found"}');
    return;
  }

  ghFetch(upstream, (err, body) => {
    if (err) {
      res.writeHead(502, { 'Content-Type': 'application/json' });
      res.end('{"error":"upstream error"}');
      return;
    }
    res.writeHead(200, {
      'Content-Type': 'application/json',
      'Cache-Control': 'public, max-age=300',
    });
    res.end(body);
  });
}).listen(PORT, '127.0.0.1', () => {
  console.log(`api listening on 127.0.0.1:${PORT}`);
});
