#!/bin/bash

temps=$(sensors | fgrep 'Core' | cut -d '(' -f '1' | grep -o "[+-][0-9]*\.[0-9]*" | sed 's/[-+]//g')

total=0
count=0

for temperature in $temps
do
	total=$(echo "$total+$temperature" | bc)
	count=$(echo "$count+1" | bc )
done

if [ "$count" -ne 0 ]
then
	avg=$(echo "scale=1;$total/$count" | bc)
else
	avg="N/A"
fi

echo "$avg"

