import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { chmod, copyFile, mkdir, mkdtemp, readFile, realpath, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';

test('iPhone E2E boots a shutdown simulator before installing the app', async t => {
  const root = await realpath(await mkdtemp(join(tmpdir(), 'whim-e2e-shutdown-')));
  t.after(() => rm(root, { recursive: true, force: true }));
  const bin = join(root, 'bin');
  await mkdir(bin);
  await mkdir(join(root, 'scripts'));
  for (const file of ['test-iphone-e2e.sh', 'apple-toolchain.sh', 'xcode-build-locations.sh',
    'xcode-build-locations.mjs', 'restart-e2e-simulator.mjs', 'terminate-process-tree.mjs']) {
    await copyFile(new URL(file, import.meta.url), join(root, 'scripts', file));
  }
  const fixtures = 'packages/WhimCore/Sources/WhimCore/WebhookConfiguration/Fixtures';
  await mkdir(join(root, fixtures), { recursive: true });
  await copyFile(new URL(`../${fixtures}/webhook-server.mjs`, import.meta.url), join(root, fixtures, 'webhook-server.mjs'));
  const state = join(root, 'state');
  const installed = join(root, 'installed');
  await writeFile(state, 'shutdown');
  const commands = {
    xcrun: `#!/bin/sh
case "$2" in
shutdown) echo 'Unable to shutdown device in current state: Shutdown' >&2; exit 149 ;;
boot) echo booting > "$WHIM_TEST_STATE" ;;
bootstatus) echo ready > "$WHIM_TEST_STATE"; echo Finished ;;
install) [ "$(cat "$WHIM_TEST_STATE")" = ready ] || { echo 'Unable to lookup in current state: Shutdown' >&2; exit 149; }; touch "$WHIM_TEST_INSTALLED" ;;
esac
`,
    xcodebuild: `#!/bin/sh
echo '[{"target":"whim","buildSettings":{"BUILD_DIR":"/fixture","PROJECT_TEMP_DIR":"/fixture/intermediates"}}]'
`,
    afconvert: '#!/bin/sh\nexit 0\n',
    maestro: '#!/bin/sh\n[ -f "$WHIM_TEST_INSTALLED" ]\n',
  };
  for (const [name, body] of Object.entries(commands)) {
    await writeFile(join(bin, name), body);
    await chmod(join(bin, name), 0o755);
  }
  const result = spawnSync('bash', [join(root, 'scripts/test-iphone-e2e.sh')], {
    encoding: 'utf8', timeout: 20000,
    env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, WHIM_IPHONE_SIMULATOR_UDID: 'fixture-iphone',
      NODE_TEST_CONTEXT: undefined,
      WHIM_IPHONE_E2E_SKIP_BUILD: '1', WHIM_TEST_STATE: state, WHIM_TEST_INSTALLED: installed },
  });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(await readFile(state, 'utf8'), 'ready\n');
});

test('E2E startup closes the stale simulator session and waits for a fresh boot', async t => {
  const root = await mkdtemp(join(tmpdir(), 'whim-simulator-restart-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const state = join(root, 'state');
  await writeFile(state, 'stale');
  const xcrun = join(root, 'xcrun');
  await writeFile(xcrun, `#!/bin/sh
set -eu
[ "$1" = simctl ] && [ "$3" = fixture-iphone ]
case "$2" in
  shutdown) [ "$(cat "$WHIM_TEST_STATE")" = stale ]; printf shutdown > "$WHIM_TEST_STATE" ;;
  boot) [ "$(cat "$WHIM_TEST_STATE")" = shutdown ]; printf booting > "$WHIM_TEST_STATE" ;;
  bootstatus) [ "$4" = -b ]; [ "$(cat "$WHIM_TEST_STATE")" = booting ]; printf ready > "$WHIM_TEST_STATE"; echo Finished ;;
  *) exit 9 ;;
esac
`);
  await chmod(xcrun, 0o755);
  execFileSync(process.execPath, [new URL('./restart-e2e-simulator.mjs', import.meta.url).pathname, 'fixture-iphone'], {
    env: { ...process.env, PATH: `${root}:${process.env.PATH}`, WHIM_TEST_STATE: state }, stdio: 'pipe',
  });
  assert.equal(await readFile(state, 'utf8'), 'ready');
});

for (const output of ['Status=3, isTerminal=YES\nData Migration Failed', 'Status=4, isTerminal=NO']) {
  test(`E2E startup rejects an unhealthy boot even when simctl exits zero: ${output}`, async t => {
    const root = await mkdtemp(join(tmpdir(), 'whim-unhealthy-simulator-'));
    t.after(() => rm(root, { recursive: true, force: true }));
    const xcrun = join(root, 'xcrun');
    await writeFile(xcrun, '#!/bin/sh\nif [ "$2" = bootstatus ]; then printf "%s\\n" "$WHIM_TEST_BOOT_OUTPUT"; fi\nexit 0\n');
    await chmod(xcrun, 0o755);
    const result = spawnSync(process.execPath, [new URL('./restart-e2e-simulator.mjs', import.meta.url).pathname, 'fixture-iphone'], {
      encoding: 'utf8', env: { ...process.env, PATH: `${root}:${process.env.PATH}`, WHIM_TEST_BOOT_OUTPUT: output },
    });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /boot.*failed|healthy boot/i);
  });
}

for (const [output, healthy] of [
  ['Unable to boot device in current state: Booted', true],
  ['Simulator service unavailable', false],
]) {
  test(`E2E startup validates a racing boot without hiding real boot errors: ${output}`, async t => {
    const root = await mkdtemp(join(tmpdir(), 'whim-racing-simulator-'));
    t.after(() => rm(root, { recursive: true, force: true }));
    const xcrun = join(root, 'xcrun');
    await writeFile(xcrun, '#!/bin/sh\ncase "$2" in\nboot) printf "%s\\n" "$WHIM_TEST_BOOT_ERROR" >&2; exit 149 ;;\nbootstatus) echo "Device already booted" ;;\nesac\n');
    await chmod(xcrun, 0o755);
    const result = spawnSync(process.execPath, [new URL('./restart-e2e-simulator.mjs', import.meta.url).pathname, 'fixture-iphone'], {
      encoding: 'utf8', env: { ...process.env, PATH: `${root}:${process.env.PATH}`, WHIM_TEST_BOOT_ERROR: output },
    });
    assert.equal(result.status === 0, healthy, result.stderr);
  });
}
