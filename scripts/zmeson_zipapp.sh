#!/bin/sh
# - this can be run in an Alpine linux chroot
# - place this script in the chroot dir and then run
#      chroot . /zmeson_zipapp.sh

meson_ver=0.61.5
meson_ver=0.62.2
meson_ver=0.63.3
meson_ver=0.64.1
meson_url=https://github.com/mesonbuild/meson/releases/download/${meson_ver}/meson-${meson_ver}.tar.gz

wget --no-check-certificate ${meson_url}
tar -xf meson-${meson_ver}.tar.gz
cd meson-${meson_ver}
./packaging/create_zipapp.py --outfile meson-${meson_ver}.pyz --interpreter '/usr/bin/env python3' #<source checkout>
mv meson-${meson_ver}.pyz ../
