#!/usr/bin/env node
const http = require('http');
const https = require('https');
const zlib = require('zlib');
const fs = require('fs');
const path = require('path');
const { URL } = require('url');

const CONFIG_PATH = path.join(__dirname, 'proxy.config.json');

let config = {
  port: 4873,
  upstream: 'https://registry.npmjs.org',
  minAgeDays: 7,
  whitelist: []
};

try {
  if (fs.existsSync(CONFIG_PATH)) {
    const raw = fs.readFileSync(CONFIG_PATH, 'utf8');
    const parsed = JSON.parse(raw);
    config = Object.assign(config, parsed);
  }
} catch (err) {
  console.error('Failed to load config:', err.message);
}

function isWhitelisted(pkgName) {
  if (!pkgName) return false;
  if (!Array.isArray(config.whitelist)) return false;
  for (const item of config.whitelist) {
    if (!item) continue;
    if (item.endsWith('/*')) {
      const scope = item.slice(0, -2);
      if (pkgName.startsWith(scope + '/')) return true;
    } else if (item === pkgName) {
      return true;
    }
  }
  return false;
}

function parsePackageNameFromUrl(urlPath) {
  try {
    const u = new URL(urlPath, 'http://localhost');
    const pathname = decodeURIComponent(u.pathname);
    if (pathname.startsWith('/-/')) return null;
    const parts = pathname.split('/').filter(Boolean);
    if (parts.length === 0) return null;
    if (pathname.startsWith('/@')) {
      if (parts.length >= 2) {
        return `${parts[0]}/${parts[1]}`;
      } else {
        return null;
      }
    } else {
      return parts[0];
    }
  } catch (e) {
    return null;
  }
}

function checkRecentPublication(pkgName, metadata) {
  try {
    if (!metadata || !metadata['dist-tags'] || !metadata.time) return false;
    const latest = metadata['dist-tags'].latest;
    if (!latest) return false;
    const timeMap = metadata.time;
    const published = timeMap[latest];
    if (!published) return false;
    const publishedTime = new Date(published);
    if (isNaN(publishedTime.getTime())) return false;
    const ageMs = Date.now() - publishedTime.getTime();
    const minAgeMs = (config.minAgeDays || 7) * 24 * 60 * 60 * 1000;
    return ageMs < minAgeMs;
  } catch (e) {
    return false;
  }
}

const server = http.createServer((req, res) => {
  const upstreamUrl = `${config.upstream}${req.url}`;

  const upstreamReq = https.request(upstreamUrl, {
    method: req.method,
    headers: Object.assign({}, req.headers, {
      'accept-encoding': req.headers['accept-encoding'] || 'gzip,deflate,br'
    })
  }, (upstreamRes) => {
    const headers = upstreamRes.headers;
    const contentType = (headers['content-type'] || '').toLowerCase();
    const encoding = (headers['content-encoding'] || '').toLowerCase();

    if (contentType.includes('application/json')) {
      const chunks = [];
      upstreamRes.on('data', (chunk) => chunks.push(chunk));
      upstreamRes.on('end', () => {
        const buffer = Buffer.concat(chunks);
        const decompress = (buf, enc, cb) => {
          if (!enc) return cb(null, buf);
          if (enc.includes('gzip')) return zlib.gunzip(buf, cb);
          if (enc.includes('deflate')) return zlib.inflate(buf, cb);
          if (enc.includes('br') && typeof zlib.brotliDecompress === 'function') return zlib.brotliDecompress(buf, cb);
          return cb(null, buf);
        };
        decompress(buffer, encoding, (err, decBuf) => {
          if (err) {
            res.writeHead(502, {'content-type':'text/plain'});
            res.end(`Failed to decompress upstream response: ${err.message}`);
            return;
          }
          let metadata;
          try {
            metadata = JSON.parse(decBuf.toString('utf8'));
          } catch (err2) {
            res.writeHead(upstreamRes.statusCode, headers);
            res.end(buffer);
            return;
          }

          const pkgName = parsePackageNameFromUrl(req.url);
          if (pkgName && isWhitelisted(pkgName)) {
            const body = JSON.stringify(metadata);
            const outHeaders = Object.assign({}, headers);
            delete outHeaders['content-encoding'];
            outHeaders['content-length'] = Buffer.byteLength(body).toString();
            res.writeHead(upstreamRes.statusCode, outHeaders);
            res.end(body);
            return;
          }

          const blocked = pkgName ? checkRecentPublication(pkgName, metadata) : false;
          if (blocked) {
            res.writeHead(403, {'content-type':'application/json'});
            res.end(JSON.stringify({
              error: 'package-blocked',
              reason: `Package '${pkgName}' was published less than ${config.minAgeDays} days ago and is blocked by local policy.`
            }));
            return;
          }

          const body = JSON.stringify(metadata);
          const outHeaders = Object.assign({}, headers);
          delete outHeaders['content-encoding'];
          outHeaders['content-length'] = Buffer.byteLength(body).toString();
          res.writeHead(upstreamRes.statusCode, outHeaders);
          res.end(body);
        });
      });

      upstreamRes.on('error', (err) => {
        res.writeHead(502, {'content-type':'text/plain'});
        res.end(`Upstream error: ${err.message}`);
      });
    } else {
      res.writeHead(upstreamRes.statusCode, headers);
      upstreamRes.pipe(res);
    }
  });

  upstreamReq.on('error', (err) => {
    res.writeHead(502, {'content-type':'text/plain'});
    res.end(`Failed to reach upstream registry: ${err.message}`);
  });

  req.pipe(upstreamReq);
});

server.listen(config.port, () => {
  console.log(`npm-age-proxy listening on port ${config.port}`);
  console.log(`Upstream registry: ${config.upstream}`);
  console.log(`Blocking packages newer than ${config.minAgeDays} days`);
});
