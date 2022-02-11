#!/bin/bash

#NOTE: this script has been replaced by the python version sway-workspace.py
#it is kept here only as reference and in case there is a system that needs this functionality and doesn't have python installed

# this script allows cycling to and from workspaces without windows on them
# which is not the default sway wm behaviour
# as the default behaviour skips over any workspaces that are defined but contain no windows

direction='next' # prev|next
action='move' # move|focus

workspace_list=("0" "1" "2" "3" "4" "5" "6" "7" "8" "9")
# workspace_list=("1" "2" "3" "4" "5" "6" "7" "8" "9" "10") # 1-indexing  if you're like that...
# workspace_list=("mercury" "venus" "earth" "mars" "jupiter" "saturn" "uranus" "neptune") # also just any name as a string

usage() {
	echo "Usage: $0 <direction> <action>";
#	echo "Usage: $0 <direction> <action> [<workspace_list>]";
	echo "		direction: prev|next ; direction in which to move";
	echo "		action: focus|move ; whether to move your focus (focus) or the window which you have focused (move)";
#	echo "		workspace_list : the comma-separated workspace name list"
	1>&2;
	exit 1;
}

if [ "$#" -lt "2" ]
then
	usage
fi

direction=$1
action=$2
#if [ "$#" -ge "3" ]
#then
#	#TODO: support parsing command-line workspace lists; for now you have to set it as a code constant
#	#currently this is not working correctly
#	workspace_list=("$3")
#fi

#echo "direction=$direction" #debug
#echo "action=$action" #debug
#echo "workspace_list=${workspace_list[@]}" #debug

#detect the current workspace based on the output of swaymsg -t get_workspaces -r | jq
#and looking for the "focused" attribute

focus_idx=0
sway_workspace_idx=-1
workspaces_json=$(swaymsg -t get_workspaces -r)
while [ "$(echo $workspaces_json | jq -r ".[${focus_idx}].focused")" != 'null' ]
do
	focus_state=$(echo $workspaces_json | jq -r ".[${focus_idx}].focused")
#	echo "focus state for index ${focus_idx} is $focus_state" #debug
	if [ "$focus_state" = "true" ]
	then
		#if the item at this index is focused then we got the focused index
		
		#if this is a workspace then we have the sway_workspace_idx
		if [ "$(echo $workspaces_json | jq -r ".[${focus_idx}].type")" = 'workspace' ] 
		then
			sway_workspace_idx=$focus_idx
			
#			echo "found a focused workspace at focus_idx=$focus_idx" #debug
			
			#and now that we're done we can stop looking
			break
		fi
	fi
	
	focus_idx=$(($focus_idx+1))
done
#echo "focus_idx=$focus_idx" #debug
sway_workspace_name="$(echo $workspaces_json | jq -r ".[${sway_workspace_idx}].name")"
#echo "sway_workspace_name=$sway_workspace_name" #debug

#if the current workspace wasn't found then return an error
if [ "$sway_workspace_idx" -lt 0 ]
then
	echo "Could not detect current workspace; please ensure that sway is running"
	exit 1
fi

workspace_list_idx=-1
list_idx=0
while [ "$list_idx" -lt "${#workspace_list[@]}" ]
do
	if [ "${workspace_list[$list_idx]}" = "$sway_workspace_name" ]
	then
		workspace_list_idx=$list_idx
		break
	fi
	
	list_idx=$(($list_idx + 1))
done

if [ "$workspace_list_idx" -lt 0 ]
then
	echo "Could not find workspace $sway_workspace_name in the array ${workspace_list[@]} ; please ensure sway config matches this script for workspace names"
	exit 1
fi

dir_offset=0
if [ "$direction" = 'next' ]
then
	dir_offset=1
elif [ "$direction" = 'prev' ]
then
	dir_offset=-1
fi

#calculate new workspace number as new_workspace_list_idx=workspace_list_idx+dir_offset with wraparound
new_workspace_list_idx=$(($workspace_list_idx + $dir_offset))
if [ "$new_workspace_list_idx" -lt 0 ]
then
	new_workspace_list_idx=$((${#workspace_list[@]} - 1))
elif [ "$new_workspace_list_idx" -ge "${#workspace_list[@]}" ]
then
	new_workspace_list_idx=0
fi

#finally get the name of the new workspace from the list
new_workspace_name=${workspace_list[$new_workspace_list_idx]}

#echo "new_workspace_list_idx=$new_workspace_list_idx" #debug
#echo "new_workspace_name=$new_workspace_name" #debug

#apply the action; either focus or move the currently selected window to the new_workspace_list_idx workspace in workspace_list

if [ "$action" = "focus" ]
then
	swaymsg workspace "$new_workspace_name"
elif [ "$action" = "move" ]
then
	swaymsg move window to workspace "$new_workspace_name"
fi

