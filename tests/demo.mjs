import { execFileSync } from 'node:child_process';
import { setTimeout as sleep } from 'node:timers/promises';

// Examples: node tests/demo.mjs                   (one POST to test)
//           node tests/demo.mjs env=prod path=get
//           node tests/demo.mjs auth=none
//           node tests/demo.mjs path=get requests=1000
const options = { env: 'test', path: 'post', auth: 'app-a', requests: '1', delayMs: '0' };
const productPath = '/products/1';
const orderBody = { productId: '1', quantity: 2 };

if (process.argv.includes('--help')) {
  console.log('Usage: node tests/demo.mjs key=value ...');
  console.log('env=test|prod|production path=get|post auth=none|wrong|app-a|app-b requests=1 delayMs=0');
  console.log('Defaults: one authenticated POST /orders to test. GET uses /products/1.');
  console.log('Product path and order body are fixed near the top of the file. Ctrl+C stops a batch.');
  process.exit(0);
}

let step = 'reading arguments; run node tests/demo.mjs --help for supported settings';
try {
  const supplied = new Set();
  for (const argument of process.argv.slice(2)) {
    const equals = argument.indexOf('=');
    const name = argument.slice(0, equals);
    if (equals < 1 || !Object.hasOwn(options, name) || supplied.has(name)) throw new Error('Invalid argument');
    options[name] = argument.slice(equals + 1);
    supplied.add(name);
  }
  const environment = options.env === 'prod' ? 'production' : options.env;
  const authentication = options.auth;
  const method = options.path.toUpperCase();
  const path = method === 'GET' ? productPath : '/orders';
  const requests = Number(options.requests);
  const delayMs = Number(options.delayMs);

  if (!['test', 'production'].includes(environment)
    || !['none', 'wrong', 'app-a', 'app-b'].includes(authentication)
    || !['GET', 'POST'].includes(method)
    || !path.startsWith('/') || path.startsWith('//') || path.includes('\\') || /[\s#]/.test(path)
    || !Number.isInteger(requests) || requests < 1 || requests > 10000
    || !Number.isInteger(delayMs) || delayMs < 0 || delayMs > 60000) {
    throw new Error('Invalid settings');
  }

  const port = environment === 'test' ? 8001 : 8002;
  console.log(`${environment}: ${method}, ${requests} request(s), port ${port}.`);
  let key = authentication === 'wrong' ? 'not-a-valid-key' : '';
  if (authentication === 'app-a' || authentication === 'app-b') {
    step = 'checking that Docker uses a local socket, not a remote engine';
    const dockerOptions = { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 10000 };
    const endpoint = process.env.DOCKER_HOST && !process.env.DOCKER_CONTEXT ? process.env.DOCKER_HOST
      : execFileSync('docker', ['context', 'inspect', '--format', '{{.Endpoints.docker.Host}}'], dockerOptions).trim();
    if (!endpoint.startsWith('unix://') && !endpoint.startsWith('npipe://')) throw new Error('Local Docker required');
    step = `reading the key from product-order-${environment}-gateway; deploy both profiles with Terraform first`;
    // Get the demo key privately from Docker. Never paste a key into this file.
    key = execFileSync('docker', ['exec', `product-order-${environment}-gateway`,
      'cat', `/var/lib/lab-secrets/${authentication}.key`],
    { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 10000 }).trim();
    if (!/^[a-f0-9]{64}$/.test(key)) throw new Error('Invalid key file');
  }

  const statuses = {};
  for (let i = 0; i < requests; i++) {
    if (i > 0) await sleep(delayMs);
    step = `sending request ${i + 1} to 127.0.0.1:${port}; check the gateway is healthy`;
    const response = await fetch(`http://127.0.0.1:${port}${path}`, {
      method,
      headers: { 'Content-Type': 'application/json', ...(key ? { 'X-Api-Key': key } : {}) },
      body: method === 'POST' ? JSON.stringify(orderBody) : undefined,
      redirect: 'error',
      signal: AbortSignal.timeout(15000),
    });
    const text = await response.text();
    statuses[response.status] = (statuses[response.status] || 0) + 1;

    // Show details for small experiments, just totals for large batches.
    if (requests <= 10) {
      console.log(`Request ${i + 1}: HTTP ${response.status}`);
      for (const header of ['x-cache-status', 'x-backend-request-id', 'cache-control',
        'x-ratelimit-remaining-second', 'x-ratelimit-remaining-minute', 'retry-after']) {
        console.log(`${header}: ${response.headers.get(header) ?? '-'}`);
      }
      console.log(text.split(key || '\0').join('[redacted]'));
    }
  }
  console.log('HTTP status counts:', statuses);
} catch {
  console.error(`Stopped while ${step}. No request was retried; raw error details are hidden to protect credentials.`);
  process.exitCode = 1;
}
