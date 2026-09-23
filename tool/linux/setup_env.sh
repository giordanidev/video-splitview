#!/usr/bin/env bash
# Provisiona uma distro WSL (Ubuntu/Debian ou Fedora/RHEL) para compilar o
# Video Splitview para Linux (Flutter desktop + libmpv via media_kit).
#
# Idempotente: pode correr as vezes que forem precisas.
#   bash tool/linux/setup_env.sh
#   FLUTTER_VERSION=3.47.5 bash tool/linux/setup_env.sh
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.47.5}"
FLUTTER_DIR="${FLUTTER_DIR:-$HOME/flutter}"

log() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }

if [[ "$(id -u)" -eq 0 ]]; then
  SUDO=""
elif sudo -n true 2>/dev/null; then
  SUDO="sudo"
else
  warn "Sem sudo sem password: vais ser pedido a password."
  SUDO="sudo"
fi

os_id=""
os_ver=""
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  os_id="${ID:-}"
  os_ver="${VERSION_ID:-}"
fi

install_deps() {
  case "$os_id" in
    ubuntu | debian)
      log "A instalar dependências de build (apt)…"
      $SUDO apt-get update
      $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y \
        clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev \
        g++ git curl ca-certificates xz-utils rsync zip unzip file \
        libmpv-dev libepoxy-dev libsecret-1-dev dpkg-dev patchelf
      ;;
    fedora | rhel | centos)
      log "A instalar dependências de build (dnf)…"
      $SUDO dnf install -y \
        clang cmake ninja-build pkgconf-pkg-config gtk3-devel xz-devel \
        gcc-c++ git curl ca-certificates xz rsync zip unzip file \
        mpv-devel libepoxy-devel libsecret-devel rpm-build patchelf
      ;;
    *)
      warn "Distro '$os_id' não reconhecida. Garante: clang, cmake, ninja, pkg-config, GTK3 dev."
      ;;
  esac
}

install_flutter() {
  if [[ -x "$FLUTTER_DIR/bin/flutter" ]]; then
    log "Flutter já existe em $FLUTTER_DIR"
  else
    log "A clonar o Flutter $FLUTTER_VERSION (shallow) em $FLUTTER_DIR…"
    git clone --depth 1 --branch "$FLUTTER_VERSION" \
      https://github.com/flutter/flutter.git "$FLUTTER_DIR" ||
      {
        warn "Clone por tag falhou; a tentar o canal stable."
        git clone --depth 1 --branch stable \
          https://github.com/flutter/flutter.git "$FLUTTER_DIR"
      }
  fi

  export PATH="$FLUTTER_DIR/bin:$PATH"
  git config --global --add safe.directory "$FLUTTER_DIR" 2>/dev/null || true

  log "A configurar o desktop Linux e a pré-buscar o motor…"
  flutter --disable-analytics >/dev/null 2>&1 || true
  flutter config --enable-linux-desktop >/dev/null
  flutter precache --linux
}

install_deps
install_flutter

log "Versão: $(flutter --version | head -n 1)"
log "Doctor (Linux):"
flutter doctor -v | sed -n '/Linux toolchain/,/^$/p' || true

# Ferramenta de AppImage (fica em cache para os empacotamentos).
# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
log "appimagetool: $(ensure_appimagetool)"

log "Ambiente pronto em $os_id $os_ver."
