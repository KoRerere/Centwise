#!/bin/bash
# Regenerate App/LucideIcons.swift from the Lucide release pinned in scripts/lucide/VERSION,
# using the icon names listed in scripts/lucide/icons.txt. Needs git and python3 (Xcode CLT).
#   bash scripts/update-lucide.sh            # pinned version
#   bash scripts/update-lucide.sh 1.57.0     # switch to another release and pin it
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
lucide_dir="$project_root/scripts/lucide"
version="${1:-$(tr -d '[:space:]' < "$lucide_dir/VERSION")}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$version" \
  --filter=blob:none --no-checkout https://github.com/lucide-icons/lucide "$work/lucide"
git -C "$work/lucide" sparse-checkout set --no-cone '/icons/*.svg' '/LICENSE'
git -C "$work/lucide" checkout --quiet
printf '%s\n' "$version" > "$work/lucide/.lucide-version"

python3 "$lucide_dir/generate.py" "$work/lucide" "$lucide_dir/icons.txt" "$project_root/App/LucideIcons.swift"
cp "$work/lucide/LICENSE" "$lucide_dir/LICENSE"
printf '%s\n' "$version" > "$lucide_dir/VERSION"
printf 'Lucide %s ready. Rebuild the app to pick up the icons.\n' "$version"
