#!/bin/bash

#this script stops the running instance of cal-reminder.py
#and then starts a new instance with expected parameters

#find all runnning instances
pids=$(ps -x | grep -F 'cal-reminders.py' | grep -F 'python3' | awk '{print $1}')

#convert the space-delimited string into an array
pids=($pids)

for pid in $pids
do
	if [ "$pid" != "" ]
	then
		#kill all cal-reminder processes that the above ps call returned
		kill  "$pid"
	fi
done

#fork and become the child process
exec python3 -u "$HOME/.config/custom-themes/neu-way-ui/scripts/cal-reminders.py" > /tmp/cal-reminders-output.log 2>&1

