#!/usr/bin/env python3
"""Match docker compose config JSON to mvm templates."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


def normalize_image(image: str) -> str:
    image = image.strip()
    if not image:
        return ""
    image = image.split("@", 1)[0]
    if ":" in image and "/" in image.split(":")[0]:
        image = image.rsplit(":", 1)[0]
    elif ":" in image and "/" not in image:
        image = image.split(":", 1)[0]
    return image.lower()


def load_image_map(path: Path) -> list[tuple[str, str]]:
    data = json.loads(path.read_text())
    entries = []
    for item in data.get("images", []):
        match = item.get("match", "").lower()
        template = item.get("template", "")
        if match and template:
            entries.append((match, template))
    entries.sort(key=lambda x: len(x[0]), reverse=True)
    return entries


def match_image(image: str, entries: list[tuple[str, str]]) -> str | None:
    norm = normalize_image(image)
    if not norm:
        return None
    for fragment, template in entries:
        if fragment in norm or norm.endswith("/" + fragment) or norm == fragment:
            return template
        if norm.endswith(fragment):
            return template
    parts = norm.split("/")
    if parts:
        last = parts[-1]
        for fragment, template in entries:
            if fragment.endswith("/" + last) or fragment == last:
                return template
    return None


def service_volumes(service: dict[str, Any]) -> list[dict[str, str]]:
    out: list[dict[str, str]] = []
    vols = service.get("volumes") or []
    for vol in vols:
        if isinstance(vol, str):
            if ":" in vol:
                host, guest = vol.split(":", 1)
                guest = guest.split(":", 1)[0]
                out.append({"host": host, "guest": guest})
            continue
        if not isinstance(vol, dict):
            continue
        if vol.get("type") not in (None, "bind", "volume"):
            continue
        host = vol.get("source") or vol.get("source_path") or ""
        guest = vol.get("target") or ""
        if host and guest:
            out.append({"host": str(host), "guest": str(guest)})
    return out


def share_hint_line(host: str, guest: str, data_hint: str, example_share: str) -> str | None:
    guest_path = guest.rstrip("/")
    if example_share:
        parts = example_share.split(":")
        if len(parts) >= 2:
            ex_guest = parts[1].split(":")[0]
            mode = parts[2] if len(parts) > 2 else "rw"
            return f"{host}:{ex_guest}:{mode}"
    if data_hint and guest_path.startswith("/data"):
        return f"{host}:{guest_path}:rw"
    if guest_path in ("/config", "/data"):
        return f"{host}:{guest_path}:rw"
    return f"{host}:{guest_path}:rw"


def match_compose(
    compose: dict[str, Any],
    entries: list[tuple[str, str]],
    known_templates: set[str],
    compose_file: str,
    template_meta: dict[str, dict[str, str]],
) -> dict[str, Any]:
    matched: list[dict[str, Any]] = []
    skipped: list[dict[str, Any]] = []
    services = compose.get("services") or {}
    if not isinstance(services, dict):
        return {"matched": matched, "skipped": skipped}

    for service_name, service in services.items():
        if not isinstance(service, dict):
            skipped.append(
                {
                    "compose_file": compose_file,
                    "service": service_name,
                    "reason": "invalid service block",
                }
            )
            continue
        image = service.get("image") or ""
        build = service.get("build")
        if not image:
            if build:
                skipped.append(
                    {
                        "compose_file": compose_file,
                        "service": service_name,
                        "reason": "build-only (no image)",
                    }
                )
            else:
                skipped.append(
                    {
                        "compose_file": compose_file,
                        "service": service_name,
                        "reason": "no image",
                    }
                )
            continue

        template = match_image(str(image), entries)
        if not template and service_name in known_templates:
            template = service_name
        if not template or template not in known_templates:
            skipped.append(
                {
                    "compose_file": compose_file,
                    "service": service_name,
                    "image": str(image),
                    "reason": "unknown image",
                }
            )
            continue

        meta = template_meta.get(template, {})
        data_hint = meta.get("data_hint", "")
        example_share = meta.get("example_share", "")
        vols = service_volumes(service)
        share_hints: list[str] = []
        for v in vols:
            line = share_hint_line(v["host"], v["guest"], data_hint, example_share)
            if line:
                share_hints.append(line)

        matched.append(
            {
                "compose_file": compose_file,
                "service": service_name,
                "image": str(image),
                "template": template,
                "instance": service_name,
                "share_hints": share_hints,
            }
        )

    return {"matched": matched, "skipped": skipped}


def run_self_test() -> int:
    root = Path(__file__).resolve().parent
    fixture = root / "fixtures" / "sample-compose-config.json"
    image_map = root / "image-map.json"
    compose = json.loads(fixture.read_text())
    entries = load_image_map(image_map)
    known = {
        "jellyfin",
        "vaultwarden",
        "postgres",
        "unknown",
    }
    meta = {
        "jellyfin": {"data_hint": "/data/jellyfin", "example_share": ""},
        "vaultwarden": {"data_hint": "/data/vaultwarden", "example_share": ""},
    }
    result = match_compose(compose, entries, known, "fixture", meta)
    names = {m["service"] for m in result["matched"]}
    if names != {"jellyfin", "vaultwarden", "postgres"}:
        print(f"unexpected matched services: {names}", file=sys.stderr)
        return 1
    skip_names = {s["service"] for s in result["skipped"]}
    if "unknown-app" not in skip_names:
        print("expected unknown-app in skipped", file=sys.stderr)
        return 1
    if not any("jellyfin" in h for m in result["matched"] if m["service"] == "jellyfin" for h in m["share_hints"]):
        pass
    jf = next(m for m in result["matched"] if m["service"] == "jellyfin")
    if not jf.get("share_hints"):
        print("expected share hints for jellyfin", file=sys.stderr)
        return 1
    print("compose-match self-test: OK")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Match compose services to mvm templates")
    parser.add_argument("--image-map", type=Path, required=False)
    parser.add_argument("--compose-file", default="")
    parser.add_argument("--templates", default="", help="comma-separated template names")
    parser.add_argument("--template-meta", type=Path, help="JSON object template -> meta")
    parser.add_argument("--test", action="store_true")
    parser.add_argument("compose_json", nargs="?", help="path to compose config json or - for stdin")
    args = parser.parse_args()

    if args.test:
        return run_self_test()

    if not args.image_map or not args.compose_json:
        parser.error("--image-map and compose_json required unless --test")

    entries = load_image_map(args.image_map)
    known = {t.strip() for t in args.templates.split(",") if t.strip()}
    template_meta: dict[str, dict[str, str]] = {}
    if args.template_meta and args.template_meta.is_file():
        template_meta = json.loads(args.template_meta.read_text())

    if args.compose_json == "-":
        compose = json.load(sys.stdin)
    else:
        compose = json.loads(Path(args.compose_json).read_text())

    result = match_compose(compose, entries, known, args.compose_file, template_meta)
    json.dump(result, sys.stdout, indent=2)
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
