#!/bin/bash

#immediately exit if any error occurs, and do not continue execution after that point
set -e

#this script is meant to set up encryption for /home and swap to prevent unauthorized users with physical access from being able to read sensitive data
#due to the fact that decryption is performed by the linux kernel and my systems don't use a dedicated /boot partition

#the underlying encryption that this script sets up is as follows:
#	block-level dm-crypt (via cryptsetup) of /home
#		mounted at bootup via prompt (in xubuntu this uses plymouth) and referenced by /etc/crypttab
#			underlying block device referenced in /etc/fstab
#			encrypted block will be accessed via /dev/mapper/home
#		bit length and others are cryptsetup default values
#			at time of writing these are:
#				algorithm: aes-xts
#				bit length: 256 bit key
#	replacement of any existing swapfile or swap partitions with encrypted versions
#		encrypted versions are refernced by /etc/crypttab
#		will use file or block device based on what's in use at the time this script runs
#		IMPORTANT: if swap space is added after this you will need to run this script again
#


#helper function: change a single line in a file
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

encsetup_status()
{
	#until otherwise shown /home is unencrypted
	home_enc_status="unencrypted"
	home_enc_status_msg="The device mounted on /home does not appear to be encrypted! Its content is visible to anyone with physical access to this machine.  "
	
	home_mounts=$(mount | fgrep "on /home ")
	
	#TODO: should this be switched to check lsblk output for whether or not encryption is enabled?
	#it seems like that might be a bit more reliable
	
	#if some /dev/mapper/* device is mounted on /home
	if [ "$(echo "$home_mounts" | fgrep "/dev/mapper")" != "" ]
	then
		#then check if home is referenced in the crypttab file
		if [ "$(cat /etc/crypttab | fgrep "home")" != "" ]
		then
			#if crypttab specifies to mount home then it's a safe bet that /home is block encrypted
			home_enc_status="block_encrypted"
			home_enc_status_msg="The device mounted on /home appears to be block-level encrypted.  Its content cannot be read by unauthorized users.  "
		else
			#this is a weird case where a /dev/mapper/* device is mounted on /home
			#but /etc/crypttab doesn't seem to reference it
			#so it's probably good but we don't really know; let's just communicate that
			home_enc_status="probably_block_encrypted"
			home_enc_status_msg="The device mounted on /home is probably block level encrypted but doesn't appear to have an entry in /etc/crypttab so we can't be sure.  "
		fi
	#if /home is NOT block level encrypted
	else
		#if it's filesystem-level encrypted with ecryptfs
		if [ "$(mount | fgrep "/home/.ecryptfs/$(whoami)")" != "" ]
		then
			#this isn't quite as good as block level encryption but at least it's something
			home_enc_status="fs_encrypted"
			home_enc_status_msg="The device mounted on /home is not block level encrypted but you appear to be using a filesystem level encryption.  This is a little less secure than block level encryption but should offer some protection against unauthorized users accessing the data.  "
		elif [ "$home_mounts" == "" ]
		then
			home_enc_status="not_a_partition"
			home_enc_status_msg="/home is not its own partition on this system and you're not using filesystem level encryption.  Your configuration therefore is unsupported by this script.  You're on your own!"
		fi
	fi
	
	#until otherwise shown swap is unencrypted
	swap_enc_status="unencrypted"
	swap_enc_status_msg="You appear to have unencrypted swap space in use.  This can leak the contents of RAM to a would-be attacker.  "
	
	swap_mounts="$(swapon --show --noheadings)"
	total_swap_lines=$(echo "$swap_mounts" | wc -l)
	encswap_lines="$(echo "$swap_mounts" | fgrep "/dev/dm-" | wc -l)"
	
	#if ALL the swap mounts are /dev/dm-* devices then it's probably encrypted
	#NOTE: if there are two swap devices in use and only one is encrypted this will show as unencrypted
	#this is intentional behaviour
	if [ "$encswap_lines" == "$total_swap_lines" ]
	then
		#if it's specified in crypttab then we can be pretty sure it's encrypted
		encswap_crypttab_lines="$(cat /etc/crypttab | fgrep "swap," | fgrep "/dev/urandom" | wc -l)"
		if [ "$encswap_crypttab_lines" -ge "$total_swap_lines" ]
		then
			swap_enc_status="block_encrypted"
			swap_enc_status_msg="All configured swap devices appear to be encrypted"
		else
			swap_enc_status="probably_block_encrypted"
			swap_enc_status_msg="The configured swap devices are probably block level encrypted but do not appear to have corresponding entries in /etc/crypttab so we can't be sure.  "
		fi
	fi
	
	mlocate_enc_status="not_installed"
	mlocate_enc_status_msg="mlocate is not installed on this machine; if you ever install it you will need to update its configuration to prevent leakage of filenames and metadata"
	
	if [ "$(which locate)" != "" ] && [ "$(which updatedb)" != "" ]
	then
		if [ -f "/etc/updatedb.conf" ]
		then
			if [ "$(cat /etc/updatedb.conf | egrep "^PRUNEPATHS(\s)*=.*(/home[^/]).*" | fgrep -o "/home" | head -n 1)" == "/home" ]
			then
				mlocate_enc_status="unindexed"
				mlocate_enc_status_msg="/home is not indexed by mlocate; you are protected against filename and metadata leaks"
			else
				mlocate_enc_status="indexed"
				mlocate_enc_status_msg="It looks like /home is indexed; this can cause filenames and other metadata to be leaked to anyone with physical access to this computer.  "
			fi
		else
			mlocate_enc_status="unconfigured"
			mlocate_enc_status_msg="It looks like mlocate is installed but there is no configuration file for it.  Please ensure that /home is unindexed to avoid leaking filenames and metadata.  "
		fi
	fi
	
	
	echo "/home:"
	echo "$home_enc_status"
	echo "$home_enc_status_msg"
	echo ""
	echo "swap:"
	echo "$swap_enc_status"
	echo "$swap_enc_status_msg"
	echo ""
	echo "mlocate:"
	echo "$mlocate_enc_status"
	echo "$mlocate_enc_status_msg"
}

#this is loosely based on the tutorial at https://mpiatkowski.medium.com/encrypting-home-partition-on-an-already-installed-linux-machine-a738b668931a
#as well as the arch linux documentation at https://wiki.archlinux.org/title/Disk_encryption#Block_device_encryption
encsetup_home()
{
	#check to make sure that this script isn't currently running from anywhere on /home
	#because we can't encrypt a directory we're running from
	if [ "$(pwd | fgrep "/home")" != "" ]
	then
		echo "Err: Cannot encrypt /home because this script is currently running from $(pwd); move this script outside of /home and try again.  "
		echo "If you're not sure of a better place try moving this script to /tmp/ and running it from there.  "
		exit 1
	fi
	
	echo "Attempting to configure encryption for /home partition..."
	
	backup_prompt="NO"
	while [ "$backup_prompt" != "YES" ]
	do
		echo "If you do not have a backup of your /home directory please press ctrl+c repeatedly to cancel this script's execution.  "
		echo "Take a backup before running this script, just in case something goes wrong during the encryption step.  "
		read -p "Do you have a backup? (type YES, all uppercase, if so): " backup_prompt
		echo ""
		echo ""
		
		if [ "$backup_prompt" == "NO" ] || [ "$backup_prompt" == "no" ] || [ "$backup_prompt" == "n" ]
		then
			exit 1
		fi
	done
	
	#detect root and home devices
	root_dev="$(mount | fgrep 'on / ' | awk '{print $1}')"
	home_dev="$(mount | fgrep 'on /home ' | awk '{print $1}')"
	
	if [ "$home_dev" == "" ] || [ "$root_dev" == "" ]
	then
		echo "Err: Could not detect root and home devices; usually this means /home is not on its own partition (a configuration unsupported by this script); exiting with error"
		exit 1
	fi
	
	echo "root_dev=${root_dev}" #debug
	echo "home_dev=${home_dev}" #debug
	
	open_home_file_cnt="$(lsof /home | wc -l)"
	if [ "$open_home_file_cnt" -gt 0 ]
	then
		echo "Err: There are open files in the home directory, meaning that we can't unmount it in order to encrypt it"
		echo "Please close the programs that are accessing files in /home (use lsof /home to view these files)"
		echo "(if this isn't possible, reboot and log in as root)"
		echo "Once that's done please try running this script again.  "
		exit 1
	fi
	
	#check how much space is needed and how much space is available to try to make a backup
	home_bytes_used="$(df --block-size 1 | fgrep "$home_dev" | awk '{print $3}')"
	root_bytes_avail="$(df --block-size 1 | fgrep "$root_dev" | awk '{print $4}')"

	#if sufficient space for a backup of /home exists on the root filesystem, put a backup there
	if [ "$home_bytes_used" -lt "$root_bytes_avail" ]
	then
		if [ -d "/preenc-backup" ]
		then
			echo "Err: /preenc-backup already exists, indicating that this script has previously been started but did not complete"
			echo "If the previous attempt did not complete successfully, make sure you have a backup of your data and then delete the /preenc-backup directory to try again.  "
			exit 1
		fi
		sudo mkdir -p /preenc-backup
		
		#NOTE: this is intentionally a cp and NOT an mv operation
		#old data will get wiped during the cryptsetup operation
		sudo cp -r -p /home /preenc-backup/
	#if sufficient space for a backup of /home does NOT exist on the root filesystem, then warn the user
	#as this means they will need to manually copy their home directory data after this script completes the encryption setup
	else
		backup_prompt="NO"
		while [ "$backup_prompt" != "YES" ]
		do
			echo "Warn: There is insufficient room to create a local backup on the root filesystem.  "
			echo "If you continue with this script you will need to copy your home directory contents from your backup manually after encryption has been set up.  "
			read -p "Continue anyway and manually copy data to /home from your backup? (type YES, all uppercase, if so): " backup_prompt
			echo ""
			echo ""
			
			if [ "$backup_prompt" == "NO" ] || [ "$backup_prompt" == "no" ] || [ "$backup_prompt" == "n" ]
			then
				exit 1
			fi
		done

	fi
	
	#once /home is backed up (if possible)
	#ensure that nothing is accessing /home
	#since something might have been opened since we started this operation
	open_home_file_cnt="$(lsof /home | wc -l)"
	if [ "$open_home_file_cnt" -gt 0 ]
	then
		echo "Err: There are open files in the home directory, meaning that we can't unmount it in order to encrypt it"
		echo "Please close the programs that are accessing files in /home (use lsof /home to view these files)"
		echo "(if this isn't possible, reboot and log in as root)"
		echo "Once that's done please try running this script again.  "
		exit 1
	fi
	
	#and unmount /home so that we can do block-level stuff to it
	sudo umount /home
	
	#wipe the device at the block level
	#this ensures that any existing data (even on ununsed sectors) is cleanly removed
	sudo cryptsetup open --type plain -d /dev/urandom "$home_dev" to_be_wiped
	sudo dd if=/dev/zero of="/dev/mapper/to_be_wiped" bs=512 count="$(("$(lsblk -o NAME,SIZE --bytes | egrep -o "to_be_wiped.*" | awk '{print $2}')" / 512))" status=progress
	sudo cryptsetup close to_be_wiped
	
	#initialize it as a luksFormat encrypted device with an ext4 filesystem
	#NOTE: we are using cryptsetup default values for things like key size and algorithm
	#because currently they are sane and fast
	#and we can reasonably expect the defaults to be updated when new improved algorithms are implemented
	sudo cryptsetup luksFormat "$home_dev"
	sudo cryptsetup open "$home_dev" home
	sudo mkfs.ext4 /dev/mapper/home
	
	crypt_home_uuid="$(lsblk -o NAME,FSTYPE,UUID,SIZE,FSAVAIL,FSUSED -f | fgrep 'crypto_LUKS' | awk '{print $3}')"
	echo "crypt_home_uuid=${crypt_home_uuid}" #debug
	sudo bash -c "echo "'"'"home UUID=${crypt_home_uuid} none luks,timeout=180"'"'" >> /etc/crypttab"
	
	#update the fstab file to comment out the old unencrypted home device
	#NOTE: if there are are multiple matching lines only the FIRST one gets commented out
	#and we ignore comment lines for the purpose of this search
	home_fstab_lineno=$(cat "/etc/fstab" | egrep -n '^[^#](.*)/home' | awk -F ':' '{print $1}' | head -n 1)
	if [ "$home_fstab_lineno" != "" ]
	then
		home_fstab_line=$(cat "/etc/fstab" | head -n "${home_fstab_lineno}" | tail -n 1)
		while [ "${home_fstab_line:0:1}" == "#" ]
		do
			home_fstab_line="${home_fstab_line:1}"
		done
		home_fstab_line="#${home_fstab_line}"
		
		sudo bash -c "$(declare -f change_file_line) ; change_file_line '/etc/fstab' '$home_fstab_lineno' '$home_fstab_line'"
	fi
	
	#and add our encrypted home device instead
	sudo bash -c "echo "'"'"/dev/mapper/home /home ext4 rw,relatime 0 2"'"'" >> /etc/fstab"
	
	#reload daemon
	sudo systemctl daemon-reload
	
	#now that /home is all nicely encrypted, re-mount it
	#NOTE: I think maybe this gets done automatically somehow? this line seems unnecessary
	sudo mount /dev/mapper/home /home
	
	#encryption setup is done!
	#if we had a backup on the root filesystem, restore it now
	
	if [ -d "/preenc-backup" ]
	then
		#copy data from the preenc backup to home
		#NOTE: technically the destination here is / and not /home because the home directory is meant to be merged with the existing /home
		#and we don't want to create a /home/home directory because that would make no sense
		sudo cp -r -p /preenc-backup/home /
		
		#once that completes successfully, delete the preenc backup from the root filesystem
		#in order to free up the space
		#NOTE: this is intentionally commented out because you should shred these files and not just rm them
		#I have a separate shredtree script that does that which I don't think should need to be a dependency of this script
#		sudo rm -r /preenc-backup
		echo "PLEASE SHRED /preenc-backup AFTER YOUR NEXT SUCCESSFUL REBOOT AND LOGIN (you can use shredtree.sh which should be included in the same directory as this script)"
	fi
	
	echo "Home is now encrypted!"
	echo "You will need to provide your encryption password on boot in order to access the data in /home.  "
}

#this is loosely based on the stackoverflow answer at https://unix.stackexchange.com/questions/64551/how-do-i-set-up-an-encrypted-swap-file-in-linux#64569
encsetup_swap()
{
	echo "Attempting to configure encryption for swap space..."
	
	#get information about current swap devices
	#partitions and files must be treated differently and multiple swap devices can exist on the same system
	#so we need to know what's currently in use in order to know what we're encrypting or replacing
	swap_devs="$(swapon --show --noheadings --bytes)"
	
	#for each swap device
	#NOTE: see the end of this loop for how that information gets passed in; bash is weird in this regard
	while read -r swap_dev
	do
		#find out about the swap device we're dealing with
		swap_path="$(echo "$swap_dev" | awk '{print $1}')"
		swap_type="$(echo "$swap_dev" | awk '{print $2}')"
		swap_size="$(echo "$swap_dev" | awk '{print $3}')"
		swap_used="$(echo "$swap_dev" | awk '{print $4}')"
		
		#skip swap devices that have already been successfully encrypted
		#nothing more needs to be done for those
		if [ "$(echo "$swap_path" | fgrep '/dev/dm-')" != "" ]
		then
			continue
		fi
		
		#make sure we have enough RAM to support disabling swap
		ram_free="$(free -b | fgrep "Mem: " | awk '{print $7}')"
		if [ "$ram_free" -lt "$swap_used" ]
		then
#			echo "ram_free=${ram_free}" #debug
#			echo "swap_used=${swap_used}" #debug
			
			#if not, ask the user to kill some programs and exit with error at this point
			echo "Err: cannot disable swap device ${swap_path} in order to encrypt it because there is not enough free RAM available to make up for the swap space currently in use.  "
			echo "Try closing some programs and running this script again.  "
			exit 1
		fi
		
		#now that we know we have the memory to disable this swap device
		#disable this swap device
		if [ "$(whoami)" != 'root' ]
		then
			echo "We need your permission to disable swap device ${swap_path} and then encrypt it.  "
		fi
		sudo swapoff "${swap_path}"
		
		#get the name as just the file basename without any path
		swap_name="$(basename "$swap_path")"
		
		#default value empty string
		#to skip fstab editing
		swap_fstab_lineno=""

		#for swap file type devices, replace them with an encrypted swapfile of the same size
		#and add the relevent entries to crypttab and fstab
		if [ "$swap_type" == "file" ]
		then
			#for clarity and consistency, rename this file to have a .crypt extension
			sudo mv "${swap_path}" "${swap_path}.crypt"
			
			#set up loop device
			loop="$(losetup -f)"
			sudo losetup ${loop} "${swap_path}.crypt"
			
			#zero out the device and set up the encryption
			sudo dd if=/dev/zero of="${loop}" bs=512 count="$(("$(lsblk -o NAME,SIZE --bytes | fgrep "$(basename ${loop})" | awk '{print $2}')" / 512))" status=progress
			
			echo "swap_name=${swap_name}" #debug
			echo "loop=${loop}" #debug
			
			sudo cryptsetup open "${loop}" "${swap_name}" --type plain --key-file /dev/urandom --key-size 256
			
			#add a line to /etc/crypttab to use this encrypted swap device on every reboot
			#NOTE: for swap partitions (rather than swap file) the second argument should be UUID-based
			#NOTE: "size" in this context is the key size, which is 256 bits as defined by the above cryptsetup
			sudo bash -c "echo "'"'"${swap_name} ${swap_path}.crypt /dev/urandom swap,cipher=aes-xts-plain64,size=256"'"'" >> /etc/crypttab"
			
			swap_fstab_lineno=$(cat "/etc/fstab" | fgrep -n "${swap_path}" | awk -F ':' '{print $1}' | head -n 1)
		#for swap partitions, encrypt the existing partition (without changing its size or location)
		#and add the relevant entries to crypttab and fstab
		elif [ "$swap_type" == "partition" ]
		then
			#zero out the device
			sudo dd if=/dev/zero of="${swap_path}" bs=512 count="$(("$(lsblk -o NAME,SIZE --bytes | fgrep "$(basename ${swap_path})" | awk '{print $2}')" / 512))" status=progress

			sudo cryptsetup open "${swap_path}" "${swap_name}" --type plain --key-file /dev/urandom --key-size 256

			#add a line to /etc/crypttab to use this encrypted swap device on every reboot
			#NOTE: for swap partitions (rather than swap file) the second argument should be UUID-based
			#NOTE: "size" in this context is the key size, which is 256 bits as defined by the above cryptsetup
			sudo bash -c "echo "'"'"${swap_name} ${swap_path} /dev/urandom swap,cipher=aes-xts-plain64,size=256"'"'" >> /etc/crypttab"
			
			swap_fstab_lineno=$(cat "/etc/fstab" | egrep -n '\s*UUID=.*\s+none\s+swap' | awk -F ':' '{print $1}' | head -n 1)
		else
			echo "Err: Unrecognized swap type ${swap_type} on swap device ${swap_path}; exiting with error"
			exit 1
		fi

		#create the swap filesystem at the specified location
		sudo mkswap "/dev/mapper/${swap_name}"
		
		#enable new swap immediately rather than waiting for a reboot
		sudo swapon "/dev/mapper/${swap_name}"
		
		#update the fstab file to comment out the old unencrypted swap device
		#NOTE: if there are are multiple matching lines only the FIRST one gets commented out
		if [ "$swap_fstab_lineno" != "" ]
		then
			swap_fstab_line=$(cat "/etc/fstab" | head -n "${swap_fstab_lineno}" | tail -n 1)
			while [ "${swap_fstab_line:0:1}" == "#" ]
			do
				swap_fstab_line="${swap_fstab_line:1}"
			done
			swap_fstab_line="#${swap_fstab_line}"
			
			sudo bash -c "$(declare -f change_file_line) ; change_file_line '/etc/fstab' '$swap_fstab_lineno' '$swap_fstab_line'"
		fi
		
		#and add our encrypted swap device instead
		sudo bash -c "echo "'"'"/dev/mapper/${swap_name} none swap sw 0 0"'"'" >> /etc/fstab"
		
	
	#NOTE: it's important that this done statement gets input from the swapdevs variable
	#as that is now it gets to be used as input to the read command at the beginning of this loop
	done <<< "$swap_devs"
	
	echo "Swap is now encrypted and will be re-enabled on every reboot.  "
}

encsetup_mlocate()
{
	#ensure /home is excluded from mlocate database, and if not exclude it now then update the database
	#this is stored in /etc/updatedb.conf in the PRUNEPATHS setting; we want PRUNEPATHS to include /home

	prunepath_lineno="$(cat "/etc/updatedb.conf" | egrep -n "^PRUNEPATHS(\s*)=.*" | awk -F ':' '{print $1}' | head -n 1)"
	
	if [ "$prunepath_lineno" != "" ]
	then
		prunepath_line="$(cat "/etc/updatedb.conf" | head -n "${prunepath_lineno}" | tail -n 1)"
		while [ "${prunepath_line:0:1}" == "#" ]
		do
			prunepath_line="${prunepath_line:1}"
		done
		
		prunepath_line_len="${#prunepath_line}"
		quote_idx="$((${#prunepath_line}-1))"
		
		while [ "${prunepath_line:$quote_idx:1}" != '"' ]
		do
			quote_idx="$((quote_idx-1))"
		done
		if [ "$quote_idx" -gt 0 ]
		then
			prunepath_line="${prunepath_line:0:$quote_idx} /home${prunepath_line:$quote_idx:${#prunepath_line}}"
		fi
		
		sudo bash -c "$(declare -f change_file_line) ; change_file_line '/etc/updatedb.conf' '$prunepath_lineno' '$prunepath_line'"

	else
		echo "Could not find prunepath line number in /etc/updatedb.conf; do you have a PRUNEPATHS setting?"
		exit 1
	fi
	
	#once this is updated re-run "updatedb" to ensure that existing entries are removed
	sudo updatedb
	
	echo "mlocate settings have been updated to prevent /home from being indexed and the associated database has been updated"
	echo "This will prevent filenames and metadata on the encrypted /home filesystem from leaking.  "
}

encsetup_encrypt()
{
	current_enc_status="$(encsetup_status)"
	home_enc_status="$(echo "$current_enc_status" | fgrep -A 2 "/home:" | head -n 2 | tail -n 1)"
	swap_enc_status="$(echo "$current_enc_status" | fgrep -A 2 "swap:" | head -n 2 | tail -n 1)"
	mlocate_enc_status="$(echo "$current_enc_status" | fgrep -A 2 "mlocate" | head -n 2 | tail -n 1)"
	
	if [ "$home_enc_status" != "unencrypted" ] && [ "$swap_enc_status" != "unencrypted" ] && [ "$mlocate_enc_status" != "indexed" ]
	then
		echo "/home: $home_enc_status" #debug
		echo "swap: $swap_enc_status" #debug
		echo "mlocate: $mlocate_enc_status" #debug
		echo "/home and swap are already encrypted as far as we can tell; nothing to configure; exiting with success status"
		exit 0
	fi
	
	#NOTE: we attempt to encrypt swap before we attempt to encrypt home
	#because encrypting swap doesn't require us to take a backup first and is less likely to cause lasting damage to anything
	#so we do the easy/simple case first
	if [ "$swap_enc_status" == "unencrypted" ]
	then
		encsetup_swap
	else
		echo "No action being taken for swap; it is either already encrypted or has an unsupported configuration"
	fi
	
	if [ "$home_enc_status" == "unencrypted" ]
	then
		encsetup_home
	else
		echo "No action being taken for /home; it is either already encrypted or has an unsupported configuration (such as not being a partition)"
	fi
	
	if [ "$mlocate_enc_status" == "indexed" ]
	then
		encsetup_mlocate
	else
		echo "No action being taken for mlocate; either /home is already unindexed or this is an unsupported configuration (such as not having mlocate installed)"
	fi
}

help_text()
{
	echo "Usage: $0 <status|encrypt>"
}

if [ "$(which cryptsetup)" == "" ]
then
	echo "cryptsetup must be installed for this script to work; please install cryptsetup and then try again"
	exit 1
fi
if [ "$(which lsof)" == "" ]
then
	echo "lsof must be installed for this script to work; please install lsof and then try again"
	exit 1
fi

if [ "$#" -lt 1 ]
then
	help_text
	exit 1
fi

subcmd="$1"
if [ "$subcmd" == "status" ]
then
	encsetup_status
elif [ "$subcmd" == "encrypt" ] || [ "$subcmd" == "setup" ]
then
	encsetup_encrypt
else
	help_text
	exit 1
fi

