#!/bin/bash

#this script is meant to install the neu-way-ui theme on top of a vanilla arch linux or ubuntu installation
#thus providing a quick way to get a configured UI on a new machine without a lot of effort
#NOTE: as both arch linux and ubuntu use systemd this script assumes that systemd is being used as the init system
#NOTE: this script MUST be run from the theme root directory (neu-way-ui) in order to work correctly, do not run it directly from scripts/
#NOTE: this script must be run as the primary user account of the new system in order for relative paths in /home/ to work correctly

#immediately exit if any error occurs, and do not continue execution after that point
set -e

#define helper functions

#pause until the user hits enter
#this is meant to prevent things like sudo timeouts
#args:
#	none
#return:
#	none
#side-effects:
#	no side-effects persist after return
pause () {
	read -p 'Press Enter to continue'
}

#change a single line in a file
#to be the new value given
#NOTE: the user executing this function must have permission to write to the file in question
#e.g. if the file is only accessible to root this function must be called with sudo
#args:
#	file_path: the path of the file to change
#	lineno: the line number within that file that should be changed
#	line_val: the new value of the line that should be changed
#return:
#	none
#side-effects:
#	writes updated file to disk before returning
change_file_line () {
	file_path="$1"
	lineno="$2"
	line_val="$3"
	
	if [ "$lineno" != "" ]
	then
		before=$(cat "$file_path" | head -n $((${lineno} - 1)))
		after=$(cat "$file_path" | tail -n $(($(wc -l "$file_path" | awk '{print $1}') - ${lineno})))
		
		#escape single quotes because we need them as part of the below bash line
		before=$(echo "${before}" | sed "s/'/'\"'\"'/g")
		after=$(echo "${after}" | sed "s/'/'\"'\"'/g")

		bash -c "printf '%s\n%s\n%s\n' '${before}' '${line_val}' '${after}' > '${file_path}'"
	fi
}

#this function updates /etc/systemd/logind.conf to set HandleLidSwitch=ignore
#args:
#	none
#return:
#	none
#side-effects:
#	edits /etc/systemd/logind.conf
ignore_handle_lid_switch () {
	#parse /etc/systemd/logind.conf and ensure [Login] HandleLidSwitch=ignore is set
	logind_lid_lineno=$(cat '/etc/systemd/logind.conf' | egrep -n "HandleLidSwitch\s*=" | awk -F ':' '{print $1}' | head -n 1)
	if [ "$logind_lid_lineno" == "" ]
	then
		sudo bash -c "echo 'HandleLidSwitch=ignore' >> '/etc/systemd/logind.conf'"
	else
		#get the line that defines the HandleLidSwitch setting
		logind_lid_line="$(cat '/etc/systemd/logind.conf' | head -n "${logind_lid_lineno}" | tail -n 1)"
		
		#if this line was commented out, uncomment it
		while [ "${logind_lid_line:0:1}" == "#" ]
		do
			logind_lid_line="${logind_lid_line:1}"
		done
		
		#update the value to be the new value we want to set (ignore)
		logind_lid_line="$(echo "${logind_lid_line}" | egrep -o '.*=')ignore"
		sudo bash -c "$(declare -f change_file_line) ; change_file_line '/etc/systemd/logind.conf' '$logind_lid_lineno' '$logind_lid_line'"
	fi
	echo "Logind configuration updated to set HandleLidSwitch=ignore; this setting will take effect on next reboot.  "
}

#this function is used to prompt the user whether or not an overwrite action is allowed
#args:
#	overwrite_path: the file or directory path that the script wants to overwrite
#return:
#	returns (echos) "true" if authorization is given, and "false" if authorization is denied
#	NOTE: because bash is stupid you need to pipe the output of this to "tail -n 1" to get the return value
#side-effects:
#	none; actual deletion of files and directories shoud only be done by calling code
authorize_overwrite () {
	overwrite_path="$1"

	#if the path exists, then ask to overwrite
	if [ -e "${overwrite_path}" ]
	then
		echo "Directory or file ${overwrite_path} already exists"
		echo "In order to run this script and set configuration, we need to overwrite it"
		read -p "Overwrite ${overwrite_path}? (Y/N) " overwrite
		
		#if permission is granted, let the calling code know
		if [ "${overwrite:0:1}" == "Y" ] || [ "${overwrite:0:1}" == "y" ]
		then
			echo "true"
		else
			echo "false"
		fi
	#if the path doesn't already exist then authorization is granted by default
	#since there's nothing to overwrite
	else
		echo "true"
	fi
}

#this function installs a package from the AUR (arch user repository)
#NOTE: the only packages installed by this script are packages that I've used before
#but we still have a pause point where the package can be checked just in case
#args:
#	pkg_name: the name of the package to install
#return:
#	none
#side-effects:
#	installs the given package (or aborts if the user didn't confirm the installation)
install_aur_package () {
	pkg_name="$1"
	
	start_dir="$(pwd)"
	
	"${HOME}/.config/custom-themes/neu-way-ui/scripts/aur-get.sh" "$pkg_name"
	mv "${pkg_name}.tar.gz" /tmp/
	cd /tmp/
	tar xvzf "${pkg_name}.tar.gz"
	cd "${pkg_name}"
	
	echo "Installing ${pkg_name} from AUR; check contents in /tmp/${pkg_name} to ensure this is as expected"
	read -p "Continue installation? (Y/N) " confirm_install

	if [ "${confirm_install:0:1}" == "Y" ] || [ "${confirm_install:0:1}" == "y" ]
	then
		makepkg -si
	#else do nothing; if install wasn't confirmed then just skip it and clean up
	fi
	
	cd "$start_dir"
	rm -rf "/tmp/${pkg_name}*"
}

#this function downloads and compiles programs that I have written and use
#args:
#	none
#return:
#	none
#side-effects:
#	downloads and installs the following programs:
#		accirc
compile_custom_programs () {
	starting_dir="$(pwd)"
	
	#install some of my own software that I use regularly
	if [ -d "${HOME}/programs/accirc" ]
	then
		echo "Skipping accirc because directory is already present..."
	else
		mkdir -p "${HOME}/programs"
		cd "${HOME}/programs"
		git clone 'https://github.com/neutrak/accirc.git'
		cd accirc
		make debug
		pause
		sudo make install
	fi
	
	cd "${starting_dir}"
}

#this is the main entry point for the theme installer script
#and can be thought of as main() for the purposes of this script
#args:
#	installer_dir: the directory of the installer
#	installer_dir_action: "link" or "copy" for whether to copy or link the theme directory
#		if linked, theme directory will be a symlink to this installer directory
#		if copied, theme directory will have its own version of all files and not be a link to this dir
#return:
#	none
#side-effects:
#	installs neu-way-ui theme and all dependencies and sets it as the in-use theme for the current user
install_neu_way_ui_theme () {
	installer_dir="$1"
	installer_dir_action="$2"
	
	theme_dest_dir="${HOME}/.config/custom-themes/neu-way-ui"

	echo "Warn: This installer script will attempt to overwrite local configuration (bashrc, tmux.conf, etc.)"
	echo "If you only want partial installation (for example a script or two) you are advised to NOT run this installer, and instead copy only those parts you want"
	read -p "Run installer script? (type YES to continue; any other input exits this script) " confirm_install
	if [ "${confirm_install}" != "YES" ]
	then
		echo "Exiting without making changes"
		exit 1
	fi
	
	if [ "${installer_dir_action}" == "copy" ]
	then
		echo "Copying theme files (config and scripts) to ${theme_dest_dir} ..."
	else
		echo "Making ${theme_dest_dir} as a symbolic link to the installer directory ..."
	fi
	
	#if the theme directory/file (~/.config/custom-themes/neu-way-ui) exists at all (and is either a file, or directory, or symbolic link)
	if [ -e "${theme_dest_dir}" ]
	then
		#if it's a link to where we already are then do nothing; this step is complete and can be skipped
		if [ -L "${theme_dest_dir}" ] && [ "$(readlink "${theme_dest_dir}")" == "${installer_dir}" ]
		then
			if [ "${installer_dir_action}" == "copy" ]
			then
				#since we know that the existing directory is a symbolic link to the installer dir
				#we can safely delete it and re-make it as a copy
				#without risking losing any data
				rm "${theme_dest_dir}"
				cp -L -r -p "${installer_dir}" "${theme_dest_dir}"
			else
				echo "Skipping creation of symbolic link to this directory because it already exists"
			fi
		#if this is something OTHER than a link to this directory
		#then we need to ask to overwrite it
		elif [ "$(authorize_overwrite "${theme_dest_dir}" | tail -n 1)" == "true" ]
		then
			rm -rf "${theme_dest_dir}"
			
			if [ "${installer_dir_action}" == "copy" ]
			then
				cp -L -r -p "${installer_dir}" "${theme_dest_dir}"
			else
				ln -s "${installer_dir}" "${theme_dest_dir}"
			fi
		else
			echo "Err: Could not install theme; theme directory already in use"
			exit 1
		fi
	#if the theme configuration directory doesn't already exist, then make it now
	#this should be the normal/general case when the script is used as intended
	else
		mkdir -p "${HOME}/.config/custom-themes/"
		if [ "${installer_dir_action}" == "copy" ]
		then
			cp -L -r -p "${installer_dir}" "${theme_dest_dir}"
		else
			ln -s "${installer_dir}" "${theme_dest_dir}"
		fi
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
	else
		echo "Unrecognized distribution; cannot continue; kernel version was $(uname -a)"
		exit 1
	fi

	#disable sleep and hibernate functionality; that's not something I ever want or use
	sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
	sudo systemctl stop sleep.target suspend.target hibernate.target hybrid-sleep.target
	
	#set logind to ignore lid switch events
	#because we don't use them or want them
	ignore_handle_lid_switch

	#detect distro (arch vs. ubuntu) and then install the appropriate required packages and dependencies
	#the following programs are required:
	#	vim (considering switching to neovim mostly for scripting options but for now we're still on vim)
	#	tmux
	#	sway (wayland compositor)
	#		swayidle
	#		swaylock
	#	waybar
	#	alacritty
	#	rofi
	#	xwayland
	#	wl-clipboard (xclip-like program for wayland)
	#	firefox
	#	pavucontrol
	#	gnome-calendar (which can integrate with nextcloud-calendar)
	#		gnome-online-accounts
	#	thunderbird
	#	pcmanfm
	#	khal vdirsyncer vdirsyncer-doc
	if [ "$distro" == 'arch' ]
	then
		echo 'Arch Linux detected; installing packages using pacman'
		
		#NOTE: /tmp is mounted as a tmpfs filesystem and not on the root partition by default in arch
		#so no action is needed to ensure that
		
		#start by updating what we already have and ensuring we have a fresh and stable base
		pause
		sudo pacman -Syu
		
		#install all build dependencies before the userspace packages
		pause
		sudo pacman -S linux-headers gcc clang make jq python python-pip at fontconfig wget base-devel git docbook-xsl which lsof guile bash-completion
		
		#install python libraries
		pause
#		pip install pytz tzlocal icalendar recurring-ical-events
#		sudo pacman -S python-pytz python-tzlocal python-icalendar python-recurring-ical-events
		sudo pacman -S python-pytz python-tzlocal python-icalendar
		
		#install userspace packages
		#TODO: add waypipe to this list if/when it is in the official arch linux repositories
		pause
		sudo pacman -S pass sway swayidle swaylock swaybg waybar otf-font-awesome xorg-xwayland alacritty firefox pavucontrol gnome-calendar gnome-online-accounts rofi thunderbird wl-clipboard khal vdirsyncer mako grim blueman oath-toolkit keepassxc remind at neovim python-pynvim pulseaudio-equalizer pavucontrol man-db man-pages texinfo vim cryptsetup minicom pcmanfm ncdu htop inkscape curl mpv mousepad ripgrep bc netctl dialog rsync encfs sonic-visualiser
		
		#install (and if necessary build) anything not available through repos
		
		#install "ccrypt" from AUR
		install_aur_package "ccrypt"
		
		#install "python-recurring-ical-events" from AUR
		install_aur_package "python-x-wr-timezone"
		install_aur_package "python-recurring-ical-events"
		
		#ensure that this user is a member of the necessary groups
		#which are at a minimum:
		#	disk wheel video audio uucp
		#and possibly:
		#	wireshark vboxusers
		pause
		active_user="$(whoami)"
		sudo usermod -a -G 'disk' "${active_user}"
		sudo usermod -a -G 'wheel' "${active_user}"
		sudo usermod -a -G 'video' "${active_user}"
		sudo usermod -a -G 'audio' "${active_user}"
		sudo usermod -a -G 'uucp' "${active_user}"
	elif [ "$distro" == 'ubuntu' ]
	then
		echo 'Ubuntu Linux detected; installing packages using apt-get'
		
		ubuntu_version="$(lsb_release -a | fgrep 'Description:' | egrep -o '[0-9]+\.[0-9]+.*')"
		echo "Detected Ubuntu version ${ubuntu_version}"
		
		#make sure /tmp is mounted as a tmpfs filesystem and not on the root partition
		#because for some reason this isn't default in ubuntu
		if [ ! -e "/etc/systemd/system/tmp.mount" ]
		then
			sudo ln -s /usr/share/systemd/tmp.mount /etc/systemd/system/tmp.mount
		fi
		sudo systemctl enable tmp.mount
		
		#start by updating what we already have and ensuring we have a fresh and stable base
		pause
		sudo bash -c 'apt-get update && apt-get dist-upgrade && apt-get autoremove && apt-get clean'
		
		#install all build dependencies before the userspace packages
		pause
		sudo apt-get install build-essential gcc clang cargo libxcb-* libgtk-layer-shell-dev jq python3 pipx at psmisc apparmor-utils fontconfig wget guile-2.2 python3-pip librust-libc-dev libssl-dev
		
		#install python libraries
		pause
		
		#NOTE: earlier in this script we already validated that we are running in the neu-way-ui theme root
		#so we know where this script is even if the theme hasn't officially been fully installed yet
		
		#if the ubuntu version in use is greater than 22.04
		if [ "$(./scripts/version-cmp.py "${ubuntu_version}" "22.04")" -gt 0 ]
		then
			#global python installation via pip is deprecated; use debian packages instead
			#python packages but installed via apt
			sudo apt-get install python3-full python3-pytzdata python3-tzlocal python3-icalendar python3-recurring-ical-events
	#		pip3 install pytz tzlocal icalendar recurring-ical-events #error: externally-managed-environment (2023-08-25, on ubuntu >= 23.04)
		#if we're on 22.04 LTS (the earliest version supported by this installer)
		else
			#not all packages are available in the repos so install global python packages via pip
			pip3 install pytz tzlocal icalendar recurring-ical-events
		fi
		
		
		#install userspace packages
		pause
		sudo apt-get install pass sway swayidle swaylock waybar xwayland ncurses-term firefox pavucontrol gnome-calendar gnome-online-accounts rofi libappindicator-* thunderbird wl-clipboard khal vdirsyncer vdirsyncer-doc mako-notifier grim blueman oathtool keepassxc remind at neovim python3-pynvim pulseaudio-equalizer pavucontrol vim cryptsetup minicom pcmanfm ncdu htop inkscape ccrypt curl mpv mousepad ripgrep rsync encfs sonic-visualiser waypipe

		#install (and if necessary build) anything not available through repos
		
		#NOTE: Ubuntu 20.04 LTS doesn't have alacritty in its repos
		#so we have to install it with cargo
		cargo install alacritty
		
		#once it's built we have to put it in the system path so that sway recognizes it
		sudo cp "${HOME}/.cargo/bin/alacritty" '/usr/bin/'
		
		#fix apparmor to allow mako notifications
		#because recent versions of ubuntu broke this
		pause
		#NOTE: before disabling apparmor for mako notifier we have to first set it to complain mod
		#because otherwise apparmor doesn't know the profile exists and can't set it to disabled
		sudo aa-complain /etc/apparmor.d/fr.emersion.Mako
		sudo aa-disable /etc/apparmor.d/fr.emersion.Mako
		
		#set snap to only run updates on saturday mornings (not every day)
		#sudo snap set system refresh.timer=sat1,00:00-2:00
		
		#set snap to never auto-update packages; only when installing new versions is explicitly requested
		#sudo snap refresh --hold
	fi
	
	#NOTE: While I use bsync ( https://github.com/dooblem/bsync ) for syncing and have skimmed its source code as of 2023-01-16 and believe it to be safe
	#I am not installing it by default here because I don't think that's something this installer should do until/unless it becomes part of the offical repositories
	#but when/if that ends up in AUR and debian repos, I should add it to the theme dependencies

	#NOTE: we use the script scripts/encryption-setup.sh in order to validate, and if necessary configure, system encryption
	#we depend on that file being included in the same package as this script; it's a dependency

	current_enc_status="$(sudo "${HOME}/.config/custom-themes/neu-way-ui/scripts/encryption-setup.sh" status)"
	home_enc_status="$(echo "$current_enc_status" | fgrep -A 2 "/home:" | head -n 2 | tail -n 1)"
	swap_enc_status="$(echo "$current_enc_status" | fgrep -A 2 "swap:" | head -n 2 | tail -n 1)"
	mlocate_enc_status="$(echo "$current_enc_status" | fgrep -A 2 "mlocate" | head -n 2 | tail -n 1)"

	if [ "$home_enc_status" == "unencrypted" ] || [ "$swap_enc_status" == "unencrypted" ] || [ "$mlocate_enc_status" == "indexed" ]
	then
		echo "Your system does not appear to be encrypted.  THIS CAN LEAVE YOUR SYSTEM READABLE TO ANYONE WITH PHYSICAL ACCESS.  It is HIGHLY recommended that you configure encryption.  "
		echo "If you use disk-level encryption you can ignore this.  If not you are STRONGLY advised to configure encryption at this time.  "
		echo "NOTE: if you are running this script from the home partition as a normal user (as you should be) it will not be possible to encrypt the /home partition until after this script completes and you log out of your normal user account"
		echo "So you may want to skip this and run the encryption-setup.sh script as root after this script completes and you log out if that's your configuration.  "
		
		read -p "Configure encryption now? (Y/N) " do_encryption_setup
		if [ "${do_encryption_setup:0:1}" == "Y" ] || [ "${do_encryption_setup:0:1}" == "y" ]
		then
			#NOTE: this is always going to fail in trying to encrypt home
			#because the script is running from home and as a normal user
			#but it's still capable of encrypting swap and updating mlocate settings at this stage
			#because of this it's recommended that you encrypt home PRIOR to running this script
			sudo "${HOME}/.config/custom-themes/neu-way-ui/scripts/encryption-setup.sh" encrypt
		else
			echo "Warn: SKIPPING ENCRYPTION SETUP.  If this was a mistake you can configure encryption using the encryption-setup.sh script after the theme installation completes.  "
		fi
	#NOTE: home_enc_status being fs_encrypted in the context of these theme scripts means that it uses ecryptfs
	#other filesystem-level encryption configurations such as encfs aren't detected as fs_encrypted and aren't handled here
	#so within this statement we know that the user is using ecryptfs for their home directory, and not some other form of filesystem encryption
	elif [ "$home_enc_status" == "fs_encrypted" ]
	then
		#TODO: test this; it should work but I've never actually tried running this script with this specific configuration
		
		#install the following lines to the user's crontab file (crontab -e) if not already present
		# */15    *       *       *       *       if [ "$(users | fgrep -o "$(whoami)")" == '' ] ; then ecryptfs-umount-private ; fi
		ecryptfs_umount_crontab_line="$(crontab -l | fgrep 'ecryptfs-umount-private')"
		if [ "${ecryptfs_umount_crontab_line}" == "" ]
		then
			existing_crontab="$(crontab -l)"
			echo "${existing_crontab}\n*/15    *       *       *       *       if [ "'"'"$(users | fgrep -o "'"'"$(whoami)"'"'")"'"'" == '' ] ; then ecryptfs-umount-private ; fi" | crontab -l
		fi
	fi
	
	#install some of my own software that I use regularly
	compile_custom_programs

	#install any necessary fonts at this time
	mkdir -p "${HOME}/.fonts/"
	
	#we use source code pro for alacritty so install that now
	cp -r -p -v "${HOME}/.config/custom-themes/neu-way-ui/assets-images-svgs/fonts/source-code-pro-release" "${HOME}/.fonts"
	
	#we use IntelOne Mono for alacritty so install that now
	cp -r -p -v "${HOME}/.config/custom-themes/neu-way-ui/assets-images-svgs/fonts/intel-one-mono-1.2.1" "${HOME}/.fonts"
	
	#update font cache
	fc-cache

	#plymouth configuration for arch
	#for arch plymouth isn't in the official repos so we have to get it from the AUR and compile it ourselves
	if [ "$distro" == 'arch' ]
	then
		#NOTE: disabled as of 2023-04-09 because
		#	a) this never actually worked properly on arch
		#	b) we shouldn't depend on AUR packages if possible
		#	c) it's just not a strictly necessary feature
		
		#however if at some point plymouth is in the normal arch packages AND this actually works
		#then it SHOULD be re-enabled
		
		pause
#		#install "plymouth-git" from AUR
#		install_aur_package "plymouth-git"
#		
#		#if plymouth was actually installed (and the installation wasn't just cancelled)
#		#then set the plymouth theme
#		if [ "$(which plymouth)" != "" ]
#		then
#			pause
#			sudo cp -r -p -v config/plymouth/neu-way-theme/* /usr/share/plymouth/themes/
#			
#			#NOTE: the -R switch here rebuilds the kernel image (equivalent to update-initramfs -u on *buntu)
#			sudo plymouth-set-default-theme -R neu-way-logo
#		fi
	#plymouth configuration for ubuntu
	#plymouth is in the repos so this just copies config and sets as default
	elif [ "$distro" == 'ubuntu' ]
	then
		pause
		sudo cp -r -p -v config/plymouth/neu-way-theme/* /usr/share/plymouth/themes/
		
		#NOTE: you have to select neu-way-logo theme from the update-alternatives selector for this to work
		#so we make the symlinks manually instead
	#	sudo update-alternatives --config default.plymouth
	#	sudo update-alternatives --config text.plymouth
		
		sudo rm /etc/alternatives/default.plymouth
		sudo ln -s /usr/share/plymouth/themes/neu-way-logo/neu-way-logo.plymouth /etc/alternatives/default.plymouth
		
		sudo rm /etc/alternatives/text.plymouth
		sudo ln -s /usr/share/plymouth/themes/neu-way-text/neu-way-text.plymouth /etc/alternatives/text.plymouth
		
		sudo update-initramfs -u
	fi
	
	#ensure bash is the login shell (and not zsh or something)
	#because that's what I use and am used to
	#and also because that's what our config files (like .bashrc) apply to
	if [ "${SHELL}" != '/bin/bash' ]
	then
		chsh -s /bin/bash
	fi

	#set display manager settings in lightdm to include the sway option and make that the default
	#lightdm is what xubuntu uses so that's what I'm assuming
	#if you have another display manager you're on your own
	#although I would guess that ~/.dmrc is respected by most common display managers
	
	#if the user-specific display manager configuration file exists
	if [ -e "${HOME}/.dmrc" ]
	then
		#then find the session definition and edit it so that sway is the default session
		#get the line number that defines the Session setting
		dmrc_session_lineno=$(cat "${HOME}/.dmrc" | egrep -n "Session\s*=" | awk -F ':' '{print $1}' | head -n 1)
		
		#if this parameter was previously unset then just set it now
		if [ "$dmrc_session_lineno" == "" ]
		then
			echo "Session=sway" >> "${HOME}/.dmrc"
		#if this parameter was previously set then change it from whatever it was to sway instead
		else
			dmrc_session_line="$(cat "${HOME}/.dmrc" | head -n "${dmrc_session_lineno}" | tail -n 1)"
			
			#if this line was commented out, uncomment it
			while [ "${dmrc_session_line:0:1}" == "#" ]
			do
				dmrc_session_line="${dmrc_session_line:1}"
			done
			
			#update the value to be the new value we want to set (sway)
			dmrc_session_line="$(echo "${dmrc_session_line}" | egrep -o '.*=')sway"
			change_file_line "${HOME}/.dmrc" "$dmrc_session_lineno" "$dmrc_session_line"
		fi
	#if the user-specific display manager configuration file does NOT exist
	else
		#then make it now with sway as default session
		echo "[Desktop]\nSession=sway\n" > "${HOME}/.dmrc"
	fi
	echo "Default display manager desktop session set to sway for user $(whoami)"
	
	#configure directories under ~/.config
	#sway, swaylock, waybar, wofi, alacritty
	cfg_dirs=("sway" "swaylock" "waybar" "rofi" "alacritty")
	for cfg_dir in "${cfg_dirs[@]}"
	do
		echo "Debug: Setting configuration for $cfg_dir..." #debug
		ln -s "${HOME}/.config/custom-themes/neu-way-ui/config/${cfg_dir}" "${HOME}/.config/${cfg_dir}"
	done

	#NOTE: we auto-start sway on login to tty1 via .bashrc
	#other ttys such as tty2 do not have this behaviour and can be used for debugging
	
	#configure setting files which live directly in ~/
	#bashrc, bash_aliases, tmux config, custom guile library, vim config
	cfg_files=(".bashrc" ".bash_aliases" ".bash_profile" ".tmux.conf" ".guile" ".vimrc")
	for cfg_file in "${cfg_files[@]}"
	do
		echo "Debug: Setting configuration file $cfg_file..." #debug
		#if this file already exists
		if [ -e "${HOME}/${cfg_file}" ]
		then
			#if it's already set correctly then do nothing
			if [ -L "${HOME}/${cfg_file}" ] && [ "$(readlink "${HOME}/${cfg_file}")" == "${HOME}/.config/custom-themes/neu-way-ui/config/${cfg_file}" ]
			then
				echo "Link ${HOME}/${cfg_file} already exists and has correct destination; skipping..."
			#if we're allowed to overwrite it, then overwrite it
			elif [ "$(authorize_overwrite "${HOME}/${cfg_file}" | tail -n 1)" == "true" ]
			then
				rm "${HOME}/${cfg_file}"
				ln -s "${HOME}/.config/custom-themes/neu-way-ui/config/${cfg_file}" "${HOME}/${cfg_file}"
			#if it already exists and we're not allowed to overwrite it
			#then skip it
			else
				echo "Skipping file ${HOME}/${cfg_file} because it already exists and we aren't allowed to overwrite it..."
			fi
		else
			ln -s "${HOME}/.config/custom-themes/neu-way-ui/config/${cfg_file}" "${HOME}/${cfg_file}"
		fi
	done
	
	#TODO: null-route suspicious hosts by adding /etc/hosts entries
	#this includes any known malware or malicious software vendors
	#and also make a command-line option for toggling this in case for some reason it's not desirable
	#but it should do it by default because I might forget to use the switch
	#and I want those null routes on my machines
	#TODO: if null routing and redirects are enabled, write this to /etc/hosts, in ADDITION to all existing contents (>>)
	#	# twitter.com -> nitter.net
	#	185.246.188.57	twitter.com
	#	
	#	# null route facebook
	#	0.0.0.0 facebook.com
	#
	#	# null route microsoft (inc. bing)
	#	0.0.0.0 microsoft.com
	#	0.0.0.0 bing.com
	#
	
	#decrypt private-config from whatever GPG or ccrypt package it's in
	#as it should be stored in an encrypted format
	#we should NEVER include logins and passwords
	#in the config files which are distributed with this theme and associated scripts
	#and even when encrypted files that contain any of this this should be ignored by git using .gitignore
	#NOTE: this assumes the private-config.tar.gz.cpt was created by the following commands:
	#	tar cvzf private-config.tar.gz private-config/
	#	ccencrypt private-config.tar.gz
	#	
	if [ "$(which ccdecrypt)" != "" ]
	then
		if [ -f "${HOME}/.config/custom-themes/neu-way-ui/private-config.tar.gz.cpt" ]
		then
			read -p "Decrypt private configuration files? (Y/N) " decrypt_private_config
			if [ "${decrypt_private_config:0:1}" == "Y" ] || [ "${decrypt_private_config:0:1}" == "y" ]
			then
				cd "${HOME}/.config/custom-themes/neu-way-ui/"
				ccdecrypt private-config.tar.gz.cpt
				tar xvzf private-config.tar.gz
				cd -
			fi
		fi
	fi
	
	if [ -d "${HOME}/.config/custom-themes/neu-way-ui/private-config" ]
	then
		read -p "Install private configuration files from private-config? (Y/N/Del) " install_private_config
		
		#if we were asked to install private configuration files, then do that
		if [ "${install_private_config:0:1}" == "Y" ] || [ "${install_private_config:0:1}" == "y" ]
		then
			#NOTE: vdirsyncer is handled as a special case here because its config directory structure is just weird
			#NOTE: private configuration is /optional/ so we only set it if the source exists
			if [ -f "${HOME}/.config/custom-themes/neu-way-ui/private-config/vdirsyncer/config" ]
			then
				echo "Debug: Setting configuration for vdirsyncer..." #debug
				mkdir -p "${HOME}/.vdirsyncer"
				
				#NOTE: for private config if the destination file already exists we always just skip it
				#and never overwrite or prompt
				if [ -e "${HOME}/.vdirsyncer/config" ]
				then
					echo "Skipping private config .vdirsycer/config because destination already exists.."
				else
					ln -s "${HOME}/.config/custom-themes/neu-way-ui/private-config/vdirsyncer/config" "${HOME}/.vdirsyncer/config"
				fi
			fi

			private_cfg_dirs=("khal" "accirc")
			for cfg_dir in "${private_cfg_dirs[@]}"
			do
				#NOTE: private configuration is /optional/ so we only set it if the source exists
				if [ -e "${HOME}/.config/custom-themes/neu-way-ui/private-config/${cfg_dir}" ]
				then
					echo "Debug: Setting configuration for $cfg_dir..." #debug
					
					#NOTE: for private config if the destination file already exists we always just skip it
					#and never overwrite or prompt
					if [ -e "${HOME}/.config/${cfg_dir}" ]
					then
						echo "Skipping private config ${cfg_dir} because destination already exists.."
					else
						ln -s "${HOME}/.config/custom-themes/neu-way-ui/private-config/${cfg_dir}" "${HOME}/.config/${cfg_dir}"
					fi
				fi
			done
			
		#if we were asked to DELETE the private configuration
		elif [ "${install_private_config}" == "Del" ]
		then
			#then do that now via shredtree
			echo "Deleting theme copy of the private configuration from ${HOME}/.config/custom-themes/neu-way-ui/private-config..."
			echo "NOTE: if this was a symlink then the installer directory will still contain a copy"
			"${HOME}/.config/custom-themes/neu-way-ui/scripts/shredtree.sh" "${HOME}/.config/custom-themes/neu-way-ui/private-config" --iterations=1 --all
		fi
	fi

	#NOTE: for now I am not using eww; I think it's really cool and plan to use it at some future date but right now it's just not stable enough to use
	#I won't use it until it's in at least the arch linux repositories and has better documentation
	#at which point I can hopefully integrate it and entirely get rid of waybar

	#download, build, and install eww (widgets)
	#cd "$HOME/programs"
	#git clone https://github.com/elkowar/eww
	#cd eww
	#cargo build --release --no-default-features --features=wayland
	#cd target/release
	#chmod +x ./eww
	#./eww daemon
	#./eww open <window_name>
	
	echo "Theme install complete; you're all set!"
	echo "Next steps: "
	echo "  Reboot and ensure everything works correctly"
	echo "  If your files aren't encrypted login as root (/home must not be in use) and run encryption-setup.sh to configure block encryption"
}


#default action is to copy the theme directory into ~/.config/custom-themes/neu-way-ui
#rather than symlinking to the current (installer) directory
#but that's an option too, which can be done with the --link-theme-dir command line option
installer_dir_action="copy"

#get the installer directory
installer_dir="$(pwd)"

#if this script is being run directly from the "scripts" directory
#then go up one level to get the root theme directory
if [ "$(basename "${installer_dir}")" == 'scripts' ]
then
	installer_dir="${installer_dir}/.."
fi

#get any argument values which were given to this script

#for each command line argument
for opt in "$@"
do
	case "$opt" in
		#copy theme directory rather than making a symbolic link
		--copy-theme-dir)
			installer_dir_action="copy"
			;;
		#make a symbolic link to the installer directory
		#rather than copying into the theme directory
		--link-theme-dir)
			installer_dir_action="link"
			;;
		#help text
		-h|--help)
			#display and exit
			echo "Usage: $0 [--copy-theme-dir|--link-theme-dir]"
			exit 1
			;;
		#hard error on unknown options
		*)
			echo "Err: Unknown or unrecognized option $opt"
			
			#stop; unrecognized options are fatal
			exit 1
			;;
	esac
	
	#go check the next argument
	shift
done

install_neu_way_ui_theme "$installer_dir" "$installer_dir_action"

