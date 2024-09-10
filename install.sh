#!/bin/bash

clear
echo "Welcome to git backuper script installator.
Let me ask you a few questions to make the installation successfull."
read -p "Press ENTER to continue" ok

clear
echo "1/7: Choose the name of your USB-to-SATA adapter from the list
"
PS3="Choose you device: "
echo 
IFS=$'\n'
list=($(lsusb | colrm 1 33))
select dev in "${list[@]}"
do
	USB_DEV=$dev
	sleep 1
	break
done

clear
echo "2/7: Enter the partition label prefix.

ATTENTION! It\'s extremely important to use disk (partition) label
AND to make sure, that labels are not overlapping!
E.g. If your partitions labels are:
	backup_disk_01
	backup_disk_02
	backup_disk_03
Enter \"backup_disk\" or \"backup_disk_\"
------------------------------------------------------------"
read -p "Write the disk label prefix: " DISK_LABEL_PREFIX 
sleep 1

clear
echo "3/7: Enter the folder name to save backups

------------------------------------------------------------"
read -p "Write the folder name: " BKP_DIR
sleep 1

clear
echo "4/7: Choose, how often you'll need to backup data

*tip: you can tune the schedule, just type: sudo crontab -e
------------------------------------------------------------"
read -p "   1) Once in hour
   2) Once in 6 hours
   3) Once a day in 3 AM
Choose interval: " interval
case $interval in
	1) INTERVAL="0 *	* * *	"
		break;;
	2) INTERVAL="0 */6	* * *	"
		break;;
	3) INTERVAL="0 3	* * *	"
		break;;
	*) INTERVAL="0 3	*/2 * *	"
esac

clear
echo "5/7: How many MONTHLY backups do you want to keep?

------------------------------------------------------------"
read -p "Number of monthly copies: " MONTHLY


clear
echo "6/7: How many WEEKLYLY backups do you want to keep?

------------------------------------------------------------"
read -p "Number of weekly copies: " WEEKLY

clear
echo "5/7: How many DAILY backups do you want to keep?

------------------------------------------------------------"
read -p "Number of daily copies: " DAILY
clear

echo "So, check all, you entered:
USB device:	   $USB_DEV
Disk label prefix: $DISK_LABEL_PREFIX
Backup directory:  $BKP_DIR
Backup interval:   $INTERVAL
$MONTHLY	monthly backups will be stored
$WEEKLY	weekly backups will be stored
$DAILY	daily backups will be stored
"
read -p "If all is OK type 1, if not - type 0 and start again
Enter your choice: " finish

if [ $finish -eq 1 ]
then
	cp -f ./gbkp.conf /etc/
	sed -i "s/USB_DEV=.*/USB_DEV=$USB_DEV/g" /etc/gbkp.conf
	sed -i "s/DISK_LABEL_PREFIX=.*/DISK_LABEL_PREFIX=$DISK_LABEL_PREFIX/g" /etc/gbkp.conf
	sed -i "s/BKP_DIR=.*/BKP_DIR=$BKP_DIR/g" /etc/gbkp.conf
	echo "$INTERVAL root /opt/gbkp" > /etc/cron.d/gbkp
	sed -i "s/MOTHLY=.*/MONTHLY=$MONTHLY/g" /etc/gbkp.conf
	sed -i "s/WEEKLY=.*/WEEKLY=$WEEKLY/g" /etc/gbkp.conf
	sed -i "s/DAILY=.*/DAILY=$DAILY/g" /etc/gbkp.conf
	cp ./gbkp.sh /opt/
	ln -s /opt/gbkp.sh /usr/bin/gbkp
else
	unset IFS
	exit 1
fi	
unset IFS
