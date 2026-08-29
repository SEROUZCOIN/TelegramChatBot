#!/usr/bin/env node
/**
 * Start the whole platform, on any operating system.
 *
 *   node run.js            start everything
 *   node run.js --stop     stop the API and admin panel
 *   node run.js --status   show what is running
 *   node run.js --logs     follow the API log
 *   node run.js --reset-db drop and rebuild the database, then start
 *
 * Node is the only thing you need installed. pnpm arrives through corepack,
 * which ships inside Node; the database is a connection URL you paste in once,
 * and this asks for it if it is missing.
 *
 * Written in plain Node rather than shell because the bash version could only
 * ever run on Linux — `service postgresql`, `su postgres` and `lsof` have no
 * Windows equivalent.
 */

'use strict';

const { spawn, spawnSync, execSync } = require('node:child_process');
const fs = require('node:fs');
const net = require('node:net');
const path = require('node:path');
const readline = require('node:readline');

const ROOT = __dirname;
const LOG_DIR = path.join(ROOT, '.logs');
const ENV_FILE = path.join(ROOT, 'apps', 'api', '.env');
const ENV_EXAMPLE = path.join(ROOT, 'apps', 'api', '.env.example');

const API_PORT = 3000;
const ADMIN_PORT = 3001;

const IS_WINDOWS = process.platform === 'win32';

/* --------------------------------------------------------------- output --- */

const useColor = process.stdout.isTTY && !process.env.NO_COLOR;
const c = (code, s) => (useColor ? `[${code}m${s}[0m` : s);
const bold = (s) => c('1', s);
const dim = (s) => c('2', s);

const step = (msg) => console.log(`\n${c('34;1', '==>')} ${msg}`);
const ok = (msg) => console.log(`    ${c('32', '✓')} ${msg}`);
const warn = (msg) => console.log(`    ${c('33', '!')} ${msg}`);
const fail = (msg) => console.log(`    ${c('31', '✗')} ${msg}`);

function die(msg, hint) {
  fail(msg);
  if (hint) console.log(`      ${dim(hint)}`);
  process.exit(1);
}

/* -------------------------------------------------------------- helpers --- */

/**
 * Run a command and wait for it.
 *
 * `shell: true` on Windows is not optional: pnpm is installed as `pnpm.cmd`
 * there, and Node's spawn will not find a .cmd without a shell.
 */
function run(cmd, args, { quiet = true, cwd = ROOT } = {}) {
  const res = spawnSync(cmd, args, {
    cwd,
    shell: IS_WINDOWS,
    stdio: quiet ? 'pipe' : 'inherit',
    encoding: 'utf8',
  });
  return {
    ok: res.status === 0,
    out: `${res.stdout || ''}${res.stderr || ''}`,
  };
}

const pnpm = (args, opts) => run('pnpm', args, opts);

/** Is something accepting connections on this port? */
function portOpen(port, timeout = 800) {
  return new Promise((resolve) => {
    const socket = net.createConnection({ port, host: '127.0.0.1' });
    const done = (result) => {
      socket.destroy();
      resolve(result);
    };
    socket.setTimeout(timeout);
    socket.once('connect', () => done(true));
    socket.once('timeout', () => done(false));
    socket.once('error', () => done(false));
  });
}

async function waitFor(check, seconds) {
  for (let i = 0; i < seconds; i += 1) {
    if (await check()) return true;
    await new Promise((r) => setTimeout(r, 1000));
  }
  return false;
}

/** Does the API answer a real request, not merely hold the port open? */
async function apiAnswers() {
  if (!(await portOpen(API_PORT))) return false;
  try {
    const res = await fetch(`http://127.0.0.1:${API_PORT}/api/plans`);
    return res.ok;
  } catch {
    return false;
  }
}

function ask(question) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      rl.close();
      resolve(answer.trim());
    });
  });
}

/* ------------------------------------------------------------------ env --- */

function readEnv() {
  if (!fs.existsSync(ENV_FILE)) return {};
  const out = {};
  for (const line of fs.readFileSync(ENV_FILE, 'utf8').split(/\r?\n/)) {
    const m = line.match(/^([A-Z0-9_]+)=(.*)$/);
    if (m) out[m[1]] = m[2].replace(/^["']|["']$/g, '');
  }
  return out;
}

function writeEnvVar(key, value) {
  let text = fs.existsSync(ENV_FILE) ? fs.readFileSync(ENV_FILE, 'utf8') : '';
  const line = `${key}=${value}`;
  text = new RegExp(`^${key}=.*$`, 'm').test(text)
    ? text.replace(new RegExp(`^${key}=.*$`, 'm'), line)
    : `${text.replace(/\s*$/, '')}\n${line}\n`;
  fs.writeFileSync(ENV_FILE, text);
}

/* -------------------------------------------------------------- process --- */

const pidFile = (name) => path.join(LOG_DIR, `${name}.pid`);

function readPid(name) {
  try {
    const pid = Number(fs.readFileSync(pidFile(name), 'utf8').trim());
    return Number.isInteger(pid) && pid > 0 ? pid : null;
  } catch {
    return null;
  }
}

function isAlive(pid) {
  if (!pid) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

/**
 * Stop a server.
 *
 * On Windows a detached child sits at the head of its own process tree, and
 * killing just that pid leaves the real server orphaned and still holding the
 * port — so the whole tree goes, via taskkill /T.
 */
function killTree(pid) {
  if (!pid) return;
  if (IS_WINDOWS) {
    spawnSync('taskkill', ['/PID', String(pid), '/T', '/F'], { stdio: 'ignore' });
    return;
  }
  try {
    process.kill(pid, 'SIGTERM');
  } catch {
    /* already gone */
  }
}

async function stopOne(name, port) {
  const pid = readPid(name);
  try {
    fs.unlinkSync(pidFile(name));
  } catch {
    /* no pid file */
  }

  if (!isAlive(pid) && !(await portOpen(port))) return false;

  killTree(pid);

  for (let i = 0; i < 6; i += 1) {
    await new Promise((r) => setTimeout(r, 700));
    if (!(await portOpen(port))) {
      ok(`stopped ${name}`);
      return true;
    }
  }

  if (!IS_WINDOWS && isAlive(pid)) {
    try {
      process.kill(pid, 'SIGKILL');
    } catch {
      /* gone */
    }
  }
  ok(`stopped ${name} (forced)`);
  return true;
}

function startDetached(name, cmd, args, cwd) {
  const logPath = path.join(LOG_DIR, `${name}.log`);
  const out = fs.openSync(logPath, 'a');

  const child = spawn(cmd, args, {
    cwd,
    detached: !IS_WINDOWS, // on Windows, detached opens a console window
    shell: IS_WINDOWS,
    stdio: ['ignore', out, out],
    windowsHide: true,
  });

  child.unref();
  if (child.pid) fs.writeFileSync(pidFile(name), String(child.pid));
  return child.pid;
}

/* ----------------------------------------------------------- subcommands --- */

async function showStatus() {
  step('Status');
  const [api, admin] = await Promise.all([apiAnswers(), portOpen(ADMIN_PORT)]);
  api ? ok(`api       :${API_PORT}`) : warn(`api       :${API_PORT}  down`);
  admin ? ok(`admin     :${ADMIN_PORT}`) : warn(`admin     :${ADMIN_PORT}  down`);
}

async function stopAll() {
  step('Stopping API and admin panel');
  const a = await stopOne('api', API_PORT);
  const b = await stopOne('admin', ADMIN_PORT);
  if (!a && !b) warn('nothing was running');
}

function followLogs() {
  const logPath = path.join(LOG_DIR, 'api.log');
  if (!fs.existsSync(logPath)) die('No API log yet. Start it first: node run.js');
  console.log(dim(`following ${logPath} — Ctrl+C to stop\n`));

  let size = fs.statSync(logPath).size;
  console.log(fs.readFileSync(logPath, 'utf8').split(/\r?\n/).slice(-30).join('\n'));

  setInterval(() => {
    const next = fs.statSync(logPath).size;
    if (next > size) {
      const fd = fs.openSync(logPath, 'r');
      const buf = Buffer.alloc(next - size);
      fs.readSync(fd, buf, 0, buf.length, size);
      fs.closeSync(fd);
      process.stdout.write(buf.toString('utf8'));
      size = next;
    }
  }, 700);
}

/* -------------------------------------------------------------- database --- */

const NEON_STEPS = `
  A database takes about two minutes and costs nothing:

    1. Open  ${bold('https://neon.tech')}  and sign up (no card needed)
    2. Create a project — any name
    3. Copy the connection string. It looks like:

       postgresql://user:password@ep-xxx.aws.neon.tech/neondb?sslmode=require

  Supabase, Railway or any other Postgres works exactly the same way.
`;

/**
 * Ask Prisma whether the database is reachable.
 *
 * Deliberately not psql: on a Windows machine that never installed Postgres
 * there is no psql to run, and the whole point of the cloud-database path is
 * that nothing has to be installed.
 */
function databaseReachable() {
  const script =
    "const{PrismaClient}=require('@prisma/client');" +
    'const p=new PrismaClient();' +
    'p.$queryRaw`SELECT 1`.then(()=>p.$disconnect()).then(()=>process.exit(0))' +
    '.catch(()=>process.exit(1));';
  return run(process.execPath, ['-e', script], { cwd: path.join(ROOT, 'apps', 'api') }).ok;
}

async function ensureDatabase() {
  step('Database');

  if (!fs.existsSync(ENV_FILE)) {
    fs.copyFileSync(ENV_EXAMPLE, ENV_FILE);
    ok('created apps/api/.env');
  }

  let url = readEnv().DATABASE_URL;

  // A URL that is present but dead is the more confusing case, so both the
  // missing and unreachable paths land on the same prompt rather than on a
  // Prisma stack trace.
  if (url) {
    process.env.DATABASE_URL = url;
    if (databaseReachable()) {
      ok('connected');
      return;
    }
    warn('the configured DATABASE_URL is not reachable');
  } else {
    warn('no DATABASE_URL is set');
  }

  if (!process.stdin.isTTY) {
    die(
      'A reachable DATABASE_URL is required.',
      'Set it in apps/api/.env, then run this again.',
    );
  }

  console.log(NEON_STEPS);
  const entered = await ask('  Paste your database URL here: ');
  if (!entered.startsWith('postgres')) {
    die('That does not look like a Postgres URL.', 'It should start with postgresql://');
  }

  writeEnvVar('DATABASE_URL', entered);
  process.env.DATABASE_URL = entered;

  if (!databaseReachable()) {
    die(
      'Could not connect with that URL.',
      'Check it was copied whole, including ?sslmode=require if your host needs it.',
    );
  }
  ok('connected, and saved to apps/api/.env');
}

/* ------------------------------------------------------------------ main --- */

async function main() {
  const arg = process.argv[2];

  fs.mkdirSync(LOG_DIR, { recursive: true });

  if (arg === '--status') return showStatus();
  if (arg === '--stop') return stopAll();
  if (arg === '--logs') return followLogs();

  console.log(bold('Starting the platform'));

  /* ---- Node ---- */
  step('Checking Node');
  const major = Number(process.versions.node.split('.')[0]);
  if (major < 20) {
    die(
      `Node ${process.versions.node} is too old — version 20 or newer is needed.`,
      'Download the LTS build from https://nodejs.org',
    );
  }
  ok(`node ${process.version} on ${process.platform}`);

  /* ---- pnpm, via corepack (ships inside Node) ---- */
  if (!run('pnpm', ['--version']).ok) {
    step('Enabling pnpm');
    try {
      execSync('corepack enable', { stdio: 'pipe' });
    } catch {
      /* reported below if pnpm is still missing */
    }
    if (!run('pnpm', ['--version']).ok) {
      die(
        'pnpm is unavailable and corepack could not enable it.',
        IS_WINDOWS
          ? 'Open PowerShell as Administrator and run: corepack enable'
          : 'Try: npm install -g pnpm',
      );
    }
  }
  ok(`pnpm ${run('pnpm', ['--version']).out.trim()}`);

  /* ---- dependencies ---- */
  if (!fs.existsSync(path.join(ROOT, 'node_modules'))) {
    step('Installing packages (first run — a minute or two)');
    if (!pnpm(['install'], { quiet: false }).ok) die('pnpm install failed');
    ok('installed');
  }

  /* ---- generate before touching the database: the probe needs the client ---- */
  step('Building');
  if (!pnpm(['--filter', '@tsp/shared', 'build']).ok) die('failed to build the shared package');
  ok('shared contracts');

  if (!pnpm(['--filter', '@tsp/api', 'exec', 'prisma', 'generate']).ok) {
    die('prisma generate failed');
  }
  ok('prisma client');

  await ensureDatabase();

  if (arg === '--reset-db') {
    warn('resetting the database — all data will be lost');
    pnpm(['--filter', '@tsp/api', 'exec', 'prisma', 'migrate', 'reset', '--force', '--skip-seed']);
  }

  if (!pnpm(['--filter', '@tsp/api', 'exec', 'prisma', 'migrate', 'deploy']).ok) {
    die('migrations failed', 'Run "node run.js --reset-db" if this is a scratch database.');
  }
  ok('migrations applied');

  // Seed only an empty database, so a restart never overwrites your own data.
  const planCount = countPlans();
  if (planCount === 0) {
    step('Seeding (first run)');
    const res = pnpm(['--filter', '@tsp/api', 'db:seed'], { quiet: false });
    if (!res.ok) die('seeding failed');
  } else {
    ok(`database already seeded (${planCount} plans)`);
  }

  if (!pnpm(['--filter', '@tsp/api', 'build']).ok) die('failed to build the API');
  ok('api');

  if (!fs.existsSync(path.join(ROOT, 'apps', 'admin', '.next'))) {
    step('Building the admin panel (first run)');
    if (!pnpm(['--filter', '@tsp/admin', 'build']).ok) die('failed to build the admin panel');
  }
  ok('admin panel');

  /* ---- servers ---- */
  step('Starting servers');
  await stopOne('api', API_PORT);
  await stopOne('admin', ADMIN_PORT);

  startDetached('api', process.execPath, ['dist/main.js'], path.join(ROOT, 'apps', 'api'));
  if (!(await waitFor(apiAnswers, 60))) {
    showLogTail('api');
    die('the API did not start', 'Full log: node run.js --logs');
  }
  ok(`api       http://localhost:${API_PORT}/api`);

  startDetached(
    'admin',
    'pnpm',
    ['exec', 'next', 'start', '-p', String(ADMIN_PORT)],
    path.join(ROOT, 'apps', 'admin'),
  );
  if (!(await waitFor(() => portOpen(ADMIN_PORT), 60))) {
    showLogTail('admin');
    die('the admin panel did not start');
  }
  ok(`admin     http://localhost:${ADMIN_PORT}`);

  /* ---- summary ---- */
  const env = readEnv();
  console.log(`
${bold('Running')}

  Admin panel   ${bold(`http://localhost:${ADMIN_PORT}`)}
  API           http://localhost:${API_PORT}/api
  API docs      http://localhost:${API_PORT}/api/docs

  Sign in as    ${env.SEED_ADMIN_EMAIL || 'admin@example.com'} / ${
    env.SEED_ADMIN_PASSWORD || 'ChangeMe123!'
  }

${bold('The phone app')}

  pnpm --filter @tsp/mobile start    ${dim('then scan the QR code with Expo Go')}

${dim(`node run.js --status   what is running
node run.js --logs     follow the API log
node run.js --stop     stop the servers`)}
`);
}

/** Plans present in the database, or 0 when it cannot be read. */
function countPlans() {
  const script =
    "const{PrismaClient}=require('@prisma/client');" +
    'const p=new PrismaClient();' +
    'p.plan.count().then(n=>{console.log(n);return p.$disconnect()})' +
    ".catch(()=>{console.log(0);return p.$disconnect()});";
  const res = run(process.execPath, ['-e', script], { cwd: path.join(ROOT, 'apps', 'api') });
  const n = Number(String(res.out).trim().split(/\r?\n/).pop());
  return Number.isInteger(n) ? n : 0;
}

function showLogTail(name) {
  const logPath = path.join(LOG_DIR, `${name}.log`);
  if (!fs.existsSync(logPath)) return;
  const lines = fs.readFileSync(logPath, 'utf8').split(/\r?\n/).slice(-15);
  console.log(dim(lines.join('\n')));
}

if (require.main === module) {
  main().catch((err) => {
    fail(err && err.message ? err.message : String(err));
    process.exit(1);
  });
}

// Exported for the unit tests, which force process.platform to exercise the
// Windows branches on a Linux machine.
module.exports = { killTree, portOpen, readEnv };
