#!/bin/bash

# $1 - old ip
# $2 - new ip

export PATH=$PATH:/usr/sbin:/usr/sbin:/usr/local/sbin;

# colors
R_C="\033[0;91m"
G_C="\033[0;92m"
N_C="\033[0m"
Y_C="\033[1;33m"
RR_C="\e[0;91m"
GG_C="\e[0;92m"
PP_C="\033[1;35m"
OO_C="\033[38;5;214m"
YY_C="\033[1;33m"
GGG_C="\033[0;32m"
BB_C="\033[1;34m"
PPP_C="\033[0;35m"

# show script version
self_current_version="1.0.3"
printf "\n${YY_C}Hello${N_C}, my version is ${YY_C}$self_current_version\n\n${N_C}"

# check privileges
if [[ $EUID -ne 0 ]]
then
	printf "\n${R_C}ERROR - This script must be run as root.${N_C}" 
	exit 1
fi

args=("$@")

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
SELF_NAME=$(basename "$0");
TSTAMP=$(echo "$(date +%d-%m-%Y-%H-%M-%Z)")

USAGE_INFO=$(echo; printf "Use 2 or 4 arguments."; echo; printf "Usage: $SCRIPT_DIR/$SELF_NAME old_ip new_ip <old_gateway> <new_gateway>")

# args check
if [[ "$#" -lt 2 ]] || [[ "$#" -eq 3 ]]; then printf "\n${R_C}Not enough args${N_C}\n"; echo ${USAGE_INFO}; exit 1; fi;

# PowerDNS mysql DB update
isp_pdns_ipchanger() {

if [[ -f "/usr/sbin/pdns_server" ]]
then
	printf "\n${G_C}Updating MySQL PowerDNS DB pdns ${N_C}\n";
	mysql -D pdns -e "update records set content=replace(content,'${args[0]}', '${args[1]}');"
	printf "\n${G_C}Update completed${N_C}\n";
fi

}

# ISP Manager general changes
proceed_with_isp() {

printf "\n${G_C}Setting ihttpd listen all ips${N_C}\n";
$ISP5_PANEL_FILE -m core ihttpd.edit ip=any elid=${args[0]} sok=ok >/dev/null 2>/dev/null

#printf "\n${G_C}Adding new ip - ${args[1]}${N_C}\n";
#$ISP5_PANEL_FILE -m ispmgr ipaddrlist.edit name=${args[1]} sok=ok >/dev/null 2>/dev/null

printf "\n${G_C}Cleaning ISP Manager cache${N_C}\n";
\rm -rf /usr/local/mgr5/var/.xmlcache/*;
\rm -f /usr/local/mgr5/etc/ispmgr.lic /usr/local/mgr5/etc/ispmgr.lic.lock /usr/local/mgr5/var/.db.cache.*;

printf "\n${G_C}Restarting ISP Manager${N_C}\n\n";
#$ISP5_PANEL_FILE -m ispmgr ipaddrlist.delete elid=${args[0]} sok=ok;
$ISP5_PANEL_FILE -m ispmgr -R
sleep 5s

}

# If no ISP Manager or not supported version detected 
proceed_without_isp() {
read -p "Continiue IP change [Y/n]" -n 1 -r
echo
	if ! [[ $REPLY =~ ^[Nn]$ ]]
		then
			printf "\n${G_C}Backing up current network settings to /root/support/$TSTAMP${N_C}\n";
			
			NETWORK_BACKUP_PATH_LIST=("/etc/network*" "/etc/sysconfig/network*" "/etc/NetworkManager*" "/etc/netplan*")

			for network_backup_item in "${NETWORK_BACKUP_PATH_LIST[@]}"
			do
				\cp -Rf ${network_backup_item} /root/support/$TSTAMP/ >/dev/null 2>/dev/null
			done

			printf "\n${G_C}Current network settings:${N_C}\n\n";

			echo "$(\ip a)"
			echo
			echo "$(\ip r)"

			printf "\n${G_C}Starting ip change systemwide${N_C}\n";

			#network manager check

			if which nmcli &> /dev/null && [[ ! -z "$( \ls -A '/etc/NetworkManager/system-connections/' )" ]]
			then
				printf "\n${G_C}NetworkManager detected${N_C}\nConfiruration in /etc/NetworkManager/system-connections/\n";
			fi 

			#netplan check
			if which netplan &> /dev/null && [[ ! -z "$( \ls -A '/etc/netplan/' )" ]]
			then
				printf "\n${G_C}Netplan detected${N_C}\nConfiruration in /etc/netplan/\n";
			fi

			IP_CHANGE_PATH_LIST=("/etc/*" "/var/named/*" "/var/lib/powerdns/*")

			for ip_change_list_item in "${IP_CHANGE_PATH_LIST[@]}"
			do
				echo "Processing ${ip_change_list_item}";
				grep --no-messages --devices=skip -RIil --exclude={*.log,*.log.*,*.run,*random*,*.jpg,*.jpeg,*.webp} ${args[0]} ${ip_change_list_item} | xargs sed -i "s@${args[0]}@${args[1]}@gi" &> /dev/null
			done

			echo
			read -p "Going thru /home/* ? (for ex. VESTA panel, Bitrix, etc. It could take a very loooooooooong time) [y/N]" -n 1 -r
			echo
			if [[ $REPLY =~ ^[Yy]$ ]]
				then
				grep --no-messages --devices=skip -RIil --exclude={*.log,*.log.*,*.run,*random*,*.jpg,*.jpeg,*.webp} ${args[0]} /home/* | xargs sed -i "s@${args[0]}@${args[1]}@gi" &> /dev/null	
			fi

			# if we change gateway
			if [[ $GATEWAY_CHANGE == "YES" ]]
			then
				printf "\n${G_C}Changing gateway address${N_C}\n";

				GATEWAY_CONFIG_PATH_LIST=("/etc/NetworkManager/system-connections/*" "/etc/netplan/*" "/etc/network/interfaces" "/etc/network/interfaces.d/*" "/etc/sysconfig/network-scripts/*");

				for gateway_config_item in "${GATEWAY_CONFIG_PATH_LIST[@]}"
				do
					echo "Processing ${gateway_config_item}"
					grep --no-messages --devices=skip -RIil --exclude={*.log,*.log.*,*.run,*random*,*.jpg,*.jpeg,*.webp} ${args[2]} ${gateway_config_item} | xargs sed -i "s@${args[2]}@${args[3]}@gi" &> /dev/null
				done

				GATEWAY_CHANGED=YES
				unset GATEWAY_CHANGE
			else
				printf "\n${Y_C}3 and 4 script's agruments are empty. ${N_C}\n";
				printf "${Y_C}If default gateway IP address / subnet mask need be changed, do it manually${N_C}\n"
			fi

			if [ "$ISP5_RTG" = "1" ]
			then
				printf "\nGenerating ISP Manager root session key\n";
				ispkey="$RANDOM$RANDOM$RANDOM$RANDOM$RANDOM$RANDOM$RANDOM"
				\timeout 3 /usr/local/mgr5/sbin/mgrctl -m ispmgr session.newkey username=root key=$ispkey &> /dev/null
				printf "\n${R_C}Update ISP license if needed, RUN manually: curl -X POST -F \"func=soft.edit\" -F \"elid=$ISP5_LITE_ELID\" -F \"out=text\" -F \"ip=${args[1]}\" -F \"sok=ok\" -ks \"https://api.ispmanager.com/billmgr\" -F \"authinfo=support@provider:password\" ${N_C}\n";
				printf "\nISP Manager WEB KEY - https://${args[1]}:1500/ispmgr?func=auth&username=root&key=$ispkey&checkcookie=no\nISP Manager WEB GO - https://ssh.hoztnode.net/?sshport=22&url=${args[1]}:1500/ispmgr \n";
			fi
			
			echo

			printf "\n${G_C}${args[0]} -> ${args[1]} was changed${N_C}\n";
			if [[ $GATEWAY_CHANGED == "YES" ]]
			then 
				printf "${G_C}Gateway IP ${args[2]} -> ${args[3]} was changed${N_C}\n"
				printf "\n${Y_C}You should check subnet mask correctness ${N_C}\n"
			fi


			printf "${Y_C}Reboot this system (init 6) manually to apply changes${N_C}\n"

			unset GATEWAY_CHANGED
		else
			printf "\n${G_C}Nothing was done. Come back, bro !${N_C}\n";
			exit 1
	fi	
}

printf "${Y_C}This will change${RR_C} ${args[0]}${N_C} with${GG_C} ${args[1]}${N_C}${N_C}"
if [[ ! -z "${3}" ]]; then GATEWAY_CHANGE=YES; printf " and ${RR_C}${args[2]}${N_C} with${GG_C} ${args[3]}${N_C}${N_C}"; fi
printf " systemwide.\n"

read -p "Proceed ? [Y/n]" -n 1 -r

echo

if ! [[ $REPLY =~ ^[Nn]$ ]]
then
	printf "Let\'s do this ma brave ${PP_C}g${N_C}${R_C}a${N_C}${OO_C}n${N_C}${YY_C}g${N_C}${G_C}s${N_C}${BB_C}t${N_C}${PPP_C}a${N_C}\nWait a bit\n"

	# check ISP4 panel
	if [[ -f "/usr/local/ispmgr/bin/ispmgr" ]]
	then 
		printf "${R_C}ISP 4 panel detected.${N_C}"
		ISP5_RTG=0
		sleep 2s
		proceed_without_isp
	fi
	
	# vars
	if [[ -f "/usr/local/mgr5/sbin/mgrctl" ]]
	then
	        ISP5_PANEL_FILE="/usr/local/mgr5/sbin/mgrctl";
		ISP5_LITE_ELID=$(/usr/local/mgr5/sbin/mgrctl -m ispmgr license.info | sed -n -e "s@^.*licid=@@p");
	        ISP5_LITE_LIC=$(/usr/local/mgr5/sbin/mgrctl -m ispmgr license.info | sed -n -e "s@^.*panel_name=@@p");
	fi
	
	mkdir -p /root/support/$TSTAMP
	
	if [ -f "$ISP5_PANEL_FILE" ]
	then 
		shopt -s nocasematch
		case "$ISP5_LITE_LIC" in
			*busines*)
				printf "\n${R_C}Business panel license detected${N_C}\n"; ISP5_RTG=0; sleep 2s; proceed_without_isp;;
			*lite*|*pro*|*host*|*trial*)
				printf "\n${G_C}Lite or trial panel license detected${N_C}\n"; ISP5_RTG=1; sleep 2s;

				ISP5_LITE_MAIN_DB_FILE="/usr/local/mgr5/etc/ispmgr.db";

				#isp manager in sqlite
				if [[ -f "$ISP5_LITE_MAIN_DB_FILE" ]]
				then
	
					\cp -f $ISP5_LITE_MAIN_DB_FILE $ISP5_LITE_MAIN_DB_FILE.$TSTAMP;
					\cp -f $ISP5_LITE_MAIN_DB_FILE /root/support/$TSTAMP/
					printf "\n${G_C}DB backup file - $ISP5_LITE_MAIN_DB_FILE.$TSTAMP (and also in /root/support/$TSTAMP/)${N_C}\n";

					printf "\n${G_C}Updating db file (changing ${args[0]} with ${args[1]})${N_C}\n";
		
					if ! which sqlite3; then apt update; apt -y install sqlite3 || yum -y install sqlite3; fi > /dev/null 2>&1
	
					sqlite3 $ISP5_LITE_MAIN_DB_FILE "update webdomain_ipaddr set value='${args[1]}' where value='${args[0]}';";
					sqlite3 $ISP5_LITE_MAIN_DB_FILE "update emaildomain set ip='${args[1]}' where ip='${args[0]}';";
					sqlite3 $ISP5_LITE_MAIN_DB_FILE "update domain_auto set name=replace(name, '${args[0]}', '${args[1]}') where name like '%${args[0]}%';";
					sqlite3 $ISP5_LITE_MAIN_DB_FILE "update global_index set field_value='${args[1]}' where field_value='${args[0]}';";

					printf "\n${G_C}Update completed${N_C}\n";
	
					isp_pdns_ipchanger
					proceed_with_isp
					proceed_without_isp
				fi
					
				#isp manager in mysql
				if mysql -D ispmgr -e "select * from webdomain_ipaddr;" >/dev/null 2>/dev/null
				then

					mysqldump --insert-ignore --complete-insert --events --routines --triggers --single-transaction --max_allowed_packet=1G --quick --lock-tables=false ispmgr > /root/support/$TSTAMP/ispmgr.sql
					if [[ $? -eq 0 ]]
					then
						printf "\n${G_C}DB backup file - /root/support/$TSTAMP/ispmgr.sql${N_C}\n";
					else
						printf "\n${R_C}MySQL DB ispmgr backup failed.{N_C}\n";
					fi
						printf "\n${G_C}Updating MySQL DB (changing ${args[0]} with ${args[1]})${N_C}\n";

						mysql -D ispmgr -e "update webdomain_ipaddr set value='${args[1]}' where value='${args[0]}';";
						mysql -D ispmgr -e "update emaildomain set ip='${args[1]}' where ip='${args[0]}';";
						mysql -D ispmgr -e "update domain_auto set name=replace(name, '${args[0]}', '${args[1]}') where name like '%${args[0]}%';";
						mysql -D ispmgr -e "update global_index set field_value='${args[1]}' where field_value='${args[0]}';";
						
						printf "\n${G_C}Update completed${N_C}\n";

						isp_pdns_ipchanger
						proceed_with_isp
						proceed_without_isp
				
				fi

	                                ;;	
	                        *)
	                                printf "\n${R_C}Unknown panel license version detected: $ISP5_LITE_LIC${N_C}\n"; ISP5_RTG=0; sleep 5s; proceed_without_isp ;;
		esac;
	
		else 
			printf "${YY_C}No ISP5 panel detected${N_C}\n"
			proceed_without_isp
	        fi;
			
else
	printf "\n${G_C}Nothing was done. Come back, bro !${N_C}\n"
	exit 0
fi