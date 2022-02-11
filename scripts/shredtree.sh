#!/bin/bash

#this script recursively shreds an entire directory, using the unix shred utility
#by default this also unlinks the shredded file and cleans up the resulting directory tree
#this option can be changed with a -k, --keep, or --keeplink option
#all other options are passed to the internal shred call

#global settings and constants

#internal field seperator is newline
#so filenames with spaces are supported
IFS=$'\n'


#shows the help text and exits
function show_help_text_and_exit {
	echo "Usage: $0 <directory> [--keeplinks] [--iterations=n] [--verbose] [--all]"
	echo "Shreds a given directory (including all subdirectories thereof)"
	echo "By default, this also removes the directory itself and all files (file links)"
	echo "To keep the files and just overwrite their contents, use the --keeplinks switch"
	echo "By default files are overwritten once; to change the overwrite iterations use the --iterations switch"
	echo "By default, hidden files are not included in the list of files to shred; use the --all switch to change that to include hidden files"

	#exit with success
	exit 0
}

#shreds the tree rooted at the given directory
#if keeplinks is false, this also removes the resulting directory tree
#if keeplinks is true, this keeps the files and just shreds their contents
function shred_tree {
	local directory="$1"
	local keeplinks="$2"
	local shred_iterations="$3"
	local verbose="$4"
	local all="$5"
	
	#strip off any trailing / characters on directory
	directory="$(echo "$directory" | sed 's/\/*$//g')"

	if [ "$verbose" = true ]
	then
		echo "shred_tree("
		echo "  directory=\"$directory\""
		echo "  keeplinks=\"$keeplinks\""
		echo "  iterations=\"$shred_iterations\""
		echo "  verbose=\"$verbose\""
		echo "  all=\"$all\""
		echo ")"
	fi
	
	#get the files in this directory
	if [ "$all" = true ]
	then
		read -d '' -r -a files <<< $(ls -A "$directory")
	else
		read -d '' -r -a files <<< $(ls "$directory")
	fi

	#for each file
	for file in "${files[@]}"
	do
		
		
		#if this file is actually a directory
		if test -d "$directory/$file"
		then
			#recursively call this function on the subdirectory
			shred_tree "$directory/$file" "$keeplinks" "$shred_iterations" "$verbose" "$all"
		#if this is a non-directory file
		else
			if [ "$verbose" = true ]
			then
				echo "[$directory/$file] shredding..."
			fi
			
			#if keeplinks is true and we're shredding but not deleting the file
			if [ "$keeplinks" = true ]
			then
				#then shred but don't delete the file...
				#bien sûr...
				shred --iterations="$shred_iterations" "$directory/$file"
			#if keeplinks is false and we're deleting the files
			else
				#shred and unlink the file
				shred --iterations="$shred_iterations" -u "$directory/$file"
			fi

			if [ "$verbose" = true ]
			then
				echo "[$directory/$file] shredded"
			fi
		fi
	done

	#if keeplinks is false and we're deleting the files
	if [ "$keeplinks" = false ]
	then
		#then delete the directories as well
		rmdir "$directory"
		
		if [ "$verbose" = true ]
		then
			echo "[$directory] shredded and removed"
		fi
	else
		if [ "$verbose" = true ]
		then
			echo "[$directory] shredded"
		fi
	fi
}

#if no arguments were given
if [ "$#" -lt 1 ]
then
	#show usage and exit (all in this function)
	show_help_text_and_exit
fi

#default argument values

dir_to_shred=''

#if the first argument is a directory
#then parse it out and keep the rest of the arguments as options
if test -d "$1"
then
	dir_to_shred="$1"
	shift
#otherwise what are you even doing idk
else
	show_help_text_and_exit
fi

#by default overwrite once
shred_iterations=1

#by default unlink and rmdir
keeplinks=false

#by default be quiet
verbose=false

#by default be noisy
#verbose=true

#by default don't include hidden files
all=false

#get any argument values which were given to this script

#for each command line argument
for opt in "$@"
do
	case "$opt" in
		#-k is the opposite of -u
		#by default files are unlinked and directories are removed
		#but you can pass this option to /avoid/ using the -u shred option
		-k|--keep|--keeplinks)
			keeplinks=true
			;;
		#pass number of iterations straight through to shred
		-n=*|--iterations=*)
    			shred_iterations="${opt#*=}"
			;;
		#verbosity
		-v|--verbose)
			verbose=true
			;;
		#all (see ls -A)
		-a|-A|--all)
			all=true
			;;
		#help text
		-h|--help)
			#display and exit (all in this function)
			show_help_text_and_exit
			;;
		#hard error on unknown options
		*)
			echo "Err: Unknown or unrecognized option $opt"
			
			#stop; unrecognized options are fatal
			exit 1
			;;
	esac
	
	#go check the next argument
	shift
done

#run the actual shred operations, now that all arguments are known
shred_tree "$dir_to_shred" "$keeplinks" "$shred_iterations" "$verbose" "$all"

