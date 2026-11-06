import { spawnSync } from 'node:child_process';

// Native XCTest can leave an automation session attached between test runners.
// Restart only the simulator owned by this E2E run before starting Maestro.
const simulator = process.argv[2];
if (!simulator) throw new Error('An E2E simulator UDID is required.');
const shutdown = spawnSync('xcrun', ['simctl', 'shutdown', simulator], { encoding: 'utf8' });
if (shutdown.error) throw shutdown.error;
if (shutdown.status !== 0 && !/Unable to shutdown device in current state: Shutdown/.test((shutdown.stdout ?? '') + (shutdown.stderr ?? ''))) {
  throw new Error(`Simulator ${simulator} shutdown failed: ${shutdown.stderr ?? shutdown.stdout ?? shutdown.status}`);
}
// A simulator viewer can boot it between shutdown and this request. Still verify
// bootstatus below; every other boot error remains fatal.
const boot = spawnSync('xcrun', ['simctl', 'boot', simulator], { encoding: 'utf8' });
if (boot.error) throw boot.error;
if (boot.status !== 0 && !/Unable to boot device in current state: Booted/.test((boot.stdout ?? '') + (boot.stderr ?? ''))) {
  throw new Error(`Simulator ${simulator} boot request failed: ${boot.stderr ?? boot.stdout ?? boot.status}`);
}

// bootstatus can exit zero even when its terminal state is Data Migration Failed.
const result = spawnSync('xcrun', ['simctl', 'bootstatus', simulator, '-b'], { encoding: 'utf8' });
if (result.stdout) process.stdout.write(result.stdout);
if (result.stderr) process.stderr.write(result.stderr);
if (result.error) throw result.error;
const output = (result.stdout ?? '') + (result.stderr ?? '');
const failedTerminal = [...output.matchAll(/Status=(\d+),\s*isTerminal=YES/g)]
  .some(match => match[1] !== '4294967295');
if (result.status !== 0 || failedTerminal || /Data Migration Failed/i.test(output)) {
  throw new Error(`Simulator ${simulator} boot failed; refusing to start E2E.`);
}
if (!/Finished|Device already booted/i.test(output)) {
  throw new Error(`Simulator ${simulator} did not report a healthy boot.`);
}
