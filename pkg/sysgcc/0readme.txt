
Packages that can only be compiled with the system compiler (chroot is OK)
because they require Xorg, GTK, or some other unportable library

Or apps that are meant to link to glibc dynamically

But all the dependencies specified in pkgdeps='...'
will be compiled and linked statically (from pkg/*.sbuild)

The libc is not linked statically

Theoretically most apps compiled on Slackware 14.0 should be quite portable
and can be used in any later glibc distro

Slackware 14.1 is not suitable for compiling portable gtk apps

==============================================================

Some packages are not compiled but downloaded:

- ddrescueview
- mkvtoolnix
- freeoffice   (softmaker freeoffice)
