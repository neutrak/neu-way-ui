#!/usr/bin/env python3

#this script polls mako notifications using the "makoctl list" utility
#and outputs a summar to a 16x2 character LCD display

import argparse
import json

#subprocess library is needed for makoctl (input) and minicom (output) calls
import subprocess

import time

#this function periodically checks for notifications in mako
#and outputs the result to the given serial device
#args:
#	ttydev: the filesystem path for the output device
#	chk_interval: the number of seconds between polling events (i.e. the polling interval)
#	disp_cols: the number of text columns available on the output device
#	disp_rows: the number of text rows available on the output device
#	scroll_rate_ms: the number of milliseconds between marquee scrolling events for long messages
#	scroll_in: whether or not to scroll text in from the right rather than starting at the text start
#return:
#	None
#side-effects:
#	reads mako notifications and outputs them to ttydev
def serial_notify_poll_loop(ttydev:str='/dev/ttyACM0',chk_interval=5,disp_cols=16,disp_rows=2,scroll_rate_ms=400,scroll_in=False):
	#clear out the output device before doing anything else
	output_p=subprocess.run(['minicom','-o','-D',ttydev],input=(''.join(["\r" for n in range(0,disp_rows)])).encode('utf-8'),bufsize=0)
	
	while True:
		mako_list_p=subprocess.run(['makoctl','list'],capture_output=True)
		if(mako_list_p.returncode!=0):
			time.sleep(chk_interval)
			continue
		
		mako_list=json.loads(mako_list_p.stdout.strip())
		notifications=[]
		
		if('data' in mako_list):
			if((type(mako_list['data']) is list) and (len(mako_list['data'])>0)):
				if(len(mako_list['data'][0])>0):
					for entry in mako_list['data']:
						notifications.extend(entry)
		
		#NOTE: regardless of the polling interval we do full/complete output before running another iteration
		#this is to ensure that long messages get output before getting overwritten
		
		#we output each notification as two lines
		#first line is summary
		#second line is body
		#TODO: generalize this better to support larger displays which could potentially fit multiple notifications in a single screen refresh
		for notification in notifications:
			scroll_pos=0
			if(scroll_in):
				scroll_pos=0-disp_cols
			
			while(scroll_pos<=max(len(notification['summary']['data']),len(notification['body']['data']),disp_cols)):
				output_lines=[]
				
				for data_type_key in ['summary','body']:
					#NOTE: for some reason my character LCD doesn't let me use the last character
					#if I attempt to use it the display scrolls up and puts what should be the second line on the first line
					#so for now there's a hard-coded -1 to prevent that last character from being used
					line_chr_offset=0
					if(len(output_lines)+1==disp_rows):
						line_chr_offset=-1
					
					if(scroll_pos>=0):
						output_line=notification[data_type_key]['data'][scroll_pos:scroll_pos+disp_cols+line_chr_offset]
						output_line+=''.join([' ' for n in range(0,disp_cols-len(output_line)+line_chr_offset)])
						output_lines.append(output_line)
					elif(scroll_pos>(0-disp_cols)):
						output_line=''.join([' ' for n in range(0,(scroll_pos*(-1)))])
						output_line+=notification[data_type_key]['data'][0:(disp_cols+scroll_pos+line_chr_offset)]
						output_line+=''.join([' ' for n in range(0,disp_cols-len(output_line)+line_chr_offset)])
						
						output_lines.append(output_line)
				
				#NOTE: this \r\r clears out the display from anything it might have previously stored
#				output_str="\r\r"
				output_str="\r"
				for line in output_lines:
					output_str+=line
				
				output_p=subprocess.run(['minicom','-o','-D',ttydev],input=output_str.encode('utf-8'),bufsize=0)
			
				time.sleep((scroll_rate_ms/1000.0))
				scroll_pos+=1
			
			#always wait 2 seconds between showing different notifications
			#to avoid infinite-scroll fatigue
			time.sleep(2)
			
		
		time.sleep(chk_interval)

if(__name__=='__main__'):
	parser=argparse.ArgumentParser(description='This script polls mako notifications via makoctl and outputs a summary to a connected serial device (expected to be a 16x2 LCD character display by default)')
	
	parser.add_argument(
		'ttydev',
		type=str,
		help='The tty device to output messages to.  In most cases this should be /dev/ttyACM0.  ',
		default=None
	)
	
	parser.add_argument(
		'--chk-interval',
		action='store',
		dest='chk_interval',
		type=float,
		help='The number of seconds between notification polling events.  Default 2 seconds.  ',
		default=2
	)
	parser.add_argument(
		'--disp-cols',
		action='store',
		dest='disp_cols',
		type=int,
		help='The number of character columns on the output device.  Default 16 columns.  ',
		default=16
	)
	parser.add_argument(
		'--disp-rows',
		action='store',
		dest='disp_rows',
		type=int,
		help='The number of character rows on the output device.  Default 2 rows.  ',
		default=2
	)
	parser.add_argument(
		'--scroll-rate-ms',
		action='store',
		dest='scroll_rate_ms',
		type=int,
		help='The number of milliseconds between scrolling output refreshes.  Default 400 milliseconds.  ',
		default=400
	)
	parser.add_argument(
		'--scroll-in',
		action='store_const',
		dest='scroll_in',
		const=True,
		help='Whether or not to scroll text in from the right (starting with a blank screen).  Default False.  ',
		default=False
	)
	
	args=parser.parse_args()
	
	serial_notify_poll_loop(args.ttydev,chk_interval=args.chk_interval,disp_cols=args.disp_cols,disp_rows=args.disp_rows,scroll_rate_ms=args.scroll_rate_ms,scroll_in=args.scroll_in)

