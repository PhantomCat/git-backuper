#!/bin/bash
#
# Git repos backup script with rsync mirroring

. /etc/gbkp.conf

if [ $(lsusb | grep -i "$USB_DEV" | wc -l) -eq 0 ]
then
	echo "[FAIL] - $(date +%F) - GIT BACKUP Failed - NO USB DEVICE!" >> /var/log/messages
	exit 1
fi

disks=$(find /dev/disk/by-label/ -name "$PREFIX*")

for label in $disks
do
	short_label=$(echo $label | awk -F"/" '{print $NF}')
	mkdir -p /srv/${short_label}
	mount $label /srv/${short_label}
	mkdir -p /srv/${short_label}/${BKP_DIR}
done

echo ${short_label}


