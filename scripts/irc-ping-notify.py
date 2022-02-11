#!/usr/bin/env python3

#this script periodically polls a file (given as the first argument)
#and if a new ping is found will send a systray-notify event for the ping in question
#ping files are expected to be in accric ping file format, https://github.com/neutrak/accirc

import argparse
import requests
import subprocess
import time
import urllib.parse

#this re-formats a message from
#"(host #chan) PING: timestamp <user> message content"
#to
#"PING :timestamp <user> message content"
#args:
#	in_str: the single line to reformat
#	pretty_timefrmt: whether or not to convert the timestamp into a human-readable format
#return:
#	returns a tuple consisting of timestamp,evnt_type,out_subject,out_details
#side-effects:
#	None
def ping_reformat(in_str,pretty_timefrmt=True):
	#we can't parse nothing
	#garbage in, garbage out
	if(in_str==''):
		return 0,''
	
	#get the event type by use of a delimiter
	idx=in_str.find(': ')
	msg_type=''
	strt_idx=idx
	while(in_str[strt_idx]!=' ' and strt_idx>0):
		strt_idx-=1
	
	if(strt_idx>0):
		strt_idx+=1
	
#	host_and_chan=in_str[0:strt_idx]

	evnt_type=in_str[strt_idx:idx]
	evnt_txt=in_str[idx+len(': '):]

	#default: these will get reset as long as everything gets parsed correctly
	out_subject=''
	out_details=''
	
	#parse out the timestamp, too, for reference
	timestamp=0
	if(len(evnt_txt)>0):
		timestamp_end_idx=evnt_txt.find(' ')
		#if there was no space then the entire message is the timestamp
		if(timestamp_end_idx<0):
			timestamp_end_idx=len(evnt_txt)-1
		
		#get the timestamp as a numeric value
		try:
			timestamp=int(evnt_txt[0:timestamp_end_idx])
		except(ValueError):
			try:
				timestamp=int(float(evnt_txt[0:timestamp_end_idx]))
			except(ValueError):
				timestamp=0
		
		out_subject=evnt_type+' ('+str(timestamp)+')'
		out_details=evnt_txt[timestamp_end_idx:]
		
		if(pretty_timefrmt):
			#prettily format the timestamp for output
			pretty_time=time.strftime('%Y-%m-%d %H:%M:%S',time.localtime(timestamp))
			
			out_subject=evnt_type+' ('+pretty_time+')'
	
	out_subject=out_subject.strip(' ')
	out_details=out_details.strip(' ')
	
	#return a tuple with the timestamp and the evnt_type and the output strings
	return timestamp,evnt_type,out_subject,out_details

#this function takes a single line from the ping file
#parses it, and depending on its timestamp sends a notification
#if a notification IS sent the last_ping_time is updated before being returned
#args:
#	line: the ping line to check and possibly notify for
#	last_ping_time: the unix timestamp of the last ping for which a notification was sent; default 0
#return:
#	returns last_ping_time
#		same as given argument if no notification is triggered
#		updated to be the most recent timestamp + 1 if a notification is triggered
#side-effects:
#	None
def ping_notify(line,last_ping_time=0):
	timestamp,evnt_type,out_subject,out_details=ping_reformat(line,pretty_timefrmt=True)
	
	#if this ping is newer than the last one we sent a notification for
	if(timestamp>last_ping_time):
		#then it's new; send a new notification now!
		subprocess.Popen([
			'notify-send',
			out_subject,
			out_details
		])
		
		#and remember the timestamp for the next time
		#so we don't send a repeat of this notification during the next polling interval
		last_ping_time=timestamp+1
	
	return last_ping_time

#this function polls the ping file
#and if a new ping is found, sends a relevant notification
#args:
#	ping_file_url: the url of the file to check for new pings
#	chk_interval: the polling interval (time between checks); units are seconds; default 5 seconds
#return:
#	None (loops forever unless SIGKILL or SIGINT is received or a fatal error occurs)
#side-effects:
#	periodically reads the file at ping_file_url
#		if a new ping is found, uses notify-send to send notification
#		if a new ping is found, plays a sound based on the type of ping
def ping_poll_loop(ping_file_url,chk_interval=5):
	last_ping_time=0
	url_parts=urllib.parse.urlparse(ping_file_url)
	
	while True:
		#initialize fcontent as empty
		fcontent=''
		
		#exception handling
		#for file I/O and network errors, when an error occurs just ignore it and try again on the next polling cycle
		#so that temporary network disruptions or file contention issues result in only a brief delay
		#rather than a hard crash
		try:
			#if this is a local file
			if(url_parts.scheme=='file'):
				#read the content of the file
				fp=open(url_parts.path,'rb')
				fcontent=fp.read()
				fp.close()
				
				#convert byte array into native string object
				fcontent=fcontent.decode('utf-8')
			#if this is a remote file
			elif(url_parts.scheme in ['http','https']):
				#get the remote data using the python requests library
				result=requests.get(ping_file_url)
				
				#if there was not an error when accessing this url
				if((result.status_code>=200) and (result.status_code<400)):
					fcontent=result.text
		except Exception as e:
			print(e) #debug
		
		#if there was any content at all to check
		if(len(fcontent)>0):
			new_last_ping_time=last_ping_time
			
			#split it into its component lines
			#and for each line send a notification if it's newer than the last ping time
			for line in fcontent.split("\n"):
				if(len(line)>0):
					new_last_ping_time=max(ping_notify(line,last_ping_time),new_last_ping_time)
		
			#NOTE: last_ping_time is updated only after all lines are processed
			#in case multiple lines with the same timestamp were detected during a single update
			last_ping_time=new_last_ping_time
			
		#wait the specified interval before polling again
		time.sleep(chk_interval)
		

if(__name__=='__main__'):
	parser=argparse.ArgumentParser(description='This script polls a user-accessible files for pings and sends a notification if a ping is found')
	
	parser.add_argument(
		'url',
		type=str,
		help='The URL to check for pings; for a local file prefix the path with file://',
		default=None
	)
	
	parser.add_argument(
		'--chk-interval',
		action='store',
		dest='chk_interval',
		type=int,
		help='The number of seconds between polling events.  Default 5 seconds.  ',
		default=5
	)
	
	args=parser.parse_args()
	
	ping_poll_loop(args.url,chk_interval=args.chk_interval)

