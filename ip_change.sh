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

if [[ -z "${1}" ]]; then printf "$R_COld ip not set up$N_C\n  Usage $SELF_NAME old_ip new_ip\n"; exit 1; fi;
if [[ -z "${2}" ]]; then printf "$G_CNew ip not set up$N_C\n  Usage $SELF_NAME old_ip new_ip\n"; exit 1; fi;


proceed_without_isp() {
read -p "Continiue IP change [Y/n]" -n 1 -r
echo
	if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]
		then
			printf "\n$G_CBacking up current network settings to /root/support/$TSTAMP$N_C\n";
			\cp -Rf /etc/network* /root/support/$TSTAMP/; &> /dev/null
			\cp -Rf /etc/sysconfig/network* /root/support/$TSTAMP/; &> /dev/null

			printf "\n$G_CCurrent network settings:$N_C\n\n";
			echo "$(ip a)"; echo; echo "$(ip r)";

			printf "\n$G_CStarting ip change systemwide$N_C\n";
			grep --no-messages --devices=skip -RIil --exclude={*.log,*.log.*,*.run,*random*} ${args[0]} /var/named* | xargs sed -i "s@${args[0]}@${args[1]}@gi" &> /dev/null
			grep --no-messages --devices=skip -RIil --exclude={*.log,*.log.*,*.run,*random*} ${args[0]} /var/lib/powerdns* | xargs sed -i "s@${args[0]}@${args[1]}@gi" &> /dev/null
			grep --no-messages --devices=skip -RIil --exclude={*.log,*.log.*,*.run,*random*} ${args[0]} /etc* | xargs sed -i "s@${args[0]}@${args[1]}@gi" &> /dev/null
			grep --no-messages --devices=skip -RIil --exclude={*.log,*.log.*,*.run,*random*} ${args[0]} /home* | xargs sed -i "s@${args[0]}@${args[1]}@gi" &> /dev/null

			printf "\n$G_C${args[0]} -> ${args[1]} changed.$N_C\n";

			if [ "$ISP5_RTG" = "1" ]; then 
				printf "\n$R_CUpdate ISP license, RUN manually: curl -X POST -F \"func=soft.edit\" -F \"elid=$ISP5_LITE_ELID\" -F \"out=text\" -F \"ip=${args[1]}\" -F \"sok=ok\" -ks \"https://api.ispmanager.com/billmgr\" -F \"authinfo=support@provider:password\" $N_C\n";
				printf "\n$G_CISP Manager - https://ssh.hoztnode.net/?url=${args[1]}:1500/ispmgr $N_C\n";
			fi;
			
			echo
			printf "If default gateway need to be changed do it manually."
		else
			printf "\n$G_CNothing is done. Come back, bro !$N_C\n";
			exit 1
	fi	
}

read -p "This will change $R_C${args[0]}$N_C with $G_C${args[1]}$N_C systemwide. Proceed ? [Y/n]" -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]
	then

	        # check ISP4 panel
	        if [[ -f "/usr/local/ispmgr/bin/ispmgr" ]]; then printf "$R_CISP 4 panel detected.$N_C"; ISP5_RTG=0; sleep 2s; proceed_without_isp; fi;
	
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
	                                printf "\n$R_CBusiness panel license detected.$N_C\n"; ISP5_RTG=0; sleep 2s; proceed_without_isp;;
	                        *lite*|*pro*|*host*)
	                                printf "\n$G_CLite panel license detected.\n  Backing up db file$N_C\n"; ISP5_RTG=1; sleep 2s;
	
	                                ISP5_LITE_MAIN_DB_FILE="/usr/local/mgr5/etc/ispmgr.db";
	
	                                \cp -f $ISP5_LITE_MAIN_DB_FILE $ISP5_LITE_MAIN_DB_FILE.$TSTAMP;
	                                \cp -f $ISP5_LITE_MAIN_DB_FILE /root/support/$TSTAMP/
	                                printf "\n$G_CBackup file - $ISP5_LITE_MAIN_DB_FILE.$TSTAMP (and also in /root/support/$TSTAMP/)$N_C\n";
	
	                                printf "\n$G_CSetting ihttpd listen all ips$N_C\n\n";
	                                $ISP5_PANEL_FILE -m core ihttpd.edit ip=any elid=${args[0]} sok=ok
	
	                                printf "\n$G_CAdding new ip - ${args[1]}$N_C\n\n";
	                                $ISP5_PANEL_FILE -m ispmgr ipaddrlist.edit name=${args[1]} sok=ok;
	
	                                printf "\n$G_CUpdating db file (changing ${args[0]} with ${args[1]})$N_C\n";
	
	                                if ! sqlite3 -v; then apt update; apt -y install sqlite || yum -y install sqlite; fi > /dev/null 2>&1

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
	                                printf "\n$R_CUnknown panel license version detected: $ISP5_LITE_LIC$N_C\n"; ISP5_RTG=0; sleep 5s; proceed_without_isp ;;
	                esac;
	
	        else 
			printf "$R_CNo ISP5 panel detected.$N_C"
			proceed_without_isp
	        fi;
		
		else 
			clear; 
			printf "\n$G_CNothing is done. Come back, bro !$N_C\n";
			exit 0;
	fi;

