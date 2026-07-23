#!/usr/bin/env python3
# Alpine/musl: copy cffi-built filter shared library to LXST.filterlib name.
# Upstream: MeshChatX scripts/docker-bake-lxst-filterlib-musl.py

from __future__ import annotations

import importlib.util
import shutil
import subprocess
import sys
import sysconfig
from pathlib import Path


def main() -> int:
	import LXST

	pkg = Path(LXST.__file__).resolve().parent
	ext_suffix = sysconfig.get_config_var("EXT_SUFFIX") or ""
	target = pkg / f"filterlib{ext_suffix}"

	import LXST.Filters  # noqa: F401

	candidates = sorted(
		pkg.glob("__pycache__/_cffi__*.cpython-*-linux-musl.so"),
		key=lambda p: p.stat().st_mtime,
		reverse=True,
	)
	if not candidates:
		print(
			"bake_lxst_filterlib_musl: no musl _cffi shared library under "
			"site-packages/LXST/__pycache__",
			file=sys.stderr,
		)
		return 1

	src = candidates[0]
	shutil.copy2(src, target)

	spec = importlib.util.find_spec("LXST.filterlib")
	if not spec or not spec.origin:
		print(
			"bake_lxst_filterlib_musl: LXST.filterlib still not discoverable "
			f"after copying {src.name}",
			file=sys.stderr,
		)
		return 1

	verify = subprocess.run(
		[
			sys.executable,
			"-c",
			"import LXST.Filters as F; raise SystemExit(0 if F.USE_NATIVE_FILTERS else 1)",
		],
		check=False,
	)
	if verify.returncode != 0:
		print(
			"bake_lxst_filterlib_musl: fresh interpreter did not load native filters",
			file=sys.stderr,
		)
		return 1

	print(f"bake_lxst_filterlib_musl: OK ({src.name} -> {target.name})")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
