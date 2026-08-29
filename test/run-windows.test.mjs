/**
 * Windows behaviour of the launcher, tested from Linux.
 *
 * The Windows-specific branches in run.js cannot be exercised on the machine
 * that develops them, and they fail in the quietest possible way: `shell: true`
 * missing means Node cannot find `pnpm.cmd`, and killing a bare pid instead of
 * the process tree leaves the real server running while the launcher reports
 * success. Both look perfect on Linux.
 *
 * So this stubs child_process and forces process.platform, and asserts on the
 * exact arguments the launcher hands to the operating system.
 *
 * Run: node --test test/run-windows.test.mjs
 */

import assert from 'node:assert/strict';
import { test } from 'node:test';
import Module from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const RUN_JS = path.join(ROOT, 'run.js');

/**
 * Load run.js with process.platform forced and child_process stubbed, so the
 * calls it would make are recorded instead of executed.
 */
function loadRunJs(platform) {
  const calls = { spawnSync: [], spawn: [] };

  const realPlatform = Object.getOwnPropertyDescriptor(process, 'platform');
  Object.defineProperty(process, 'platform', { value: platform, configurable: true });

  const realLoad = Module._load;
  Module._load = function patched(request, parent, isMain) {
    if (request === 'node:child_process' || request === 'child_process') {
      return {
        spawnSync: (cmd, args, opts) => {
          calls.spawnSync.push({ cmd, args, opts });
          return { status: 0, stdout: '', stderr: '' };
        },
        spawn: (cmd, args, opts) => {
          calls.spawn.push({ cmd, args, opts });
          return { pid: 4242, unref() {} };
        },
        execSync: () => '',
      };
    }
    return realLoad.apply(this, [request, parent, isMain]);
  };

  const require_ = Module.createRequire(import.meta.url);
  delete require_.cache[RUN_JS];
  const mod = require_(RUN_JS);

  Module._load = realLoad;
  Object.defineProperty(process, 'platform', realPlatform);

  return { mod, calls };
}

test('on Windows, stopping a server kills the whole process tree', () => {
  const { mod, calls } = loadRunJs('win32');

  mod.killTree(1234);

  assert.equal(calls.spawnSync.length, 1, 'should shell out to taskkill');
  const { cmd, args } = calls.spawnSync[0];

  assert.equal(cmd, 'taskkill');
  assert.deepEqual(args, ['/PID', '1234', '/T', '/F']);

  // /T is the part that matters. Without it the launcher kills the wrapper,
  // reports "stopped", and leaves the server holding the port.
  assert.ok(args.includes('/T'), 'must terminate the tree, not just the pid');
  assert.ok(args.includes('/F'), 'must force, or a busy server ignores it');
});

test('on Linux and macOS, stopping uses a signal rather than taskkill', () => {
  for (const platform of ['linux', 'darwin']) {
    const { mod, calls } = loadRunJs(platform);

    const realKill = process.kill;
    const signals = [];
    process.kill = (pid, sig) => signals.push({ pid, sig });

    mod.killTree(1234);

    process.kill = realKill;

    assert.equal(calls.spawnSync.length, 0, `${platform} must not call taskkill`);
    assert.deepEqual(signals, [{ pid: 1234, sig: 'SIGTERM' }]);
  }
});

test('killTree ignores a missing pid instead of throwing', () => {
  const { mod } = loadRunJs('win32');
  assert.doesNotThrow(() => mod.killTree(null));
  assert.doesNotThrow(() => mod.killTree(undefined));
  assert.doesNotThrow(() => mod.killTree(0));
});

test('the launcher spawns through a shell on Windows so pnpm.cmd resolves', () => {
  const source = readSource();

  // Every spawn/spawnSync in the file must pass shell: IS_WINDOWS. Node cannot
  // execute a .cmd without a shell, so a hardcoded `shell: false` would make
  // every pnpm call fail on Windows with a bare ENOENT.
  const spawnOptions = source.match(/shell:\s*[A-Za-z_]+/g) || [];
  assert.ok(spawnOptions.length >= 2, 'both spawn paths should set shell');
  for (const opt of spawnOptions) {
    assert.match(opt, /shell:\s*IS_WINDOWS/, `expected shell: IS_WINDOWS, saw "${opt}"`);
  }
});

test('detached is off on Windows, where it would open a console window', () => {
  const source = readSource();
  assert.match(
    source,
    /detached:\s*!IS_WINDOWS/,
    'detached must be disabled on Windows',
  );
  assert.match(source, /windowsHide:\s*true/, 'the child console must stay hidden');
});

test('no Linux-only command survives in the launcher', () => {
  const source = readSource();
  for (const forbidden of ['lsof', 'pg_isready', 'su postgres', 'service postgresql', 'redis-cli']) {
    assert.ok(
      !source.includes(forbidden),
      `run.js must not depend on "${forbidden}" — it does not exist on Windows`,
    );
  }
});

test('paths are joined rather than concatenated with slashes', () => {
  const source = readSource();
  // A literal "apps/api" inside a path expression would break on Windows.
  assert.ok(
    !/['"`]\.?\/?apps\/api['"`]/.test(source),
    'build paths with path.join, not embedded forward slashes',
  );
});

/**
 * The launcher's source with comments removed.
 *
 * Every scan below must look at code only. run.js documents *why* it avoids
 * lsof and *why* `shell: true` matters on Windows, and matching raw text made
 * those explanations register as the very problems they describe.
 */
let cachedSource = null;
function readSource() {
  if (cachedSource === null) {
    const require_ = Module.createRequire(import.meta.url);
    const raw = require_('node:fs').readFileSync(RUN_JS, 'utf8');
    cachedSource = raw.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
  }
  return cachedSource;
}
