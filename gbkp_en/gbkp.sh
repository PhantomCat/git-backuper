#!/bin/bash
# Git repos backup script with rsync mirroring

# Local variables to make our life easier
logfile=/var/log/gbkp/git-backuper_$(date "+%F_%H-%M-%S").log
touch $logfile

# Let's check the config file
if [ ! -f /etc/gbkp/gbkp.conf ]
then
	echo "[ERROR] - $(date "+%F_%T") - no cofig file" >> $logfile
	exit 1
else
	# include it with all of its variables
	. /etc/gbkp/gbkp.conf
fi

# Sending initial email
for mail in $EMAIL_TO
do
	echo -e "Subject:Git backup routine - START\n\nGit backup route will start in 10 minutes! Make sure that you istalled the disks!" | sendmail $mail
done
sleep 600

# check if the USB-to-SATA adapter is attached and powered on
if [ $(lsusb | grep -i "$USB_DEV" | wc -l) -eq 0 ]
then
	echo "[FAIL] - $(date "+%F_%T") - GIT BACKUP Failed - NO USB DEVICE!" >> $logfile
	exit 1
fi

# get all disks (partitions) with label we used to write backups
disks=$(find /dev/disk/by-label/ -name "$DISK_LABEL_PREFIX*")

# choose the first disk in list as a primary to work on
primary_backup_disk=/srv/$(echo $disks | awk '{print $1}' | awk -F"/" '{print $NF}')

# creating the mounting points,
# mounting partitions and 
# creating backup directories on them
for label in $disks
do
	short_label=$(echo $label | awk -F"/" '{print $NF}')
	mkdir -p /srv/${short_label}
	sleep 1
	mount $label /srv/${short_label} >> $logfile
	sleep 1
	mkdir -p /srv/${short_label}/${BKP_DIR}/git
	mkdir -p /srv/${short_label}/${BKP_DIR}/archives
done

# read the repositories list and pull them into last mounted drive's backup directory
while read line
do
	if [ $(grep $line ${primary_backup_disk}/${BKP_DIR}/cloned | wc -l) -eq 0 ]
	then	
		repo_dir=$(echo $line | cut -f 2 -d ":" | sed 's/\.git$//g')
		git clone $line ${primary_backup_disk}/${BKP_DIR}/git/${repo_dir} >> $logfile
		echo $line >> ${primary_backup_disk}/${BKP_DIR}/cloned
	else
		echo "$line is already cloned, will be just updated" >> $logfile
	fi
done < /etc/gbkp/repo.list

# Get directories with git repositories cloned
git_dirs=$(find ${primary_backup_disk}/${BKP_DIR}/git/ -type d -name '.git' | sed 's/\.git//g')

# in case the git repo already have the directory - get inside it and pull all branches in it
for dir in ${git_dirs}
do
	cd $dir
	pwd >> $logfile
	git pull --all --recurse-submodules >> $logfile
	if [ $? -eq 0 ]
	then
		echo "[OK] - $(date "+%F_%T") Successfully pulled git in $dir" >> $logfile
	else	
		echo -e "[ERROR] - $(date "+%F_%T") Not pulled git in $dir\n\t\tTRY TO PULL IT BY HAND" >> $logfile
	fi
	sleep 1

	#return to the clonning directory
	cd /srv/
done

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
	find ${primary_backup_disk}/${BKP_DIR}/archives/ -type f -name "*_monthly.tar.gz" -mtime +$(echo "$MONTHLY * 30" | bc) -delete >> $logfile
else
	echo "[WARNING] - $(date "+%F_%T") There is only ONE monthly archive left " >> $logfile
fi

# Sync backup directories in drives
for label in $disks
do
	short_label=$(echo $label | awk -F"/" '{print $NF}')
	if [ "/srv/${short_label}" != ${primary_backup_disk} ]
	then
		echo -e "------------------------------\n\nSyncronization of disk ${short_label} started" >> $logfile 
		rsync -aqzhHl --delete ${primary_backup_disk}/${BKP_DIR} /srv/${short_label}/${BKP_DIR} >> $logfile
		echo -e "------------------------------\n\nSyncronization of disk ${short_label} finished" >> $logfile 
	fi
done

# Cleaning old log files
find /var/log/ -type f -name "git-backup*.log" -mtime +30 -delete >> $logfile

# Unmounting drives
cd /srv/
for label in $disks
do
	short_label=$(echo $label | awk -F"/" '{print $NF}')
	echo "Unmounting /srv/${short_label}" >> $logfile
	mounted=1
	while [ $mounted -eq 1 ]
	do
		umount /srv/${short_label} 2>> $logfile
		if [ $(mount | grep "/srv/${short_label}" | wc -l) -eq 0 ]
		then
			mounted=0
			echo "/srv/${short_label} unmounted" >> $logfile
		else
			sleep 10 
		fi
	done
	rmdir /srv/${short_label} >> $logfile
done

# sharing primary disk in RO
cp --remove-destination /etc/gbkp/smbd.conf /etc/samba/smbd.conf
for label in $disks
do
	short_label=$(echo $label | awk -F"/" '{print $NF}')
	mkdir -p /mnt/${BKP_DIR}/${short_label}
	mount $label /mnt/${BKP_DIR}/${short_label}
	echo -e "[${short_label}]\n\tguest ok = Yes\n\tpath = /mnt/${BKP_DIR}/${short_label}\n\n" >> /etc/samba/smbd.conf
done
cp --remove-destination /etc/samba/smbd.conf /etc/samba/smb.conf
smbd
serv_ip=$(hostname -I | cut -f 1 -d " ")

# Sending email
if [ $(grep -E 'ERROR|WARNING' $logfile | wc -l) -eq 0 ]
then
	body=/tmp/gbkp_$(date "+%F_%H-%M").msg
	echo "
Backup $(date) was successful.

Started sharing on \\\\${serv_ip} (smb://${serv_ip}/ for linux)

Sharing time 1 hour.

See log in attachment" > $body
	mpack -s "Git backup routine - OK." -d $body $logfile ${EMAIL_TO}
else
	body=/tmp/gbkp_$(date "+%F_%H-%M").msg
	echo "
Backup $(date) has ERRORS or WARNINGS!

Started sharing on \\\\${serv_ip} (smb://${serv_ip} for linux)

Sharing time 1 hour.

See log in attachment" > $body
	mpack -s "Git backup routine - NOT OK." -d $body $logfile ${EMAIL_TO}
fi

# Finishing all jobs after one hour
sleep 360
killall smbd
umount /mnt/${BKP_DIR}/*
rmdir /mnt/${BKP_DIR}/*

# Sending finishing emails
for mail in $EMAIL_TO
do
	echo -e "Subject:Git backup routine - All Done.\n\nNow you can remove disks and put them into safe!" | sendmail $mail
done
