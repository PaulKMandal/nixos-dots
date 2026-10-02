"""Hardware-free regression tests: fake sysfs, Sway IPC, and root commands."""
import contextlib
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest
from unittest import mock

BASE = Path(__file__).resolve().parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location('framework_' + name, BASE / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def put(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(str(text))


class TemporaryTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)

    def patch(self, target, name, **kwargs):
        p = mock.patch.object(target, name, **kwargs)
        result = p.start()
        self.addCleanup(p.stop)
        return result


class DisplayTests(TemporaryTest):
    def setUp(self):
        super().setUp()
        self.d = load('desktop')
        self.d.RUNTIME = self.base / 'runtime'
        self.d.BACKLIGHT = self.base / 'backlight'
        self.d.LEDS = self.base / 'leds'
        self.d.SUPPLY = self.base / 'supply'
        self.d.PROFILE_STATUS = self.base / 'profile.json'
        self.d.CHARGE_STATUS = self.base / 'charge.json'
        self.panel = self.d.BACKLIGHT / 'amdgpu_bl1'
        put(self.panel / 'type', 'raw')
        put(self.panel / 'max_brightness', 1000)
        put(self.panel / 'brightness', 700)
        self.keyboard = self.d.LEDS / 'chromeos::kbd_backlight'
        put(self.keyboard / 'brightness', 50)
        put(self.d.SUPPLY / 'BAT1/type', 'Battery')
        put(self.d.SUPPLY / 'BAT1/status', 'Discharging')
        put(self.d.SUPPLY / 'BAT1/capacity', 60)
        put(self.d.SUPPLY / 'AC/type', 'Mains')
        put(self.d.SUPPLY / 'AC/online', 0)
        self.mode120 = {'width': 2880, 'height': 1920, 'refresh': 120000}
        self.mode60 = {'width': 2880, 'height': 1920, 'refresh': 60000}
        self.monitors = [
            {'name': 'eDP-1', 'active': True, 'power': True,
             'current_mode': self.mode120.copy(), 'modes': [self.mode120, self.mode60]},
            {'name': 'DP-1', 'active': True, 'power': True, 'current_mode': self.mode120.copy(),
             'modes': [self.mode120, self.mode60]},
            {'name': 'DP-2', 'active': False, 'power': False},
        ]
        self.commands = []
        self.run = self.patch(self.d, 'run', side_effect=self.fake_run)
        self.notify = self.patch(self.d, 'notify')
        self.sleep = self.patch(self.d.time, 'sleep')
        env = mock.patch.dict(os.environ, {'SWAYSOCK': '/fake/sway-ipc'})
        env.start()
        self.addCleanup(env.stop)

    def fake_run(self, argv, **kwargs):
        self.commands.append(argv)
        stdout = ''
        if argv[0] == 'swaymsg':
            if argv[-1] == 'get_outputs':
                stdout = json.dumps(self.monitors)
            else:
                parts = shlex.split(argv[-1])
                if parts[0] != 'output':
                    raise AssertionError(argv)
                monitor = next(o for o in self.monitors if o['name'] == parts[1])
                if parts[2] == 'power':
                    monitor['power'] = parts[3] == 'on'
                elif parts[2] == 'mode':
                    size, refresh = parts[3].split('@')
                    width, height = map(int, size.split('x'))
                    monitor['current_mode'] = {'width': width, 'height': height,
                                               'refresh': round(float(refresh[:-2]) * 1000)}
                else:
                    raise AssertionError('Unexpected/moving-workspace command: ' + str(argv))
                stdout = '[{"success":true}]'
        elif argv[0] == 'brightnessctl':
            dev = next(a.split('=', 1)[1] for a in argv if a.startswith('--device='))
            root = self.d.BACKLIGHT if '--class=backlight' in argv else self.d.LEDS
            put(root / dev / 'brightness', argv[-1])
        return subprocess.CompletedProcess(argv, 0, stdout, '')

    def saved(self):
        return self.d.read_json(self.d.RUNTIME / 'display.json')

    def current(self):
        return int((self.panel / 'brightness').read_text())

    def test_zero_then_off_then_up_at_one_percent(self):
        put(self.panel / 'brightness', 10)
        self.d.display('down')
        self.assertEqual(self.current(), 0)
        self.assertTrue(self.monitors[0]['power'])
        self.d.display('down')
        self.assertTrue(self.saved()['manual_off'])
        self.assertFalse(self.monitors[0]['power'])
        self.assertFalse(self.monitors[1]['power'])
        self.assertEqual((self.keyboard / 'brightness').read_text(), '0')
        self.commands.clear()
        self.d.display('up')
        self.assertEqual(self.current(), 10)
        self.assertTrue(self.monitors[0]['power'])
        self.assertTrue(self.monitors[1]['power'])
        self.assertFalse(self.monitors[2]['power'])
        self.assertEqual(self.commands[0][0], 'brightnessctl')
        self.assertEqual((self.keyboard / 'brightness').read_text(), '50')
        self.assertFalse(self.saved()['manual_off'])

    def test_manual_dark_ignores_idle_mouse_and_repeated_down(self):
        self.d.display('screen-off')
        for action in ('down', 'idle-resume', 'idle-dim', 'idle-off'):
            self.d.display(action)
        self.assertTrue(self.saved()['manual_off'])
        self.assertFalse(self.monitors[0]['power'])
        self.assertFalse(self.monitors[1]['power'])

    def test_after_resume_reblanks_manual_dark(self):
        self.d.display('screen-off')
        self.monitors[0]['power'] = True
        self.d.display('after-resume')
        self.assertFalse(self.monitors[0]['power'])

    def test_after_resume_reasserts_active_outputs_twice(self):
        self.d.display('idle-off')
        self.commands.clear()
        self.d.display('after-resume')
        power_on = [a for a in self.commands if a[0] == 'swaymsg' and ' power on' in a[-1]]
        # Both active outputs are nudged twice; inactive outputs remain untouched.
        self.assertEqual(len(power_on), 4)
        self.assertTrue(self.monitors[0]['power'])
        self.assertTrue(self.monitors[1]['power'])
        self.assertFalse(self.monitors[2]['power'])
        self.sleep.assert_called_once_with(self.d.RESUME_RETRY_DELAY)

    def test_refresh_policy_waits_for_resume_guard(self):
        with self.d.state() as data:
            data['resume_guard_until'] = 200.0
        with mock.patch.object(self.d.time, 'time', return_value=100.0):
            self.d.policy_tick()
        self.assertEqual(self.monitors[0]['current_mode'], self.mode120)
        with mock.patch.object(self.d.time, 'time', return_value=201.0):
            self.d.policy_tick()
        self.assertEqual(self.monitors[0]['current_mode'], self.mode60)

    def test_manual_off_after_idle_off_recovers_original_outputs(self):
        self.d.display('idle-off')
        self.d.display('screen-off')
        self.d.display('up')
        self.assertTrue(self.monitors[0]['power'])
        self.assertTrue(self.monitors[1]['power'])

    def test_brightness_failure_never_wakes_at_full_brightness(self):
        self.d.display('screen-off')
        self.patch(self.d, 'set_percent', side_effect=RuntimeError('permission denied'))
        with self.assertRaisesRegex(RuntimeError, 'permission denied'):
            self.d.display('up')
        self.assertFalse(self.monitors[0]['power'])
        self.assertTrue(self.saved()['manual_off'])

    def test_no_internal_backlight_still_allows_dpms(self):
        self.d.display('screen-off')
        self.patch(self.d, 'set_percent', side_effect=self.d.NoBacklight('absent'))
        self.d.display('screen-on')
        self.assertTrue(self.monitors[1]['power'])

    def test_idle_dimming_restores_previous_level(self):
        self.d.display('idle-dim')
        self.assertEqual(self.current(), 100)
        self.d.display('idle-resume')
        self.assertEqual(self.current(), 700)

    def test_idle_does_not_brighten_an_already_dark_panel(self):
        put(self.panel / 'brightness', 0)
        self.d.display('idle-dim')
        self.assertEqual(self.current(), 0)

    def test_manual_brightness_overrides_idle_dimming_restore(self):
        self.d.display('idle-dim')
        self.d.display('down')
        self.d.display('idle-resume')
        self.assertEqual(self.current(), 50)

    def test_idle_pause_skips_dimming_and_off(self):
        with self.d.state() as data:
            data['idle_paused'] = True
        self.d.display('idle-dim')
        self.d.display('idle-off')
        self.assertEqual(self.current(), 700)
        self.assertTrue(self.monitors[0]['power'])

    def test_corrupt_state_recovers(self):
        put(self.d.RUNTIME / 'display.json', 'not JSON')
        self.d.display('screen-off')
        self.assertTrue(self.saved()['manual_off'])

    def test_new_sway_session_discards_stale_darkness(self):
        put(self.d.RUNTIME / 'display.json', json.dumps({'swaysock': '/old', 'manual_off': True}))
        self.d.display('down')
        self.assertEqual(self.current(), 650)
        self.assertNotIn('manual_off', self.saved())

    def test_battery_policy_caps_brightness_and_refresh_preserves_external(self):
        self.d.policy_tick()
        self.assertEqual(self.current(), 350)
        self.assertEqual(self.monitors[0]['current_mode'], self.mode60)
        self.assertEqual(self.monitors[1]['current_mode'], self.mode120)
        self.assertEqual((self.keyboard / 'brightness').read_text(), '0')

    def test_ac_policy_restores_pre_battery_settings(self):
        self.d.policy_tick()
        put(self.d.SUPPLY / 'AC/online', 1)
        self.d.policy_tick()
        self.assertEqual(self.current(), 700)
        self.assertEqual(self.monitors[0]['current_mode'], self.mode120)
        self.assertEqual((self.keyboard / 'brightness').read_text(), '50')

    def test_plugging_in_while_dark_does_not_cause_delayed_bright_wake(self):
        self.d.policy_tick()
        self.d.display('screen-off')
        put(self.d.SUPPLY / 'AC/online', 1)
        self.d.policy_tick()
        self.d.display('up')
        self.d.policy_tick()
        self.assertEqual(self.current(), 10)
        self.assertTrue(self.monitors[0]['power'])

    def test_policy_does_not_repeatedly_override_user_brightness(self):
        self.d.policy_tick()
        put(self.panel / 'brightness', 600)
        self.d.policy_tick()
        self.assertEqual(self.current(), 600)

    def test_policy_does_not_wake_manual_darkness(self):
        self.d.display('screen-off')
        self.d.policy_tick()
        self.assertFalse(self.monitors[0]['power'])
        self.assertEqual(self.monitors[0]['current_mode'], self.mode120)

    def test_policy_does_not_wake_idle_darkness(self):
        self.d.display('idle-off')
        self.d.policy_tick()
        self.assertFalse(self.monitors[0]['power'])

    def test_policy_does_not_invent_sixty_hz(self):
        self.monitors[0]['modes'] = [self.mode120]
        self.d.policy_tick()
        self.assertEqual(self.monitors[0]['current_mode'], self.mode120)

    def test_force_ac_allows_ac_settings_while_unplugged(self):
        self.d.policy_tick()
        put(self.d.PROFILE_STATUS, '{"mode":"ac"}')
        self.d.policy_tick()
        self.assertEqual(self.current(), 700)
        self.assertEqual(self.monitors[0]['current_mode'], self.mode120)

    def test_idle_sleep_refuses_manual_darkness(self):
        self.d.display('screen-off')
        lock = self.patch(self.d, 'lock_screen')
        self.d.sleep_now(idle=True)
        lock.assert_not_called()

    def test_idle_sleep_refuses_ac_power(self):
        put(self.d.SUPPLY / 'AC/online', 1)
        lock = self.patch(self.d, 'lock_screen')
        self.d.sleep_now(idle=True)
        lock.assert_not_called()

    def test_idle_sleep_refuses_busy_work(self):
        self.patch(self.d, 'busy_work', return_value=True)
        lock = self.patch(self.d, 'lock_screen')
        self.d.sleep_now(idle=True)
        lock.assert_not_called()

    def test_idle_sleep_locks_and_honors_inhibitors(self):
        self.patch(self.d, 'busy_work', return_value=False)
        lock = self.patch(self.d, 'lock_screen')
        self.d.sleep_now(idle=True)
        lock.assert_called_once()
        self.assertIn(['systemctl', '--check-inhibitors=yes', 'sleep'], self.commands)

    def test_sleep_does_not_proceed_after_lock_failure(self):
        self.patch(self.d, 'lock_screen', side_effect=RuntimeError('lock failed'))
        with self.assertRaises(RuntimeError):
            self.d.sleep_now()
        self.assertFalse(any(a[0] == 'systemctl' for a in self.commands))

    def test_busy_detector_fails_awake_on_unavailable_daemon(self):
        original = self.d.read_text
        self.patch(self.d, 'read_text', side_effect=lambda p, default='': '0 0 0' if str(p) == '/proc/loadavg' else original(p, default))
        self.run.side_effect = None
        self.run.return_value = subprocess.CompletedProcess([], 1, '', 'cannot connect')
        self.assertTrue(self.d.busy_work())

    def test_busy_detector_recognizes_vm(self):
        self.patch(self.d, 'read_text', return_value='0 0 0')
        self.run.side_effect = None
        self.run.return_value = subprocess.CompletedProcess([], 0, 'win11\n', '')
        self.assertTrue(self.d.busy_work())

    def test_status_rejects_other_boot_cache(self):
        put(self.d.CHARGE_STATUS, '{"ok":true,"limit":80,"boot_id":"old"}')
        result = self.d.status()
        self.assertEqual(result['class'], 'charge-error')
        self.assertIn('?', result['text'])

    def test_status_uses_verified_limit(self):
        boot = self.d.read_text(Path('/proc/sys/kernel/random/boot_id'))
        put(self.d.CHARGE_STATUS, json.dumps({'ok': True, 'limit': 80, 'boot_id': boot,
                                            'backend': 'ectool', 'verified_at': 1}))
        self.assertEqual(self.d.status()['text'], '⏻ 80%')

    def test_usb_peripheral_battery_is_excluded(self):
        put(self.d.SUPPLY / 'mouse/type', 'Battery')
        put(self.d.SUPPLY / 'mouse/scope', 'Device')
        self.assertEqual([p.name for p in self.d.batteries()], ['BAT1'])


class RootTests(TemporaryTest):
    def setUp(self):
        super().setUp()
        self.r = load('root')
        self.r.STATE = self.base / 'state'
        self.r.RUNTIME = self.base / 'run'
        self.r.SUPPLY = self.base / 'supply'
        self.r.DMI_VENDOR = self.base / 'vendor'
        put(self.r.DMI_VENDOR, 'Framework\n')
        self.limit = self.r.SUPPLY / 'BAT1/charge_control_end_threshold'
        put(self.limit.parent / 'type', 'Battery')
        put(self.limit, '100\n')
        # Safety net: no test is permitted to call real EC or TLP commands.
        self.run = self.patch(self.r, 'run', side_effect=AssertionError('unmocked root command'))

    def test_exact_ec_integer_parser(self):
        self.assertEqual(self.r.ec_limit('80\n'), 80)
        for text in ('limit: 80', '80 100', '101', '-1', '', '80%; echo bad'):
            with self.subTest(text=text), self.assertRaises(RuntimeError):
                self.r.ec_limit(text)

    def test_sysfs_is_preferred(self):
        self.assertEqual(self.r.backend(), ('sysfs', self.limit))

    def test_nonframework_is_rejected(self):
        put(self.r.DMI_VENDOR, 'Other Vendor')
        with self.assertRaises(RuntimeError):
            self.r.backend()

    def test_multiple_system_thresholds_are_rejected(self):
        put(self.r.SUPPLY / 'BAT2/type', 'Battery')
        put(self.r.SUPPLY / 'BAT2/charge_control_end_threshold', '100')
        with self.assertRaises(RuntimeError):
            self.r.backend()

    def test_peripheral_threshold_is_ignored(self):
        put(self.r.SUPPLY / 'mouse/type', 'Battery')
        put(self.r.SUPPLY / 'mouse/scope', 'Device')
        put(self.r.SUPPLY / 'mouse/charge_control_end_threshold', '100')
        self.assertEqual(self.r.backend(), ('sysfs', self.limit))

    def test_first_restore_defaults_to_eighty(self):
        result = self.r.charge('restore-charge')
        self.assertEqual(result['limit'], 80)
        self.assertEqual(json.loads((self.r.STATE / 'desired-charge.json').read_text()), {'limit': 80})

    def test_restore_retries_transient_backend_failure(self):
        original = self.r.charge_once
        calls = {'count': 0}

        def flaky(action):
            calls['count'] += 1
            if calls['count'] < 3:
                raise OSError('EC not ready')
            return original(action)

        self.patch(self.r, 'charge_once', side_effect=flaky)
        sleeper = self.patch(self.r.time, 'sleep')
        result = self.r.charge('restore-charge')
        self.assertEqual(result['limit'], 80)
        self.assertEqual(calls['count'], 3)
        self.assertEqual(sleeper.call_count, 2)

    def test_toggle_eighty_to_hundred_and_back(self):
        self.assertEqual(self.r.charge('charge-toggle')['limit'], 80)
        self.assertEqual(self.r.charge('charge-toggle')['limit'], 100)
        self.assertEqual(self.r.charge('charge-toggle')['limit'], 80)

    def test_saved_hundred_is_restored(self):
        put(self.r.STATE / 'desired-charge.json', '{"limit":100}')
        put(self.limit, '80')
        self.assertEqual(self.r.charge('restore-charge')['limit'], 100)

    def test_bad_saved_value_is_never_written(self):
        put(self.r.STATE / 'desired-charge.json', '{"limit":120}')
        with self.assertRaises(RuntimeError):
            self.r.charge('restore-charge')
        self.assertEqual(self.limit.read_text(), '100\n')

    def test_readback_failure_does_not_persist_success(self):
        put(self.r.STATE / 'desired-charge.json', '{"limit":100}')
        self.patch(self.r, 'read_limit', return_value=100)
        with self.assertRaisesRegex(RuntimeError, 'Read-back failed'):
            self.r.charge('charge-80')
        self.assertEqual(json.loads((self.r.STATE / 'desired-charge.json').read_text()), {'limit': 100})

    def test_start_threshold_brought_below_cap(self):
        start = self.limit.with_name('charge_control_start_threshold')
        put(start, 90)
        self.r.charge('charge-80')
        self.assertEqual(int(start.read_text()), 75)

    def test_status_read_is_not_desired_setting_mutation(self):
        self.r.charge('charge-status')
        self.assertFalse((self.r.STATE / 'desired-charge.json').exists())
        self.assertEqual(self.limit.read_text(), '100\n')

    def test_invalid_write_limit_refused(self):
        with self.assertRaises(RuntimeError):
            self.r.write_limit('sysfs', self.limit, 50)

    def test_ec_fallback_uses_fixed_argv(self):
        self.limit.unlink()
        self.run.side_effect = None
        self.run.return_value = '80'
        self.assertEqual(self.r.backend(), ('ectool', None))
        self.assertEqual(self.r.read_limit('ectool', None), 80)
        self.run.assert_called_once_with([self.r.ECTOOL, 'fwchargelimit'])

    def test_failure_cache_says_failure(self):
        self.patch(self.r.os, 'geteuid', return_value=0)
        self.patch(self.r, 'charge', side_effect=RuntimeError('unsupported firmware'))
        with self.assertRaises(RuntimeError):
            self.r.main(['charge-toggle'])
        result = json.loads((self.r.STATE / 'charge-status.json').read_text())
        self.assertFalse(result['ok'])
        self.assertIn('unsupported firmware', result['error'])

    def test_arbitrary_arguments_and_nonroot_refused(self):
        for argv in (['shell'], ['charge-80', 'extra'], ['/tmp/helper']):
            with self.assertRaises(RuntimeError):
                self.r.main(argv)
        self.patch(self.r.os, 'geteuid', return_value=1000)
        with self.assertRaises(RuntimeError):
            self.r.main(['charge-80'])

    def test_profile_uses_tlp_18_compatible_commands(self):
        self.patch(self.r.os, 'geteuid', return_value=0)
        self.run.side_effect = None
        self.run.return_value = ''
        for action, command in [('auto', 'start'), ('ac', 'ac'), ('battery', 'bat')]:
            with contextlib.redirect_stdout(io.StringIO()):
                self.r.main(['profile-' + action])
            self.run.assert_called_with([self.r.TLP, command])
            self.assertEqual(json.loads((self.r.RUNTIME / 'profile.json').read_text())['mode'], action)


class WaybarTests(TemporaryTest):
    def setUp(self):
        super().setUp()
        self.w = load('waybar')
        self.w.POWER = '/nix/store/test/bin/framework-power'
        env = mock.patch.dict(os.environ, {'HOME': str(self.base), 'XDG_CONFIG_HOME': str(self.base / 'xdg'),
                                          'WAYBAR_CONFIG_DIR': '', 'XDG_CONFIG_DIRS': ''})
        env.start()
        self.addCleanup(env.stop)

    def test_reuses_existing_power_identifier_order_and_icon(self):
        bar = {'modules-right': ['clock', 'custom/power', 'battery'],
               'custom/power': {'format': '⏻', 'menu-file': '/original/power_menu.xml',
                                'menu': 'on-click', 'on-click': 'old action'},
               'battery': {'format': '{capacity}% {icon}'}}
        original = copy.deepcopy(bar)
        changed = self.w.overlay(bar)
        self.assertEqual(changed['modules-right'], original['modules-right'])
        self.assertIn('charge-toggle', changed['custom/power']['on-click'])
        self.assertIn('menu', changed['custom/power']['on-click-right'])
        self.assertNotIn('menu-file', changed['custom/power'])
        self.assertEqual(changed['battery']['format'], original['battery']['format'])
        self.assertEqual(bar, original)

    def test_nested_group_power_is_reused(self):
        bar = {'modules-right': ['group/tray'], 'group/tray': {'modules': ['clock', 'custom/power']}}
        result = self.w.overlay(bar)
        self.assertEqual(result['modules-right'], ['group/tray'])
        self.assertNotIn('custom/framework-power', result)
        self.assertIn('charge-toggle', result['custom/power']['on-click'])

    def test_unusually_named_power_icon_is_detected(self):
        bar = {'modules-right': ['custom/button'], 'custom/button': {'format': '\uf011'}}
        result = self.w.overlay(bar)
        self.assertEqual(result['modules-right'], ['custom/button'])
        self.assertIn('charge-toggle', result['custom/button']['on-click'])

    def test_adds_only_one_fallback_and_handles_null_modules(self):
        result = self.w.overlay({'modules-right': None})
        self.assertEqual(result['modules-right'], ['custom/framework-power'])
        self.assertEqual(self.w.overlay(result)['modules-right'], result['modules-right'])

    def test_named_battery_instances_get_click_actions(self):
        result = self.w.overlay({'modules-right': ['battery#main'], 'battery#main': None})
        self.assertIn('charge-toggle', result['battery#main']['on-click'])

    def test_battery_tooltip_note_is_not_duplicated(self):
        bar = {'modules-right': ['battery']}
        result = self.w.overlay(self.w.overlay(bar))
        self.assertEqual(result['battery']['tooltip-format'].count('Click:'), 1)

    def test_includes_are_first_wins_and_deep_merged(self):
        put(self.base / 'shared.jsonc', '{clock:{format:"included", tooltip:true}, "custom/power":{format:"⏻"}}')
        bar = {'include': 'shared.jsonc', 'clock': {'format': 'local'}}
        result = self.w.expand_includes(bar, self.base)
        self.assertEqual(result['clock'], {'format': 'local', 'tooltip': True})
        self.assertNotIn('include', result)

    def test_include_cycle_rejected(self):
        put(self.base / 'a.json', '{include:"b.json"}')
        put(self.base / 'b.json', '{include:"a.json"}')
        with self.assertRaisesRegex(ValueError, 'cycle'):
            self.w.expand_includes({'include': 'a.json'}, self.base)

    def test_prepare_multiple_jsonc_bars_preserves_source_and_css(self):
        source = self.base / 'config.jsonc'
        text = '[ // comment\n {"modules-right":["custom/power",]}, {"modules-right":["battery"]}, ]'
        put(source, text)
        put(self.base / 'style.css', '/* unchanged */')
        target = self.base / 'runtime/waybar.json'
        self.w.prepare(source, target)
        rows = json.loads(target.read_text())
        self.assertEqual(len(rows), 2)
        self.assertIn('charge-toggle', rows[0]['custom/power']['on-click'])
        self.assertEqual(source.read_text(), text)
        self.assertEqual((self.base / 'style.css').read_text(), '/* unchanged */')

    def test_waybar_config_dir_takes_precedence(self):
        put(self.base / 'xdg/waybar/config', '{}')
        put(self.base / 'override/config.jsonc', '{}')
        with mock.patch.dict(os.environ, {'WAYBAR_CONFIG_DIR': str(self.base / 'override')}):
            self.assertEqual(self.w.find_config(), self.base / 'override/config.jsonc')

    def test_home_waybar_search_path(self):
        put(self.base / 'waybar/config', '{}')
        self.assertEqual(self.w.find_config(), self.base / 'waybar/config')

    def test_config_preferred_over_jsonc(self):
        put(self.base / 'xdg/waybar/config', '{}')
        put(self.base / 'xdg/waybar/config.jsonc', '{}')
        self.assertEqual(self.w.find_config(), self.base / 'xdg/waybar/config')

    def test_invalid_config_does_not_overwrite_last_runtime_copy(self):
        source = self.base / 'config'
        target = self.base / 'runtime/config'
        put(source, '{unparseable!')
        put(target, 'previous')
        with self.assertRaises(ValueError):
            self.w.prepare(source, target)
        self.assertEqual(target.read_text(), 'previous')


class ConfigSafetyTests(unittest.TestCase):
    def test_brightness_bindings_available_under_lock(self):
        source = (BASE / 'home.nix').read_text()
        for key in ('XF86MonBrightnessDown', 'XF86MonBrightnessUp', 'Mod4+Ctrl+o'):
            self.assertIn('bindsym --locked ' + key, source)

    def test_no_forced_deep_or_powertop_autotune(self):
        source = (BASE / 'configuration.nix').read_text()
        self.assertIn('powerManagement.powertop.enable = false', source)
        self.assertNotIn('boot.kernelParams', source)
        self.assertNotIn('powertop --auto-tune', source)
        self.assertNotIn('START_CHARGE_THRESH', source)
        self.assertNotIn('STOP_CHARGE_THRESH', source)

    def test_existing_resume_swap_and_ac_lid_behavior(self):
        source = (BASE / 'configuration.nix').read_text()
        self.assertIn('boot.resumeDevice = "/dev/disk/by-label/nixos-swap"', source)
        self.assertIn('HandleLidSwitchExternalPower = "ignore"', source)
        self.assertNotIn('swapDevices =', source)

    def test_charge_limit_is_reverified_after_boot(self):
        source = (BASE / 'configuration.nix').read_text()
        self.assertIn('systemd.timers.framework-charge-limit', source)
        self.assertIn('OnBootSec = "30s"', source)
        self.assertIn('OnUnitActiveSec = "10min"', source)
        self.assertIn('systemctl --no-block restart framework-charge-limit.service', source)
        self.assertNotIn('RemainAfterExit = true;\n    };\n  };\n  # The EC/charge', source)


if __name__ == '__main__':
    unittest.main(verbosity=2)
