#!/bin/sh
#
# BUILD_TYPE=system
#

s_apps='
aqualung
binutils
bison
#cdrtools
ddrescuewview
engrampa
freeoffice
libdvdcss
geany
#git
gtkdialog
gparted
gphoto
gsmartcontrol
gtkdialog
mkvtoolnix
mpv
rxvt-unicode
strace
#xclip
wgtkdesk
#wlxde
'

for i in ${s_apps}
do
	case $i in '#'*)
		continue ;;
	esac
	./build.sh -arch system -pkg ${i}
done
