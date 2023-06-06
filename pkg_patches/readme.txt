the 0* dirs are local source packages that may eventually be moved somewhere else...

add patches to a directory with the same name as the $pkgname
and the patches will be applied automatically:

example:
- bash/patch1.patch

if a patch is meant only for a specific libc, system or cpu architecture
you can add subdirectories

currently recognized subdirectories (depends on the cross-compiler triplet)
- musl    (linux)
- uclibc  (linux)
- glibc
- mingw   (windows)
- freebsd
- openbsd
- netbsd

examples:
- bash/musl/patch-for-musl.patch
- 7zip/musl/musl.patch

(files without extensions are ignored, i.e: readme)

======

There is a special patch without extension that is automatically
applied if STATIC_LINK=yes (set by build.sh targets or cmd args)

- static_link
