"""Sway/Waybar power controls. Hardware actions are delegated to root.py.

Manual darkness is NOT idle DPMS: only an explicit screen-on / brightness-up
clears it. All display mutations share a lock, including the AC/BAT watcher.
"""
import contextlib
import fcntl
import html
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

RUNTIME = Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}')) / 'framework-power-user'
SUPPLY = Path('/sys/class/power_supply')
BACKLIGHT = Path('/sys/class/backlight')
LEDS = Path('/sys/class/leds')
CHARGE_STATUS = Path('/var/lib/framework-power/charge-status.json')
PROFILE_STATUS = Path('/run/framework-power/profile.json')
STEPS = [0, 1, 2, 3, 5] + list(range(10, 101, 5))
RESUME_RETRY_DELAY = 0.75
RESUME_POLICY_GUARD = 8.0


class NoBacklight(RuntimeError):
    pass


def read_json(path, default=None):
    try:
        value = json.loads(path.read_text())
        return value if isinstance(value, dict) else ({} if default is None else default)
    except (OSError, ValueError):
        return {} if default is None else default


def read_text(path, default=''):
    try:
        return path.read_text().strip()
    except OSError:
        return default


def run(argv, *, check=True, timeout=15, **kwargs):
    result = subprocess.run(argv, text=True, capture_output=True, timeout=timeout, **kwargs)
    if check and result.returncode:
        raise RuntimeError((result.stderr or result.stdout).strip() or
                           f'{argv[0]} failed ({result.returncode})')
    return result


def notify(title, body, urgent=False):
    run(['notify-send', '-a', 'Framework power', '-u', 'critical' if urgent else 'normal',
         '-h', 'string:x-canonical-private-synchronous:framework-power', title, body], check=False)


@contextlib.contextmanager
def state():
    RUNTIME.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (RUNTIME / 'display.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        data = read_json(RUNTIME / 'display.json')
        sock = os.environ.get('SWAYSOCK', '')
        if data.get('swaysock') != sock:
            data = {'swaysock': sock}
        try:
            yield data
        finally:
            fd, temporary = tempfile.mkstemp(prefix='.display-', dir=RUNTIME)
            try:
                with os.fdopen(fd, 'w') as stream:
                    json.dump(data, stream)
                os.replace(temporary, RUNTIME / 'display.json')
            finally:
                if os.path.exists(temporary):
                    os.unlink(temporary)


def outputs():
    return json.loads(run(['swaymsg', '-r', '-t', 'get_outputs']).stdout)


def sway(command):
    result = json.loads(run(['swaymsg', '-r', '-t', 'command', command]).stdout)
    if not result or any(not row.get('success') for row in result):
        raise RuntimeError(f'Sway rejected {command}: {result}')


def output_power(names, enabled):
    present = {output['name'] for output in outputs()}
    for name in names:
        if name in present:
            sway(f'output {json.dumps(name)} power {"on" if enabled else "off"}')


def lit_outputs():
    return [o['name'] for o in outputs()
            if o.get('active') and o.get('power', o.get('dpms', True))]


def panel():
    devices = [p for p in sorted(BACKLIGHT.glob('*')) if (p / 'max_brightness').exists()]
    if not devices:
        raise NoBacklight('No laptop backlight found; use screen-off / screen-on for DPMS.')
    # Prefer the native GPU backlight over duplicate ACPI interfaces.
    devices.sort(key=lambda p: read_text(p / 'type') != 'raw')
    return devices[0]


def brightness():
    dev = panel()
    maximum = int((dev / 'max_brightness').read_text())
    current = int((dev / 'brightness').read_text())
    if maximum <= 0:
        raise RuntimeError('The panel reports an invalid brightness range.')
    return current, maximum


def set_brightness(value):
    run(['brightnessctl', '--class=backlight', '--device=' + panel().name,
         '--min-value=0', 'set', str(value)])


def percent(value, maximum):
    return 0 if value <= 0 else max(1, round(100 * value / maximum))


def set_percent(value):
    _, maximum = brightness()
    set_brightness(0 if value == 0 else max(1, round(maximum * value / 100)))


def keyboard_off(data, key):
    saved = data.setdefault(key, {})
    for dev in LEDS.glob('*kbd_backlight*'):
        current = read_text(dev / 'brightness')
        if current.isdecimal():
            saved.setdefault(dev.name, int(current))
            run(['brightnessctl', '--class=leds', '--device=' + dev.name,
                 '--min-value=0', 'set', '0'], check=False)


def keyboard_restore(data, key):
    for name, value in data.pop(key, {}).items():
        if (LEDS / name).exists():
            run(['brightnessctl', '--class=leds', '--device=' + name,
                 '--min-value=0', 'set', str(value)], check=False)


def screen_off(data):
    # Include already-idle-blanked outputs so brightness-up can recover them.
    names = sorted(set(lit_outputs() + data.get('idle_outputs', [])))
    data['manual_off'] = True
    data['manual_outputs'] = names
    data.pop('idle_outputs', None)
    data.pop('idle_brightness', None)
    keyboard_off(data, 'dark_keyboard')
    output_power(names, False)


def wake(data, low=False):
    # Set brightness BEFORE DPMS-on to avoid a bright flash in a dark room.
    if low:
        try:
            set_percent(1)
            data['keep_wake_brightness'] = True
        except NoBacklight:
            # DPMS-only fallback for a desktop / disconnected internal panel.
            pass
    names = data.get('manual_outputs', []) + data.get('idle_outputs', [])
    if not names:
        names = [o['name'] for o in outputs() if o.get('active')]
    output_power(sorted(set(names)), True)
    keyboard_restore(data, 'dark_keyboard')
    data['manual_off'] = False
    data.pop('manual_outputs', None)
    data.pop('idle_outputs', None)
    data.pop('idle_brightness', None)
    data.pop('policy_signature', None)


def resume_display(data):
    """Recover displays after system suspend without racing DRM/Sway startup.

    Sway/wlroots can report outputs as active before the panel has completed its
    resume.  Reassert DPMS immediately, then once more after a short settling
    period.  Delay refresh-rate policy changes for a few seconds so a 60/120 Hz
    transition cannot race the panel's resume path.
    """
    data['resume_guard_until'] = time.time() + RESUME_POLICY_GUARD
    if data.get('manual_off'):
        # Firmware may light a deliberately-dark panel during resume.  Let the
        # DRM device settle, then reassert darkness without clearing manual_off.
        time.sleep(RESUME_RETRY_DELAY)
        output_power([o['name'] for o in outputs() if o.get('active')], False)
        return

    saved = data.pop('idle_brightness', None)
    if saved:
        try:
            current, _ = brightness()
            if current == saved['dimmed']:
                # Restore brightness before lighting the panel to avoid a dim/bright
                # flash during wake.
                set_brightness(saved['before'])
        except (NoBacklight, OSError, RuntimeError, KeyError):
            pass

    expected = sorted(set(data.pop('idle_outputs', []) +
                          [o['name'] for o in outputs() if o.get('active')]))
    output_power(expected, True)
    time.sleep(RESUME_RETRY_DELAY)
    # A second DPMS-on is intentional.  It works around resume races where the
    # first command arrives while wlroots/DRM is still rebuilding the output.
    output_power(expected, True)
    data.pop('policy_signature', None)


def display(action):
    with state() as data:
        if action == 'screen-off':
            if not data.get('manual_off'):
                screen_off(data)
            return
        if action in ('up', 'screen-on') and data.get('manual_off'):
            wake(data, low=True)
            return
        if action == 'screen-on':
            wake(data)
            return
        if action == 'after-resume':
            resume_display(data)
            return
        if action == 'idle-resume':
            if data.get('manual_off'):
                return
            output_power(data.pop('idle_outputs', []), True)
            saved = data.pop('idle_brightness', None)
            if saved:
                current, _ = brightness()
                if current == saved['dimmed']:
                    set_brightness(saved['before'])
            return
        if data.get('manual_off'):
            return # Repeated brightness-down and idle events must never wake.
        if action in ('idle-dim', 'idle-off'):
            if data.get('idle_paused'):
                return
            if action == 'idle-off':
                names = lit_outputs()
                data['idle_outputs'] = sorted(set(data.get('idle_outputs', []) + names))
                output_power(names, False)
            elif on_battery():
                current, maximum = brightness()
                dimmed = max(1, round(maximum * 0.10))
                if current > dimmed and not data.get('idle_brightness'):
                    set_brightness(dimmed)
                    data['idle_brightness'] = {'before': current, 'dimmed': dimmed}
            return
        # Explicit brightness keys supersede an earlier automatic idle dim.
        data.pop('idle_brightness', None)
        if action == 'up' and data.get('idle_outputs'):
            output_power(data.pop('idle_outputs'), True)
        current, maximum = brightness()
        current_pct = percent(current, maximum)
        if action == 'down' and current == 0:
            screen_off(data)
            return
        if action == 'down':
            target = max([step for step in STEPS if step < current_pct], default=0)
        else:
            target = min([step for step in STEPS if step > current_pct], default=100)
        set_percent(target)
    notify('Brightness', f'{target}%')


def batteries():
    return [p for p in sorted(SUPPLY.glob('*'))
            if read_text(p / 'type') == 'Battery' and read_text(p / 'scope') != 'Device'
            and read_text(p / 'present', '1') == '1']


def on_battery():
    # AC/USB-C supplies expose online; include all non-battery supply types.
    supplies = [p for p in SUPPLY.glob('*') if (p / 'online').exists()
                and read_text(p / 'type') != 'Battery']
    if any(read_text(p / 'online') == '1' for p in supplies):
        return False
    return bool(batteries()) and (bool(supplies) or any(
        read_text(p / 'status') == 'Discharging' for p in batteries()))


def battery_details():
    result = []
    for battery in batteries():
        def number(name):
            try:
                return float(read_text(battery / name))
            except ValueError:
                return 0.0
        watts = number('power_now') / 1e6
        if not watts:
            watts = number('current_now') * number('voltage_now') / 1e12
        full, design = number('energy_full'), number('energy_full_design')
        if not design:
            full, design = number('charge_full'), number('charge_full_design')
        health = f' · health {100 * full / design:.0f}%' if design else ''
        result.append(f"{battery.name}: {read_text(battery / 'capacity', '?')}% · "
                      f"{read_text(battery / 'status', 'unknown')} · {watts:.1f} W{health}")
    return result


def choose_mode(output):
    current = output.get('current_mode') or {}
    candidates = [m for m in output.get('modes', [])
                  if m.get('width') == current.get('width')
                  and m.get('height') == current.get('height')
                  and 59000 <= m.get('refresh', 0) <= 61000]
    return min(candidates, key=lambda m: abs(m['refresh'] - 60000), default=None)


def set_mode(name, mode):
    sway(f'output {json.dumps(name)} mode {mode["width"]}x{mode["height"]}'
         f'@{mode["refresh"] / 1000:.3f}Hz')


def policy_tick():
    bat = on_battery()
    profile = read_json(PROFILE_STATUS).get('mode', 'auto')
    saving = profile == 'battery' or (profile == 'auto' and bat)
    with state() as data:
        if data.get('manual_off') or data.get('idle_outputs'):
            return # Mode-setting must not undo deliberate DPMS-off.
        if time.time() < data.get('resume_guard_until', 0):
            return # Do not race panel/DRM recovery with a refresh-rate change.
        data.pop('resume_guard_until', None)
        panels = [o for o in outputs() if o.get('active') and
                  o['name'].startswith(('eDP-', 'LVDS-', 'DSI-'))]
        signature = [saving, [o['name'] for o in panels]]
        if data.get('policy_signature') == signature:
            return
        if saving:
            if 'ac_brightness' not in data:
                try:
                    current, maximum = brightness()
                    data['ac_brightness'] = current
                    if percent(current, maximum) > 35:
                        set_percent(35)
                except RuntimeError:
                    pass
            keyboard_off(data, 'ac_keyboard')
            saved_modes = data.setdefault('ac_modes', {})
            for output in panels:
                mode = choose_mode(output)
                current = output.get('current_mode')
                if mode and current and mode != current:
                    saved_modes.setdefault(output['name'], current)
                    set_mode(output['name'], mode)
        else:
            if 'ac_brightness' in data:
                previous = data.pop('ac_brightness')
                # Plugging in while manually dark must not cause a delayed
                # bright flash after the user deliberately wakes at 1%.
                if not data.get('keep_wake_brightness'):
                    set_brightness(previous)
            keyboard_restore(data, 'ac_keyboard')
            available = {o['name']: o for o in panels}
            for name, mode in data.pop('ac_modes', {}).items():
                if name in available and mode in available[name].get('modes', []):
                    set_mode(name, mode)
        data.pop('keep_wake_brightness', None)
        data['policy_signature'] = signature


def root_action(action):
    helper = Path('/etc/framework-power/root-command').read_text().strip()
    if not helper.startswith('/nix/store/') or '\n' in helper:
        raise RuntimeError('Invalid installed root-helper path.')
    result = run(['/run/wrappers/bin/sudo', '-n', helper, action], timeout=50)
    data = json.loads(result.stdout)
    if action.startswith('charge-'):
        notify('Battery charge limit', f"Verified {data['limit']}% cap ({data['backend']}).")
    else:
        notify('Power policy', {'auto': 'Automatic AC/battery settings',
                               'ac': 'AC settings forced until automatic mode or reboot',
                               'battery': 'Battery settings forced until automatic mode or reboot'}[data['mode']])
        policy_tick()


def lock_screen():
    # A separate lock prevents concurrent before-sleep / idle / manual lock races.
    RUNTIME.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (RUNTIME / 'screen-lock.lock').open('a') as guard:
        fcntl.flock(guard, fcntl.LOCK_EX)
        if run(['pgrep', '-u', str(os.getuid()), '-x', 'swaylock'], check=False).returncode:
            # Do not capture pipes inherited by the daemonized lock process.
            # -f returns only after the compositor confirms the lock.
            result = subprocess.run(['swaylock', '-f', '--color', '000000'],
                                    stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                    stderr=subprocess.DEVNULL, timeout=15)
            if result.returncode:
                raise RuntimeError('swaylock failed; refusing to initiate sleep.')


def idle_lock():
    with state() as data:
        paused = data.get('idle_paused', False)
    if not paused:
        lock_screen()


def busy_work():
    # Never pause active VMs/containers just because the keyboard was idle.
    if float(read_text(Path('/proc/loadavg'), '0').split()[0]) >= 1.0:
        return True
    for argv in (['virsh', '-c', 'qemu:///system', 'list', '--state-running', '--name'],
                 ['docker', 'ps', '-q']):
        try:
            result = run(argv, check=False, timeout=5)
            if result.returncode == 0 and result.stdout.strip():
                return True
            if result.returncode != 0:
                # Cannot determine whether workloads are running: fail awake.
                return True
        except (OSError, subprocess.SubprocessError):
            return True
    return False


def sleep_now(action='sleep', idle=False):
    if idle:
        with state() as data:
            blocked = data.get('manual_off') or data.get('idle_paused')
        if blocked or not on_battery() or busy_work():
            return
    lock_screen()
    # Honor logind blockers rather than forcibly suspending another workload.
    run(['systemctl', '--check-inhibitors=yes', action], timeout=30)


def toggle_idle():
    with state() as data:
        data['idle_paused'] = not data.get('idle_paused', False)
        paused = data['idle_paused']
    if paused:
        display('idle-resume')
    notify('Automatic idle actions', 'Paused until toggled or logout; lid and critical battery still apply.'
           if paused else 'Enabled')


def status(icon='⏻'):
    charge = read_json(CHARGE_STATUS)
    boot_id = read_text(Path('/proc/sys/kernel/random/boot_id'))
    good = charge.get('ok') is True and charge.get('boot_id') == boot_id
    cap = str(charge['limit']) + '%' if good else '?'
    policy = read_json(PROFILE_STATUS).get('mode', 'auto')
    lines = [f'Charge limit: {cap}', 'Left-click: toggle 80% / 100%',
             'Right-click: power menu', f'Power policy selection: {policy}']
    if good:
        checked = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(charge['verified_at']))
        lines.append(f"{charge['backend']} · last verified {checked}")
    else:
        lines.append(charge.get('error', 'Not verified in this boot; run power diagnostics.'))
    lines += battery_details()
    return {'text': f'{icon} {cap}', 'tooltip': html.escape('\n'.join(lines)),
            'class': 'charge-error' if not good else 'charge-capped' if charge['limit'] == 80 else 'charge-full'}


def menu():
    with state() as data:
        idle = 'Resume automatic idle actions' if data.get('idle_paused') else 'Pause automatic idle actions'
    choices = {
        'Toggle charge cap: 80% / 100%': lambda: root_action('charge-toggle'),
        'Charge to 100%': lambda: root_action('charge-100'),
        'Cap charging at 80%': lambda: root_action('charge-80'),
        'Power policy: automatic AC / battery': lambda: root_action('profile-auto'),
        'Power policy: force battery-saving settings': lambda: root_action('profile-battery'),
        'Power policy: force AC settings (boost allowed)': lambda: root_action('profile-ac'),
        'Screen off; keep applications running': lambda: display('screen-off'),
        'Screen on': lambda: display('screen-on'),
        idle: toggle_idle,
        'Lock screen': lock_screen,
        'Sleep; hibernate after 1 hour on battery when supported': sleep_now,
        'Suspend only': lambda: sleep_now('suspend'),
        'Hibernate now': lambda: sleep_now('hibernate'),
        'Power diagnostics': lambda: subprocess.Popen(['kitty', '--hold', sys.executable, __file__, 'doctor']),
        'Reboot…': lambda: confirmed('reboot'),
        'Shut down…': lambda: confirmed('poweroff'),
    }
    result = run(['wofi', '--dmenu', '--prompt', 'Framework power', '--width', '650'],
                 input='\n'.join(choices), check=False, timeout=None)
    if result.returncode == 0 and result.stdout.strip() in choices:
        choices[result.stdout.strip()]()


def confirmed(action):
    result = run(['wofi', '--dmenu', '--prompt', f'Confirm {action}'],
                 input='Cancel\nConfirm\n', check=False, timeout=None)
    if result.returncode == 0 and result.stdout.strip() == 'Confirm':
        run(['systemctl', '--check-inhibitors=yes', action])


def doctor():
    print('FRAMEWORK POWER — read-only diagnostics\n')
    for path in ('/sys/class/dmi/id/product_name', '/sys/class/dmi/id/bios_version',
                 '/sys/power/state', '/sys/power/mem_sleep', '/sys/power/resume',
                 '/sys/power/image_size', '/proc/swaps'):
        print(f'{path}:\n{read_text(Path(path), "unavailable")}\n')
    print('Charge status (hardware verification is on boot/click/resume):')
    print(json.dumps(read_json(CHARGE_STATUS), indent=2))
    print('\n'.join(battery_details()))
    swap = Path('/dev/disk/by-label/nixos-swap')
    if swap.exists():
        device = swap.stat().st_rdev
        print(f'Expected disk resume device: {os.major(device)}:{os.minor(device)} ({swap.resolve()})')
    else:
        print('WARNING: configured disk swap label is absent.')
    for argv in (['swapon', '--show', '--bytes'],
                 ['busctl', 'call', 'org.freedesktop.login1', '/org/freedesktop/login1',
                  'org.freedesktop.login1.Manager', 'CanHibernate'],
                 ['busctl', 'call', 'org.freedesktop.login1', '/org/freedesktop/login1',
                  'org.freedesktop.login1.Manager', 'CanSuspendThenHibernate'],
                 ['systemd-inhibit', '--list'],
                 ['tlp-stat', '-s'],
                 ['systemctl', '--user', 'is-active', 'swayidle.service', 'framework-power-watch.service']):
        print('\n$ ' + ' '.join(argv))
        result = run(argv, check=False)
        print(result.stdout or result.stderr)
    print('Save work before the first real hibernate/resume test. Configuration checks cannot prove a hardware round trip.')


def watch():
    warned = set()
    last_error = None
    while True:
        try:
            policy_tick()
            if not on_battery():
                warned.clear()
            else:
                levels = [int(read_text(p / 'capacity', '100')) for p in batteries()]
                level = min(levels, default=100)
                threshold = 8 if level <= 8 else 15 if level <= 15 else None
                if threshold and threshold not in warned:
                    notify('Battery low', f'{level}% remaining. Critical action is configured at 3%.', True)
                    warned.add(threshold)
            last_error = None
        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
            if str(error) != last_error:
                print(f'framework-power-watch: {error}', file=sys.stderr, flush=True)
                last_error = str(error)
        time.sleep(15)


def main(argv):
    action = argv[0] if argv else 'menu'
    if action in ('up', 'down', 'screen-off', 'screen-on', 'idle-dim', 'idle-off', 'idle-resume', 'after-resume'):
        display(action)
    elif action.startswith(('charge-', 'profile-')):
        allowed = {'charge-toggle', 'charge-80', 'charge-100', 'charge-status',
                   'profile-auto', 'profile-ac', 'profile-battery'}
        if action not in allowed:
            raise RuntimeError('Unsupported power action.')
        root_action(action)
    elif action == 'status':
        print(json.dumps(status(argv[1] if len(argv) > 1 else '⏻')))
    elif action == 'menu':
        menu()
    elif action == 'watch':
        watch()
    elif action == 'lock':
        lock_screen()
    elif action == 'idle-lock':
        idle_lock()
    elif action == 'idle-sleep':
        sleep_now(idle=True)
    elif action in ('sleep', 'suspend', 'hibernate'):
        sleep_now(action)
    elif action == 'idle-toggle':
        toggle_idle()
    elif action == 'doctor':
        doctor()
    else:
        raise RuntimeError('Usage: framework-power [menu|doctor|up|down|screen-off|screen-on|'
                           'charge-toggle|charge-80|charge-100|profile-auto|profile-ac|'
                           'profile-battery|sleep|suspend|hibernate|idle-toggle]')


if __name__ == '__main__':
    try:
        main(sys.argv[1:])
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f'framework-power: {error}', file=sys.stderr)
        try:
            notify('Power action failed', str(error), True)
        except (OSError, subprocess.SubprocessError, RuntimeError):
            pass
        sys.exit(1)
