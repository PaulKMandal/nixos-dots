#!/usr/bin/env python3
"""Recreate ONLY the existing AUX backport's context from the local kernel tarball.

No network requests, Nix-store writes, kernel installation, or service changes.
A code-token guard verifies the whole target function; only whitespace/comments
may differ from the reviewed baseline. Git checks the generated diff against a
copy of the complete source file before the repository patch can be replaced.
"""
# AMD-derived fragments: Copyright 2015, 2026 Advanced Micro Devices, Inc.
# MIT license terms are reproduced in the accompanying README.md.
from __future__ import annotations

import argparse
import difflib
import hashlib
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
from typing import NamedTuple

VERSION = "6.12.90"
TARGET = "drivers/gpu/drm/amd/display/amdgpu_dm/amdgpu_dm.c"
FUNCTION = "amdgpu_dm_process_dmub_aux_transfer_sync"
PATCH_NAME = "amdgpu-dmub-aux-reply-bounds.patch"

# Semantic baseline transcribed from the upstream v6.12.90 source view.
# It is NOT used as patch context: context is read from the user's source archive.
EXPECTED_FUNCTION = r'''int amdgpu_dm_process_dmub_aux_transfer_sync(
		struct dc_context *ctx,
		unsigned int link_index,
		struct aux_payload *payload,
		enum aux_return_code_type *operation_result)
{
	struct amdgpu_device *adev = ctx->driver_context;
	struct dmub_notification *p_notify = adev->dm.dmub_notify;
	int ret = -1;

	mutex_lock(&adev->dm.dpia_aux_lock);
	if (!dc_process_dmub_aux_transfer_async(ctx->dc, link_index, payload)) {
		*operation_result = AUX_RET_ERROR_ENGINE_ACQUIRE;
		goto out;
	}
	if (!wait_for_completion_timeout(&adev->dm.dmub_aux_transfer_done, 10 * HZ)) {
		DRM_ERROR("wait_for_completion_timeout timeout!");
		*operation_result = AUX_RET_ERROR_TIMEOUT;
		goto out;
	}
	if (p_notify->result != AUX_RET_SUCCESS) {
		if (p_notify->result == AUX_RET_ERROR_PROTOCOL_ERROR) {
			DRM_WARN("DPIA AUX failed on 0x%x(%d), error %d\n",
					payload->address, payload->length,
					p_notify->result);
		}
		*operation_result = AUX_RET_ERROR_INVALID_REPLY;
		goto out;
	}
	payload->reply[0] = adev->dm.dmub_notify->aux_reply.command & 0xF;
	if (adev->dm.dmub_notify->aux_reply.command & 0xF0)
		payload->reply[0] = (adev->dm.dmub_notify->aux_reply.command >> 4) & 0xF;

	/*write req may receive a byte indicating partially written number as well*/
	if (p_notify->aux_reply.length)
		memcpy(payload->data, p_notify->aux_reply.data,
				p_notify->aux_reply.length);
	/* success */
	ret = p_notify->aux_reply.length;
	*operation_result = p_notify->result;
out:
	reinit_completion(&adev->dm.dmub_aux_transfer_done);
	mutex_unlock(&adev->dm.dpia_aux_lock);
	return ret;
}
'''
OLD_BLOCK = '''if (p_notify->aux_reply.length)
	memcpy(payload->data, p_notify->aux_reply.data,
			p_notify->aux_reply.length);
/* success */
ret = p_notify->aux_reply.length;'''
NEW_BLOCK = '''if (p_notify->aux_reply.length && payload->data) {
	/* Bound the reply to the scratch buffer it was read into. */
	ret = min_t(uint32_t, p_notify->aux_reply.length,
		    sizeof(p_notify->aux_reply.data));
	/*
	 * During a write-status-update retry the caller zeroes
	 * payload->length while still expecting the partial-write
	 * status byte in payload->data (see dce_aux_transfer_with_retries),
	 * so only clamp to payload->length for regular transfers.
	 */
	if (!payload->write_status_update)
		ret = min_t(int, ret, payload->length);

	memcpy(payload->data, p_notify->aux_reply.data, ret);
} else {
	/* success */
	ret = p_notify->aux_reply.length;
}'''
HEADER = '''Subject: [LOCAL BACKPORT] drm/amd/display: bound DMUB AUX replies on Linux 6.12.90

Receive-length logic adapted from upstream Linux v7.3-rc4:
https://raw.githubusercontent.com/torvalds/linux/v7.3-rc4/drivers/gpu/drm/amd/display/amdgpu_dm/amdgpu_dm_dmub.c

This is a local test backport, not an official stable commit or a verified
hardware fix. Only the receive copy and returned length are changed.
Context and line numbers were generated from the locally supplied kernel
source archive after verifying the complete function's code tokens.

'''

# Keep C operators and literals as distinct tokens. In particular, "- >" must
# not compare equal to "->". Comments/whitespace are ignored, not executable code.
LEXER = re.compile(
    r'\s+|/\*.*?\*/|//[^\r\n]*|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\''
    r'|[A-Za-z_][A-Za-z_0-9]*|0[xX][0-9A-Fa-f]+[uUlL]*|[0-9]+[uUlL]*'
    r'|>>=|<<=|->|>>|<<|&&|\|\||==|!=|<=|>=|\+\+|--|\+=|-=|\*=|/=|%='
    r'|&=|\|=|\^=|##|\.\.\.|[^\s]', re.DOTALL,
)


class Refuse(RuntimeError):
    pass


class Token(NamedTuple):
    value: str
    start: int
    end: int


def tokens(text: str) -> list[Token]:
    return [Token(m[0], m.start(), m.end()) for m in LEXER.finditer(text)
            if not (m[0].isspace() or m[0].startswith(("/*", "//")))]


def values(text: str) -> list[str]:
    return [t.value for t in tokens(text)]


def occurrences(haystack: list[str], needle: list[str]) -> list[int]:
    return [i for i in range(len(haystack) - len(needle) + 1)
            if haystack[i:i + len(needle)] == needle]


def function_tokens(source: str) -> list[Token]:
    ts = tokens(source)
    vs = [t.value for t in ts]
    found = []
    for i in occurrences(vs, ["int", FUNCTION, "("]):
        j = i + 3
        while j < len(ts) and ts[j].value not in ("{", ";"):
            j += 1
        if j == len(ts) or ts[j].value != "{":
            continue  # Forward declaration, not a function definition.
        depth, k = 1, j + 1
        while k < len(ts) and depth:
            depth += (ts[k].value == "{") - (ts[k].value == "}")
            k += 1
        if depth:
            raise Refuse("Unbalanced braces in target function.")
        found.append(ts[i:k])
    if len(found) != 1:
        raise Refuse(f"Expected exactly one target function; found {len(found)}.")
    return found[0]


def make_repair(source_bytes: bytes) -> tuple[bytes, bytes]:
    source = source_bytes.decode("utf-8")
    if "\x00" in source:
        raise Refuse("Source contains a NUL byte; not a normal C text file.")
    fn = function_tokens(source)
    actual = [t.value for t in fn]
    if actual != values(EXPECTED_FUNCTION):
        excerpt = source[fn[0].start:fn[-1].end]
        raise Refuse("Target function differs in CODE, not just context/formatting.\n"
                     "No patch was overwritten. Actual function follows:\n" + excerpt[:20000])
    old = values(OLD_BLOCK)
    starts = occurrences(actual, old)
    if len(starts) != 1:
        raise Refuse("Expected exactly one unchanged reply-copy block.")
    i = starts[0]
    start, end = fn[i].start, fn[i + len(old) - 1].end
    indent = source[source.rfind("\n", 0, start) + 1:start]
    if indent.strip():
        raise Refuse("Target statement is not at the beginning of a source line.")
    newline = "\r\n" if "\r\n" in source else "\n"
    replacement = newline.join((indent if n and line else "") + line
                               for n, line in enumerate(NEW_BLOCK.splitlines()))
    fixed = source[:start] + replacement + source[end:]
    expected_tokens = actual[:i] + values(NEW_BLOCK) + actual[i + len(old):]
    if [t.value for t in function_tokens(fixed)] != expected_tokens:
        raise Refuse("Internal check failed: unexpected code change.")
    diff = "".join(difflib.unified_diff(source.splitlines(keepends=True),
                                      fixed.splitlines(keepends=True),
                                      fromfile="a/" + TARGET, tofile="b/" + TARGET,
                                      n=3))
    if not diff:
        raise Refuse("No patch was produced.")
    return (HEADER + diff).encode(), fixed.encode()


def read_source_archive(path: Path) -> bytes:
    requested = {f"linux-{VERSION}/Makefile", f"linux-{VERSION}/{TARGET}"}
    found: dict[str, bytes] = {}
    # Stream the archive; no member is extracted onto the filesystem.
    with tarfile.open(path, "r|*") as archive:
        for member in archive:
            name = member.name.removeprefix("./")
            if name not in requested:
                continue
            if name in found or not member.isfile() or member.size > 10 * 1024 * 1024:
                raise Refuse(f"Duplicate, non-regular, or oversized source member: {name}")
            stream = archive.extractfile(member)
            if stream is None:
                raise Refuse(f"Cannot read source member: {name}")
            found[name] = stream.read()
    if set(found) != requested:
        raise Refuse(f"Archive must contain linux-{VERSION}/Makefile and the target C file.")
    makefile = found[f"linux-{VERSION}/Makefile"].decode()
    nums = []
    for key in ("VERSION", "PATCHLEVEL", "SUBLEVEL"):
        matches = re.findall(rf"^{key}\s*=\s*(\d+)\s*$", makefile, re.MULTILINE)
        if len(matches) != 1:
            raise Refuse(f"Cannot establish {key} from source Makefile.")
        nums.append(matches[0])
    if ".".join(nums) != VERSION:
        raise Refuse(f"Expected kernel {VERSION}; Makefile reports {'.'.join(nums)}.")
    extra = re.findall(r"^EXTRAVERSION[ \t]*=[ \t]*(.*)$", makefile, re.MULTILINE)
    if len(extra) != 1 or extra[0].strip():
        raise Refuse("Unexpected kernel EXTRAVERSION; review the source before patching.")
    return found[f"linux-{VERSION}/{TARGET}"]


def verify_existing_patch(current: bytes) -> None:
    """Never overwrite a user-modified backport with different added/removed code."""
    text = current.decode()
    if (text.count("--- a/" + TARGET + "\n") != 1 or
            text.count("+++ b/" + TARGET + "\n") != 1):
        raise Refuse("Existing patch has unexpected source-file headers.")
    body = text[text.index("+++ b/" + TARGET + "\n") + len("+++ b/" + TARGET + "\n"):]
    if sum(line.startswith("@@ ") for line in body.splitlines()) != 1:
        raise Refuse("Existing patch must contain exactly one hunk.")
    removed = "\n".join(line[1:] for line in body.splitlines() if line.startswith("-"))
    added = "\n".join(line[1:] for line in body.splitlines() if line.startswith("+"))
    if values(removed) != values(OLD_BLOCK) or values(added) != values(NEW_BLOCK):
        raise Refuse("Existing patch changes different code. Refusing to overwrite it.")


def validate_diff(original: bytes, fixed: bytes, patch_bytes: bytes) -> None:
    git = shutil.which("git")
    if not git:
        raise Refuse("git must be available for the strict apply/reverse checks.")
    env = os.environ.copy()
    for key in list(env):
        if key.startswith("GIT_"):
            del env[key]
    with tempfile.TemporaryDirectory(prefix="amdgpu-aux-preflight.") as temp:
        root = Path(temp)
        f = root / TARGET
        f.parent.mkdir(parents=True)
        f.write_bytes(original)
        p = root / "repair.patch"
        p.write_bytes(patch_bytes)
        command = [git, "-c", "apply.ignoreWhitespace=no", "apply", "--no-index",
                   "--whitespace=nowarn"]
        for flags, expected in [(["--check"], original), ([], fixed),
                                (["--reverse", "--check"], fixed), (["--reverse"], original)]:
            result = subprocess.run(command + flags + [str(p)], cwd=root, env=env,
                                    capture_output=True, text=True, timeout=60)
            if result.returncode or f.read_bytes() != expected:
                raise Refuse("Generated diff failed strict apply/reverse validation:\n"
                             + result.stdout + result.stderr)
        # Also check with GNU patch when it is installed. Git alone is sufficient
        # on the laptop; its context check above has no fuzz/whitespace relaxation.
        patch_tool = shutil.which("patch")
        if patch_tool:
            result = subprocess.run([patch_tool, "--batch", "--forward", "--fuzz=0", "-p1",
                                     "-i", str(p)], cwd=root, capture_output=True, text=True, timeout=60)
            if result.returncode or f.read_bytes() != fixed:
                raise Refuse("GNU patch zero-fuzz validation failed:\n" + result.stdout + result.stderr)


def replace_with_backup(path: Path, before: bytes, after: bytes) -> Path:
    if path.is_symlink() or not path.is_file() or path.read_bytes() != before:
        raise Refuse("Patch file changed during preparation or is not a regular file.")
    backup_dir = Path.home() / ".local/state/framework-amdgpu-repair"
    backup_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, backup_name = tempfile.mkstemp(prefix="before-context-refresh.", suffix=".patch", dir=backup_dir)
    with os.fdopen(fd, "wb") as stream:
        stream.write(before)
        stream.flush()
        os.fsync(stream.fileno())
    mode = stat.S_IMODE(path.stat().st_mode)
    fd, new_name = tempfile.mkstemp(prefix=".aux-repair.", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(after)
            os.fchmod(stream.fileno(), mode)
            stream.flush()
            os.fsync(stream.fileno())
        if path.is_symlink() or path.read_bytes() != before:
            raise Refuse("Patch file changed before replacement; refusing.")
        os.replace(new_name, path)
    finally:
        if os.path.exists(new_name):
            os.unlink(new_name)
    return Path(backup_name)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-archive", type=Path, required=True,
                        help="Exact immutable Linux source tarball reported in the failed Nix build")
    parser.add_argument("--patch-file", type=Path,
                        default=Path(__file__).resolve().parent / PATCH_NAME)
    parser.add_argument("--write", action="store_true", help="Replace the repository patch after all checks")
    args = parser.parse_args()
    try:
        path = args.patch_file.absolute()
        if path.is_symlink() or not path.is_file():
            raise Refuse("Expected the existing regular patch file installed by 0004.")
        current = path.read_bytes()
        verify_existing_patch(current)
        source = read_source_archive(args.source_archive)
        generated, fixed = make_repair(source)
        validate_diff(source, fixed, generated)
        print(f"PASS: kernel source version is {VERSION}")
        print("PASS: entire target function matches reviewed code tokens")
        print("PASS: only the intended reply-copy code changes")
        print("PASS: generated diff applies/reverses exactly against the complete local C file")
        print(f"Original C file SHA256: {hashlib.sha256(source).hexdigest()}")
        print(f"Generated patch SHA256: {hashlib.sha256(generated).hexdigest()}")
        if generated == current:
            print("Already refreshed; no files changed.")
        elif args.write:
            backup = replace_with_backup(path, current, generated)
            print(f"Previous patch saved to: {backup}")
            print(f"Updated: {path}")
        else:
            print("Check-only run: no repository files changed. Add --write to replace the patch.")
        print("No kernel was built or installed by this helper.")
        return 0
    except (Refuse, OSError, UnicodeError, tarfile.TarError, subprocess.SubprocessError) as error:
        print(f"REFUSED: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
