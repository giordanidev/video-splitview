#!/bin/bash
# Compila o libmpv do Windows (mingw-w64) com o codec set COMPLETO do FFmpeg.
#
# Porque é preciso: o `media_kit_libs_windows_video` embute um libmpv cujo
# FFmpeg foi compilado com `--disable-decoders/--disable-demuxers` e depois
# reativado só com uma whitelist (~67 decoders / ~50 demuxers). Ficam de fora
# Bink, ProRes, DNxHD, DV, 10-bit, MXF, image2, VobSub, VC-1, WMV, MPEG-4 ASP,
# DivX/MVC, Indeo, VP3/5/7, Cinepak, FlashSV e os codecs legados QuickTime.
# O DLL gerado aqui é LGPL (todos os componentes nativos do FFmpeg são LGPL) e
# autossuficiente: liga estaticamente contra as libs do MSYS2.
#
# Requer MSYS2 (https://www.msys2.org) com o toolchain MINGW64. Correr via
# `powershell -ExecutionPolicy Bypass -File tool/build_libmpv_windows.ps1`.
set -euo pipefail
export MSYSTEM=MINGW64
export PATH="/mingw64/bin:$PATH"

ROOT=${LIBMPV_BUILD_ROOT:-/f/libmpv-build}
FFMPEG=$ROOT/ffmpeg
MPV=$ROOT/mpv
ANGLE=$ROOT/angle
FFMPEG_PREFIX=/opt/ffmpeg-mpv
MPV_PREFIX=/opt/mpv
JOBS=${JOBS:-12}

mkdir -p "$ROOT/logs"
exec > >(tee "$ROOT/logs/build_libmpv.log") 2>&1

step() { echo; echo "############ $* ############"; date '+%Y-%m-%d %H:%M:%S'; }

# ---------------------------------------------------------------------------
step "0/4 dependências MSYS2 (pacman)"
missing=0
for p in gcc pkgconf meson ninja python gperf nasm \
         libplacebo dav1d libass harfbuzz freetype fribidi libiconv \
         opus speex libvorbis libsoxr libmysofa zimg libwebp libbs2b \
         libpng libjpeg-turbo bzip2 gmp lame mbedtls libxmlvulkan-headers; do
  if [ "$p" = "libxmlvulkan-headers" ]; then
    pacman -Qi mingw-w64-x86_64-vulkan-headers >/dev/null 2>&1 || missing=1
  elif ! pacman -Qi "mingw-w64-x86_64-$p" >/dev/null 2>&1; then
    echo "em falta: mingw-w64-x86_64-$p"
    missing=1
  fi
done
if [ "$missing" = "1" ]; then
  echo "A instalar pacotes em falta..."
  pacman -S --noconfirm --needed \
    mingw-w64-x86_64-gcc mingw-w64-x86_64-pkgconf mingw-w64-x86_64-meson \
    mingw-w64-x86_64-ninja mingw-w64-x86_64-python mingw-w64-x86_64-gperf \
    mingw-w64-x86_64-nasm mingw-w64-x86_64-libplacebo mingw-w64-x86_64-dav1d \
    mingw-w64-x86_64-libass mingw-w64-x86_64-harfbuzz \
    mingw-w64-x86_64-freetype mingw-w64-x86_64-fribidi \
    mingw-w64-x86_64-libiconv mingw-w64-x86_64-opus mingw-w64-x86_64-speex \
    mingw-w64-x86_64-libvorbis mingw-w64-x86_64-libsoxr \
    mingw-w64-x86_64-libmysofa mingw-w64-x86_64-zimg \
    mingw-w64-x86_64-libwebp mingw-w64-x86_64-libbs2b \
    mingw-w64-x86_64-libpng mingw-w64-x86_64-libjpeg-turbo \
    mingw-w64-x86_64-bzip2 mingw-w64-x86_64-gmp mingw-w64-x86_64-lame \
    mingw-w64-x86_64-mbedtls mingw-w64-x86_64-libxml2 \
    mingw-w64-x86_64-vulkan-headers
fi

# ---------------------------------------------------------------------------
step "1/4 headers EGL/KHR do ANGLE (obrigatórios para mpv no Windows)"
if [ ! -d "$ANGLE/include/EGL" ]; then
  rm -rf "$ANGLE"
  git clone --depth 1 --filter=blob:none --sparse https://github.com/google/angle.git "$ANGLE"
  git -C "$ANGLE" sparse-checkout set include/EGL include/KHR
fi
for d in EGL KHR; do
  if [ -d "/mingw64/include/$d" ] && [ ! -d "/mingw64/include/$d.msys-backup" ]; then
    mv "/mingw64/include/$d" "/mingw64/include/$d.msys-backup"
  fi
  rm -rf "/mingw64/include/$d"
  cp -r "$ANGLE/include/$d" "/mingw64/include/$d"
done
# O ANGLE actual removeu este token, ainda referenciado pelo codigo do mpv
# 0.38 (caminho morto: o app usa D3D11/ANGLE, nao D3D9).
if ! grep -q EGL_PLATFORM_ANGLE_TYPE_D3D9_ANGLE /mingw64/include/EGL/eglext_angle.h; then
  cat >> /mingw64/include/EGL/eglext_angle.h <<'EOF'

/* Compat shim: removido no ANGLE actual, ainda usado pelo codigo do mpv. */
#ifndef EGL_PLATFORM_ANGLE_TYPE_D3D9_ANGLE
#define EGL_PLATFORM_ANGLE_TYPE_D3D9_ANGLE 0x00020003
#endif
EOF
fi

# ---------------------------------------------------------------------------
step "2/4 FFmpeg (sem whitelist: todos os demuxers/decoders/parsers/encoders)"
if [ ! -d "$FFMPEG" ]; then
  git clone --depth 1 --branch n7.1.1 https://github.com/FFmpeg/FFmpeg.git "$FFMPEG"
fi
cd "$FFMPEG"
if [ ! -f ffbuild/config.mak ]; then
  ./configure \
    --prefix="$FFMPEG_PREFIX" \
    --pkg-config=pkg-config \
    --pkg-config-flags=--static \
    --extra-cflags="-I/mingw64/include" \
    --extra-ldflags="-L/mingw64/lib" \
    --extra-libs="-lbcrypt -luserenv -lole32 -lws2_32 -lshlwapi" \
    --arch=x86_64 \
    --target-os=mingw32 \
    --disable-gpl \
    --disable-nonfree \
    --enable-version3 \
    --enable-static \
    --disable-shared \
    --enable-pic \
    --disable-doc \
    --disable-debug \
    --disable-programs \
    --disable-stripping \
    --enable-optimizations \
    --enable-runtime-cpudetect \
    --enable-small \
    --enable-network \
    --disable-muxers \
    --disable-filters \
    --enable-filter=overlay \
    --enable-filter=equalizer \
    --disable-protocols \
    --enable-protocol=async \
    --enable-protocol=cache \
    --enable-protocol=crypto \
    --enable-protocol=data \
    --enable-protocol=file \
    --enable-protocol=pipe \
    --enable-protocol=subfile \
    --enable-bsfs \
    --enable-hwaccels \
    --enable-d3d11va \
    --enable-dxva2 \
    --enable-zlib \
    --enable-bzlib \
    --enable-gmp \
    --enable-libmp3lame \
    --enable-libopus \
    --enable-libvorbis \
    --enable-libsoxr \
    --enable-libspeex \
    --enable-libmysofa \
    --enable-libfreetype \
    --enable-libfribidi \
    --enable-libharfbuzz \
    --enable-libwebp \
    --enable-libzimg \
    --enable-libbs2b \
    --enable-mbedtls \
    --enable-libdav1d \
    --enable-libvpx
fi
make -j"$JOBS"
make install

# ---------------------------------------------------------------------------
step "3/4 libmpv (libmpv-2.dll)"
if [ ! -d "$MPV" ]; then
  git clone --depth 1 --branch v0.38.0 https://github.com/mpv-player/mpv.git "$MPV"
fi
cd "$MPV"
rm -rf build

MESON_OPTS=(
  --prefix="$MPV_PREFIX"
  --libdir=lib
  --default-library=shared
  --prefer-static
  -Doptimization=3
  -Db_ndebug=true
  -Db_lto=false
  -Dgpl=false
  -Dlibmpv=true
  -Dbuild-date=false
  -Dtests=false
  -Dlua=disabled
  -Dcplayer=false
  -Dcplugins=disabled
  -Djavascript=disabled
  -Dvapoursynth=disabled
  -Dlibarchive=disabled
  -Dcdda=disabled
  -Dpdf-build=disabled
  -Dhtml-build=disabled
  -Dmanpage-build=disabled
  -Dopenal=disabled
  -Ddirect3d=disabled
  -Dshaderc=disabled
  -Dspirv-cross=disabled
  -Dvulkan=enabled
  -Degl-angle=enabled
  -Ddrm=disabled
  -Dgl-x11=disabled
  -Dx11=disabled
  -Dwayland=disabled
  -Doss-audio=disabled
  -Dpulse=disabled
  -Dalsa=disabled
  -Djack=disabled
)

PKG_CONFIG_PATH="$FFMPEG_PREFIX/lib/pkgconfig" \
LDFLAGS="-L/mingw64/lib -static-libgcc -static-libstdc++" \
meson setup build "${MESON_OPTS[@]}"
ninja -C build

# ---------------------------------------------------------------------------
step "4/4 copiar para third_party/libmpv/windows-x64"
DLL=$(find "$MPV/build" -name 'libmpv-2.dll' | head -1)
[ -n "$DLL" ] || { echo "libmpv-2.dll nao encontrado"; exit 1; }
echo "origem: $DLL"
objdump -p "$DLL" | grep 'DLL Name' || true

# O repo (ou o proprio script, se estiver a correr de dentro dele).
DEST=""
for cand in "$OLDPWD/third_party/libmpv/windows-x64" "/f/giordanidev/video-splitview/third_party/libmpv/windows-x64"; do
  if [ -d "$(dirname "$(dirname "$cand")")" ]; then DEST="$cand"; break; fi
done
[ -n "$DEST" ] || { echo "destino nao encontrado"; exit 1; }
mkdir -p "$DEST"
cp "$DLL" "$DEST/libmpv-2.dll"
# Dependencias de runtime que o MSYS2 fornece como DLL separada.
for extra in libwinpthread-1.dll libshaderc_shared.dll; do
  src=$(ls /mingw64/bin/"$extra" 2>/dev/null || true)
  [ -n "$src" ] && cp "$src" "$DEST/$extra" && echo "copiado: $extra"
done
ls -la "$DEST"
echo "=== BUILD LIBMPV OK ==="
