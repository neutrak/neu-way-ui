#!/bin/bash

#this is meant as a complete audio control script that dynamically detects the device to use
#so that key bindings can always work correctly

#possible actions are:
#	mute-toggle:	mutes/unmutes main audio output
#	vol-up:		increases volume on main audio output by 2dB
#	vol-down:	decreases volume on main audio output by 2dB

action=""
if [ $# -lt '1' ]
then
	echo "Usage: $0 <[mute-toggle|vol-up|vol-down]>"
	exit 1
fi

action="$1"

#if pulse is installed
if [ $(which pactl) == '/usr/bin/pactl' ]
then
	#dynamically detect the primary audio output device
	#as the last-connected pulse sink in the list
#	pulse_sink="$(pacmd list-sinks | fgrep index | tail -n 1 | egrep -o ': [0-9]+' | egrep -o '[0-9]+')"
	
	#keep the existing default sink, even if other sinks are present later in the list
	#by only considering the default index, denoted by "* index"
	pulse_sink="$(pacmd list-sinks | fgrep "* index" | tail -n 1 | egrep -o ': [0-9]+' | egrep -o '[0-9]+')"
	
#	pacmd set-default-sink "$pulse_sink"
	
	if [ "$action" == "mute-toggle" ]
	then
		echo "[pulse] mute-toggle..."
		pactl set-sink-mute "$pulse_sink" toggle
	elif [ "$action" == "vol-down" ]
	then
		echo "[pulse] vol-down..."
		pulse_delta="-2dB"
		pactl set-sink-volume "$pulse_sink" "$pulse_delta"
	elif [ "$action" == "vol-up" ]
	then
		echo "[pulse] vol-up..."
		pulse_delta="+2dB"
		pactl set-sink-volume "$pulse_sink" "$pulse_delta"
	fi
else
	card=0
	channel="Master"
	if [ "$action" == "mute-toggle" ]
	then
		echo "[alsa] mute-toggle..."
		amixer -c $card set $channel toggle
		amixer -c $card set "Headphone" unmute
	elif [ "$action" == "vol-down" ]
	then
		echo "[alsa] vol-down..."
		delta="2dB-"
		amixer -c $card set $channel $delta
	elif [ "$action" == "vol-up" ]
	then
		echo "[alsa] vol-up..."
		delta="2dB+"
		amixer -c $card set $channel $delta
	fi
fi

