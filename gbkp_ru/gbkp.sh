#!/bin/bash
# Скрипт резервного копирования репозиториев Git с зеркалированием rsync

# Локальные переменные, которые облегчат нам жизнь
logfile=/var/log/gbkp/git-backuper_$(date "+%F_%H-%M-%S").log
touch $logfile

# Давайте проверим файл конфигурации
if [ ! -f /etc/gbkp/gbkp.conf ]
then
	echo "[ERROR] - $(date "+%F_%T") - no cofig file" >> $logfile
	exit 1
else
	# включим его со всеми его переменными
	. /etc/gbkp/gbkp.conf
fi

# Отправка начального электронного письма
for mail in $EMAIL_TO
do
	echo -e "Subject:Процедура резервного копирования Git - НАЧАЛО\n\nПроцедура резервного копирования Git начнется через 10 минут! Убедитесь, что вы установили диски!" | sendmail $mail
done
sleep 600

# проверим, подключен ли адаптер USB-SATA и включен ли он
if [ $(lsusb | grep -i "$USB_DEV" | wc -l) -eq 0 ]
then
	echo "[ERROR] - $(date "+%F_%T") - Резервное копирование GIT-репозиториев провалилось. Отсутвствует устройство USB!" >> $logfile
	exit 1
fi

# получим все диски (разделы) с метками, которые мы использовали для записи резервных копий
disks=$(find /dev/disk/by-label/ -name "$DISK_LABEL_PREFIX*")

# выберем первый диск в списке как основной для работы
primary_backup_disk=/srv/$(echo $disks | awk '{print $1}' | awk -F"/" '{print $NF}')

# создание точек монтирования,
# монтирование разделов и
# создание резервных каталогов в них
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

# прочитаем список репозиториев и перенесем их в резервную папку последнего смонтированного диска
while read line
do
	if [ $(grep $line ${primary_backup_disk}/${BKP_DIR}/cloned | wc -l) -eq 0 ]
	then	
		repo_dir=$(echo $line | cut -f 2 -d ":" | sed 's/\.git$//g')
		git clone $line ${primary_backup_disk}/${BKP_DIR}/git/${repo_dir} >> $logfile
		echo $line >> ${primary_backup_disk}/${BKP_DIR}/cloned
	else
		echo "$line уже склонирован, обновим содержимое на следующем шаге" >> $logfile
	fi
done < /etc/gbkp/repo.list

# получим каталоги с клонированными репозиториями git
git_dirs=$(find ${primary_backup_disk}/${BKP_DIR}/git/ -type d -name '.git' | sed 's/\.git//g')

# если для репозитория git уже есть каталог - зайдём в него и спуллим все его ветки
for dir in ${git_dirs}
do
	cd $dir
	pwd >> $logfile
	git pull --all --recurse-submodules >> $logfile
	if [ $? -eq 0 ]
	then
		echo "[OK] - $(date "+%F_%T") репозторий успешно стянут в $dir" >> $logfile
	else	
		echo -e "[ERROR] - $(date "+%F_%T") Не удалось стянуть репозиторий $dir\n\t\tПОПРОБУЙТЕ СПУЛЛИТЬ ЭТОТ РЕПОЗИТОРИЙ ВРУЧНУЮ!" >> $logfile
	fi
	sleep 1

	# возврат в общую директорию
	cd /srv/
done

# архивация и сжатие в tar.gz каждого каталога git с отметкой даты
# добавление суффиксов "ежедневно", "еженедельно" и "ежемесячно" для улучшения ротации резервных копий
# в случае, если резервное копирование выполняется один раз в неделю, то первый бекап месяца назначается "ежемесячным"
# остальные - "еженедельными"
if [ $INTERVAL -eq 2 ]
then
	m_day=$(date +"%d")
	if [ $m_day -le 7 ]
	then
		# Первый еженедельный бекап назначается ежемесячным
		suffix="monthly"
	else
		# остальные - обычные, еженедельные
		suffix="weekly"
	fi
else
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
fi

for dir in ${git_dirs}
do
	tar cvzf ${primary_backup_disk}/${BKP_DIR}/archives/$(echo $dir | sed "s:$(pwd)\/::g" | sed 's:/:_:g')_$(date "+%Y_%m_%d_%H-%M-%S")_$suffix.tar.gz $dir
done

# удаление старых сжатых архивов резервных копий, следуя настройкам (в /etc/gbkp/gbkp.conf)
# в случае, если выбран сохранения раз в неделю - пропускаем ежедневные бекапы, а бекап первой недели месяца называем ежемесячным
if [ $INTERVAL -ne 2 ]
then
	if [ $(find ${primary_backup_disk}/${BKP_DIR}/archives/ -type f -name "*_daily.tar.gz" | wc -l) -ge 1 ]
	then
		find ${primary_backup_disk}/${BKP_DIR}/archives/ -type f -name "*_daily.tar.gz" -mtime +$DAILY -delete >> $logfile
	else
		echo "[WARNING] - $(date "+%F_%T") There is only ONE daily archive left " >> $logfile
	fi
else
	# если у нас количество ежемесячных копий настроено так, что будут удаляться еженедельные копии - исправляем
	if [ $MONTHLY -lt $(echo "$WEEKLY / 4" | bc) ]
	then 
		MONTHLY=$(echo "$WEEKLY / 4 + 1" | bc)
	fi
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

# синхронизация директорий резервных копий ведущего диска с остальными в группе дисков
for label in $disks
do
	short_label=$(echo $label | awk -F"/" '{print $NF}')
	if [ "/srv/${short_label}" != ${primary_backup_disk} ]
	then
		echo -e "------------------------------\n\nНачата синхронизация диска ${short_label}" >> $logfile 
		rsync -aqzhHl --delete ${primary_backup_disk}/${BKP_DIR} /srv/${short_label}/${BKP_DIR} >> $logfile
		echo -e "------------------------------\n\nСинхронизация диска ${short_label} завершена" >> $logfile 
	fi
done

# Удаление файлов логирования старше 30 дней
find /var/log/ -type f -name "git-backup*.log" -mtime +30 -delete >> $logfile

# Размонтирование дисков
cd /srv/
for label in $disks
do
	short_label=$(echo $label | awk -F"/" '{print $NF}')
	echo "Размонтирование /srv/${short_label}" >> $logfile
	mounted=1
	while [ $mounted -eq 1 ]
	do
		umount /srv/${short_label} 2>> $logfile
		if [ $(mount | grep "/srv/${short_label}" | wc -l) -eq 0 ]
		then
			mounted=0
			echo "/srv/${short_label} размонтирован" >> $logfile
		else
			sleep 10 
		fi
	done
	rmdir /srv/${short_label} >> $logfile
done

# Предоставление доступа к дискам в режиме "только чтение" по протокому SMB
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
Резервное копирование $(date) прошло успешно.

Предоставлен доступ по адресу: \\\\${serv_ip} (smb://${serv_ip}/ для linux)

Время доступа - 1 час.

Во вложении лог-файл резервного копирования" > $body
	mpack -s "Резервное копирование Git-репозиториев. - OK" -d $body $logfile ${EMAIL_TO}
else
	body=/tmp/gbkp_$(date "+%F_%H-%M").msg
	echo "
Резервное копирование $(date) закончено с ошибками или предупреждениями!
Ознакомьтесь с лог-файлом во вложении!

Предоставлен доступ по адресу: \\\\${serv_ip} (smb://${serv_ip} для linux)

Время доступа - 1 час.

Во вложении лог-файл резервного копирования" > $body
	mpack -s "Резервное копирование Git-репозиториев. - НЕ OK." -d $body $logfile ${EMAIL_TO}
fi

# Завершение всех заданий спустя час после начала предоставления доступа
sleep 3600
killall smbd
umount /mnt/${BKP_DIR}/*
rmdir /mnt/${BKP_DIR}/*

# рассылка email о завершении предоставления доступа и необходимости перемещения носителей в сейф
for mail in $EMAIL_TO
do
	echo -e "Subject:Резервное копирование Git-репозиториев. - Завершено.\n\nТеперь вам необходимо выключить адаптер USB-SATA, извлечь носители и поместить их (носители) в сейф." | sendmail $mail
done
