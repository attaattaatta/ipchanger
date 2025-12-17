#!/bin/bash

# $1 - old ip
# $2 - new ip

export PATH=$PATH:/usr/sbin:/usr/local/sbin

# Colors
R_C="\033[0;91m"
G_C="\033[0;92m"
N_C="\033[0m"
Y_C="\033[1;33m"
PP_C="\033[1;35m"
OO_C="\033[38;5;214m"
BB_C="\033[1;34m"

# Script version
self_current_version="1.0.21"
printf "\n${Y_C}Hello${N_C}, my version is ${Y_C}$self_current_version\n\n${N_C}"

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
    printf "\n${R_C}ERROR - This script must be run as root.${N_C}\n"
    exit 1
fi

# one instance run lock
LOCKFILE=/tmp/bash_ip_changer.lock
exec 9>"$LOCKFILE"

if ! flock -n 9; then
    PID=""
    if command -v lsof >/dev/null 2>&1; then
        PID=$(lsof -t "$LOCKFILE" 2>/dev/null | grep -v "^$$\$" | head -n1)
    elif command -v fuser >/dev/null 2>&1; then
        PID=$(fuser "$LOCKFILE" 2>/dev/null 2>/dev/null | tr ' ' '\n' | grep -v "^$$\$" | head -n1)
    fi
    
    if [ -n "$PID" ]; then
        printf "\n%s is ${LRV}already locked${NCV} by PID %s\n\n" "$LOCKFILE" "$PID"
    else
        printf "\n%s ${LRV}already exists${NCV}\nInstall 'lsof' or 'fuser' to see the PID.\n\n" "$LOCKFILE"
    fi
    
    exit 1
fi

trap 'exec 9>&-; rm -f "$LOCKFILE"' EXIT

args=("$@")

# isp vars
MGR_PATH="/usr/local/mgr5"
MGRBIN="$MGR_PATH/sbin/mgrctl"
MGRCTL="$MGR_PATH/sbin/mgrctl -m ispmgr"
MGR_MAIN_CONF_FILE="$MGR_PATH/etc/ispmgr.conf"

# other vars
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
SELF_NAME=$(basename "$0")
TSTAMP=$(date +%d-%m-%Y-%H-%M-%Z)

USAGE_INFO=$(echo; printf "Use 2 or 4 arguments."; echo; printf "Usage: $SCRIPT_DIR/$SELF_NAME old_ip new_ip <old_gateway> <new_gateway>")

# Check arguments
if [[ "$#" -lt 2 ]] || [[ "$#" -eq 3 ]]; then
    printf "\n${R_C}Not enough args${N_C}\n"
    echo "${USAGE_INFO}"
    exit 1
fi

# IP validation
validate_ip() {
    valid_ip_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    IFS='.' read -r i1 i2 i3 i4 <<< "$arg"

    if [[ ! $arg =~ $valid_ip_regex ]] || (( i1 > 255 || i2 > 255 || i3 > 255 || i4 > 255 )); then
        printf "\n${Y_C}WARNING ${arg} does not look like an valid IPv4 address. ${N_C}\n"
        read -p "Proceed anyway ? [y/N]" -n 1 -r
        echo

        if ! [[ $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

}

for arg in "$@"; do
    validate_ip "$arg"
done

# Update PowerDNS MySQL DB
isp_pdns_ipchanger() {
    if [[ -f "/usr/sbin/pdns_server" ]]; then
        printf "\n${G_C}Updating MySQL PowerDNS DB pdns ${N_C}"
        mysql -D pdns -e "update records set content=replace(content,'${args[0]}', '${args[1]}');" >/dev/null 2>/dev/null
        mysql -D powerdns -e "update records set content=replace(content,'${args[0]}', '${args[1]}');" >/dev/null 2>/dev/null
        printf " - ${G_C}OK${N_C}\n"
    fi
}

# ISP Manager changes
proceed_with_isp() {
    printf "\n${G_C}Setting ihttpd listen all ips${N_C}\n"
    $ISP5_PANEL_FILE -m core ihttpd.edit ip=any elid=${args[0]} sok=ok >/dev/null 2>/dev/null

    printf "\n${G_C}Cleaning ISP Manager cache${N_C}\n"
    rm -rf /usr/local/mgr5/var/.xmlcache/*
    rm -f /usr/local/mgr5/etc/ispmgr.lic /usr/local/mgr5/etc/ispmgr.lic.lock /usr/local/mgr5/var/.db.cache.*

    printf "\n${G_C}Restarting ISP Manager${N_C}\n\n"
    $ISP5_PANEL_FILE -m ispmgr -R
    sleep 5s
}

# Proceed without ISP Manager
proceed_without_isp() {
    read -p "Continue IP change [Y/n]" -n 1 -r
    echo
    if ! [[ $REPLY =~ ^[Nn]$ ]]; then
        printf "\n${G_C}Backing up current network settings to /root/support/$TSTAMP${N_C}\n"

        NETWORK_BACKUP_PATH_LIST=("/etc/network*" "/etc/sysconfig/network*" "/etc/NetworkManager*" "/etc/netplan*")

        for network_backup_item in "${NETWORK_BACKUP_PATH_LIST[@]}"; do
            cp -Rf ${network_backup_item} /root/support/$TSTAMP/ >/dev/null 2>/dev/null
        done

        printf "\n${G_C}Current network settings:${N_C}\n\n"
        ip a
        echo
        ip r

        printf "\n${G_C}Starting IP change systemwide${N_C}\n"

        # Network manager check
        if which nmcli &> /dev/null && [[ ! -z "$(ls -A '/etc/NetworkManager/system-connections/')" ]]; then
            printf "\n${G_C}NetworkManager detected${N_C}\nConfiguration in /etc/NetworkManager/system-connections/\n"
        fi

        # Netplan check
        if which netplan &> /dev/null && [[ ! -z "$(ls -A '/etc/netplan/')" ]]; then
            printf "\n${G_C}Netplan detected${N_C}\nConfiguration in /etc/netplan/\n"
        fi

        IP_CHANGE_PATH_LIST=("/etc/*" "/var/named/*" "/var/lib/powerdns/*" "/usr/local/mgr5/etc/ihttpd.conf")

        for ip_change_list_item in "${IP_CHANGE_PATH_LIST[@]}"; do
            echo "Processing ${ip_change_list_item}"
            {
            grep --no-messages --devices=skip -rIil --exclude={*.log,*.log.*,*.run,*random*,*.jpg,*.jpeg,*.webp} ${args[0]} ${ip_change_list_item} | xargs sed -i "s@${args[0]}@${args[1]}@gi" 
            find ${ip_change_list_item} -depth -iname "*${args[0]}*" -exec bash -c 'mv "$0" "${0//'"${args[0]}"'/'"${args[1]}"'}"' {} \;
            } &> /dev/null
        done

	echo
	echo "Processing Docker"
	{
		systemctl stop docker
		sed -i "s@${args[0]}@${args[1]}@gi" /var/lib/docker/containers/*/hostconfig.json
		systemctl start docker
	} &> /dev/null

        echo
        read -p "Going through /home/* and /opt/* /usr/local/fastpanel2/* ? (for ex. VESTA panel, Bitrix, etc. It could take a very loooooooong time) [y/N]" -n 1 -r

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo
            echo "Processing /home/* /opt/* /usr/local/fastpanel2/*"
            {
            grep --no-messages --devices=skip -rIil --exclude={*.log,*.log.*,*.run,*random*,*.jpg,*.jpeg,*.webp} ${args[0]} /home/* | xargs sed -i "s@${args[0]}@${args[1]}@gi"
            grep --no-messages --devices=skip -rIil --exclude={*.log,*.log.*,*.run,*random*,*.jpg,*.jpeg,*.webp} ${args[0]} /opt/* | xargs sed -i "s@${args[0]}@${args[1]}@gi"
            grep --no-messages --devices=skip -rIil --exclude={*.log,*.log.*,*.run,*random*,*.jpg,*.jpeg,*.webp} ${args[0]} /usr/local/fastpanel2/* | xargs sed -i "s@${args[0]}@${args[1]}@gi"
            find /home/* /opt/* /usr/local/fastpanel2/* -depth -iname "*${args[0]}*" -exec bash -c 'mv "$0" "${0//'"${args[0]}"'/'"${args[1]}"'}"' {} \; 
            } &> /dev/null
        fi

        # If gateway change is needed
        if [[ $GATEWAY_CHANGE == "YES" ]]; then
            printf "\n${G_C}Changing gateway address${N_C}\n"

            GATEWAY_CONFIG_PATH_LIST=("/etc/NetworkManager/system-connections/*" "/etc/netplan/*" "/etc/network/interfaces" "/etc/network/interfaces.d/*" "/etc/sysconfig/network*")

            for gateway_config_item in "${GATEWAY_CONFIG_PATH_LIST[@]}"; do
                echo "Processing ${gateway_config_item}"
                grep --no-messages --devices=skip -rIil --exclude={*.log,*.log.*,*.run,*random*,*.jpg,*.jpeg,*.webp} ${args[2]} ${gateway_config_item} | xargs sed -i "s@${args[2]}@${args[3]}@gi" &> /dev/null
            done

            GATEWAY_CHANGED=YES
            unset GATEWAY_CHANGE
        else
            printf "\n${Y_C}3 and 4 script's arguments were empty ${N_C}\n"
            printf "If default gateway IP address / subnet mask need to be changed, do it manually\n"
        fi

        if [ "$ISP5_RTG" = "1" ]; then
            printf "\n${Y_C}To update ISP Manager license, run:${N_C}\ncurl -X POST -F \"func=soft.edit\" -F \"elid=$ISP5_LITE_ELID\" -F \"out=text\" -F \"ip=${args[1]}\" -F \"sok=ok\" -ks \"https://api.ispmanager.com/billmgr\" -F \"authinfo=support@provider:password\"\n"

            # ISP Manager root access key generation and print

            ispkey="$RANDOM$RANDOM$RANDOM$RANDOM$RANDOM$RANDOM$RANDOM"
            if timeout 3 $MGRBIN -m ispmgr session.newkey username=root key=$ispkey > /dev/null 2>&1; then

                ihttpd_conf="/usr/local/mgr5/etc/ihttpd.conf"
                ihttpd_ip=$(grep -v '^#' $ihttpd_conf 2>/dev/null  | grep ip | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}')
                ihttpd_port=$(grep -v '^#' $ihttpd_conf 2>/dev/null | grep port | grep -oE [[:digit:]]+)
                ispgenurlp1="ISP Manager KEY - https://"
                ispgenurlp2="/ispmgr?func=auth&username=root&key=$ispkey&checkcookie=no"

                printf "\n${Y_C}Generating ISP Manager root session key${N_C} "

                if [[ -z $ihttpd_port ]]; then
                    ihttpd_port="1500"
                fi

                if [[ -z $ihttpd_ip ]]; then
                    ihttpd_ip="${args[1]}"
                fi

                printf "\n${ispgenurlp1}${ihttpd_ip}:${ihttpd_port}${ispgenurlp2}\n"
            fi
        fi

        echo

        printf "${Y_C}${args[0]} -> ${args[1]} was changed${N_C}\n"
        if [[ $GATEWAY_CHANGED == "YES" ]]; then
            printf "${G_C}Gateway IP ${args[2]} -> ${args[3]} was changed${N_C}\n"
            printf "\n${Y_C}You should check subnet mask correctness ${N_C}\n"
        fi

        printf "Adjust the network mask if necessary and reboot this system (${Y_C}run init 6${N_C}) manually to apply all changes\n"

        unset GATEWAY_CHANGED
    else
        printf "\n${G_C}Nothing was done. Come back, bro!${N_C}\n"
        exit 1
    fi
}

printf "${Y_C}This will change${R_C} ${args[0]}${N_C} with${G_C} ${args[1]}${N_C}"
if [[ ! -z "${3}" ]]; then GATEWAY_CHANGE=YES; printf " and ${R_C}${args[2]}${N_C} with${G_C} ${args[3]}${N_C}"; fi
printf " systemwide.\n"

read -p "Proceed? [Y/n]" -n 1 -r

echo

if ! [[ $REPLY =~ ^[Nn]$ ]]; then
    printf "Let's do this my brave ${PP_C}g${N_C}${R_C}a${N_C}${OO_C}n${N_C}${Y_C}g${N_C}${G_C}s${N_C}${BB_C}t${N_C}${PP_C}a${N_C}\nWait a bit\n"

    # Check ISP4 panel
    if [[ -f "/usr/local/ispmgr/bin/ispmgr" ]]; then
        printf "${R_C}ISP 4 panel detected.${N_C}"
        ISP5_RTG=0
        sleep 2s
        proceed_without_isp
    fi

    # Variables
    if [[ -f "$MGRBIN" ]]; then
        ISP5_PANEL_FILE="$MGRBIN"
        ISP5_LITE_ELID=$($MGRCTL license.info | sed -n -e "s@^.*licid=@@p")
        ISP5_LITE_LIC=$($MGRCTL license.info | sed -n -e "s@^.*panel_name=@@p")
    fi

    mkdir -p /root/support/$TSTAMP

    if [ -f "$ISP5_PANEL_FILE" ]; then
        shopt -s nocasematch

        # processing ISP Manager disabled sites
        grep --no-messages --devices=skip -rIil --exclude={*.log,*.log.*,*.run,*random*,*.jpg,*.jpeg,*.webp} ${args[0]} ${MGR_PATH}/var/usrtmp/ispmgr/* | xargs sed -i "s@${args[0]}@${args[1]}@gi" >/dev/null 2>/dev/null

        case "$ISP5_LITE_LIC" in
            *busines*)
                printf "\n${R_C}Business panel license detected${N_C}\n"
                ISP5_RTG=0
                sleep 2s
                proceed_without_isp
                ;;
            *lite*|*pro*|*host*|*trial*)
                printf "\n${G_C}Lite or trial panel license detected${N_C}\n"
                ISP5_RTG=1
                sleep 2s

                ISP5_LITE_MAIN_DB_FILE="/usr/local/mgr5/etc/ispmgr.db"

                # ISP Manager in SQLite
                if [[ -f "$ISP5_LITE_MAIN_DB_FILE" ]]; then
                    cp -f $ISP5_LITE_MAIN_DB_FILE $ISP5_LITE_MAIN_DB_FILE.$TSTAMP
                    cp -f $ISP5_LITE_MAIN_DB_FILE /root/support/$TSTAMP/
                    printf "\n${G_C}DB backup file - $ISP5_LITE_MAIN_DB_FILE.$TSTAMP (and also in /root/support/$TSTAMP/)${N_C}\n"

                    printf "\n${G_C}Updating db file (changing ${args[0]} with ${args[1]})${N_C}\n"

                    if ! which sqlite3; then apt update; apt -y install sqlite3 || yum -y install sqlite3; fi > /dev/null 2>&1

                    sqlite3 $ISP5_LITE_MAIN_DB_FILE "update webdomain_ipaddr set value='${args[1]}' where value='${args[0]}';"
                    sqlite3 $ISP5_LITE_MAIN_DB_FILE "update emaildomain set ip='${args[1]}' where ip='${args[0]}';"
                    sqlite3 $ISP5_LITE_MAIN_DB_FILE "update domain_auto set name=replace(name, '${args[0]}', '${args[1]}') where name like '%${args[0]}%';"
                    sqlite3 $ISP5_LITE_MAIN_DB_FILE "update global_index set field_value='${args[1]}' where field_value='${args[0]}';"
                    sqlite3 $ISP5_LITE_MAIN_DB_FILE "update db_server set host = '${args[1]}' || substr(host, instr(host, ':')) where host like '${args[0]}:%';"
                    sqlite3 $ISP5_LITE_MAIN_DB_FILE "update db_mysql_servers set hostname = '${args[1]}' where hostname = '${args[0]}';"
                    sqlite3 $ISP5_LITE_MAIN_DB_FILE "delete from ipaddr where name='${args[0]}';"

                    printf "\n${G_C}Update completed${N_C}\n"

                    isp_pdns_ipchanger
                    proceed_with_isp
                    proceed_without_isp
                fi

                # ISP Manager in MySQL
                if mysql -D ispmgr -e "select * from webdomain_ipaddr;" >/dev/null 2>/dev/null; then
                    mysqldump --insert-ignore --complete-insert --events --routines --triggers --single-transaction --max_allowed_packet=1G --quick --lock-tables=false ispmgr > /root/support/$TSTAMP/ispmgr.sql
                    if [[ $? -eq 0 ]]; then
                        printf "\n${G_C}DB backup file - /root/support/$TSTAMP/ispmgr.sql${N_C}\n"
                    else
                        printf "\n${R_C}MySQL DB ispmgr backup failed.${N_C}\n"
                    fi
                    printf "\n${G_C}Updating MySQL DB (changing ${args[0]} with ${args[1]})${N_C}\n"

                    mysql -D ispmgr -e "update webdomain_ipaddr set value='${args[1]}' where value='${args[0]}';"
                    mysql -D ispmgr -e "update emaildomain set ip='${args[1]}' where ip='${args[0]}';"
                    mysql -D ispmgr -e "update domain_auto set name=replace(name, '${args[0]}', '${args[1]}') where name like '%${args[0]}%';"
                    mysql -D ispmgr -e "update global_index set field_value='${args[1]}' where field_value='${args[0]}';"
                    mysql -D ispmgr -e "update db_server set host = concat('${args[1]}', substring(host, locate(':', host))) where host like '${args[0]}:%';"
                    mysql -D ispmgr -e "update db_mysql_servers set hostname = '${args[1]}' where hostname = '${args[0]}';"
                    mysql -D ispmgr -e "delete from ipaddr where name='${args[0]}';"

                    printf "\n${G_C}Update completed${N_C}\n"

                    isp_pdns_ipchanger
                    proceed_with_isp
                    proceed_without_isp
                fi
                ;;
            *)
                printf "\n${R_C}Unknown panel license version detected: $ISP5_LITE_LIC${N_C}\n"
                ISP5_RTG=0
                sleep 5s
                proceed_without_isp
                ;;
        esac
    else
        printf "${Y_C}No ISP5 panel detected${N_C}\n"
        proceed_without_isp
    fi
else
    printf "\n${G_C}Nothing was done. Come back, bro!${N_C}\n"
    exit 0
fi