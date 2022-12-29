#!/bin/sh

cd "$(dirname $0)"

find -maxdepth 1 -type l -delete

pkgs=$(find -mindepth 2 -maxdepth 4 -type f -name '*.sbuild' | grep -v 0--libs)

for i in $pkgs
do
	name=$(basename $i)
	ln -snfv $i $name
done

