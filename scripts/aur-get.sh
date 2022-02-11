#!/bin/bash

pkgname="$1"

prefix="${pkgname:0:2}"

#wget "https://aur.archlinux.org/packages/${prefix}/${pkgname}/${pkgname}.tar.gz"
wget "https://aur.archlinux.org/cgit/aur.git/snapshot/${pkgname}.tar.gz"

