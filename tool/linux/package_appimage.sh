#!/usr/bin/env bash
# Gera um AppImage portátil a partir do bundle do Flutter.
# O libmpv e o seu fecho de dependências vão embutidos; GTK/X11/GL vêm do host.
#   bash package_appimage.sh --version 0.0.21 --bundle <dir> --dest <dist> --icon <png>
set -euo pipefail
# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

VERSION="" BUNDLE="" DEST="" ICON=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="${2:-}"; shift 2 ;;
    --bundle) BUNDLE="${2:-}"; shift 2 ;;
    --dest) DEST="${2:-}"; shift 2 ;;
    --icon) ICON="${2:-}"; shift 2 ;;
    *) die "Opção desconhecida: $1" ;;
  esac
done
[[ -n "$VERSION" && -d "$BUNDLE" && -n "$DEST" ]] || die "faltam --version/--bundle/--dest"
[[ -f "$ICON" ]] || die "ícone não encontrado: $ICON"

ARCH="$(arch_raw)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
APPDIR="$STAGE/$APP_NAME.AppDir"

mkdir -p "$APPDIR/usr/lib/$APP_NAME" \
  "$APPDIR/usr/bin" \
  "$APPDIR/usr/share/applications" \
  "$APPDIR/usr/share/icons/hicolor/256x256/apps"

cp -a "$BUNDLE/." "$APPDIR/usr/lib/$APP_NAME/"
ln -sf "../lib/$APP_NAME/$APP_NAME" "$APPDIR/usr/bin/$APP_NAME"

# Ficheiros obrigatórios na raiz do AppDir.
cp "$ICON" "$APPDIR/$APP_NAME.png"
cp "$ICON" "$APPDIR/usr/share/icons/hicolor/256x256/apps/$APP_NAME.png"
write_desktop_file "$APPDIR/$APP_NAME.desktop"
cp "$APPDIR/$APP_NAME.desktop" "$APPDIR/usr/share/applications/$APP_NAME.desktop"

cat >"$APPDIR/AppRun" <<'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$HERE/usr/lib/video-splitview/lib:$HERE/usr/lib:${LD_LIBRARY_PATH:-}"
exec "$HERE/usr/lib/video-splitview/video-splitview" "$@"
EOF
chmod +x "$APPDIR/AppRun"

# Embutir o libmpv e o respetivo fecho de dependências.
log "A recolher dependências do libmpv…" >&2
mapfile -t seed < <(
  printf '%s\n' "$APPDIR/usr/lib/$APP_NAME/$APP_NAME"
  find "$APPDIR/usr/lib/$APP_NAME/lib" -name '*.so*' -type f 2>/dev/null
)
bundle_lib_deps "$APPDIR/usr/lib/$APP_NAME/lib" "${seed[@]}"

TOOL="$(ensure_appimagetool)"
mkdir -p "$DEST"
OUT="$DEST/${APP_NAME}-v${VERSION}-linux-$(arch_modern).AppImage"
rm -f "$OUT"
ARCH="$ARCH" APPIMAGE_EXTRACT_AND_RUN=1 "$TOOL" "$APPDIR" "$OUT"
chmod +x "$OUT"
log "Artefacto: $OUT"
printf '%s\n' "$OUT"
