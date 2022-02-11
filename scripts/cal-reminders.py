#!/usr/bin/env python3

#this script reads ics files (expected to be populated through vdirsyncer)
#and shows any scheduled reminders for events

import argparse
import datetime
import icalendar
import os
import pytz
import recurring_ical_events
import sys
import time

#detect timezone from system settings
#but fall back to America/Toronto if the library for that isn't installed
TIMEZONE='America/Toronto'

try:
	import tzlocal
	TIMEZONE=tzlocal.get_localzone().zone
except ImportError as e:
	pass

print('Using timezone ',TIMEZONE) #debug

#this function gets the current time in a timezone-aware manner
#args:
#	None
#
#return:
#	returns a datetime.datetime object with the current timezone-aware time
#	using configured timezone
#
#side-effects:
#	None
def get_now():
#	local_tz=pytz.reference.LocalTimezone()
#	local_tz=datetime.datetime.now().astimezone().tzinfo
#	local_tz=pytz.timezone(TIMEZONE)
	local_tz=None
	return datetime.datetime.now(tz=local_tz)


#this function escapes quotes so that the string can be included within a bash string in certain contexts
#args:
#	argstr: the string to be escaped
#
#return:
#	returns a (more) sanitized version of the provided argstr
#
#side-effects:
#	None
def bash_quote(argstr):
	argstr=argstr.replace('\`','') #remove backticks
	argstr=argstr.replace('\$','') #remove dollar signs
	
#	argstr=argstr.replace('\"','\"\'\"\'\"')
	argstr=argstr.replace('\"','') #remove double-quotes
	argstr=argstr.replace('\'','\'"\'"\'') #escape single-quotes
	return argstr

#this function deletes any existing scheduled notifications for the given event
#args:
#	event_id: the uuid of the event to clear notifications for
#
#return:
#	None
#
#side-effects:
#	removes jobs in the at queue which contain the string "event_id = "+event_id in their command string
#	as those jobs are by definition for the event we're clearing out notifications for
def clear_notifications_for_event(event_id):
	#get all the scheduled jobs from at
	job_numbers=os.popen('atq | awk \'{print $1}\'').read()
	if(len(job_numbers)>0):
		job_numbers=job_numbers.split("\n")
	else:
		job_numbers=[]
	
	#for each of them
	for job_number in job_numbers:
		#skip empty strings
		if(job_number==''):
			continue
		
		#if this at job matches the event_id we were given
		event_id_match=os.popen('at -c '+str(job_number)+' | fgrep -o \'event_id = '+str(event_id)+'\'').read()
		if(len(event_id_match)>0):
			#then clear out that job
			os.popen('atrm '+str(job_number))

#this function gets the next occurrance of an event
#args:
#	event: the icalendar.Event to get the next occurance for
#
#return:
#	returns a datetime.datetime object for the next time the event occurs
#	or None if next occurrance can't be determined
#
#side-effects:
#	None
def get_next_occurrance(event):
	now=get_now()
	
	#if this isn't an event
	if(not isinstance(event,icalendar.Event)):
		#then the next occurrance is never
		return None
	
	#find all occurrances of this event from now to 5 years from now
	#(figuring that to be worth having in the calendar any event needs to occur at least once in 5 years)
	occurrances=recurring_ical_events.of(event).between(now,now+datetime.timedelta(days=(365.25*5)))
	if(len(occurrances)>0):
		dt_start_time=occurrances[0].decoded('DTSTART')
		
		#if this is an "all day event" that doesn't include an actual start time but just a date
		#then assume it starts at 0:00 on that day
		#and convert data types accordingly
		if((not isinstance(dt_start_time,datetime.datetime)) and (isinstance(dt_start_time,datetime.date))):
			dt_start_time=datetime.datetime(
				year=dt_start_time.year,
				month=dt_start_time.month,
				day=dt_start_time.day,
			)
		
		#otherwise return the time of the first occurrance which is after the present time
		return dt_start_time
	
	#if we got here and didn't return that means that the event isn't in the future and doesn't recur
	#which means there is no next occurrance; this event has already occurred for the last time
	#(and may or may not still be actively ongoing)
	return None

#this function gets all the events from the given calendar and returns them as a list
#args:
#	cal: the icalendar.Calendar object to check
#
#return:
#	list of event objects (or empty list if no events are found)
#
#side-effects:
#	None
def get_events_from_cal(cal) -> list:
	#accumulator, initially empty
	acc=[]
	
	#if this is an event then we're at a leaf node
	if(isinstance(cal,icalendar.Event)):
#		print('Event found: ',cal)
		acc=[cal]
		return acc
	
	#skip files which can't be parsed
	if(len(cal.errors)>0):
		print('Err: ics file malformed: ',cal.errors)
		return []
	
	#for each subcomponent, get the events from that as well
	#and store them in the accumulator
	#NOTE: if cal was an event we already returned prior to this recursive call
	for subcomponent in cal.subcomponents:
		acc.extend(get_events_from_cal(subcomponent))
	
	return acc


#this function gets all the valarms for a particular event and returns them as a list
#args:
#	event: the icalendar.Event object to check
#
#return:
#	list of valarm objects (or empty list if no valarms are found)
#
#side-effects:
#	None
def get_valarms_from_event(event) -> list:
	#accumulator, initially empty
	acc=[]
	
	#if this is an alarm then we're at a leaf node
	#so just return that as a single-element list
	if(isinstance(event,icalendar.Alarm)):
		acc=[event]
		return acc
	
	#skip files which can't be parsed
	if(len(event.errors)>0):
		print('Err: ics file malformed: ',event.errors)
		return []
	
	#for each subcomponent, get the alarms from that as well
	#and store them in the accumulator
	#NOTE: if event was an alarm we already returned prior to this recursive call
	for subcomponent in event.subcomponents:
		acc.extend(get_valarms_from_event(subcomponent))
	
	return acc

#this function scans through the given directory recursively looking for ics files
#when an ics file is found its information is cached
#and if there are any upcoming reminders for the event (VALARMS) notifications are scheduled via the `at` utility
#
#args:
#	icsdir: the top level directory to look for ics files
#
#return:
#	None
#
#side-effects:
#	reads ics files, updates event cache, and schedules notifications
def scan_ics_files(icsdir:str=None):
	now=get_now()
	utc_now=datetime.datetime.utcnow()
	
	if(icsdir is None):
		raise Exception('Err: ICS directory not provided')
		return None
	
	if(not os.path.isdir(icsdir)):
		raise Exception('Err: Given ICS directory '+str(icsdir)+' is not actually a directory on disk')
		return None
	
#	print('Checking in '+icsdir) #debug
	
	#for each file in the directory
	filenames=os.listdir(icsdir)
	for fname in filenames:
		fpath=os.path.join(icsdir,fname)
		
		#if this is a directory, then recurse
		#as we want to search for ics files in all subdirectories as well
		if(os.path.isdir(fpath)):
			scan_ics_files(os.path.join(icsdir,fname))
			continue
		
		#if this isn't a directory, check if it has the .ics file extension
		#we ignore any files that aren't ics files
		fname_parts=fname.split('.')
		if(fname_parts[len(fname_parts)-1]!='ics'):
			continue
		
#		print('Found ics file '+fpath+' ...') #debug
		
		#read the ics file content
		fp=open(fpath)
		fcontent=fp.read()
		fp.close()
		
#		print('Read '+str(len(fcontent))+' characters') #debug
		
		#TODO: parse ics, store events and tasks in an sqlite3 cache, and show reminders as needed using notify-send
		cal=icalendar.Calendar.from_ical(fcontent)
		
		#get the events out of the ics file
		#(the way nextcloud stores these there's one event per ics file, so this should be list with one item in practice)
		events=get_events_from_cal(cal)
#		print('Found '+str(len(events))+' event(s)') #debug
		
		for event in events:
			next_occurrance=get_next_occurrance(event)
			summary=event.get('SUMMARY')
			description=event.get('DESCRIPTION')
			event_id=event.get('UID')

			#check atq to make sure there isn't already a reminder for this event scheduled
			#(if necessary we might need to include some uuid information to identify which event this reminder is for)
			#if there is already a reminder then clear it out before adding the new one
			clear_notifications_for_event(event_id)
			
			#if this event isn't already over, look for any alarms/reminders
			if(not (next_occurrance is None)):
				print('Event "'+summary+'" ('+str(event_id)+') next occurs at ',next_occurrance) #debug
				
				valarms=get_valarms_from_event(event)
				
				for valarm in valarms:
					valarm_time=next_occurrance+valarm.decoded('TRIGGER')
					
					is_tz_aware=False
					if((not (valarm_time.tzinfo is None)) and (not (valarm_time.tzinfo.utcoffset(valarm_time) is None))):
						is_tz_aware=True
					
#					print('valarm_time=',valarm_time)
#					print('is_tz_aware=',is_tz_aware) #debug
#					print('now=',now) #debug
#					print('utc_now=',utc_now) #debug
					
					#if this alarm is meant to be sent AT or AFTER the current time
					#NOTE: this check is necessary because although the event itself might be in the future
					#the alarm time might at this point be in the past
					if((is_tz_aware and (valarm_time>=pytz.timezone(TIMEZONE).localize(now))) or ((not is_tz_aware) and valarm_time>=utc_now)):
						#schedule an alarm/reminder/notification for the valarm time
						#using the unix "at" and "notify-send" utilities
						
						print('Scheduling reminder for "'+summary+'" at ',valarm_time,'...') #debug
						
						cmd='echo \''
						
						#tag the job with the event uid so we can later figure out what jobs correspond to what events
						cmd+='# event_id = '+event_id+"\n"
						
						cmd+='notify-send "['+next_occurrance.strftime('%Y-%m-%d %H:%M')+'] '+bash_quote(summary)+'"'
						if(not (description is None)):
							cmd+=' "'+bash_quote(description)+'"'
						
						cmd+='\' | at -M -t \''+(valarm_time.strftime('%Y%m%d%H%M'))+'\' 2> /dev/null'
						
	#					print(cmd) #debug
						os.popen(cmd).read()

if(__name__=='__main__'):
	parser=argparse.ArgumentParser(
		description='This script reads ics event files (calendar event format) and shows corresponding reminders'
	)
	
	parser.add_argument(
		'--icsdir',
		type=str,
		help='The directory to scan for ics files',
		default=os.path.join(os.environ['HOME'],'.vdirsyncer','calendars')
	)

	parser.add_argument(
		'--poll-interval',
		type=int,
		help='The number of seconds between syncing/polling events; default 43200 seconds (12 hours)',
		default=43200
#		help='The number of seconds between syncing/polling events; default 3600 seconds (1 hour)',
#		default=3600
	)
	
	args=parser.parse_args()
	
	while True:
		try:
			#get recent information from online calendars
			print('Synchronizing calendars using vdirsyncer...') #debug
			os.popen('vdirsyncer sync').read()
			
			#wait 5 seconds to make sure all files have finished writing after the sync operation
			time.sleep(5)
			
			#scan ics files and look for event information and updates
			print('Scanning ics files for events...') #debug
			scan_ics_files(args.icsdir)
		#if anything bad/unexpected happens, just wait until the next cycle and try again
		#rather than hard-crashing
		except Exception as e:
			print('Err: '+str(e)) #debug
		
		print('Waiting until '+(datetime.datetime.now()+datetime.timedelta(seconds=args.poll_interval)).strftime('%Y-%m-%d %H:%M')+' before re-syncing calendar information...') #debug
		
		#wait the polling interval before checking again
		time.sleep(args.poll_interval)

