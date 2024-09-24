#!/bin/bash

# Проверка на наличие параметров запуска
if [ $# -gt 0 ]
then
	if [ $# -eq 1 ]
	then
		case $1 in
			# Добавление репозиториев в список
			"--add-json")
				mkdir -p /etc/gbkp
				if [ $(find . -name "gbkp*.json" | wc -l) -ge 1 ]
				then
					for jsonfile in $(find $(pwd) -name "gbkp*.json")
					do
						jq -r '.[].ssh_url_to_repo' $jsonfile >> /etc/gbkp/repo.list
						echo "Новый файл json добавлен в систему резервного копирования" 
					done
				else
					echo ".json-файл с именем типа gbkp...json не найден в текущей папке"
					exit 1
				fi
				exit
				;;
			# Создание нового списка
			"--new-json")
				mkdir -p /etc/gbkp
				echo "Внимание! Все ссылки на репозитории будут заменены на список из новейшего файла в текущей директории."
				read -p "Вы уверены? (введите \"yes\"): " sure
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
						echo ".json-файл с именем типа gbkp...json не найден в текущей папке"
						exit 1
					fi
				else
					echo OK
					exit
				fi
				;;
			*) 
				echo "Неизвестный параметр. Внимательно прочтите файл README.md"
				exit 1
				;;
		esac
	else
		echo "Слишком много параметров, ожидался один или ни одного."
		exit 1
	fi
fi

clear
echo "Добро пожаловать в инсталятор скрипта резервного копирования git-репозиториев.
Позвольте задать вам несколько вопросов, чтобы работа системы была успешной."
read -p "...для продолжения нажмите ENTER" ok

clear
echo "1/11: Выберите из списка наименование вашего адаптера USB-to-SATA
"
PS3="Выберите устройство: "
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
echo "2/11: Введите префикс разделов резервного копирования.

ВНИМАНИЕ! Особенно важно использовать метки разделов (дисков),
А ТАКЖЕ, убедиться в том, что метки не перекрывают друг друга полностью 
(должны отличаться окончанием)
На данный момент метки подключенных дисков следующие:"
if [ $(ls /dev/disk/by-label/ | wc -l) -lt 1 ]
then
	echo "ОШИБКА! В вашей системе не обнаружено дисков (разделов) с метками. Читайте инструкции в файле README.md"
	exit 1
fi
for label in $(ls /dev/disk/by-label/)
do
	echo -e "\t$label"
done
echo "Введите левую часть метки дисков, которая не отличается 
от диска к диску и будет сигнализировать системе, 
что данный набор дисков является набором для резервного копирования.
Вместе с этим, введённая информация не должна содержать информацию, 
относящуюся только к одному диску из набора, а также должна отличаться
от меток, использующих другие наборы дисков.
------------------------------------------------------------"
read -p "Введите префикс метки: " DISK_LABEL_PREFIX 
sleep 1

clear
echo "3/11: Введите имя папки для сохранения резервных копий

На дисках для резервных копий будет создана дополнительная папка
------------------------------------------------------------"
read -p "Введите имя папки: " BKP_DIR
sleep 1

clear
echo "4/11: Выберите, как часто будут выполнять резервные копии

*совет: Вы можете дополнительно настроить расписание, 
просто введите в коммандной строке: sudo vim /etc/cron.d/gbkp
------------------------------------------------------------"
read -p "   1) Раз в день, в 10:10, каждый рабочий день 
   2) Каждый понедельник в 10:10
Выберите интервал: " interval
case $interval in
	1) INTERVAL="10 10 * * 1-5	"
		break;;
	2) INTERVAL="10 10 * * 1	"
		break;;
	*) echo "Неожиданный параметр, буду использовать первый вариант."
		INTERVAL="10 10 * * 1-5	"
		break;;
esac

clear
echo "5/11: Как много ЕЖЕМЕСЯЧНЫХ резервных копий вы собираетесь сохранять?

------------------------------------------------------------"
ok=0
while [ $ok -eq 0 ]
do
	read -p "Количество ежемесячных копий: " MONTHLY
	if [[ $MONTHLY =~ ^[[:digit:]]+$ ]]
	then
		ok=1
	else
		echo "Неправильный ввод!"
	fi
done



clear
echo "6/11: Как много ЕЖЕНЕДЕЛЬНЫХ резервных копий вы собираетесь сохранять?

------------------------------------------------------------"
ok=0
while [ $ok -eq 0 ]
do
	read -p "Количество еженедельных копий: " WEEKLY
	if [[ $WEEKLY =~ ^[[:digit:]]+$ ]]
	then
		ok=1
	else
		echo "Неправильный ввод!"
	fi
done

clear
if [ $interval -ne 2 ]
then
	echo "7/11: Как много ЕЖЕДНЕВНЫХ резервных копий вы собираетесь сохранять?

------------------------------------------------------------"
	ok=0
	while [ $ok -eq 0 ]
	do
		read -p "Количество ежедневных копий: " DAILY
		if [[ $DAILY =~ ^[[:digit:]]+$ ]]
		then
			ok=1
		else
			echo "Неправильный ввод!"
		fi
	done
else
	DAILY=1
fi

clear
echo "8/11: Email-адрес для ОТПРАВКИ сообщений:

Только один адрес может быть указан.
------------------------------------------------------------"
ok=0
while [ $ok -eq 0 ]
do
	read -p "Email-адрес оправителя сообщений: " EMAIL_FROM
	if [[ $EMAIL_FROM =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
	then
		ok=1
	else
		echo "Неправильный ввод!"
	fi
done

clear
echo "9/11: Пароль для email-адреса отправителя:

ВНИМАНИЕ! Пароль не будет скрыт и не будет зашифрован в системе.
Вы должны ввести существующий праоль от существующего аккаунта
------------------------------------------------------------"
read -p "Пароль: " EMAIL_PASS

clear
echo "10/11: Адрес сервера SMTP:

Ваш сервер SMTP, на котором был создан аккаунт для отправки сообщений.
------------------------------------------------------------"
ok=0
while [ $ok -eq 0 ]
do
	read -p "Адрес сервера: " SMTP_SERVER
	if [[ $SMTP_SERVER =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
	then
		ok=1
	else
		echo "Неправильный ввод!"
	fi
done

clear
echo "11/11: Email-адреса для оповещения сотрудников:

На эти адреса будут приходить письма от сервера.
*совет: Вы можете добавить более одного адреса, просто разделите их пробелами
------------------------------------------------------------"
unset IFS
ok=0
while [ $ok -eq 0 ]
do
	read -p "Адреса получателей (TO): " EMAIL_TO
	for email in $EMAIL_TO
	do
		if [[ $email =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
		then
			ok=1
		else
			echo -e "ВНИМАНИЕ! $email - недействительный почтовый адрес!\nперепроверьте все адреса и введите заново только действительные."
			ok=0
			break
		fi
	done
done
clear

echo "Итак, давайте проверим информацию, которую я получил:
USB-устройство: $USB_DEV
Префикс дисков: $DISK_LABEL_PREFIX
Папка РК:       $BKP_DIR
Интервал РК:    $(if [ $interval -eq 2 ]; then echo "Каждый понедельник в 10:10"; else echo "Раз в день, в 10:10, каждый рабочий день")
$MONTHLY	будет сохранено ежемесячных РК
$WEEKLY	будет сохранено еженедельных РК
$DAILY	будет сохранено ежедневных РК
Сообщения будут отправляться с адреса: $EMAIL_FROM
С паролем:                             $EMAIL_PASS
Через сервер SMPT:                     $SMTP_SERVER (по-умолчанию используется 587 порт)
Получатели:                            $EMAIL_TO
"
read -p "Если все данные верны введите 1, если нет - 0, после чего нажмите Enter
Введите ваш выбор: " finish

if [ $finish -eq 1 ]
then

	# Установка почтовых утилит, которые используются системой 
	if [ $(dpkg -l | grep -E "ssmtp|mpack" | grep -E "^ii" | wc -l) -ge 2 ]
	then
		echo "Утилиты ssmtp and mpack уже установлены, пропускаю их установку"
	else
		apt update
		apt install ssmtp mpack -y -qqq
	fi
	
	# Создание папки настроек программы в /etc/
	mkdir -p /etc/gbkp

	# Если конфигурационный файл существует - делаем его резервную копию
	if [ -f /etc/gbkp/gbkp.conf ]
	then
		mv /etc/gbkp/gbkp.conf /etc/gbkp/gbkp.conf_$(date "+%Y_%m_%d_%H-%M-%S").bak
	fi
	cp -f ./gbkp.conf /etc/gbkp/
	sed -i "s/USB_DEV=.*/USB_DEV=$USB_DEV/g" /etc/gbkp/gbkp.conf
	sed -i "s/DISK_LABEL_PREFIX=.*/DISK_LABEL_PREFIX=$DISK_LABEL_PREFIX/g" /etc/gbkp/gbkp.conf
	sed -i "s/BKP_DIR=.*/BKP_DIR=$BKP_DIR/g" /etc/gbkp/gbkp.conf
	echo "$INTERVAL root /opt/gbkp.sh" > /etc/cron.d/gbkp
	sed -i "s/INTERVAL=.*/INTERVAL=$interval/g" /etc/gbkp/gbkp.conf
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

	# Собираем первый список репозиториев
	if [ $(find . -name "gbkp*.json" | wc -l) -ge 1 ]
        then
        	jq -r '.[].ssh_url_to_repo' $(\
                find $(pwd) -name "gbkp*.json" -type f -printf '%T@ %p\n' | \
                sort -k 1nr | sed 's/^[^ ]* //' | head -n 1\
                )  > /etc/gbkp/repo.list
                exit
         else
                echo ".json-файл с именем типа gbkp...json не найден в текущей папке"
                exit 1
         fi
else
	unset IFS
	exit 1
fi	
unset IFS
