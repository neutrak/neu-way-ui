#!/bin/bash

#clear the primary (middle-click) clipboard
#NOTE: I know wl-copy has a -c flag that's supposed to clear the clipboard, but it doesn't work reliably
echo -n "" | wl-copy -p

err_code=$?
if [ $err_code != "0" ]
then
	exit $err_code
fi

#clear the secondary (ctrl+c ctrl+v) clipboard
#NOTE: I know wl-copy has a -c flag that's supposed to clear the clipboard, but it doesn't work reliably
echo -n "" | wl-copy

err_code=$?
if [ $err_code != "0" ]
then
	exit $err_code
fi

#send the user a message letting them know that the clipboards were cleared
#because without any output you can't know if anything actually happened
#swaynag -t 'warning' --background '#287755' --border-bottom '#287755' --button-background '#900000' --border '#900000' --text '#ffffff' -m "Wayland clipboards successfully cleared"

notify-send -t 5000 "Clipboards Cleared" "Primary and secondary clipboards have been cleared"

