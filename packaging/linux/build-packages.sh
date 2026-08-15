#!/usr/bin/env bash
# Build the Linux desktop packages — a .deb and an .rpm — from a finished
# `flutter build linux --release` bundle.
#
#   usage: packaging/linux/build-packages.sh <version> <bundle-dir> [out-dir]
#
# Why packages at all, when there was an AppImage: an AppImage is deliberately
# self-contained and touches nothing, which is exactly why it leaves no menu
# entry and no icon — you chmod +x it and run it from a terminal, forever. The
# ask was "the equivalent of an .exe I download": something you double-click,
# that installs, and that then appears in the applications menu like any other
# program. On Linux that is a distro package.
#
# Both packages install the same way:
#   /opt/openote/                                        the bundle, verbatim
#   /usr/bin/openote                                     symlink onto PATH
#   /usr/share/applications/org.openote.openote.desktop  the menu entry + icon
#   /usr/share/icons/hicolor/512x512/apps/               the icon itself
#   /usr/share/mime/packages/openote.xml                 describes a .onote
#
# The desktop entry is named for the GTK application id, not "openote". Modern
# desktops — Wayland in particular — match a running window to its entry by
# that basename, and app/linux/runner/my_application.cc:138 sets the prgname to
# APPLICATION_ID ("org.openote.openote"). Named "openote", the launcher shows a
# second generic icon beside the real one rather than highlighting it.
#
# Runnable on any Debian-ish machine with `dpkg-deb` and `rpmbuild` (the latter
# from the `rpm` package). Deliberately a script and not inline YAML so it can
# be run and debugged locally, exactly like packaging/windows/openote.iss.
set -euo pipefail

VERSION="${1:?usage: build-packages.sh <version> <bundle-dir> [out-dir]}"
BUNDLE="${2:?usage: build-packages.sh <version> <bundle-dir> [out-dir]}"
OUT="${3:-$PWD}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
ICON="$REPO/app/assets/icon/openote_icon.png"

[ -x "$BUNDLE/openote" ] || { echo "no openote binary in $BUNDLE" >&2; exit 1; }
[ -f "$ICON" ] || { echo "no icon at $ICON" >&2; exit 1; }

# The loader contract, asserted here rather than discovered by a user whose app
# silently loses OneNote import: app/lib/core/onote_ffi.dart looks for the core
# next to the executable first.
[ -f "$BUNDLE/libonote_core.so" ] || {
  echo "libonote_core.so is missing from the bundle — the packaged app would" >&2
  echo "start but have no OneNote import and no text engine." >&2
  exit 1
}

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ROOT="$STAGE/root"

echo "==> staging package tree"
install -d "$ROOT/opt/openote" \
           "$ROOT/usr/bin" \
           "$ROOT/usr/share/applications" \
           "$ROOT/usr/share/icons/hicolor/512x512/apps" \
           "$ROOT/usr/share/mime/packages" \
           "$ROOT/usr/share/doc/openote"

cp -r "$BUNDLE"/. "$ROOT/opt/openote/"
chmod 755 "$ROOT/opt/openote/openote"
ln -s /opt/openote/openote "$ROOT/usr/bin/openote"
install -m644 "$HERE/org.openote.openote.desktop" \
  "$ROOT/usr/share/applications/org.openote.openote.desktop"
install -m644 "$HERE/openote.xml" "$ROOT/usr/share/mime/packages/openote.xml"
install -m644 "$ICON" "$ROOT/usr/share/icons/hicolor/512x512/apps/openote.png"
install -m644 "$REPO/LICENSE" "$ROOT/usr/share/doc/openote/copyright"

# ── .deb ────────────────────────────────────────────────────────────────────
# Depends is hand-written rather than auto-generated. `dpkg-shlibdeps` would
# pin the exact library versions present on the BUILD machine, which is a
# debian:12 container chosen deliberately (see release.yml's linux job) —
# those versions would then be unsatisfiable on the distros it exists to reach.
#
# libmpv is how video plays inside the app, and it is a LINK-time dependency,
# not a dlopen. media_kit_video's Linux plugin does
# `target_link_libraries(... PkgConfig::mpv ...)`, so the soname of whatever
# libmpv the BUILD HOST had is baked into libmedia_kit_video_plugin.so and
# resolved by ld.so before main() — get it wrong and the app does not start at
# all, rather than starting without video.
#
# `libmpv2` alone, NOT `libmpv2 | libmpv1`. The alternation looked like it
# covered both Ubuntu generations and covered neither honestly: the binary
# needs exactly ONE soname, so offering an alternative that cannot satisfy it
# just means apt installs the wrong library and reports success. The release is
# built in a debian:12 container (mpv 0.35.1, libmpv.so.2), so .so.2 is what
# this asks for, and release.yml's "Verify shared-library dependencies" step
# asserts the built binary agrees rather than trusting this line to stay in
# step. Bookworm is picked for its glibc 2.36 floor; that it also gives .so.2
# is the reason bookworm and not an older Debian.
echo "==> building .deb"
install -d "$ROOT/DEBIAN"
cat > "$ROOT/DEBIAN/control" <<EOF
Package: openote
Version: ${VERSION}
Section: office
Priority: optional
Architecture: amd64
Maintainer: Openote <noreply@openote.org>
Depends: libgtk-3-0, libglib2.0-0, libstdc++6, libmpv2
Homepage: https://openote.org
Description: Open-source alternative to Microsoft OneNote
 A freeform notebook with handwriting, maths and an open file format.
 Notes are stored locally in a documented SQLite container; syncing is
 done through a folder your cloud already keeps in step, with no account
 and no sign-in.
EOF

cat > "$ROOT/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
# Refresh the caches that make the menu entry and the .onote association
# appear without a logout. Each is guarded: a minimal desktop may not ship
# every tool, and a missing cache updater must not fail the install.
[ -x "$(command -v update-desktop-database)" ] && update-desktop-database -q /usr/share/applications || true
[ -x "$(command -v update-mime-database)" ] && update-mime-database /usr/share/mime || true
[ -x "$(command -v gtk-update-icon-cache)" ] && gtk-update-icon-cache -qtf /usr/share/icons/hicolor || true
exit 0
EOF
cp "$ROOT/DEBIAN/postinst" "$ROOT/DEBIAN/postrm"
chmod 755 "$ROOT/DEBIAN/postinst" "$ROOT/DEBIAN/postrm"

dpkg-deb --root-owner-group --build "$ROOT" \
  "$OUT/openote-${VERSION}-linux-amd64.deb"

# Take DEBIAN/ back out before the rpm runs. The rpm below installs by copying
# this same tree wholesale into its buildroot, and DEBIAN/ is not in its
# %files list — rpmbuild fails the build on unpackaged files by default
# (`%_unpackaged_files_terminate_build` is 1), so leaving it here is a
# guaranteed "Installed (but unpackaged) file(s) found: /DEBIAN/control".
#
# Removing it beats raising the rpm's tolerance: that flag exists to catch
# exactly the mistake of shipping something you did not mean to, and turning
# it off to paper over one known stray would blind it to the next real one.
rm -rf "$ROOT/DEBIAN"

# ── .rpm ────────────────────────────────────────────────────────────────────
# Built from the SAME staged tree, so the two packages cannot drift.
#
# `AutoReqProv: no` for the same reason Depends is hand-written: rpmbuild would
# scan every bundled .so and emit requires naming the build machine's exact
# soname set, which a different distro will not provide under those names. The
# real runtime needs are declared by hand below.
#
# `mpv-libs` is Fedora's and RHEL's name for libmpv — the same dependency the
# .deb spells `libmpv2` — and it is in the default repositories, so
# this does not quietly require RPM Fusion to be enabled.
echo "==> building .rpm"
install -d "$STAGE/rpm"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
cat > "$STAGE/rpm/SPECS/openote.spec" <<EOF
Name:           openote
Version:        ${VERSION}
Release:        1
Summary:        Open-source alternative to Microsoft OneNote
License:        AGPL-3.0-or-later
URL:            https://openote.org
BuildArch:      x86_64
AutoReqProv:    no
Requires:       gtk3
Requires:       glib2
Requires:       libstdc++
Requires:       mpv-libs

%description
A freeform notebook with handwriting, maths and an open file format.
Notes are stored locally in a documented SQLite container; syncing is
done through a folder your cloud already keeps in step, with no account
and no sign-in.

%install
cp -r ${ROOT}/. %{buildroot}/

%files
/opt/openote
/usr/bin/openote
/usr/share/applications/org.openote.openote.desktop
/usr/share/icons/hicolor/512x512/apps/openote.png
/usr/share/mime/packages/openote.xml
/usr/share/doc/openote/copyright

%post
update-desktop-database -q /usr/share/applications 2>/dev/null || :
update-mime-database /usr/share/mime 2>/dev/null || :
gtk-update-icon-cache -qtf /usr/share/icons/hicolor 2>/dev/null || :

%postun
update-desktop-database -q /usr/share/applications 2>/dev/null || :
update-mime-database /usr/share/mime 2>/dev/null || :
gtk-update-icon-cache -qtf /usr/share/icons/hicolor 2>/dev/null || :
EOF

rpmbuild --define "_topdir $STAGE/rpm" \
         --define "_build_id_links none" \
         -bb "$STAGE/rpm/SPECS/openote.spec"
mv "$STAGE/rpm/RPMS/x86_64/openote-${VERSION}-1.x86_64.rpm" \
   "$OUT/openote-${VERSION}-linux-x86_64.rpm"

echo "==> done"
ls -la "$OUT"/openote-"${VERSION}"-linux-*.deb "$OUT"/openote-"${VERSION}"-linux-*.rpm
