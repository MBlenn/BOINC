#!/bin/bash
#
# v20250220 - initial version
#
unset -v WUname
targetDiff=10
sleep=90

while getopts hs:t:w: opt
do
   case $opt in
        t) targetDiff=$OPTARG;;
        w) WUname=$OPTARG;;
	s) sleep=$OPTARG;;
        h) help;;
        *) exit;;
   esac
done

if [[ -z $WUname ]]; then
	echo "WU name not specified, use -w to set"
	exit 1
else
	echo "WU name specified:		$WUname"
fi
echo "Sleep interval (s):		${sleep}"
echo "Progress diff target (%):	${targetDiff}"

while true; do 
	numWUs=$(boinccmd --get_task_summary ws| awk -v pattern=$WUname '$1 ~ pattern { if($2=="executing") print }' | wc -l)

	if [[ numWUs -lt 2 ]]; then
		sleep 30
		continue
	fi

	activeWUs=$(boinccmd --get_task_summary cws | awk -v pattern=$WUname '$2 ~ pattern { if($3=="executing") print $1" "$2"|"}'); 
	topWUpct=$(echo -e $activeWUs | tr '[|]' '\n' | sed -E 's/%//g' | sort -rn | egrep -v "^$" | head -1 | awk '{ print $1 }')
	lowWUpct=$(echo -e $activeWUs | tr '[|]' '\n' | sed -E 's/%//g' | sort -rn | egrep -v "^$" | tail -1 | awk '{ print $1 }')
	lowWU=$(echo -e $activeWUs | tr '[|]' '\n' | sed -E 's/%//g' | sort -rn | egrep -v "^$" | tail -1 | awk '{ print $2 }')

	WUpctDiff=$( echo "${topWUpct}-${lowWUpct}" | bc -l)
	if (( $(echo "$WUpctDiff < $targetDiff" |bc -l) )); then 
		echo -e $activeWUs | tr '[|]' '\n'
		lowResult=$(boinccmd --get_state | grep "   name: ${lowWU}_" | awk '{ print $2 }')
		echo "WUpctDiff is $WUpctDiff, target >${targetDiff}%, suspending $lowResult"

		projectUrl=$(boinccmd --get_tasks | egrep -A 2 $lowResult | awk '/project URL/ {print $3 }')
		echo boinccmd --task ${projectUrl} ${lowResult} suspend
		boinccmd --task ${projectUrl} ${lowResult} suspend
		sleep 30
		echo boinccmd --task ${projectUrl} ${lowResult} resume
		boinccmd --task ${projectUrl} ${lowResult} resume
		sleep $sleep
	fi
	sleep 30
done
