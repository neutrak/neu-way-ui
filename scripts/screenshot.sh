#!/bin/bash

#make screenshots directory if it does not already exist
mkdir -p ~/images/screenshots

#go there
cd ~/images/screenshots

window_id=''
current_window_only=false
if [ $# -ge 1 ]
then
	if [ "$1" == 'current-window' ]
	then
		#if we're only taking a screenshot of the current window
		#then include the window name in the output filename
		window_id="$(swaymsg -t get_tree | jq -r '.. | select(.focused?) | .name')-"
		current_window_only=true
	fi
fi

#get the datestamp for the filename
fname="${window_id}$(date +'%Y-%m-%d-%R:%S')-screenshot.png"

#take screenshot using grim
if [ "$current_window_only" == 'true' ]
then
	grim -g "$(swaymsg -t get_tree | jq -r '.. | select(.focused?) | .rect | "\(.x),\(.y) \(.width)x\(.height)"')" "$fname"
else
	grim "$fname"
fi

#display message
notify-send -t 5000 "screenshot saved" "~/images/screenshots/$fname"

