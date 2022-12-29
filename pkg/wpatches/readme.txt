
call `patch_package` inside a .sbuild script
and the it will look for patches for the specified argument or $pkgname

where the argument or $pkgname is a directory 

this is meant for packages that require more than one patch
that is downloaded from somewhere

the patches I produce contain all the changes in a single file
but it may be placed here if the package is not important
