// Serve a pasta build/web aplicando os cabeçalhos do arquivo _headers (como a Netlify faz).
// Uso: node test_e2e/servir.js [porta] [pasta]
const http = require('http'), fs = require('fs'), path = require('path');
const porta = Number(process.argv[2] || 8091);
const raiz = path.resolve(process.argv[3] || path.join(__dirname, '..', 'build', 'web'));
const tipos = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.json': 'application/json', '.wasm': 'application/wasm', '.png': 'image/png', '.ico': 'image/x-icon', '.otf': 'font/otf', '.ttf': 'font/ttf', '.map': 'application/json' };
function cabecalhos() {
  const texto = fs.readFileSync(path.join(raiz, '_headers'), 'utf8');
  const h = {}; let aplicaTodos = false;
  for (const linha of texto.split('\n')) {
    if (!linha.trim() || linha.trim().startsWith('#')) continue;
    if (!linha.startsWith(' ')) { aplicaTodos = linha.trim() === '/*'; continue; }
    if (!aplicaTodos) continue;
    const i = linha.indexOf(':'); h[linha.slice(0, i).trim()] = linha.slice(i + 1).trim();
  }
  return h;
}
const h = cabecalhos();
http.createServer((req, res) => {
  let caminho = decodeURIComponent(req.url.split('?')[0]); if (caminho === '/') caminho = '/index.html';
  const arquivo = path.join(raiz, caminho);
  if (!arquivo.startsWith(raiz) || !fs.existsSync(arquivo) || fs.statSync(arquivo).isDirectory()) { res.writeHead(404, h); return res.end('404'); }
  res.writeHead(200, { ...h, 'Content-Type': tipos[path.extname(arquivo)] || 'application/octet-stream' });
  fs.createReadStream(arquivo).pipe(res);
}).listen(porta, () => console.log('servindo', raiz, 'na porta', porta, 'com', Object.keys(h).length, 'cabeçalhos'));
