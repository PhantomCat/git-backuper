#!/bin/bash
#
# Git repos backup script with rsync mirroring

# Local variables to make our life easier
logfile=/var/log/git-backuper_$(date "+%F_%H%-%M-%S").log

# Let's check the config file
if [ ! -f /etc/gbkp.conf ]
then
	echo "ERROR, no cofig file" >> $logfile
	exit 1
else
	# include it with all of its variables
	. /etc/gbkp.conf
fi

# check if the USB-to-SATA adapter is attached and powered on
if [ $(lsusb | grep -i "$USB_DEV" | wc -l) -eq 0 ]
then
	echo "[FAIL] - $(date "+%F_%T") - GIT BACKUP Failed - NO USB DEVICE!" >> $logfile
	exit 1
fi

# get all disks (partitions) with label we used to write backups
disks=$(find /dev/disk/by-label/ -name "$PREFIX*")

# choose the first disk in list as a primary to work on
primary_backup_disk=/srv/$(echo $disks | head -n 1 | awk -F"/" '{print $NF}')

# creating the mounting points,
# mounting partitions and 
# creating backup directories on them
for label in $disks
do
	short_label=$(echo $label | awk -F"/" '{print $NF}')
	mkdir -p /srv/${short_label}
	mount $label /srv/${short_label}
	mkdir -p /srv/${short_label}/${BKP_DIR}
	mkdir -p /srv/${short_label}/${BKP_DIR}/archives
done

# read the repositories list and pull them into last mounted drive's backup directory
while read line
do
	if [ $(grep $line /var/local/gbkp/cloned | wc -l) -eq 0 ]
	then	
		repo_dir=$(echo $line | cut -f 2 -d ":" | sed 's/.git$//g')
		git clone $line ${primary_backup_disk}/${BKP_DIR}/${repo_dir}
		echo $line >> /var/local/gbkp/cloned
	fi
done < /var/local/gbkp/repos.list

# Get directories with git repositories cloned
git_dirs=$(find ${primary_backup_disk}/${BKP_DIR}/ -type d -name '.git' | sed 's/.git//g')

# in case the git repo already have the directory - get inside it and pull all branches in it
for dir in ${git_dirs}
do
	cd $dir
	git pull --all --recurse-submodules
	if [ $? -eq 0 ]
	then
		echo "[OK] - $(date "+%F_%T") Successfully pulled git in $dir" >> $logfile
	else	
		echo -e "[ERROR] - $(date "+%F_%T") Not puuled git in $dir\n\t\tTRY TO PULL IT BY HAND" >> $logfile
	fi
done

#return to the clonning directory
cd ${primary_backup_disk}/${BKP_DIR}

# archiving and compressing to tar.gz every git directory with date-stamp
# adding "daily", "weekly" and "monthly" suffix to make backup rotation great
w_day=$(date +"%u")
m_day=$(date +"%d")

if [ $m_day -eq 1 ]
then
	suffix="montly"
elif [ $w_day -eq 1 ]
then
	suffix="weekly"
else
	suffix="daily"
fi

for dir in ${git_dirs}
do
	tar cvzf ${primary_backup_disk}/${BKP_DIR}/archives/$(echo $dir | sed "s:$(pwd)\/::g" | sed 's:/:_:g')_$(date "+%Y_%m_%d_%H-%M-%S")_$suffix.tar.gz $dir
done

# remove old backups following the configuration rules
if [ $(find ${primary_backup_disk}/${BKP_DIR}/archives/ -type f -name "*_daily.tar.gz" | wc -l) -ge 1 ]
then
	find ${primary_backup_disk}/${BKP_DIR}/archives/ -type f -name "*_daily.tar.gz" -mtime +$DAILY -delete >> $logfile
else
	echo "[WARNING] - $(date "+%F_%T") There is only ONE daily archive left " >> $logfile
fi

if [ $(find ${primary_backup_disk}/${BKP_DIR}/archives/ -type f -name "*_weekly.tar.gz" | wc -l) -ge 1 ]
then
	find ${primary_backup_disk}/${BKP_DIR}/archives/ -type f -name "*_weekly.tar.gz" -mtime +$(echo "$WEEKLY * 7" | bc) -delete >> $logfile
else
	echo "[WARNING] - $(date "+%F_%T") There is only ONE weekly archive left " >> $logfile
fi

if [ $(find ${primary_backup_disk}/${BKP_DIR}/archives/ -type f -name "*_monthly.tar.gz" | wc -l) -ge 1 ]
then
	find ${primary_backup_disk}/${BKP_DIR}/archives/ -type f -name "*_monthly.tar.gz" -mtime +&(echo "$MONTHLY * 30" | bc) -delete >> $logfile
else
	echo "[WARNING] - $(date "+%F_%T") There is only ONE monthly archive left " >> $logfile
fi

# Sync backup directories in drives
for label in $disks
do
	short_label=$(echo $label | awk -F"/" '{print $NF}')
	if [ "/srv/${short_label}" != ${primary_backup_disk} ]
	then
		rsync -aqzhHl --delete ${primary_backup_disk}/${BKP_DIR} /srv/${short_label}/${BKP_DIR} >> $logfile
	fi
done


# Cleaning old log files
find /var/log/ -type f -name "git-backup*.log" -mtime -30 -delete >> $logfile

# Unmounting drives
sync
for label in $disks
do
	umount $label >> $logfile
done

# Sending email
if [ $(grep "ERROR|WARNING" $logfile | wc -l) -eq 0 ]
then
	body=/tmp/$(date "+%F_%H-%M").txt
	echo -e "Backup $(date) was successful.\nSee log in attachment" > $body
	mpack -s "Git backup routine - OK." -d $body $logfile $RECIPIENT
else
	body=/tmp/$(date "+%F_%H-%M").txt
	echo -e "Backup $(date) had ERRORS!\nSee log in attachment" > $body
	mpack -s "Git backup routine - NOT OK." -d $body $logfile $RECIPIENT
fi

