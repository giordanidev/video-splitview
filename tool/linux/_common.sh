#!/usr/bin/env bash
# Helpers partilhados pelos scripts de build/empacotamento Linux do Video Splitview.
# Não executar diretamente: cada script faz `source _common.sh`.
set -euo pipefail

log() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

_LINUX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$_LINUX_DIR/../.." && pwd)"

APP_NAME="video-splitview"
APP_DISPLAY="Video Splitview"
APP_COMMENT="Side by side, frame by frame. (libmpv)"
APP_CATEGORIES="AudioVideo;Video;Player;"
APP_MAINTAINER="Giordani Sarturi <giordanisarturi@gmail.com>"
APP_HOMEPAGE="https://github.com/giordanidev/video-splitview"
APP_LICENSE="MIT"

# --- Distro / arquitetura ----------------------------------------------------

distro_id() {
  # shellcheck disable=SC1091
  ( . /etc/os-release; printf '%s' "${ID:-linux}" )
}

distro_label() {
  # shellcheck disable=SC1091
  ( . /etc/os-release; printf '%s%s' "${ID:-linux}" "${VERSION_ID:-}" )
}

arch_deb() {
  case "$(uname -m)" in
    x86_64) echo amd64 ;;
    aarch64) echo arm64 ;;
    *) uname -m ;;
  esac
}

arch_raw() { uname -m; }

# Arquitetura no padrão dos artefactos (x86_64 -> x64, aarch64 -> arm64).
arch_modern() {
  case "$(uname -m)" in
    x86_64) echo x64 ;;
    aarch64) echo arm64 ;;
    *) uname -m ;;
  esac
}

# --- appimagetool ------------------------------------------------------------

ensure_appimagetool() {
  local arch dir tool
  arch="$(arch_raw)"
  dir="${VIDEO_SPLITVIEW_CACHE:-$HOME/.cache/video-splitview}"
  tool="$dir/appimagetool-$arch.AppImage"
  if [[ ! -x "$tool" ]]; then
    mkdir -p "$dir"
    log "A descarregar appimagetool ($arch)…" >&2
    local urls=(
      "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$arch.AppImage"
      "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-$arch.AppImage"
    )
    local ok=0 url
    for url in "${urls[@]}"; do
      if curl -fL --retry 3 -sS "$url" -o "$tool"; then ok=1; break; fi
      warn "Falhou: $url"
    done
    [[ "$ok" -eq 1 ]] || die "Não consegui descarregar o appimagetool."
    chmod +x "$tool"
  fi
  printf '%s' "$tool"
}

# --- Empacotamento: ficheiros comuns -----------------------------------------

write_desktop_file() {
  local target="$1"
  cat >"$target" <<EOF
[Desktop Entry]
Type=Application
Name=$APP_DISPLAY
Comment=$APP_COMMENT
Exec=$APP_NAME
Icon=$APP_NAME
Terminal=false
Categories=$APP_CATEGORIES
EOF
}

# Reescreve o RPATH do bundle para caminhos relativos ($ORIGIN), removendo
# referências à pasta temporária de build do Flutter (que o `check-rpaths` do
# RPM rejeita e que seriam inválidas depois de instalado).
normalize_bundle_rpaths() {
  local bundle="$1"
  if ! command -v patchelf >/dev/null; then
    warn "patchelf não encontrado; a manter o RPATH original do bundle."
    return 0
  fi
  [[ -f "$bundle/$APP_NAME" ]] &&
    patchelf --set-rpath '$ORIGIN/lib' "$bundle/$APP_NAME" 2>/dev/null || true
  local libdir="$bundle/lib" f
  [[ -d "$libdir" ]] || return 0
  for f in "$libdir"/*.so; do
    [[ -e "$f" ]] || continue
    [[ "$(basename "$f")" == "libapp.so" ]] && continue
    patchelf --set-rpath '$ORIGIN' "$f" 2>/dev/null || true
  done
}

# --- AppImage: empacotar o fecho de dependências do libmpv -------------------

is_excluded_lib() {
  case "$1" in
    ld-linux* | linux-vdso* | libc.so* | libm.so* | libpthread* | libdl.so* | \
      librt.so* | libgcc_s* | libstdc++* | libnsl* | libresolv* | libutil* | \
      libanl*) return 0 ;;
    libGL* | libEGL* | libGLX* | libGLdispatch* | libOpenGL* | libgbm* | \
      libdrm* | libvulkan* | libwayland* | libX*.so* | libxcb* | libxkb* | \
      libxshmfence* | libexpat* | libz.so*) return 0 ;;
    libgtk* | libgdk* | libglib* | libgobject* | libgio* | libgmodule* | \
      libpango* | libcairo* | libatk* | libharfbuzz* | libfontconfig* | \
      libfreetype* | libpixman* | libfribidi* | libepoxy* | libgraphite* | \
      libthai* | libdatrie* | libselinux* | libpcre* | libffi* \
      ) return 0 ;;
    libasound* | libpulse* | libpipewire* | libjack* | libvdpau* | libva*) return 0 ;;
    *) return 1 ;;
  esac
}

# Copia para $1 (libdir) o fecho das dependências de $2.. (binários/.so),
# excluindo bibliotecas de sistema/gráficas/áudio que devem vir do host.
bundle_lib_deps() {
  local libdir="$1"
  shift
  [[ $# -gt 0 ]] || return 0
  mkdir -p "$libdir"

  local queue=("$@")
  while [[ ${#queue[@]} -gt 0 ]]; do
    local obj="${queue[0]}"
    queue=("${queue[@]:1}")
    [[ -e "$obj" ]] || continue
    local line path base
    while IFS= read -r line; do
      path="$(printf '%s' "$line" | sed -n 's/.*=> \(\/[^ ]*\).*/\1/p')"
      if [[ -z "$path" ]]; then
        path="$(printf '%s' "$line" | sed -n 's#^[[:space:]]*\(/[^ ]*\).*#\1#p')"
      fi
      [[ -n "$path" ]] || continue
      base="$(basename "$path")"
      is_excluded_lib "$base" && continue
      if [[ ! -e "$libdir/$base" ]]; then
        cp -fL "$path" "$libdir/$base"
        queue+=("$libdir/$base")
      fi
    done < <(ldd "$obj" 2>/dev/null || true)
  done
}
