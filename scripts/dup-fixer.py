#!/usr/bin/env python3

#this script is meant to scan a directory for duplicate files
#including 3 or more copies of the same file
#it will then prompt the user for which of the paths and filenames is the canonical version
#and then show the following options:
#	keep one copy and symlink the other copies to it (recommended)
#	keep all copies
#	keep one copy and delete the other copies
#	manually choose what to do with each copy

import argparse
import hashlib
import os
import time

#this gets the checksum for a given file
#args:
#	fpath: the full path of the file to get a checksum for
#	hash_algo: the hashing algorithm to use for duplicate detection
#return:
#	returns the checksum of the given file as a string
#side-effects:
#	none
def checksum_file(fpath:str,hash_algo:str) -> str:
	if(not os.path.isfile(fpath)):
		raise Exception('Err: Checksum requested for non-existent file '+str(fpath))
	
	#declare buffer size
	HASH_BUF_BYTES=1024
	
	#initialize hash object based on requested hash algorithm
	hash_obj=None
	if(hash_algo=='sha1'):
		hash_obj=hashlib.sha1()
	elif(hash_algo=='sha256'):
		hash_obj=hashlib.sha256()
	elif(hash_algo=='md5'):
		hash_obj=hashlib.md5()
	
	#read the file in as binary blocks
	with open(fpath,'rb') as fp:
		block=0
		while(block!=b''):
			block=fp.read(HASH_BUF_BYTES)
			#update the hash with each block
			hash_obj.update(block)
	
	#return the hash that resulted once the file has been thoroughly read
	#and format it as a hex string
	return hash_obj.hexdigest()


#fix duplicates in a directory and all subdirectories thereof
#args:
#	directory: the directory to search for duplicates
#	hash_algo: the hashing algorithm to use for duplicate detection
#	ignore_git: whether or not to ignore git repositories during duplicate checking
#return:
#	returns the hash_acc value that was detected
#side-effects:
#	no side-effects persist after return
def dup_find(directory:str,hash_algo:str,ignore_git:bool=False) -> dict:
	#hash_acc: the accumulator of hashes in the following data format
	#	{
	#		"file_hash_0":[
	#			"/path/to/file/0",
	#			"/path/to/file/1"
	#		],
	#		"file_hash_1":[
	#			"/path/to/file/2"
	#		]
	#	}
	hash_acc:dict={}
	
	if(not os.path.isdir(directory)):
		raise Exception('Err: Given directory '+directory+' does not exist')
		return hash_acc
	
	#for each file or directory within this directory
	dir_contents=os.listdir(directory)
	
	#if we're ignoring git repositories
	if(ignore_git):
		#if this is a git repository
		for fname in dir_contents:
			basename=os.path.split(fname)[1]
			if(basename=='.git'):
				print('Skipping directory '+directory+' because it is a git repository...') #debug
				#then skip it and all of its contents
				return []
	
	print('Scanning directory "'+directory+'" ...') #debug
	
	for fname in dir_contents:
		fpath=os.path.join(directory,fname)
		
		#if this file is a symbolic or hard link then skip it
		#as those aren't really duplicates so much as pointers
		#NOTE: since symlinks can be directories as well as simple files
		#this check needs to be done first, before the isdir and isfile checks
		#in order to account for all cases
		if(os.path.islink(fpath)):
			continue
		#if it is itself a directory, then recurse to the subdirectory
		elif(os.path.isdir(fpath)):
			subdir_hash_acc=dup_find(directory=fpath,hash_algo=hash_algo,ignore_git=ignore_git)
			#once we've got the hash_acc for the subdirectory,
			#merge it with the parent directory hash_acc
			for hash_key in subdir_hash_acc:
				if(hash_key in hash_acc):
					hash_acc[hash_key].extend(subdir_hash_acc[hash_key])
				else:
					hash_acc[hash_key]=subdir_hash_acc[hash_key]
		#if this is a normal file, then get the checksum for it
		elif(os.path.isfile(fpath)):
			fhash=checksum_file(fpath=fpath,hash_algo=hash_algo)
			#if no files with this checksum have yet been found
			if(not (fhash in hash_acc)):
				#initialize a list now
				hash_acc[fhash]=[]
			
			#TODO: sanity check, verify that logical filesize is identical for all copies
			
			#append the current file path to the list of files with the found checksum
			#regardless of whether that list previously existed or was just initialized
			hash_acc[fhash].append(fpath)
	
	return hash_acc

#this function takes a list of identical files
#and for all copies except the canonical one (give by dup_files[canonical_idx])
#deletes the copy and in its place puts a symlink which points to the canonical copy
#args:
#	dup_files: the list of files with identical checksum (i.e. duplicate files)
#	canonical_idx: the index in the dup_files list of the canonical copy
#	auth_symlinks: whether or not to show a confirmation prompt before creating each symlink; true to show the prompt, false to not show a prompt
#return:
#	none
#side-effects:
#	deletes all copies other than the canonical copy
#	in place of deleted copies places symbolic links which point to the canonical copy
def dup_symlink(dup_files:list,canonical_idx:int,auth_symlinks:bool):
	#sanity check, ensure canonical_idx is in the correct range
	if((canonical_idx<0) or (canonical_idx>=len(dup_files))):
		raise Exception('Err: Canonical Index out of range; dup_files='+str(dup_files)+'; canonical_idx='+str(canonical_idx))
	
	#for each copy
	for path_idx in range(0,len(dup_files)):
		#if this is the canonical copy, don't do anything
		#that copy must remain in place
		if(path_idx==canonical_idx):
			continue
		
		fpath=dup_files[path_idx]
		
		#for all other copies
		
		#fix paths because the paths that are found in the dup list are relative to the given directory
		#and are not absolute nor do they account for subdirectory weirdness
		can_path_parts=os.path.split(dup_files[canonical_idx])[0].split(os.path.sep)
		dup_path_parts=os.path.split(fpath)[0].split(os.path.sep)
		
		#find the path to the canonical directory relative to the dup path directory
		#start with the path to the canonical copy of the file
		dest_path=dup_files[canonical_idx]
		
		#for each directory from the root (shared) directory to the duplicate file path
		for dir_idx in range(0,len(dup_path_parts)):
			#skip references to the current directory as they are meaningless in the context of a symlink
			if(dup_path_parts[dir_idx]=='.'):
				continue
			
			#ensure that we're going up until we hit a shared directory
			#before drilling back down to the destination
			dest_path=os.path.join('..',dest_path)
		
		#get a version of the file path that python can print for user interaction purposes
		decoded_fpath=fpath.encode('utf-8','ignore').decode('utf-8')
		decoded_dest_path=dest_path.encode('utf-8','ignore').decode('utf-8')
		
		#if per-link authorization was requested...
		if(auth_symlinks):
			#ensure this is something we should delete before doing the actual operation
			authorized=False
			while(not authorized):
				print('Please enter y to authorize the deletion (and replacement by symlink) of '+decoded_fpath)
				print('If replaced the symlink will point from '+decoded_fpath+' to '+decoded_dest_path)
				print('Use ctrl+c if you don\'t want to allow this symlink and would instead like to terminate the script')
				auth_input=input()
				if(auth_input=='y'):
					authorized=True
		
		print('Replacing "'+decoded_fpath+'" with symlink ...')
		
		#delete this copy
		os.unlink(fpath)
		
		#in place of the old copy, put a symlink which has the same name
		#and points to the canonical copy
		
		#NOTE: documentation for os.symlink is weird as the destination of the symlink is "src"
		#and the location of the symbolic link itself is referred to as "dest"
		#but this is the correct call, I've tested it
		os.symlink(dest_path,fpath)
		
		#NOTE: on future runs of this script symbolic links are ignored
		#so this won't be detected as a duplicate in the future

#this function takes a list of identical files
#and for all copies except the canonical one (give by dup_files[canonical_idx])
#deletes the copy
#args:
#	dup_files: the list of files with identical checksum (i.e. duplicate files)
#	canonical_idx: the index in the dup_files list of the canonical copy
#	auth_rm: whether or not to show a confirmation prompt before each deletion; true to show the prompt, false to not show a prompt
#return:
#	none
#side-effects:
#	deletes all copies other than the canonical copy
def dup_rm(dup_files:list,canonical_idx:int,auth_rm:bool):
	#sanity check, ensure canonical_idx is in the correct range
	if((canonical_idx<0) or (canonical_idx>=len(dup_files))):
		raise Exception('Err: Canonical Index out of range; dup_files='+str(dup_files)+'; canonical_idx='+str(canonical_idx))
	
	#for each copy
	for path_idx in range(0,len(dup_files)):
		#if this is the canonical copy, don't do anything
		#that copy must remain in place
		if(path_idx==canonical_idx):
			continue
		
		fpath=dup_files[path_idx]
		
		#for all other copies
		
		#if per-link authorization was requested...
		if(auth_rm):
			#ensure this is something we should delete before doing the actual operation
			authorized=False
			while(not authorized):
				print('Please enter y to authorize the deletion of '+fpath)
				print('Use ctrl+c if you don\'t want to allow this deletion and would instead like to terminate the script')
				auth_input=input()
				if(auth_input=='y'):
					authorized=True
		
		print('Deleting "'+fpath+'" ...')
		#delete this copy
		os.unlink(fpath)

#this function iterates through the given list of hashes and prompts the user to resolve any duplicates
#args:
#	hash_list: the list of hashes returned by dup_find
#	auth_symlinks: whether or not to show a confirmation prompt before creating each symlink; true to show the prompt, false to not show a prompt
#	auth_rm: whether or not to show a confirmation prompt before doing a delete/rm operation; true to show the prompt, false to not show a prompt
#return:
#	None
#side-effects:
#	for duplicate files (files for which multiple paths exist for the same hash)
#		prompts the user for the resolution action
#		resolves the duplication as the user specified
#			typically this means leaving one copy and making the other copies be symlinks to it
def dup_fix(hash_list:list,auth_symlinks:bool=False,auth_rm:bool=False):
	#get a total count of the number of duplicate files to give us some idea of how long this will take
	unique_files=0
	total_files=0
	for fhash in hash_list:
		unique_files+=1
		total_files+=len(hash_list[fhash])
	
	print('There were '+str(unique_files)+' unique files found and '+str(total_files)+' total files')
	print('Meaning that '+str(total_files-unique_files)+' duplicates exist')
	
	#for each checksum/hash
	for fhash in hash_list:
		#if this is the only file with the hash (i.e. it is unique)
		#then skip it, it's not a duplicate and there's nothing to do
		if(len(hash_list[fhash])<2):
			continue

		dup_files=hash_list[fhash]

		selected_action=None
		while(selected_action is None):
			print('Duplicates found: ')
			for f_idx in range(0,len(dup_files)):
				#NOTE: this encoding handling is needed for files which contain certain characters such as swedish glyphs
				decoded_fname=dup_files[f_idx].encode('utf-8','ignore').decode('utf-8')
				print("\t"+str(f_idx)+': '+decoded_fname)
			
			print('Choose action: ')
			print("\t"+'l: (l)ink:    Keep canonical copy and symlink the other copies to it (recommended)')
			print("\t"+'s: (s)kip:    Keep all copies (no changes)')
			print("\t"+'r: (r)emove:  Keep canonical copy and delete (rm) all other copies')
#			print("\t"+'m: (m)anual:  Choose action for each file copy (apart from the canonical copy which must always be kept)')
			
			action=input()
			if(action in ['l','s','r','link','skip','remove']):
				selected_action=action
			else:
				print('Err: Unrecognized action '+action+'; please choose from the above action list')
				continue
		
		#for actions which require it, prompt the user for the canonical path to this file
		if(selected_action in ['l','r','link','remove']):
			canonical_idx=-1
			canonical_path=None
			while(canonical_path is None):
#				print('Duplicates found: ')
#				for f_idx in range(0,len(dup_files)):
#					#NOTE: this encoding handling is needed for files which contain certain characters such as swedish glyphs
#					decoded_fname=dup_files[f_idx].encode('utf-8','ignore').decode('utf-8')
#					print("\t"+str(f_idx)+': '+decoded_fname)
				
				print('Select canonical path by index: ')
				canonical_idx=input()
				try:
					canonical_idx=int(canonical_idx)
				except ValueError as e:
					print('Err: Could not interpret '+str(canonical_idx)+' as a number; please enter index and not filename')
					continue
				
				if(canonical_idx>=len(dup_files)):
					print('Err: Given index '+str(canonical_idx)+' is outside of option range [0,'+str(len(dup_files)-1)+']; please try again')
					continue
				
				canonical_path=dup_files[canonical_idx]
				print('Canonical path is '+(canonical_path.encode('utf-8','ignore').decode('utf-8'))+'; the copy at this location will be kept')
			
			if(selected_action in ['l','link']):
				print('Adjusting all non-canonical copies to be symlinks...')
				
				#for all copies other than the canonical copy
				#delete the file and create a symlink to the canonical copy
				#with the same name as what the old copy had
				dup_symlink(dup_files=dup_files,canonical_idx=canonical_idx,auth_symlinks=auth_symlinks)
			elif(selected_action in ['r','remove']):
				print('Removing (deleting) all non-canonical copies; only the canonical copy will remain')
				
				#for all copies other than the canonical copy
				#delete those copies
				dup_rm(dup_files=dup_files,canonical_idx=canonical_idx,auth_rm=auth_rm)
		
		elif(selected_action in ['s','skip']):
			print('Skipping this file set (keeping all copies)...')
			
			#this intentionally does nothing
			pass
		
		

if(__name__=='__main__'):
	parser=argparse.ArgumentParser(description='This is a duplicate fixer script.  It finds and fixed duplicates under the given directory.  ')
	parser.add_argument(
		'directory',
		type=str,
		help='The directory to check for duplicates (subdirectories of this are checked as well); if you aren\'t sure what to provide, try "." (current directory)',
		default=None
	)
	parser.add_argument(
		'--hash-algo',
		dest='hash_algo',
		type=str,
		help='The checksum algorithm to use for the purpose of detecting duplication',
		default='sha1',
		choices=['sha1','md5','sha256']
	)
	#add --auth-symlink option so the per-file prompts can be enabled
	parser.add_argument(
		'--auth-symlinks',
		dest='auth_symlinks',
		action='store_const',
		const=True,
		default=False,
		help='Pass the --auth-symlinks switch in order to require all symlink paths to be confirmed before they are created; by default symlinks are created without a confirmation prompt once the option is selected'
	)
	#add --auth-rm option so the per-file prompts can be enabled
	parser.add_argument(
		'--auth-rm',
		dest='auth_rm',
		action='store_const',
		const=True,
		default=False,
		help='Pass the --auth-rm switch in order to require all deletions to be confirmed before they are done; by default removal is done without a confirmation prompt once the option is selected'
	)
	#add --ignore-git option so that git directories can be skipped
	#because they have a bunch of default files that get flagged and also partially-linked git repositories seem like a huge issue
	parser.add_argument(
		'--ignore-git',
		dest='ignore_git',
		action='store_const',
		const=True,
		default=False,
		help='Pass the --ignore-git switch in order to ignore git repositories and .git directory contents when checking for duplicates'
	)
	
	args=parser.parse_args()

	#change to the given directory and execute everything relative to '.' after that
	#this is necessary for the reliable and correct creation of symlinks
	os.chdir(args.directory)
	
	hash_list=dup_find('.',args.hash_algo,ignore_git=args.ignore_git)
#	print(hash_list) #debug
	dup_fix(hash_list,auth_symlinks=args.auth_symlinks,auth_rm=args.auth_rm)

