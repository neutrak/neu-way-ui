#~/.bashrc ; bash startup file

#if bash is not running interactively, don't do anything
if [ "$(echo "$-" | fgrep -o 'i')" == '' ]
then
	return
fi

#don't put duplicate lines in the history file
HISTCONTROL=ignoredups

#keep 1000 lines of command history and a file large enough to store that
HISTSIZE=1000
HISTFILESIZE=2000

#append to the history file, don't overwrite it
shopt -s histappend

#set us-altgr-intl as keymap
#NOTE: this is already done in sway configuration and so is only needed for console and X11
#so normally this shouldn't really matter
export XKB_DEFAULT_LAYOUT=us
export XKB_DEFAULT_VARIANT=altgr-intl
export XKB_DEFAULT_OPTIONS=compose:ralt

#if color is supported
if [ -e '/usr/bin/tput' ]
then
	#set a color prompt
	PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
	#otherwise set a still-usable non-color prompt
	PS1='\u@\h:\w\$ '
fi

#set PATH so it includes user's private ~/.local/bin if it exists
if [ -d "$HOME/.local/bin" ]
then
	PATH="$HOME/.local/bin:$PATH"
fi

#set PATH so it includes user's private bin if it exists
if [ -d "$HOME/bin" ] ; then
	PATH="$HOME/bin:$PATH"
fi

#set PATH so it includes user's cargo bin if it exists
#necessary for alacritty on ubuntu
if [ -d "$HOME/.cargo/bin" ] ; then
	PATH="$HOME/.cargo/bin:$PATH"
fi

#alias definitions (stored in a separate file)
if [ -f ~/.bash_aliases ]
then
	. ~/.bash_aliases
fi


#detect which linux distribution is in use
#supported distributions are currently arch and ubuntu
#NOTE: for ubuntu lightdm is expected, as is present on xubuntu
#other display managers require manual configuration
distro=''
if [ -n "$(uname -a | fgrep -o 'arch')" ]
then
	distro='arch'
elif [ -n "$(uname -a | fgrep -o 'Ubuntu')" ]
then
	distro='ubuntu'
fi

#run any/all arch-specific behaviour
if [ "${distro}" == 'arch' ]
then
	#on login to tty1, auto-start sway (the wayland compositor)
	#other ttys such as tty2 do not have this behaviour and can be used for debugging
	if [ -z $DISPLAY ] && [ "$(tty)" = '/dev/tty1' ]
	then
		exec sway
	fi
elif [ "${distro}" == 'ubuntu' ]
then
	#NOTE: bash tab completion should be enabled automatically by /etc/bash.bashrc or /etc/profile
	#but just in case, it's also enabled here
	. /etc/bash_completion
fi

