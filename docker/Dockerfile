# OmnibandTk — imagen de dependencias para la prueba de concepto (Fase 1).
#
# Esta imagen NO compila el juego: hornea la parte lenta y estable (toolchain +
# Tcl/Tk 8.6.16 compilado desde fuente + treectrl 2.4.1). El juego se compila
# aparte montando el repo (ver docker/build.sh), para poder iterar rápido.
#
# Modernizacion (2026-06): subido de Tcl/Tk 8.5.7 -> 8.6.16 y treectrl 2.2.9 ->
# 2.4.1. Se mantiene la compilacion desde fuente porque CMake necesita los headers
# internos (tkInt.h). El uso de API interna es superficial; des-vendar (usar
# Tcl/Tk 8.6 del sistema) es un paso posterior.
#
# Base: Debian 12 (bookworm) -> gcc 12 y cmake 3.25, que aún acepta
# CMAKE_MINIMUM_REQUIRED(VERSION 2.6) y trata las construcciones C antiguas
# (implicit-int, implicit function decl) como warnings, no errores.
# Imagen base fijada por digest (no solo por tag): el tag "12-slim" flota con cada
# point release de Debian; el digest la ancla a un contenido exacto y reproducible.
FROM debian:12-slim@sha256:0104b334637a5f19aa9c983a91b54c89887c0984081f2068983107a6f6c21eeb

# Componentes vendados, fijados por versión + commit. Los SHA256 de los tarballs se
# verifican tras descargar (ver más abajo): un pin de versión sin checksum no protege
# si el origen cambia el contenido o desaparece.
ARG TCL_VER=8.6.16
ARG TREECTRL_VER=2.4.1
ARG TKHTML_SHA=e6bf0ab04a8cf967452283be23533154c1982978
ARG TCL_SHA256=91cb8fa61771c63c262efb553059b7c7ad6757afa5857af6265e4b0bdc2a14a5
ARG TK_SHA256=be9f94d3575d4b3099d84bc3c10de8994df2d7aa405208173c709cc404a7e5fe
ARG TREECTRL_SHA256=c2d19cfc7ce8b150cb50a6b63dc6327c91fb71f76b4f2947e0334a15d5f869d3
ARG TKHTML_SHA256=31fea50d99276f70373014c047e8574eb080626f37220600f16e3dfb81f38d79
ARG PREFIX=/opt/tcltk8616
ARG SRCDIR=/opt/src

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        make \
        curl \
        ca-certificates \
        zlib1g-dev \
        libx11-dev \
        libxext-dev \
        libxft-dev \
        libxss-dev \
        libfontconfig1-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR ${SRCDIR}

# --- Tcl (desde fuente; conservamos el árbol: CMake necesita sus headers internos) ---
RUN curl -fsSL -o tcl.tar.gz \
      "https://downloads.sourceforge.net/project/tcl/Tcl/${TCL_VER}/tcl${TCL_VER}-src.tar.gz" \
    && echo "${TCL_SHA256}  tcl.tar.gz" | sha256sum -c - \
    && tar xzf tcl.tar.gz && rm tcl.tar.gz \
    && cd tcl${TCL_VER}/unix \
    && ./configure --prefix=${PREFIX} --enable-shared CFLAGS="-fcommon -w" \
    && make -j"$(nproc)" \
    && make install

# --- Tk (contra el Tcl recién compilado) ---
RUN curl -fsSL -o tk.tar.gz \
      "https://downloads.sourceforge.net/project/tcl/Tcl/${TCL_VER}/tk${TCL_VER}-src.tar.gz" \
    && echo "${TK_SHA256}  tk.tar.gz" | sha256sum -c - \
    && tar xzf tk.tar.gz && rm tk.tar.gz \
    && cd tk${TCL_VER}/unix \
    && ./configure --prefix=${PREFIX} --enable-shared \
         --with-tcl=${SRCDIR}/tcl${TCL_VER}/unix CFLAGS="-fcommon -w" \
    && make -j"$(nproc)" \
    && make install

# --- treectrl (solo necesitamos sus headers para compilar treectrl.c) ---
RUN curl -fsSL -o treectrl.tar.gz \
      "https://downloads.sourceforge.net/project/tktreectrl/tktreectrl/tktreectrl-${TREECTRL_VER}/tktreectrl-${TREECTRL_VER}.tar.gz" \
    && echo "${TREECTRL_SHA256}  treectrl.tar.gz" | sha256sum -c - \
    && tar xzf treectrl.tar.gz && rm treectrl.tar.gz \
    && cd tktreectrl-${TREECTRL_VER} \
    && ./configure \
         --prefix=${PREFIX} --exec-prefix=${PREFIX} \
         --with-tcl=${PREFIX}/lib --with-tk=${PREFIX}/lib \
         --with-tclinclude=${SRCDIR}/tcl${TCL_VER}/generic \
         --with-tkinclude=${SRCDIR}/tk${TCL_VER}/generic \
         CFLAGS="-fcommon -w" \
    && make -j"$(nproc)" \
    && make install

# --- Tkhtml 3.0 (mirror Debian-astro de olebole; declara versión 3.0 y compila
#     en sistemas modernos). Necesario en la creación de personaje (birth).
#     Fijado por commit (TKHTML_SHA), NO por la rama "main": main es la punta móvil
#     del repo y descargarla haría el build no reproducible (cambiaría o se rompería
#     sin tocar nada aquí). El tarball por SHA de commit es inmutable.
#     -DNDEBUG: desactiva los assert() de depuración de Tkhtml3 (en concreto
#     CHECK_INTEGER_PLAUSIBILITY en htmllayout.h, que aborta si una coordenada
#     de layout supera 10M; salta p.ej. en la pantalla de birth de ZAngbandTk).
#     Es el comportamiento de un build release; sin él el juego cae con SIGABRT. ---
RUN curl -fsSL -o tkhtml.tar.gz \
      "https://github.com/olebole/tkhtml3/archive/${TKHTML_SHA}.tar.gz" \
    && echo "${TKHTML_SHA256}  tkhtml.tar.gz" | sha256sum -c - \
    && tar xzf tkhtml.tar.gz && rm tkhtml.tar.gz \
    && cd tkhtml3-${TKHTML_SHA} \
    && chmod +x configure \
    && sh configure \
         --prefix=${PREFIX} --exec-prefix=${PREFIX} \
         --with-tcl=${PREFIX}/lib --with-tk=${PREFIX}/lib \
         --with-tclinclude=${SRCDIR}/tcl${TCL_VER}/generic \
         --with-tkinclude=${SRCDIR}/tk${TCL_VER}/generic \
         CFLAGS="-fcommon -w -DNDEBUG" \
    && make -j"$(nproc)" \
    && make install

# Runtime headless: servidor X virtual + fuentes (para validar el arranque de la GUI)
RUN apt-get update && apt-get install -y --no-install-recommends \
        xvfb \
        xauth \
        xfonts-base \
        fonts-dejavu-core \
        imagemagick \
        x11vnc \
        fluxbox \
        novnc \
        websockify \
        zip \
        unzip \
    && rm -rf /var/lib/apt/lists/*

# Rutas que docker/build.sh pasa a CMake mediante -D
ENV OMNI_TCL_PREFIX=${PREFIX}
ENV OMNI_TCL_SRC=${SRCDIR}/tcl${TCL_VER}
ENV OMNI_TK_SRC=${SRCDIR}/tk${TCL_VER}
ENV OMNI_TREECTRL_HDRS=${SRCDIR}/tktreectrl-${TREECTRL_VER}/generic

WORKDIR /work
