#define environmental conditions so different aliases can be applied in different contexts

#current session id based on process variables
#login_session_id=$(cat /proc/"$$"/sessionid)

#current session id from ps because ubuntu is dumb
login_session_id="$(ps --pid "$$" -o "pid,lsession" | tail -n 1 | awk '{print $2}')"

#figure out whether the current session is wayland or x11 or cli
is_wayland=false
is_x11=false
if [ "$(loginctl show-session -p Type $login_session_id)" == "Type=wayland" ]
then
	is_wayland=true
elif [ "$(loginctl show-session -p Type $login_session_id)" == "Type=x11" ]
then
	is_x11=true
fi

#absolute essentials section
alias nvm='unset HISTFILE && exit'
alias cp='cp -p -v'

#colors on common utilities
#all terminals this will run on are expected to have color support
alias ls='ls --color=always'
alias grep='grep --color=always'
alias egrep='grep -E --color=always'
alias fgrep='grep -F --color=always'

#helpful program extensions
alias youtube-dl='youtube-dl --no-mtime'
alias ff-profile-select='firefox --new-instance --ProfileManager'
alias firefox-profile-select='firefox --new-instance --ProfileManager'
alias ff-wayland='MOZ_ENABLE_WAYLAND=1 firefox --new-instance --ProfileManager'
alias pulseaudio-equalizer='qpaeq' # I always forget the name of the binary for this; this is the package name

#iff this is x11, then alias tmpv
if [ $is_x11 == "true" ]
then
	alias tmpv="mpv -quiet -fs --vo=gpu --wid=`xwininfo -id $WINDOWID -tree | tail -n 2 | grep -oP '0x[0-9a-f]+ '`"
fi

#iff this is wayland, use wayland for mpv video output
if [ $is_wayland == "true" ]
then
#	alias mpv="mpv --vo=wlshm" # MEMORY LEAK on *buntu 22.04 :(
#	alias mpv="mpv --vo=gpu"
	alias mpv="mpv --vo=gpu --ao=pulse," #default to pulseaudio, required for bluetooth headsets (falls back to other sound services if pulse isn't configured due to comma)
fi

#short scripts
alias bios='[ -f /usr/sbin/dmidecode ] && sudo -v && echo -n "Motherboard" && sudo /usr/sbin/dmidecode -t 1 | grep "Manufacturer\|Product Name\|Serial Number" | tr -d "\t" | sed "s/Manufacturer//" && echo -ne "\nBIOS" && sudo /usr/sbin/dmidecode -t 0 | grep "Vendor\|Version\|Release" | tr -d "\t" | sed "s/Vendor//"'
alias spellcheck='echo y | ~/.config/custom-themes/neu-way-ui/scripts/line-diff.py --color --line ""'
alias spell='spellcheck'


