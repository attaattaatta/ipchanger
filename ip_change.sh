#!/bin/bash

# $1 - old ip
# $2 - new ip

export PATH=$PATH:/usr/sbin:/usr/sbin:/usr/local/sbin;

# colors
R_C="\033[0;91m";
G_C="\033[0;92m";
N_C="\033[0m";

args=("$@")

SELF_NAME=$(basename "$0");

if [[ -z "${1}" ]]; then printf "${R_C}Old ip not set up${N_C}\n  Usage $SELF_NAME old_ip new_ip\n"; exit 1; fi;
if [[ -z "${2}" ]]; then printf "${G_C}New ip not set up${N_C}\n  Usage $SELF_NAME old_ip new_ip\n"; exit 1; fi;


proceed_without_isp() {
read -p "Continiue IP change [Y/n]" -n 1 -r
echo
	if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]
		then
			printf "\n${G_C}Backing up current network settings to /root/support/$TSTAMP${N_C}\n";
			\cp -Rf /etc/network* /root/support/$TSTAMP/; &> /dev/null
			\cp -Rf /etc/sysconfig/network* /root/support/$TSTAMP/; &> /dev/null

			printf "\n${G_C}Current network settings:${N_C}\n\n";
			echo "$(ip a)"; echo; echo "$(ip r)";

			printf "\n${G_C}Starting ip change systemwide${N_C}\n";
			grep --no-messages --devices=skip -RIil --exclude={*.log,*.log.*,*.run,*random*,*.jpg,*.webp} ${args[0]} /var/named* | xargs sed -i "s@${args[0]}@${args[1]}@gi" &> /dev/null
			grep --no-messages --devices=skip -RIil --exclude={*.log,*.log.*,*.run,*random*,*.jpg,*.webp} ${args[0]} /var/lib/powerdns* | xargs sed -i "s@${args[0]}@${args[1]}@gi" &> /dev/null
			grep --no-messages --devices=skip -RIil --exclude={*.log,*.log.*,*.run,*random*,*.jpg,*.webp} ${args[0]} /etc* | xargs sed -i "s@${args[0]}@${args[1]}@gi" &> /dev/null
			grep --no-messages --devices=skip -RIil --exclude={*.log,*.log.*,*.run,*random*,*.jpg,*.webp} ${args[0]} /home* | xargs sed -i "s@${args[0]}@${args[1]}@gi" &> /dev/null

			printf "\n${G_C}${args[0]} -> ${args[1]} changed.${N_C}\n";

			if [ "$ISP5_RTG" = "1" ]; then 
				printf "\n${R_C}Update ISP license, RUN manually: curl -X POST -F \"func=soft.edit\" -F \"elid=$ISP5_LITE_ELID\" -F \"out=text\" -F \"ip=${args[1]}\" -F \"sok=ok\" -ks \"https://api.ispmanager.com/billmgr\" -F \"authinfo=support@provider:password\" ${N_C}\n";
				printf "\n${G_C}ISP Manager - https://ssh.hoztnode.net/?url=${args[1]}:1500/ispmgr ${N_C}\n";
			fi;
			
			echo
			printf "If default gateway IP address / subnet mask need to be changed, do it manually.\n"
		else
			printf "\n${G_C}Nothing is done. Come back, bro !${N_C}\n";
			exit 1
	fi	
}

RR_C=$'\e[0;91m'
GG_C=$'\e[0;92m'
PP_C="\033[1;35m"
OO_C="\033[38;5;214m";
YY_C="\033[1;33m"
GGG_C="\033[0;32m"
BB_C="\033[1;34m"
PPP_C="\033[0;35m"
NN_C=$'\033[0m'

read -p "This will change${RR_C} ${args[0]}${NN_C} with${GG_C} ${args[1]}${NN_C} systemwide. Proceed ? [Y/n]" -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]
	then
		printf "Let\'s do this ma brave ${PP_C}g${N_C}${R_C}a${N_C}${OO_C}n${N_C}${YY_C}g${N_C}${G_C}s${N_C}${BB_C}t${N_C}${PPP_C}a${N_C}\nWait a bit\n"

	        # check ISP4 panel
	        if [[ -f "/usr/local/ispmgr/bin/ispmgr" ]]; then printf "${R_C}ISP 4 panel detected.${N_C}"; ISP5_RTG=0; sleep 2s; proceed_without_isp; fi;
	
	        # vars
		if [[ -f "/usr/local/mgr5/sbin/mgrctl" ]]
		then
	        ISP5_PANEL_FILE="/usr/local/mgr5/sbin/mgrctl";
		ISP5_LITE_ELID=$(/usr/local/mgr5/sbin/mgrctl -m ispmgr license.info | sed -n -e "s@^.*licid=@@p");
	        ISP5_LITE_LIC=$(/usr/local/mgr5/sbin/mgrctl -m ispmgr license.info | sed -n -e "s@^.*panel_name=@@p");
		fi
	        TSTAMP=$(echo "$(date +%d-%m-%Y-%H-%M-%Z)")
	
	        mkdir -p /root/support/$TSTAMP
	
	        if [ -f "$ISP5_PANEL_FILE" ]; then shopt -s nocasematch;
	                case "$ISP5_LITE_LIC" in
	                        *busines*)
	                                printf "\n${R_C}Business panel license detected.${N_C}\n"; ISP5_RTG=0; sleep 2s; proceed_without_isp;;
	                        *lite*|*pro*|*host*)
	                                printf "\n${G_C}Lite panel license detected.\n\nBacking up db file${N_C}\n"; ISP5_RTG=1; sleep 2s;
	
	                                ISP5_LITE_MAIN_DB_FILE="/usr/local/mgr5/etc/ispmgr.db";
	
	                                \cp -f $ISP5_LITE_MAIN_DB_FILE $ISP5_LITE_MAIN_DB_FILE.$TSTAMP;
	                                \cp -f $ISP5_LITE_MAIN_DB_FILE /root/support/$TSTAMP/
	                                printf "\n${G_C}Backup file - $ISP5_LITE_MAIN_DB_FILE.$TSTAMP (and also in /root/support/$TSTAMP/)${N_C}\n";
	
	                                printf "\n${G_C}Setting ihttpd listen all ips${N_C}\n\n";
	                                $ISP5_PANEL_FILE -m core ihttpd.edit ip=any elid=${args[0]} sok=ok
	
	                                printf "\n${G_C}Adding new ip - ${args[1]}${N_C}\n\n";
	                                $ISP5_PANEL_FILE -m ispmgr ipaddrlist.edit name=${args[1]} sok=ok;
	
	                                printf "\n${G_C}Updating db file (changing ${args[0]} with ${args[1]})${N_C}\n";
	
	                                if ! sqlite3 -v; then apt update; apt -y install sqlite3 || yum -y install sqlite3; fi > /dev/null 2>&1

	                                sqlite3 $ISP5_LITE_MAIN_DB_FILE "update webdomain_ipaddr set value='${args[1]}' where value='${args[0]}';";
	                                sqlite3 $ISP5_LITE_MAIN_DB_FILE "update emaildomain set ip='${args[1]}' where ip='${args[0]}';";
	                                sqlite3 $ISP5_LITE_MAIN_DB_FILE "update domain_auto set name=replace(name, '${args[0]}', '${args[1]}') where name like '%${args[0]}%';";
	                                sqlite3 $ISP5_LITE_MAIN_DB_FILE "update global_index set field_value='${args[1]}' where field_value='${args[0]}';";
	
					\rm -rf /usr/local/mgr5/var/.xmlcache/*;
					\rm -f /usr/local/mgr5/etc/ispmgr.lic /usr/local/mgr5/etc/ispmgr.lic.lock /usr/local/mgr5/var/.db.cache.*;
	
#                           		$ISP5_PANEL_FILE -m ispmgr ipaddrlist.delete elid=${args[0]} sok=ok;
	                                $ISP5_PANEL_FILE -m ispmgr -R
					sleep 5s
					proceed_without_isp
	                                ;;	
	                        *)
	                                printf "\n${R_C}Unknown panel license version detected: $ISP5_LITE_LIC${N_C}\n"; ISP5_RTG=0; sleep 5s; proceed_without_isp ;;
	                esac;
	
	        else 
			printf "${R_C}No ISP5 panel detected.${N_C}\n"
			proceed_without_isp
	        fi;
		
		else 
			clear; 
			printf "\n${G_C}Nothing is done. Come back, bro !${N_C}\n";
			exit 0;
	fi;

