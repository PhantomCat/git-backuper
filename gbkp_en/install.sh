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
                                        mv /etc/gbkp/repo.list /etc/gbkp/repo.list_$(date "+%Y_%m_%d_%H-%M-%S").bak
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
		echo "Too many parameters, one or none was expected."
		exit 1
	fi
fi

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
Your partitions labels at this time are:"
if [ $(ls /dev/disk/by-label/ | wc -l) -lt 1 ]
then
	echo "ERROR! There is no any labeled disks in your system. Read the instructions in README.md file!"
	exit 1
fi
for label in $(ls /dev/disk/by-label/)
do
	echo -e "\t$label"
done
echo "Enter the left side of labels, that doesn't differs 
from each to other, and at the same time - differs from
others, that will not be used as backup disks.
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

*tip: you can tune the schedule, just type: 
	sudo vim /etc/cron.d/gbkp
------------------------------------------------------------"
read -p "   1) Once a day in 10:10 AM every working day
   2) Once a week in 10:10 on Monday
Choose interval: " interval
case $interval in
	1) INTERVAL="10 10 * * 1-5	"
		break;;
	2) INTERVAL="10 10 * * 1	"
		break;;
	*) echo "non-excepted parameter was given, will take first"
		INTERVAL="10 10 * * 1-5	"
		break;;
esac

clear
echo "5/11: How many MONTHLY backups do you want to keep?

------------------------------------------------------------"
ok=0
while [ $ok -eq 0 ]
do
	read -p "Number of monthly copies: " MONTHLY
	if [[ $MONTHLY =~ ^[[:digit:]]+$ ]]
	then
		ok=1
	else
		echo "Wrong input!"
	fi
done



clear
echo "6/11: How many WEEKLYLY backups do you want to keep?

------------------------------------------------------------"
ok=0
while [ $ok -eq 0 ]
do
	read -p "Number of weekly copies: " WEEKLY
	if [[ $WEEKLY =~ ^[[:digit:]]+$ ]]
	then
		ok=1
	else
		echo "Wrong input!"
	fi
done

clear
echo "7/11: How many DAILY backups do you want to keep?

------------------------------------------------------------"
ok=0
while [ $ok -eq 0 ]
do
	read -p "Number of daily copies: " DAILY
	if [[ $DAILY =~ ^[[:digit:]]+$ ]]
	then
		ok=1
	else
		echo "Wrong input!"
	fi
done

clear
echo "8/11: Email address to send emails FROM:

Only one address is accepting. It must be sat up in advance. 
------------------------------------------------------------"
ok=0
while [ $ok -eq 0 ]
do
	read -p "Email address FROM: " EMAIL_FROM
	if [[ $EMAIL_FROM =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
	then
		ok=1
	else
		echo "Wrong input!"
	fi
done

clear
echo "9/11: Password of email address \"FROM\":

You must enter existing real password from the account above.
------------------------------------------------------------"
read -p "Password: " EMAIL_PASS

clear
echo "10/11: SMTP server address:

Your SMTP server, which has email account from previos questions.
------------------------------------------------------------"
ok=0
while [ $ok -eq 0 ]
do
	read -p "Server address: " SMTP_SERVER
	if [[ $SMTP_SERVER =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
	then
		ok=1
	else
		echo "Wrong input!"
	fi
done

clear
echo "11/11: Email addresses to send emails TO:
TIP: You can add more, than one email to receive,
just break them with spaces
------------------------------------------------------------"
unset IFS
ok=0
while [ $ok -eq 0 ]
do
	read -p "Who will receive emails (TO): " EMAIL_TO
	for email in $EMAIL_TO
	do
		if [[ $email =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
		then
			ok=1
		else
			echo -e "ATTENTION! $email is wrong!\nRecheck the addresses and enter them again."
			ok=0
			break
		fi
	done
done
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

	# Install mailing software we need 
	if [ $(dpkg -l | grep -E "ssmtp|mpack" | grep -E "^ii" | wc -l) -ge 2 ]
	then
		echo "ssmtp and mpack packages are already installed, skipping installation"
	else
		apt update
		apt install ssmtp mpack -y -qqq
	fi
	
	# Creating directory in /etc/
	mkdir -p /etc/gbkp

	# If configuration file exists - make its backup
	if [ -f /etc/gbkp/gbkp.conf ]
	then
		mv /etc/gbkp/gbkp.conf /etc/gbkp/gbkp.conf_$(date "+%Y_%m_%d_%H-%M-%S").bak
	fi
	cp -f ./gbkp.conf /etc/gbkp/
	sed -i "s/USB_DEV=.*/USB_DEV=$USB_DEV/g" /etc/gbkp/gbkp.conf
	sed -i "s/DISK_LABEL_PREFIX=.*/DISK_LABEL_PREFIX=$DISK_LABEL_PREFIX/g" /etc/gbkp/gbkp.conf
	sed -i "s/BKP_DIR=.*/BKP_DIR=$BKP_DIR/g" /etc/gbkp/gbkp.conf
	echo "$INTERVAL root /opt/gbkp.sh" > /etc/cron.d/gbkp
	sed -i "s/MOTHLY=.*/MONTHLY=$MONTHLY/g" /etc/gbkp/gbkp.conf
	sed -i "s/WEEKLY=.*/WEEKLY=$WEEKLY/g" /etc/gbkp/gbkp.conf
	sed -i "s/DAILY=.*/DAILY=$DAILY/g" /etc/gbkp/gbkp.conf
	if [ -f /etc/ssmtp/ssmtp.conf ]
	then
		mv /etc/ssmtp/ssmtp.conf /etc/ssmtp/ssmtp.conf_$(date "+%Y_%m_%d_%H-%M-%S").bak
	fi
	echo -e "UseSTARTTLS=YES\nmailhub=${SMTP_SERVER}:587\nAuthUser=$EMAIL_FROM\nAuthPass=${EMAIL_PASS}\nFromLineOverride=YES" > /etc/ssmtp/ssmtp.conf
	if [ -f /etc/ssmtp/revaliases ]
	then
		mv /etc/ssmtp/revaliases /etc/ssmtp/revaliases_$(date "+%Y_%m_%d_%H-%M-%S").bak
	fi
	echo "root:${EMAIL_FROM}:${SMTP_SERVER}:587" > /etc/ssmtp/revaliases
	sed -i "s/EMAIL_TO=.*/EMAL_TO=$EMAIL_TO/g" /etc/gbkp/gbkp.conf
	if [[ ! -f /opt/gbkp.sh ]]
	then
		cp ./gbkp.sh /opt/
	fi
	if [[ ! -f /usr/bin/gbkp ]]
	then
		ln -s /opt/gbkp.sh /usr/bin/gbkp
	fi

	# Making first list of repositories
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
	unset IFS
	exit 1
fi	
unset IFS
