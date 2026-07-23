# Compile domain and hosts-format blocklists into dnsmasq address lines.
# Usage: compile-blocklists.py ALLOWLIST OUT.conf LIST1 LIST2 ...

from __future__ import annotations

import re
import sys
from pathlib import Path

DOMAIN_RE = re.compile(
    r"^(?=.{1,253}$)(?!-)[A-Za-z0-9-]{1,63}(?<!-)(\.(?!-)[A-Za-z0-9-]{1,63}(?<!-))*$"
)


def normalize_domain(raw: str) -> str | None:
    d = raw.strip().lower().rstrip(".")
    if not d or d.startswith("#"):
        return None
    if d.startswith("*."):
        d = d[2:]
    if not DOMAIN_RE.match(d):
        return None
    if d in {"localhost", "local", "broadcasthost"}:
        return None
    return d


def parse_line(line: str) -> str | None:
    line = line.strip()
    if not line or line.startswith("#") or line.startswith("!"):
        return None
    # hosts format: 0.0.0.0 domain or 127.0.0.1 domain
    parts = line.split()
    if not parts:
        return None
    if parts[0] in {"0.0.0.0", "127.0.0.1", "::", "::1"}:
        if len(parts) < 2:
            return None
        return normalize_domain(parts[1])
    # plain domain or adblock-ish ||domain^
    token = parts[0]
    if token.startswith("||"):
        token = token[2:]
    token = token.split("^", 1)[0]
    token = token.split("$", 1)[0]
    return normalize_domain(token)


def load_domains(path: Path) -> set[str]:
    out: set[str] = set()
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        print(f"warn: skip {path}: {exc}", file=sys.stderr)
        return out
    for line in text.splitlines():
        domain = parse_line(line)
        if domain:
            out.add(domain)
    return out


def main() -> int:
    if len(sys.argv) < 3:
        print(
            "usage: compile-blocklists.py ALLOWLIST OUT.conf LIST [LIST...]",
            file=sys.stderr,
        )
        return 2

    allow_path = Path(sys.argv[1])
    out_path = Path(sys.argv[2])
    list_paths = [Path(p) for p in sys.argv[3:]]

    allow = load_domains(allow_path) if allow_path.is_file() else set()
    blocked: set[str] = set()
    for path in list_paths:
        if path.is_file():
            blocked |= load_domains(path)

    blocked -= allow

    lines = [f"address=/{domain}/0.0.0.0" for domain in sorted(blocked)]
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")
    print(f"wrote {len(lines)} blocked domains to {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
