#!/bin/sh

# 2 dots = includes category
for i in $(ls *.*.sbuild)
do
	symlink=${i#*.} # remove graphics. / audio. / etc
	ln -snfv ${i} ${symlink}
done

ln -snfv optical.libburn.sbuild cdrskin.sbuild
ln -snfv optical.libcdio-paranoia.sbuild cd-paranoia.sbuild
