#!/usr/bin/env bash
# Gera um pacote .deb (Ubuntu/Debian) a partir do bundle do Flutter.
#   bash package_deb.sh --version 0.0.21 --bundle <dir> --dest <dist> --icon <png>
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
command -v dpkg-deb >/dev/null || die "dpkg-deb não encontrado (apt install dpkg-dev)"

ARCH="$(arch_deb)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ROOT="$STAGE/${APP_NAME}_${VERSION}_${ARCH}"

mkdir -p "$ROOT/DEBIAN" \
  "$ROOT/usr/lib/$APP_NAME" \
  "$ROOT/usr/bin" \
  "$ROOT/usr/share/applications" \
  "$ROOT/usr/share/pixmaps" \
  "$ROOT/usr/share/doc/$APP_NAME"

cp -a "$BUNDLE/." "$ROOT/usr/lib/$APP_NAME/"
ln -sf "/usr/lib/$APP_NAME/$APP_NAME" "$ROOT/usr/bin/$APP_NAME"

write_desktop_file "$ROOT/usr/share/applications/$APP_NAME.desktop"
[[ -f "$ICON" ]] && cp "$ICON" "$ROOT/usr/share/pixmaps/$APP_NAME.png"

cat >"$ROOT/usr/share/doc/$APP_NAME/copyright" <<EOF
Copyright (c) Giordani Sarturi
Licença: $APP_LICENSE
EOF

INSTALLED_KB="$(du -sk "$ROOT/usr" | cut -f1)"
cat >"$ROOT/DEBIAN/control" <<EOF
Package: $APP_NAME
Version: $VERSION
Architecture: $ARCH
Maintainer: $APP_MAINTAINER
Installed-Size: $INSTALLED_KB
Section: video
Priority: optional
Homepage: $APP_HOMEPAGE
Depends: libgtk-3-0 | libgtk-3-0t64, libmpv2 | libmpv1, libepoxy0, libglib2.0-0 | libglib2.0-0t64
Description: $APP_DISPLAY - $APP_COMMENT
 Side by side, frame by frame. Desktop video comparator (libmpv/media_kit).
EOF

mkdir -p "$DEST"
OUT="$DEST/${APP_NAME}-v${VERSION}-$(distro_id)-$(arch_modern).deb"
rm -f "$OUT"
dpkg-deb --build --root-owner-group "$ROOT" "$OUT" >/dev/null
log "Artefacto: $OUT"
printf '%s\n' "$OUT"
