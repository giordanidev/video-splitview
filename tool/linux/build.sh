#!/usr/bin/env bash
# Compila o Video Splitview para Linux e gera o instalador nativo da distro
# (.deb no Ubuntu/Debian, .rpm no Fedora/RHEL) e, opcionalmente, um AppImage.
#
# Corre DENTRO do Linux (WSL, container ou máquina Linux):
#   bash tool/linux/build.sh
#   bash tool/linux/build.sh --with-appimage
#   bash tool/linux/build.sh --skip-setup --with-appimage --version 0.0.21
#
# No Windows usa-se tool/build_wsl_linux.ps1, que invoca este script dentro do WSL.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/_common.sh"

WITH_APPIMAGE=0
SKIP_SETUP=0
VERSION=""
DEST=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-appimage) WITH_APPIMAGE=1; shift ;;
    --skip-setup) SKIP_SETUP=1; shift ;;
    --version) VERSION="${2:-}"; shift 2 ;;
    --dest) DEST="${2:-}"; shift 2 ;;
    -h | --help) sed -n '2,10p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) die "Opção desconhecida: $1" ;;
  esac
done

DEST="${DEST:-$REPO_ROOT/dist}"
WORK="${VIDEO_SPLITVIEW_BUILD_DIR:-$HOME/video-splitview-build}"
FLUTTER_BIN="${FLUTTER_DIR:-$HOME/flutter}/bin"
ICON="$REPO_ROOT/assets/icon/video_splitview.png"

export PATH="$FLUTTER_BIN:$PATH"
command -v flutter >/dev/null || die "flutter não encontrado (corre primeiro tool/linux/setup_env.sh)."

# --- 1) Sincronizar o código para o filesystem Linux -------------------------
log "A sincronizar $REPO_ROOT -> $WORK"
mkdir -p "$WORK"
rsync -a --delete \
  --exclude '.git/' \
  --exclude 'build/' \
  --exclude '.dart_tool/' \
  --exclude 'dist/' \
  --exclude '.orchestrate/' \
  --exclude '.idea/' \
  "$REPO_ROOT"/ "$WORK"/
# Defensivo: o runner pode ter ficado com CRLF vindo do Windows.
find "$WORK/tool" -name '*.sh' -exec sed -i 's/\r$//' {} + 2>/dev/null || true

# --- 2) Provisionar, se necessário -------------------------------------------
if [[ "$SKIP_SETUP" -eq 0 ]]; then
  log "A garantir o toolchain (setup_env.sh)…"
  bash "$WORK/tool/linux/setup_env.sh"
fi

# --- 3) Versão ----------------------------------------------------------------
if [[ -z "$VERSION" ]]; then
  VERSION="$(sed -n "s/.*appVersion *= *'\([^']*\)'.*/\1/p" \
    "$WORK/lib/backend/generated/version.dart" | head -n 1)"
fi
[[ -n "$VERSION" ]] || VERSION="0.0.0"

log "Build Linux $(arch_raw) — versão $VERSION ($(distro_label))"

# --- 4) Compilar --------------------------------------------------------------
cd "$WORK"
flutter pub get
flutter build linux --release --build-name "$VERSION"

BUNDLE="$WORK/build/linux/x64/release/bundle"
[[ -d "$BUNDLE" ]] || die "Bundle não encontrado: $BUNDLE"
mkdir -p "$DEST"

# Normalizar RPATH (remove caminhos da pasta de build do Flutter).
log "A normalizar o RPATH do bundle…"
normalize_bundle_rpaths "$BUNDLE"

# --- 5) Instalador nativo da distro ------------------------------------------
case "$(distro_id)" in
  ubuntu | debian)
    bash "$WORK/tool/linux/package_deb.sh" \
      --version "$VERSION" --bundle "$BUNDLE" --dest "$DEST" --icon "$ICON"
    ;;
  fedora | rhel | centos)
    bash "$WORK/tool/linux/package_rpm.sh" \
      --version "$VERSION" --bundle "$BUNDLE" --dest "$DEST" --icon "$ICON"
    ;;
  *)
    warn "Sem instalador nativo para '$(distro_id)'; a saltar."
    ;;
esac

# --- 6) AppImage portátil (opcional) -----------------------------------------
if [[ "$WITH_APPIMAGE" -eq 1 ]]; then
  bash "$WORK/tool/linux/package_appimage.sh" \
    --version "$VERSION" --bundle "$BUNDLE" --dest "$DEST" --icon "$ICON"
fi

log "Concluído. Artefactos em $DEST"
