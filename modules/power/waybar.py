"""Overlay power actions onto an unmanaged Waybar JSON/JSONC configuration.

Only the runtime copy is changed. CSS, module identifiers/order, unrelated
commands and the original on-disk configuration remain untouched.
"""
import copy
import json
import os
from pathlib import Path
import shlex
import sys
import tempfile

import json5

POWER = '@power@'
WAYBAR = '@waybar@'


def first_wins(destination, source):
    for key, value in source.items():
        if key not in destination:
            destination[key] = copy.deepcopy(value)
        elif isinstance(destination[key], dict) and isinstance(value, dict):
            first_wins(destination[key], value)


def config_directories():
    home = Path.home()
    directories = []
    if os.environ.get('WAYBAR_CONFIG_DIR'):
        directories.append(Path(os.path.expandvars(os.path.expanduser(os.environ['WAYBAR_CONFIG_DIR']))))
    if os.environ.get('XDG_CONFIG_HOME'):
        directories.append(Path(os.environ['XDG_CONFIG_HOME']) / 'waybar')
    directories += [home / '.config/waybar', home / 'waybar', Path('/etc/xdg/waybar')]
    # Also respect additional XDG search locations used by downstream setups.
    directories += [Path(p) / 'waybar' for p in os.environ.get('XDG_CONFIG_DIRS', '').split(':') if p]
    directories.append(Path.cwd() / 'resources')
    return list(dict.fromkeys(directories))


def include_path(filename, base):
    path = Path(os.path.expandvars(os.path.expanduser(filename)))
    # Upstream resolves the literal path first, then global config directories.
    # Finally accept source-relative paths, without evaluating shell commands.
    candidates = [path] if path.is_absolute() else [Path.cwd() / path] + [d / path for d in config_directories()] + [base / path]
    for candidate in candidates:
        if candidate.is_file():
            return candidate.resolve()
    raise ValueError(f'Waybar include not found: {filename}')


def expand_includes(obj, base, parents=()):
    if not isinstance(obj, dict):
        raise ValueError('Each Waybar configuration must be an object.')
    result = copy.deepcopy(obj)
    include = result.pop('include', []) or []
    if isinstance(include, str):
        include = [include]
    for filename in include:
        path = include_path(filename, base)
        if path in parents or len(parents) >= 20:
            raise ValueError(f'Waybar include cycle / depth limit: {path}')
        parsed = json5.loads(path.read_text())
        if not isinstance(parsed, dict):
            raise ValueError(f'Waybar include must contain an object: {path}')
        first_wins(result, expand_includes(parsed, path.parent, parents + (path,)))
    return result


def visible_modules(bar):
    result = []
    seen = set()
    def visit(name):
        if not isinstance(name, str) or name in seen:
            return
        seen.add(name)
        result.append(name)
        if name.startswith('group/'):
            for child in (bar.get(name) or {}).get('modules', []) or []:
                visit(child)
    for side in ('modules-left', 'modules-center', 'modules-right'):
        for name in bar.get(side, []) or []:
            visit(name)
    return result


def is_power(name, definition):
    if not name.startswith('custom/'):
        return False
    short = name.split('/', 1)[1].split('#', 1)[0].lower()
    if short in ('power', 'framework-power', 'powermenu', 'power-menu', 'power_menu', 'wlogout', 'shutdown', 'exit'):
        return True
    return ('power_menu' in str(definition.get('menu-file', '')) or
            any(icon in str(definition.get('format', '')) for icon in ('⏻', '\uf011')))


def overlay(bar):
    bar = copy.deepcopy(bar)
    names = visible_modules(bar)
    power_names = [name for name in names if is_power(name, bar.get(name) or {})]
    if not power_names:
        # The uploaded repo has no Waybar config. Discover its real module at
        # launch; only add one icon when no existing power module is present.
        power_names = ['custom/framework-power']
        if bar.get('modules-right') is None:
            bar['modules-right'] = []
        bar['modules-right'].append(power_names[0])
    for name in power_names:
        original = bar.get(name) or {}
        icon = str(original.get('format', '⏻'))
        if not icon or '{' in icon or '}' in icon:
            icon = '⏻'
        updated = copy.deepcopy(original)
        for key in ('menu', 'menu-file', 'menu-actions', 'exec-if', 'format-alt',
                    'format-alt-click', 'format-icons', 'restart-interval', 'signal'):
            updated.pop(key, None)
        updated.update({
            'exec': f'{shlex.quote(POWER)} status {shlex.quote(icon)}',
            'return-type': 'json', 'format': '{}', 'interval': 30, 'tooltip': True,
            'on-click': f'{shlex.quote(POWER)} charge-toggle',
            'on-click-right': f'{shlex.quote(POWER)} menu',
            'on-click-middle': f'{shlex.quote(POWER)} lock',
            'exec-on-event': True,
        })
        bar[name] = updated
    for name in names:
        if name.split('#', 1)[0] == 'battery':
            if bar.get(name) is None:
                bar[name] = {}
            definition = bar[name]
            # Also wire the battery icon, avoiding ambiguity about "power icon".
            for key in ('menu', 'menu-file', 'menu-actions'):
                definition.pop(key, None)
            definition['on-click'] = f'{shlex.quote(POWER)} charge-toggle'
            definition['on-click-right'] = f'{shlex.quote(POWER)} menu'
            original = definition.get('tooltip-format', '{capacity}% · {timeTo}')
            note = '\nClick: 80% / 100% cap; right-click: power menu'
            if not original.endswith(note):
                definition['tooltip-format'] = original + note
    return bar


def find_config():
    # Match Waybar's preference for config over config.jsonc.
    for directory in config_directories():
        for name in ('config', 'config.jsonc'):
            if (directory / name).is_file():
                return directory / name
    return None


def prepare(source, target):
    if source:
        parsed = json5.loads(source.read_text())
        multi = isinstance(parsed, list)
        rows = parsed if multi else [parsed]
        rows = [overlay(expand_includes(row, source.parent, (source.resolve(),))) for row in rows]
    else:
        multi = False
        rows = [overlay({'layer': 'top', 'modules-left': ['sway/workspaces'],
                         'modules-right': ['battery', 'clock'],
                         'clock': {'format': '{:%H:%M}'}})]
    target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, temporary = tempfile.mkstemp(prefix='.waybar-', dir=target.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(rows if multi else rows[0], stream, indent=2)
            stream.write('\n')
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return target


def main():
    source = find_config()
    runtime = Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}')) / 'framework-power-user'
    try:
        target = prepare(source, runtime / 'waybar.json')
    except (OSError, ValueError, TypeError, KeyError) as error:
        print(f'Power overlay could not be generated: {error}. Original Waybar config is unchanged.', file=sys.stderr)
        if '--prepare' in sys.argv or not source:
            raise
        # Keep the original bar available rather than replacing a complex
        # configuration we could not interpret. The menu hotkey remains usable.
        os.execv(WAYBAR, [WAYBAR, '-c', str(source)])
    if '--prepare' in sys.argv:
        return
    argv = [WAYBAR, '-c', str(target)]
    if source and (source.parent / 'style.css').is_file():
        argv += ['-s', str(source.parent / 'style.css')]
    os.execv(WAYBAR, argv)


if __name__ == '__main__':
    main()
