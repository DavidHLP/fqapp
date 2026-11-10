#!/usr/bin/env bash
# Package a trusted release bundle, without rebuilding or launching the app.
set -euo pipefail
if [[ $# != 3 ]]; then
  echo "Usage: $0 BUNDLE NEW_OUTPUT_DIR BUNDLE_SOURCE_COMMIT" >&2
  exit 2
fi
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
bundle=$(realpath -e -- "$1")
output=$(realpath -m -- "$2")
revision=$(git -C "$root" rev-parse --verify --end-of-options "$3^{commit}")
[[ $bundle != / && $output != / && ! -e $output ]]
case "$output/" in "$bundle/"*) echo 'Output must be outside bundle' >&2; exit 2;; esac
for tool in makepkg patchelf python tar zstd readelf ldd desktop-file-validate; do
  command -v "$tool" >/dev/null
done
mkdir -m755 -- "$output"
stage="$output/payload/fqapp"
mkdir -p -- "$stage/build/linux/x64/release/bundle" "$stage/packaging"
# Reject escaping links before copying or modifying anything from the bundle.
if [[ -n $(find "$bundle" -type l -print -quit) ]]; then
  echo 'Bundle symlinks require review' >&2; exit 2
fi
cp -a -- "$bundle/." "$stage/build/linux/x64/release/bundle/"
cp -r -- "$root/packaging/arch" "$stage/packaging/"
cp -- "$root/LICENSE" "$root/LINUX.md" "$stage/"
python "$root/packaging/arch/prepare_bundle.py" "$stage/build/linux/x64/release/bundle" > "$output/elf-report.txt"
desktop-file-validate "$stage/packaging/arch/com.fqapp.fqapp.desktop"
: "${FLUTTER_ROOT:?Set FLUTTER_ROOT to Flutter 3.47.9 for its license notices}"
licenses="$stage/build/linux/x64/release/bundle/licenses"
mkdir -p -- "$licenses"
cp -- "$root/LICENSE" "$licenses/"
cp -r -- "$root/assets/fonts/"*OFL* "$root/assets/licenses" "$licenses/"
cp -- "$FLUTTER_ROOT/bin/cache/artifacts/engine/linux-x64/"LICENSE* "$licenses/"
{
  echo "bundle_source_commit=$revision"
  echo "packaging_commit=$(git -C "$root" rev-parse HEAD)"
  echo 'status=draft; GUI/account/license/recovery acceptance pending'
  cat -- "$FLUTTER_ROOT/bin/cache/flutter.version.json"
  rustc --version
  echo "arch_repository_policy=local installed package set; see pacman manifest"
  pacman -Q
} > "$output/build-manifest.txt"
cp -- "$output/build-manifest.txt" "$stage/build/linux/x64/release/bundle/"
tar --zstd -cf "$output/fqapp-bundle.tar.zst" -C "$output/payload" fqapp
python - "$root" "$output" "$revision" <<'PY'
import hashlib, pathlib, re, subprocess, sys
root, output = map(pathlib.Path, sys.argv[1:3])
recipe = (root / 'packaging/arch/PKGBUILD').read_text()
version = re.search(r'^version: ([^+\s]+)', subprocess.check_output(
    ['git', '-C', str(root), 'show', sys.argv[3] + ':pubspec.yaml'], text=True), re.M)[1]
assert re.fullmatch(r'[0-9]+(?:\.[0-9]+)+', version)
recipe = re.sub(r'^pkgver=.*', 'pkgver=' + version, recipe, flags=re.M)
recipe = recipe[:recipe.index('\nbuild() {')] + recipe[recipe.index('\npackage() {'):]
recipe = recipe.replace('fqapp-source.tar.zst', 'fqapp-bundle.tar.zst')
recipe = re.sub(r'makedepends=\([\s\S]*?\)\n', '', recipe)
recipe = recipe.replace('0000000000000000000000000000000000000000000000000000000000000000', hashlib.file_digest(
    (output / 'fqapp-bundle.tar.zst').open('rb'), 'sha256').hexdigest())
(output / 'PKGBUILD').write_text(recipe)
PY
(cd -- "$output" && makepkg --nodeps --noconfirm)
# --nodeps permits packaging on a prepared host without installing any packages.
# It is NOT proof of clean-machine dependency satisfaction.
(cd -- "$output" && makepkg --printsrcinfo > .SRCINFO)
printf 'Draft package and evidence: %s\n' "$output"
