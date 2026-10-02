"""Narrow, root-only Framework charge-limit and TLP control helper.

Installed in the immutable Nix store; only fixed actions are sudo-authorized.
Never imports user code, accepts paths, executes a shell, or flashes firmware.
"""
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

STATE = Path('/var/lib/framework-power')
RUNTIME = Path('/run/framework-power')
SUPPLY = Path('/sys/class/power_supply')
DMI_VENDOR = Path('/sys/class/dmi/id/sys_vendor')
ECTOOL = '@ectool@'
TLP = '@tlp@'
ACTIONS = ('charge-toggle', 'charge-80', 'charge-100', 'charge-status',
           'restore-charge', 'profile-auto', 'profile-ac', 'profile-battery')
RESTORE_ATTEMPTS = 8
RESTORE_RETRY_DELAY = 1.5


def atomic_json(path, value):
    path.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.' + path.name, dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(value, stream)
            stream.write('\n')
            stream.flush()
            os.fsync(stream.fileno())
            os.fchmod(stream.fileno(), 0o644)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def run(argv):
    result = subprocess.run(argv, text=True, capture_output=True, timeout=40,
                            env={'PATH': '@rootPath@', 'LC_ALL': 'C', 'HOME': '/root'})
    if result.returncode:
        raise RuntimeError((result.stderr or result.stdout).strip() or
                           f'{argv[0]} failed ({result.returncode})')
    return result.stdout.strip()


def ec_limit(text):
    # The pinned fw-ectool prints exactly a decimal integer, not a sentence.
    if not text.strip().isdecimal():
        raise RuntimeError(f'Unrecognized EC charge-limit response: {text!r}')
    value = int(text.strip())
    if not 0 <= value <= 100:
        raise RuntimeError(f'Invalid EC charge limit: {value}')
    return value


def backend():
    vendor = DMI_VENDOR.read_text().strip().lower()
    if vendor != 'framework':
        raise RuntimeError('Charge control is restricted to Framework hardware.')
    batteries = []
    for battery in sorted(SUPPLY.glob('*')):
        try:
            if (battery / 'type').read_text().strip() != 'Battery':
                continue
            scope = battery / 'scope'
            if scope.exists() and scope.read_text().strip() == 'Device':
                continue
            threshold = battery / 'charge_control_end_threshold'
            if threshold.exists():
                batteries.append(threshold)
        except OSError:
            continue
    if len(batteries) > 1:
        raise RuntimeError('Multiple system-battery thresholds found; refusing to guess.')
    if batteries:
        return ('sysfs', batteries[0])
    return ('ectool', None)


def read_limit(kind, path):
    if kind == 'sysfs':
        return ec_limit(path.read_text())
    return ec_limit(run([ECTOOL, 'fwchargelimit']))


def write_limit(kind, path, value):
    if value not in (80, 100):
        raise RuntimeError('Only 80% and 100% limits are permitted.')
    if kind == 'sysfs':
        start = path.with_name('charge_control_start_threshold')
        # Preserve an existing start threshold unless it would prevent this cap.
        if start.exists() and int(start.read_text()) >= value:
            start.write_text(str(value - 5) + '\n')
        path.write_text(str(value) + '\n')
    else:
        run([ECTOOL, 'fwchargelimit', str(value)])
    actual = read_limit(kind, path)
    if actual != value:
        raise RuntimeError(f'Read-back failed: requested {value}%, hardware reports {actual}%.')
    return actual


def saved_charge_limit():
    desired_file = STATE / 'desired-charge.json'
    if desired_file.exists():
        desired = json.loads(desired_file.read_text())['limit']
    else:
        desired = 80
    if desired not in (80, 100):
        raise RuntimeError('Invalid saved charge limit; refusing to write it.')
    return desired


def charge_once(action):
    desired_file = STATE / 'desired-charge.json'
    kind, path = backend()
    current = read_limit(kind, path)
    desired = current
    if action == 'restore-charge':
        desired = saved_charge_limit()
    elif action == 'charge-toggle':
        desired = 100 if current == 80 else 80
    elif action.startswith('charge-') and action[7:] in ('80', '100'):
        desired = int(action[7:])
    if action != 'charge-status':
        if desired not in (80, 100):
            raise RuntimeError('Invalid saved charge limit; refusing to write it.')
        if current != desired:
            current = write_limit(kind, path, desired)
        # Persist only after hardware verification. A failed click is never success.
        atomic_json(desired_file, {'limit': desired})
    result = {'ok': True, 'limit': current, 'backend': kind,
              'verified_at': time.time(), 'boot_id': boot_id()}
    atomic_json(STATE / 'charge-status.json', result)
    return result


def charge(action):
    if action != 'restore-charge':
        return charge_once(action)
    # Validate persistent state once before retrying transient EC/sysfs failures.
    # A corrupt or unsupported saved value must fail immediately, not sleep/retry.
    saved_charge_limit()
    last = None
    for attempt in range(RESTORE_ATTEMPTS):
        try:
            return charge_once(action)
        except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as error:
            last = error
            if attempt + 1 < RESTORE_ATTEMPTS:
                time.sleep(RESTORE_RETRY_DELAY)
    raise last


def boot_id():
    return Path('/proc/sys/kernel/random/boot_id').read_text().strip()


def main(argv):
    if len(argv) != 1 or argv[0] not in ACTIONS:
        raise RuntimeError('Usage: framework-power-root ' + '|'.join(ACTIONS))
    if os.geteuid() != 0:
        raise RuntimeError('Use framework-power for desktop actions; root is required here.')
    # These fixed, root-owned directories are never taken from environment variables.
    STATE.mkdir(mode=0o755, parents=True, exist_ok=True)
    RUNTIME.mkdir(mode=0o755, parents=True, exist_ok=True)
    with (RUNTIME / 'control.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        action = argv[0]
        if action.startswith('profile-'):
            mode = action.removeprefix('profile-')
            run([TLP, {'auto': 'start', 'ac': 'ac', 'battery': 'bat'}[mode]])
            result = {'mode': mode, 'requested_at': time.time()}
            atomic_json(RUNTIME / 'profile.json', result)
        else:
            try:
                result = charge(action)
            except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as error:
                atomic_json(STATE / 'charge-status.json', {
                    'ok': False, 'error': str(error), 'verified_at': time.time(),
                    'boot_id': boot_id()})
                raise
    print(json.dumps(result))


if __name__ == '__main__':
    try:
        main(sys.argv[1:])
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as error:
        print(f'framework-power-root: {error}', file=sys.stderr)
        sys.exit(1)
