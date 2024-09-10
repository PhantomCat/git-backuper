#!/bin/bash
#
# Git repos backup script with rsync mirroring

# Let's check the config file
if [ ! -f /etc/gbkp.conf ]
then
	echo "ERROR, no cofig file" >> /var/log/git-backuper.log
	exit 1
else
	# include it with all of its variables
	. /etc/gbkp.conf
fi

# check if the USB-to-SATA adapter is attached and powered on
if [ $(lsusb | grep -i "$USB_DEV" | wc -l) -eq 0 ]
then
	echo "[FAIL] - $(date +%F) - GIT BACKUP Failed - NO USB DEVICE!" >> /var/log/git-backuper.log
	exit 1
fi

# get all disks (partitions) with label we used to write backups
disks=$(find /dev/disk/by-label/ -name "$PREFIX*")

# creating the mounting points,
# mounting partitions and 
# creating backup directories on them
for label in $disks
do
	short_label=$(echo $label | awk -F"/" '{print $NF}')
	mkdir -p /srv/${short_label}
	mount $label /srv/${short_label}
	mkdir -p /srv/${short_label}/${BKP_DIR}
done

# read the repositories list and pull them into last mounted drive's backup directory
while read line
do
	if [ $(grep $line /var/local/gbkp/cloned | wc -l) -eq 0 ]
	then	
		repo_dir=$(echo $line | cut -f 2 -d ":" | sed 's/.git$//g')
		git clone $line /srv/${short_label}/${repo_dir}
		echo $line >> /var/local/gbkp/cloned
	fi
done < /var/local/gbkp/repos.list

# Get directories with git repositories cloned
git_dirs=$(find /srv/${short_path}/ -type d -name '.git' | sed 's/.git//g')

# in case the git repo already have the directory - get inside it and pull all branches in it
for dir in ${git_dirs}
do
	cd $dir
	git pull --all --recurse-submodules
	if [ $? -eq 0 ]
	then
		echo "[OK] - $(date +%F) Successfully pulled git in $dir" >> /var/log/git-backuper.log
	else	
		echo -e "[ERROR] - $(date +%F) Not puuled git in $dir\n\t\tTRY TO PULL IT BY HAND" >> /var/log/git-backuper.log
	fi
done

# TODO
# archive and compress to tar.gz every git directory with date-stamp


# TODO
# remove old backups following the configuration rules


# TODO
# rotate log files


# TODO
# unmount drives


