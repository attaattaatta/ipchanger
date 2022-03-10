#!/bin/bash

# $1 - old ip
# $2 - new ip

export PATH=$PATH:/usr/sbin:/usr/sbin:/usr/local/sbin;
clear;

# colors
R_C="\033[0;91m";
G_C="\033[0;92m";
N_C="\033[0m";

SELF_NAME=$(basename "$0");

if [[ -z "${1}" ]]; then printf "$R_C Old ip not set up$N_C\n  Usage $SELF_NAME old_ip new_ip\n"; exit 1; else printf "$R_C Old ip - $1$N_C\n"; fi;
if [[ -z "${2}" ]]; then printf "$G_C New ip not set up$N_C\n  Usage $SELF_NAME old_ip new_ip\n"; exit 1; else printf "$G_C New ip - $2$N_C\n"; fi;

echo -n "  DO NOT delete $1 in Billing now ! Did you add $2 in the Billing ? [y/n] ";
read answer;
if [[ "$answer" != "${answer#[Yy]}" ]] ; then

        # check ISP4 panel
        if [[ -f "/usr/local/ispmgr/bin/ispmgr" ]]; then printf "$R_C ISP 4 panel detected. Use your hands. Aborting.$N_C"; ISP5_RTG=0; sleep 2s; exit 1; fi;

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
                                printf "\n$R_C Business panel license detected. Use your hands. Aborting.$N_C\n"; ISP5_RTG=0; sleep 2s; exit 1 ;;
                        *lite*|*pro*|*host*)
                                printf "\n$G_C Lite panel license detected.\n  Backing up db file$N_C\n"; ISP5_RTG=1; sleep 2s;

                                ISP5_LITE_MAIN_DB_FILE="/usr/local/mgr5/etc/ispmgr.db";

                                \cp -f $ISP5_LITE_MAIN_DB_FILE $ISP5_LITE_MAIN_DB_FILE.$TSTAMP;
                                \cp -f $ISP5_LITE_MAIN_DB_FILE /root/support/$TSTAMP/
                                printf "\n$G_C  Backup file - $ISP5_LITE_MAIN_DB_FILE.$TSTAMP (and also in /root/support/$TSTAMP/)$N_C\n";

                                printf "\n$G_C  Setting ihttpd listen all ips$N_C\n\n";
                                $ISP5_PANEL_FILE -m core ihttpd.edit ip=any elid=$1 sok=ok

                                printf "\n$G_C  Adding new ip - $2$N_C\n\n";
                                $ISP5_PANEL_FILE -m ispmgr ipaddrlist.edit name=$2 sok=ok;

                                printf "\n$G_C  Updating db file (changing $1 with $2)$N_C\n";

                                sqlite3_exist=$(if ! sqlite3 -v; then apt -y install sqlite || yum -y install sqlite; fi > /dev/null 2>&1);
                                sqlite3 $ISP5_LITE_MAIN_DB_FILE "update webdomain_ipaddr set value='$2' where value='$1';";
                                sqlite3 $ISP5_LITE_MAIN_DB_FILE "update emaildomain set ip='$2' where ip='$1';";
                                sqlite3 $ISP5_LITE_MAIN_DB_FILE "update domain_auto set name=replace(name, '$1', '$2') where name like '%$1%';";
                                sqlite3 $ISP5_LITE_MAIN_DB_FILE "update global_index set field_value='$2' where field_value='$1';";

				\rm -rf /usr/local/mgr5/var/.xmlcache/*;
				\rm -f /usr/local/mgr5/etc/ispmgr.lic /usr/local/mgr5/etc/ispmgr.lic.lock /usr/local/mgr5/var/.db.cache.*;

                                printf "\n$G_C  Update completed. Removing old ip - $1$N_C\n";
                                $ISP5_PANEL_FILE -m ispmgr ipaddrlist.delete elid=$1 sok=ok;
                                $ISP5_PANEL_FILE -m ispmgr exit
                                ;;	
                        *)
                                printf "\n$R_C  Unknown panel license detected. Version: $ISP5_LITE_LIC. Aborting.$N_C\n"; ISP5_RTG=0; sleep 5s; exit 1 ;;
                esac;

        else printf "$R_C  No ISP5 panel detected.$N_C";

        fi;

        printf "\n$G_C  Backing up current network settings to /root/support/$TSTAMP$N_C\n";
        \cp -Rf /etc/network* /root/support/$TSTAMP/;
	\cp -Rf /etc/sysconfig/network* /root/support/$TSTAMP/;

        printf "\n$G_C  Current network settings:$N_C\n\n";
        echo "$(ip a)"; echo; echo "$(ip r)";

        printf "\n$G_C  Starting ip change systemwide$N_C\n";
	grep --devices=skip -RIil --exclude={*.run*,*random*} $1 /var/named* | xargs sed -i "s@$1@$2@gi";
	grep --devices=skip -RIil --exclude={*.run*,*random*} $1 /var/lib/powerdns* | xargs sed -i "s@$1@$2@gi";
	grep --devices=skip -RIil --exclude={*.run*,*random*} $1 /etc* | xargs sed -i "s@$1@$2@gi";

	printf "\n$G_C  $1 -> $2 changed.$N_C\n";

	if [ "$ISP5_RTG" = "1" ]; then 
		printf "\n$R_C  Update ISP license, RUN manually: curl -X POST -F \"func=soft.edit\" -F \"elid=$ISP5_LITE_ELID\" -F \"out=text\" -F \"ip=$2\" -F \"sok=ok\" -ks \"https://my.ispsystem.com/billmgr\" -F \"authinfo=support@provider:password\" $N_C\n";
		printf "\n$G_C  ISP Manager - https://ssh.hoztnode.net/?url=$2:1500/ispmgr $N_C\n";
	fi;
	
	echo;
	echo -n "  Default gateway need to be changed ? [y/n] ";
	read answer;
	if [ "$answer" != "${answer#[Yy]}" ] ;then
		printf "\n$G_C  Ok. Change gateway manually and delete old ip $1 from Billing with reboot (do not check -billing only- checkbox). $N_C\n";
		printf "\n$G_C  Good luck, bro ! $N_C";
		exit 0;
	fi;
	printf "\n$R_C  Now delete old ip $1 from Billing with reboot (do not check -billing only- checkbox). $N_C";
	printf "\n$G_C  And don't forget to check DNS afterwards. $N_C";
	printf "\n$G_C  Good luck, bro ! $N_C";

else 
	clear; 
	printf "\n$G_C  Nothing is done. Come back, bro !$N_C\n";
	exit 0;
fi;