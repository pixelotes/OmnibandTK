# Omniband

A modernization of **OmnibandTk**, the package of classic Angband variants with a
Tcl/Tk graphical interface. This repository updates the libraries and makes the
code build on a modern toolchain, and it includes a reproducible Docker
environment so you can build and play it on any current machine.

## What OmnibandTk is

OmnibandTk was created by Tim Baker (known as "tnb" on the Angband forums). It is a
package that bundles four classic Angband variants under a single Tcl/Tk graphical
interface, with switchable tilesets, sound, and macro management. The included
variants are:

- AngbandTk
- KAngbandTk
- OAngbandTk
- ZAngbandTk

All of them are based on the 2.9.x Angband codebase. Version 1.5 was released in
July 2009, and its source code became available in August of that same year. The
project has been dormant since then, and the code assumed tools and libraries of
its time (Tcl/Tk 8.5, internal APIs, Windows-only dependencies) that no longer
build as-is on modern systems.

## What this repository does

The goal is to get OmnibandTk 1.5 building and running on current systems without
depending on the author's original machine. Specifically:

- Each variant's engine is built as a shared library (`angband.so`) loaded by the
  Tcl/Tk interpreter through a small launcher executable.
- The era's dependencies and extensions (treectrl, TkHtml, TclZip, zlib) have been
  ported to native Linux libraries, replacing what previously existed only as
  Windows binaries.
- The 64-bit portability issues that broke the random number generator and the
  savefile format have been fixed.
- All four variants build cleanly and start up with graphics.

For the technical detail of the porting process, see [PORTING.md](PORTING.md).

## Docker

To avoid depending on the exact libraries your machine happens to have installed,
the build lives inside a Docker image (Debian with the toolchain and all
dependencies pinned). This makes the project reproducible today and future-proof.

All scripts are run from the root of the repository and require Docker.

Build the four variants:

```sh
./docker/build.sh
```

Play interactively over VNC (in the browser or with a native client). With no
argument it shows a variant picker on connect:

```sh
./docker/play.sh            # variant picker
./docker/play.sh ZAngbandTk # launches that variant directly
```

Then connect from your machine to `http://localhost:6080/vnc.html` (browser) or to
`vnc://localhost:5900` with a native client. The password is `omniband`.

Verify that a variant initializes automatically (headless, no VNC):

```sh
./docker/launch.sh AngbandTk
```

## Status and plans

The four original variants build and start up. Work is in progress to also port
ToME (Tales of Middle Earth), reusing the same tile engine, and to replace the
sound (which in the original relied on a proprietary Windows library) with a free
backend.

## Credits

OmnibandTk and the variants it bundles are the work of Tim Baker and the authors of
each Angband variant, building on the original work of the Angband community. This
repository only modernizes the build and adds the Docker environment.

## References

- [OmnibandTk 1.5 on the Angband forums](https://angband.live/forums/forum/angband/variants/1911-omnibandtk-1-5)
- [List of Angband variants (RogueBasin)](https://roguebasin.com/index.php?title=List_of_Angband_variants)
