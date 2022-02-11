#!/bin/bash

#this script packages up the entire theme directory into a .tar.gz for easy distribution
#it also excludes the private configuration files from that package so that this can be distributed publically

if [ "$(basename "$(pwd)")" != "neu-way-ui" ]
then
	echo "This packaging script expects to be run from the neu-way-ui directory but is being run from $(pwd) instead"
	echo "This can lead to unexpected behaviour so we are going to exit with an error instead of running the script..."
	exit 1
fi

installer_dir="$(pwd)"

cd ..
tar --exclude='neu-way-ui/private-config' --exclude='neu-way-ui/private-config.tar.gz.cpt' --exclude='neu-way-ui/.git' --exclude='neu-way-ui/.gitignore' --exclude='.*.swp' -cvzf neu-way-ui.tar.gz neu-way-ui
cd -

echo "Theme packaged at ../neu-way-ui.tar.gz"

