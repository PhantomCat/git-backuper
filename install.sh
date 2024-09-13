#!/bin/bash

# Let's check the running parameters
if [ $# -gt 0 ]
then
	if [ $# -eq 1 ]
	then
		case $1 in
			# Adding git repos to the list
			"--add-json")
				mkdir -p /etc/gbkp
				if [ $(find . -name "gbkp*.json" | wc -l) -ge 1 ]
				then
					for jsonfile in $(find $(pwd) -name "gbkp*.json")
					do
						jq -r '.[].ssh_url_to_repo' $jsonfile >> /etc/gbkp/repo.list
						echo "New json file added to backup system" 
					done
				else
					echo "No .json file named gbkp...json was found here"
					exit 1
				fi
				exit
				;;
			# Make a new list
			"--new-json")
				mkdir -p /etc/gbkp
				echo "All json files will be replaced with the NEWEST one."
				read -p "Are you sure? (type \"yes\"): " sure
				if [ $sure = "yes" ]
				then
					if [ $(find . -name "gbkp*.json" | wc -l) -ge 1 ]
					then
						jq -r '.[].ssh_url_to_repo' $(\
							find $(pwd) -name "gbkp*.json" -type f -printf '%T@ %p\n' | \
							sort -k 1nr | sed 's/^[^ ]* //' | head -n 1\
						)  > /etc/gbkp/repo.list
						exit
					else
						echo "No .json file named gbkp...json was found here"
						exit 1
					fi
				else
					echo OK
					exit
				fi
				;;
			*) 
				echo "Unknown parameter. Read the README.md file."
				exit 1
				;;
		esac
	else
		echo "Too many parameters, one was expected."
		exit 1
	fi
fi

# Install mailing software we need 
apt update
apt install ssmtp mpack -y -qqq

clear
echo "Welcome to git backuper script installator.
Let me ask you a few questions to make the installation successfull."
read -p "Press ENTER to continue" ok

clear
echo "1/11: Choose the name of your USB-to-SATA adapter from the list
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
echo "2/11: Enter the partition label prefix.

ATTENTION! It\'s extremely important to use disk (partition) label
AND to make sure, that labels are not overlapping!
E.g. Your partitions labels at this time are:"
for label in /dev/disk/by-label/*
do
	echo -e "\t$label"
done
echo "Enter the left side of labels, that doesn't differs 
------------------------------------------------------------"
read -p "Write the disk label prefix: " DISK_LABEL_PREFIX 
sleep 1

clear
echo "3/11: Enter the folder name to save backups

------------------------------------------------------------"
read -p "Write the folder name: " BKP_DIR
sleep 1

clear
echo "4/11: Choose, how often you'll need to backup data

*tip: you can tune the schedule, just type: sudo crontab -e
------------------------------------------------------------"
read -p "   1) Once in hour
   2) Once in 6 hours
   3) Once a day in 3 AM
   4) Once a week in 10:10 on Monday
Choose interval: " interval
case $interval in
	1) INTERVAL="0 * * * *	"
		break;;
	2) INTERVAL="0 */6 * * *	"
		break;;
	3) INTERVAL="0 3 * * *	"
		break;;
	4) INTERVAL="10 10 * * 1"
	*) INTERVAL="0 3 */2 * *	"
esac

clear
echo "5/11: How many MONTHLY backups do you want to keep?

------------------------------------------------------------"
read -p "Number of monthly copies: " MONTHLY


clear
echo "6/11: How many WEEKLYLY backups do you want to keep?

------------------------------------------------------------"
read -p "Number of weekly copies: " WEEKLY

clear
echo "7/11: How many DAILY backups do you want to keep?

------------------------------------------------------------"
read -p "Number of daily copies: " DAILY
clear

clear
echo "8/11: Email address to send emails FROM:

------------------------------------------------------------"
read -p "Email address FROM: " EMAIL_FROM
clear

clear
echo "9/11: Password of email address \"FROM\":

------------------------------------------------------------"
read -p "Password: " EMAIL_PASS
clear

clear
echo "10/11: SMTP server address:

------------------------------------------------------------"
read -p "Server address: " SMTP_SERVER
clear

clear
echo "11/11: Email addresses to send emails TO:
TIP: You can add more, than one email to receive,
just break them with spaces
------------------------------------------------------------"
read -p "Who will receive emails (TO): " EMAIL_TO
clear

echo "So, check all, you entered:
USB device:	   $USB_DEV
Disk label prefix: $DISK_LABEL_PREFIX
Backup directory:  $BKP_DIR
Backup interval:   $INTERVAL
$MONTHLY	monthly backups will be stored
$WEEKLY	weekly backups will be stored
$DAILY	daily backups will be stored
Email will be sent from: $EMAIL_FROM
With password $EMAIL_PASS
Through the $SMTP_SERVER (port 587 by default)
to $EMAIL_TO
"
read -p "If all is OK type 1, if not - type 0 and start again
Enter your choice: " finish

if [ $finish -eq 1 ]
then
	mkdir -p /etc/gbkp
	cp -f ./gbkp.conf /etc/gbkp/
	sed -i "s/USB_DEV=.*/USB_DEV=$USB_DEV/g" /etc/gbkp/gbkp.conf
	sed -i "s/DISK_LABEL_PREFIX=.*/DISK_LABEL_PREFIX=$DISK_LABEL_PREFIX/g" /etc/gbkp/gbkp.conf
	sed -i "s/BKP_DIR=.*/BKP_DIR=$BKP_DIR/g" /etc/gbkp/gbkp.conf
	echo "$INTERVAL root /opt/gbkp.sh" > /etc/cron.d/gbkp
	sed -i "s/MOTHLY=.*/MONTHLY=$MONTHLY/g" /etc/gbkp/gbkp.conf
	sed -i "s/WEEKLY=.*/WEEKLY=$WEEKLY/g" /etc/gbkp/gbkp.conf
	sed -i "s/DAILY=.*/DAILY=$DAILY/g" /etc/gbkp/gbkp.conf
	echo -e "UseSTARTTLS=YES\nmailhub=${SMTP_SERVER}:587\nAuthUser=$EMAIL_FROM\nAuthPass=${EMAIL_PASS}\nFromLineOverride=YES" > /etc/ssmtp/ssmtp.conf
	echo "root:${EMAIL_FROM}:${SMTP_SERVER}:587" > /etc/ssmtp/revaliases
	sed -i "s/EMAIL_TO=.*/EMAL_TO=$EMAIL_TO/g" /etc/gbkp/gbkp.conf
	cp ./gbkp.sh /opt/
	ln -s /opt/gbkp.sh /usr/bin/gbkp
else
	unset IFS
	exit 1
fi	
unset IFS
