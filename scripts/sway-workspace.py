#!/usr/bin/env python3

# this script allows cycling to and from workspaces without windows on them
# which is not the default sway wm behaviour
# as the default behaviour skips over any workspaces that are defined but contain no windows

import json
import subprocess
import sys

direction='next' # prev|next
action='move' # move|focus

workspace_list=["0","1","2","3","4","5","6","7","8","9"]
# workspace_list=["1","2","3","4","5","6","7","8","9","10"] # 1-indexing  if you're like that...
# workspace_list=["mercury","venus","earth","mars","jupiter","saturn","uranus","neptune"] # also just any name as a string

def usage():
	print('Usage: '+sys.argv[0]+' <direction> <action> [<workspace_list>]')
	print('		direction: prev|next ; direction in which to move')
	print('		action: focus|move ; whether to move your focus (focus) or the window which you have focused (move)')
	print('		workspace_list : the comma-separated workspace name list')
#	1>&2;
	sys.exit(1)

if(len(sys.argv)<3):
	usage()

#TODO: use argparse to make argument parsing cleaner and help text better
direction=sys.argv[1]
action=sys.argv[2]
if(len(sys.argv)>=4):
	workspace_list=sys.argv[3].split(',')

#print('direction=',direction) #debug
#print('action=',action) #debug
#print('workspace_list=',workspace_list) #debug

#detect the current workspace based on the output of swaymsg -t get_workspaces -r
#then parsing that output as json
#and looking for the "focused" attribute

focus_idx=0
sway_workspace_idx=-1
swaymsg_rslt=subprocess.run(['swaymsg','-t','get_workspaces','-r'],capture_output=True)
workspace_state=json.loads(swaymsg_rslt.stdout)
for focus_idx in range(0,len(workspace_state)):
	if(workspace_state[focus_idx]['focused']):
		#if the item at this index is focused then we got the focused index
		
		#if this is a workspace then we have the sway_workspace_idx
		if(workspace_state[focus_idx]['type']=='workspace'):
			sway_workspace_idx=focus_idx
			
#			print('found a focused workspace at focus_idx=',focus_idx) #debug
			
			#and now that we found it we can stop looking
			break


#print('focus_idx=',focus_idx) #debug
sway_workspace_name=workspace_state[sway_workspace_idx]['name']
#print('sway_workspace_name=',sway_workspace_name) #debug

#if the current workspace wasn't found then return an error
if(sway_workspace_idx<0):
	print('Could not detect current workspace; please ensure that sway is running')
	sys.exit(1)

workspace_list_idx=-1
for list_idx in range(0,len(workspace_list)):
	if(workspace_list[list_idx]==sway_workspace_name):
		workspace_list_idx=list_idx
		break

if(workspace_list_idx<0):
	print('Could not find workspace '+sway_workspace_name+' in the array '+str(workspace_list)+' ; please ensure sway config matches this script for workspace names')
	sys.exit(1)

dir_offset=0
if(direction=='next'):
	dir_offset=1
elif(direction=='prev'):
	dir_offset=-1

#calculate new workspace number as new_workspace_list_idx=workspace_list_idx+dir_offset with wraparound
new_workspace_list_idx=workspace_list_idx+dir_offset
if(new_workspace_list_idx<0):
	new_workspace_list_idx=len(workspace_list)-1
elif(new_workspace_list_idx>=len(workspace_list)):
	new_workspace_list_idx=0

#finally get the name of the new workspace from the list
new_workspace_name=workspace_list[new_workspace_list_idx]

#print('new_workspace_list_idx=',new_workspace_list_idx) #debug
#print('new_workspace_name=',new_workspace_name) #debug

#apply the action; either focus or move the currently selected window to the new_workspace_list_idx workspace in workspace_list

if(action=='focus'):
	subprocess.run(['swaymsg','workspace',new_workspace_name])
elif(action=='move'):
	subprocess.run(['swaymsg','move','window','to','workspace',new_workspace_name])

