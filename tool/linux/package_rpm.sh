#!/usr/bin/env bash
# Gera um pacote .rpm (Fedora/RHEL) a partir do bundle do Flutter.
#   bash package_rpm.sh --version 0.0.21 --bundle <dir> --dest <dist> --icon <png>
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
command -v rpmbuild >/dev/null || die "rpmbuild não encontrado (dnf install rpm-build)"
[[ -f "$ICON" ]] || die "ícone não encontrado: $ICON"

ARCH="$(arch_raw)"
TOP="$(mktemp -d)"
trap 'rm -rf "$TOP"' EXIT
mkdir -p "$TOP"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

DESKTOP="$TOP/$APP_NAME.desktop"
write_desktop_file "$DESKTOP"

SPEC="$TOP/SPECS/$APP_NAME.spec"
cat >"$SPEC" <<EOF
Name:       $APP_NAME
Version:    $VERSION
Release:    1
Summary:    $APP_DISPLAY - $APP_COMMENT
License:    $APP_LICENSE
URL:        $APP_HOMEPAGE
BuildArch:  $ARCH
AutoReqProv: no
Requires:   gtk3
Requires:   mpv-libs
Requires:   libepoxy

%description
Side by side, frame by frame. Desktop video comparator (libmpv/media_kit).

%prep
%build

%install
mkdir -p %{buildroot}/usr/lib/$APP_NAME
cp -a "$BUNDLE"/. %{buildroot}/usr/lib/$APP_NAME/
mkdir -p %{buildroot}/usr/bin
ln -sf /usr/lib/$APP_NAME/$APP_NAME %{buildroot}/usr/bin/$APP_NAME
mkdir -p %{buildroot}/usr/share/applications
install -m 0644 "$DESKTOP" %{buildroot}/usr/share/applications/$APP_NAME.desktop
mkdir -p %{buildroot}/usr/share/pixmaps
install -m 0644 "$ICON" %{buildroot}/usr/share/pixmaps/$APP_NAME.png

%files
/usr/lib/$APP_NAME
/usr/bin/$APP_NAME
/usr/share/applications/$APP_NAME.desktop
/usr/share/pixmaps/$APP_NAME.png

%changelog
EOF

rpmbuild -bb \
  --define "_topdir $TOP" \
  --define "_build_id_links none" \
  "$SPEC"

RPM_FILE="$(find "$TOP/RPMS" -name '*.rpm' | head -n 1)"
[[ -n "$RPM_FILE" ]] || die "rpmbuild não produziu nenhum .rpm"
mkdir -p "$DEST"
OUT="$DEST/${APP_NAME}-v${VERSION}-$(distro_id)-$(arch_modern).rpm"
cp -f "$RPM_FILE" "$OUT"
log "Artefacto: $OUT"
printf '%s\n' "$OUT"
