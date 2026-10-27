#!/usr/bin/env python3
"""Validate prepared store assets without uploading or making attestations."""
import argparse
import json
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STORE = ROOT / "AppStore"


def image_info(path):
    with path.open("rb") as source:
        signature = source.read(8)
        if signature == b"\x89PNG\r\n\x1a\n":
            source.seek(16)
            width, height = struct.unpack(">II", source.read(8))
            _, color_type = source.read(2)
            alpha = color_type in (4, 6)
            source.seek(8)
            while True:
                head = source.read(8)
                if len(head) != 8:
                    break
                length, kind = struct.unpack(">I4s", head)
                alpha = alpha or kind == b"tRNS"
                source.seek(length + 4, 1)
                if kind == b"IEND":
                    break
            return width, height, alpha
        source.seek(0)
        if source.read(2) != b"\xff\xd8":
            raise ValueError("Expected PNG or JPEG")
        while True:
            marker = source.read(1)
            if not marker:
                raise ValueError("JPEG frame dimensions missing")
            if marker != b"\xff":
                continue
            marker = source.read(1)
            while marker == b"\xff":
                marker = source.read(1)
            if marker in (b"\xd8", b"\xd9"):
                continue
            length_bytes = source.read(2)
            if len(length_bytes) != 2:
                raise ValueError("Invalid JPEG marker")
            length = struct.unpack(">H", length_bytes)[0]
            if marker[0] in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7,
                             0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
                frame = source.read(5)
                height, width = struct.unpack(">HH", frame[1:])
                return width, height, False
            source.seek(length - 2, 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--allow-pending-screenshots", action="store_true")
    parser.add_argument("--require-submission-ready", action="store_true")
    args = parser.parse_args()
    configuration = json.loads((STORE / "submission.json").read_text())
    screenshots = json.loads((STORE / "screenshots.json").read_text())
    errors = []
    pending_captures = []
    captured_sets = {}
    limits = {"name": 30, "subtitle": 30, "promotional_text": 170,
              "description": 4000, "whats_new": 4000}
    for locale in configuration["locales"]:
        folder = STORE / "metadata" / locale
        for field, limit in limits.items():
            value = (folder / (field + ".txt")).read_text().strip()
            if not value or len(value) > limit:
                errors.append(f"{locale}/{field}: expected 1..{limit} characters")
        keywords = (folder / "keywords.txt").read_text().strip()
        if not keywords or len(keywords.encode("utf-8")) > 100:
            errors.append(f"{locale}/keywords: expected 1..100 UTF-8 bytes")
        for field in ("beta_description", "what_to_test"):
            if not (folder / (field + ".txt")).read_text().strip():
                errors.append(f"{locale}/{field}: missing test information")
        for device, specification in screenshots["sets"].items():
            images = sorted(p for p in (STORE / "screenshots" / locale / device).glob("*")
                            if p.suffix.lower().lstrip(".") in screenshots["formats"])
            key = locale + "/" + device
            if not images and specification["required"]:
                pending_captures.append(key)
                if not args.allow_pending_screenshots:
                    errors.append(key + ": native captures required")
            if images:
                captured_sets[key] = len(images)
            if len(images) > screenshots["maximum_per_device_size"]:
                errors.append(key + ": more than 10 screenshots")
            accepted = {tuple(size) for size in specification["accepted_dimensions"]}
            for image in images:
                try:
                    width, height, alpha = image_info(image)
                    if (width, height) not in accepted:
                        errors.append(str(image.relative_to(STORE)) + ": wrong native dimensions")
                    if alpha:
                        errors.append(str(image.relative_to(STORE)) + ": alpha channel/transparency is not allowed")
                except (OSError, ValueError, struct.error) as error:
                    errors.append(str(image.relative_to(STORE)) + ": " + str(error))
    width, height, alpha = image_info(STORE / "assets" / "AppIcon-1024.png")
    if (width, height) != (1024, 1024) or alpha:
        errors.append("App icon must be opaque 1024x1024")
    pending_owner = [key for key, value in configuration["owner_fields_required"].items()
                     if value is None or value is False or value == ""]
    for key in ("subscription_group_id", "price", "billing_grace_period_enabled"):
        if configuration["subscription"].get(key) is None:
            pending_owner.append("subscription." + key)
    if args.require_submission_ready and pending_owner:
        errors.append("Owner decisions and declarations are incomplete")
    result = {"asset_checks_passed": not errors, "captured_sets": captured_sets,
              "pending_capture_sets": pending_captures, "pending_owner_fields": pending_owner,
              "submission_ready": not errors and not pending_captures and not pending_owner,
              "errors": errors}
    print(json.dumps(result, indent=2))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
