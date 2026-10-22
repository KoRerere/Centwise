#!/usr/bin/env python3
"""Regenerate lib/app/lucide_icons.dart from a checkout of https://github.com/lucide-icons/lucide.

Usage:
  git clone --depth 1 --filter=blob:none --sparse https://github.com/lucide-icons/lucide.git /tmp/lucide
  (cd /tmp/lucide && git sparse-checkout set icons)
  python3 scripts/gen_icons.py /tmp/lucide/icons

Add a name to NAMES to bundle another icon (use the file name from lucide.dev, without .svg).
"""
import os
import re
import sys

NAMES = """
settings cog search plus chevron-left chevron-right chevron-down x check
utensils train-front shopping-bag house sparkles ellipsis briefcase gift heart book-open
layout-grid folder-search credit-card archive piggy-bank arrow-left-right arrow-down-to-line
arrow-up-right arrow-down-left equal calendar text-align-start lock info delete circle-alert
list-filter circle-x split chart-pie download upload coffee pill car plane gamepad-2
graduation-cap shirt baby dumbbell smartphone zap droplet receipt wallet banknote hand-coins
trending-up dog film music scissors stethoscope bus fuel tag shield-check file-down file-up
circle-question-mark folder-open landmark bike hamburger cake beer pizza apple sofa wrench
lightbulb tv gem ticket hotel map-pin palette store package trash pencil wallet-cards
cloud cloud-check refresh-cw log-out circle-user-round sun-moon languages
undo-2 cloud-off shopping-basket laptop users user fish bath flame wifi phone mic square-parking app-window footprints
""".split()


def main() -> None:
    icons_dir = sys.argv[1] if len(sys.argv) > 1 else "/tmp/lucide/icons"
    here = os.path.dirname(os.path.abspath(__file__))
    target = os.path.join(here, "..", "lib", "app", "lucide_icons.dart")
    lines = [
        "// GENERATED from lucide-icons/lucide (ISC License, https://lucide.dev). Do not edit by hand.",
        "// Only the icons Centwise uses are bundled; regenerate with scripts/gen_icons.py.",
        "",
        "const Map<String, String> lucideSvgs = {",
    ]
    for name in NAMES:
        with open(os.path.join(icons_dir, name + ".svg"), encoding="utf-8") as handle:
            svg = handle.read()
        body = re.search(r">(.*)</svg>", svg, re.S).group(1)
        body = re.sub(r"\s+", " ", body).strip().replace("'", "\\'")
        lines.append(f"  '{name}': '{body}',")
    lines.append("};")
    with open(target, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")
    print(f"wrote {len(NAMES)} icons to {os.path.normpath(target)}")


if __name__ == "__main__":
    main()
