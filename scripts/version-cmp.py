#!/usr/bin/python3

import re

#this is a comparison function for version numbers of the format
# [0-9]+(\.[0-9]+)*
#arguments
#	ver_a : the first version string to compare
#	ver_b : the second version string to compare
#return value
#	-1 if ver_a < ver_b where < means older
#	0 if ver_a == ver_b
#	1 if ver_a > ver_b where > means newer
def version_cmp(ver_a,ver_b):
	
	#find the first occurrance of a . character in each version string
	#as we're only going to compare what's before the dot
	a_dot_idx=ver_a.find('.')
	b_dot_idx=ver_b.find('.')
	
	#this comparison is done in a major and b major
	#(get the major version numbers only, ignoring others for now)
	ver_a_major=ver_a
	if(a_dot_idx>=0):
		ver_a_major=ver_a[0:a_dot_idx]
	
	ver_b_major=ver_b
	if(b_dot_idx>=0):
		ver_b_major=ver_b[0:b_dot_idx]
	
	#if either parameter is null
	if(ver_a_major=='' or ver_b_major==''):
		#then the non-null parameter is larger (even if it is 0)
		
		if(ver_b_major!=''):
			return -1
		if(ver_a_major!=''):
			return 1
		
		#if both parameters are null then they are equal, because null is equal to null
		return 0
	
	#since we know the numbers aren't null, convert them to you know, numbers
	ver_a_major=int(ver_a_major)
	ver_b_major=int(ver_b_major)

	#if a was smaller in major version number then it doesn't matter what minor versions are
	if(ver_a_major<ver_b_major):
		# a < b
		return -1
	
	#if a was larger in major version number then it doesn't matter what minor versions are
	if(ver_a_major>ver_b_major):
		# a > b
		return 1
	
	#if we got to this point and didn't return then the major versions are equal
	#if needed, check the minor versions recursively
	if((a_dot_idx>=0) or (b_dot_idx>=0)):
		ver_a_minor=''
		if(a_dot_idx>=0):
			#note that because the dot is part of the string, we add one to advance past the dot for the recursive call
			ver_a_minor=ver_a[a_dot_idx+1:]

		ver_b_minor=''
		if(b_dot_idx>=0):
			#note that because the dot is part of the string, we add one to advance past the dot for the recursive call
			ver_b_minor=ver_b[b_dot_idx+1:]
		
		return version_cmp(ver_a_minor,ver_b_minor)
	
	#if there were no minor versions then end the comparison; the version numbers were equal
	return 0

#unit test
def test_version_cmp():
	assert(version_cmp('0','0')==0)
	assert(version_cmp('','')==0)
	assert(version_cmp('1','1')==0)
	assert(version_cmp('0','1')==-1)
	assert(version_cmp('1','0')==1)
	assert(version_cmp('0','')==1)
	assert(version_cmp('','0')==-1)
	assert(version_cmp('1.2','1')==1)
	assert(version_cmp('1','1.1')==-1)
	assert(version_cmp('1.1.5','1.1.6')==-1)
	assert(version_cmp('1.1.6','1.1.5')==1)
	assert(version_cmp('1.1.5','1.1.5')==0)
	assert(version_cmp('1.2.3','1.3.2')==-1)
	assert(version_cmp('1.3.2','1.3.2')==0)
	assert(version_cmp('1.3.2','1.2.3')==1)
	assert(version_cmp('1.2.3','2.3.1')==-1)
	assert(version_cmp('1.2.3','3.1.2')==-1)


if(__name__=='__main__'):
	#first verify that everything is working by running a very brief unit test
	test_version_cmp()
	
	#if the version test passed, then parse arguments

	import argparse
	desc='Compare two version numbers in a manner similar to strcmp()'+"\n"
	desc+='Outputs:'+"\n"
	desc+="\t"+'-1 if the first string is less than the second string'+"\n"
	desc+="\t"+'0 if the strings are equal'+"\n"
	desc+="\t"+'1 if the first string is greater than the second string'+"\n"
	
	parser = argparse.ArgumentParser(description=desc, formatter_class=argparse.RawTextHelpFormatter)
	parser.add_argument('ver_a', type=str, help='the first version string to compare', default=None)
	parser.add_argument('ver_b', type=str, help='the second version string to compare', default=None)
	
	args = parser.parse_args()
	
	#strip out any non-numeric characters so that we're doing the comparison only on the numeric portion
	args.ver_a=re.sub('[^0-9\.]','',args.ver_a)
	args.ver_b=re.sub('[^0-9\.]','',args.ver_b)
	
	print(version_cmp(args.ver_a,args.ver_b))
	
