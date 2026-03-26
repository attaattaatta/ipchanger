#!/bin/bash

# $1 - old ip
# $2 - new ip

export PATH=$PATH:/usr/sbin:/usr/local/sbin

# Colors
RC="\033[0;91m"
GC="\033[0;92m"
NC="\033[0m"
YC="\033[1;33m"
PPC="\033[1;35m"
OOC="\033[38;5;214m"
BBC="\033[1;34m"

# Script version
self_current_version="1.0.25"
printf "\n${YC}Hello${NC}, my version is ${YC}$self_current_version\n\n${NC}"

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
    printf "\n${RC}ERROR:${NC} This script must be run as root\n"
    exit 1
fi

# one instance run lock
LOCKFILE=/root/bash_ip_changer.lock
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
MGR_MAINCONF_FILE="$MGR_PATH/etc/ispmgr.conf"
ISP5_LITE_MAIN_DB_FILE="/usr/local/mgr5/etc/ispmgr.db"
ISP_LIC_BAD="0"

# other vars
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
SELF_NAME=$(basename "$0")
TSTAMP=$(date +%d-%m-%Y-%H-%M-%Z)

USAGE_INFO=$(echo; printf "Use 2 or 4 arguments."; echo; printf "Usage: $SCRIPT_DIR/$SELF_NAME old_ip new_ip <old_gateway> <new_gateway>")

# Check arguments
if [[ "$#" -lt 2 ]] || [[ "$#" -eq 3 ]]; then
    printf "\n${RC}ERROR:${NC} Not enough args\n"
    echo "${USAGE_INFO}"
    exit 1
fi

# IP validation
validate_ip() {
    valid_ip_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    IFS='.' read -r i1 i2 i3 i4 <<< "$arg"

    if [[ ! $arg =~ $valid_ip_regex ]] || (( i1 > 255 || i2 > 255 || i3 > 255 || i4 > 255 )); then
        printf "\n${YC}WARNING:${NC} ${arg} does not look like an valid IPv4 address.\n"
        read -p "Proceed anyway ? [y/N]" -n 1 -r
        echo

        if ! [[ $REPLY =~ ^([Yy]|$'\xd0\xbd'|$'\xd0\x9d')$ ]]; then
            exit 1
        fi
    fi

}

for arg in "$@"; do
    validate_ip "$arg"
done

# Backup function
backup() {
	local BACKUP_ROOT_DIR="/root/support"
	local DIR_LIST=("/etc/" "/usr/local/mgr5/etc/" "/var/spool/cron/" "/var/named/" "/var/lib/powerdns/")

	BACKUP_DIR="${BACKUP_ROOT_DIR}/$(date '+%d-%b-%Y-%H-%M-%Z')"

	local ROOT_DF=$(df "$BACKUP_ROOT_DIR" | sed 1d | awk '{print $5}' | sed 's@%@@gi')
	local exec_command=""

	if [[ "$ROOT_DF" -le 95 ]]; then

		if \mkdir -p "$BACKUP_ROOT_DIR"; then

			\mkdir -p "$BACKUP_DIR" &> /dev/null
			for backup_item in "${DIR_LIST[@]}"
			do
				if [[ -d "$backup_item" ]]; then
					backup_item_size=$(\du -sm "${backup_item}" &>/dev/null | awk '{print $1}')

					if [[ "${backup_item_size}" -lt 2000 ]]; then
						printf "Processing ${GC}backup${NC} ${BACKUP_DIR}${backup_item}"

						if { rsync -RaHAXSlq "${backup_item}/" "${BACKUP_DIR}/" && exec_command="rsync"; } &>/dev/null || { \cp -Rfp --parents --reflink=auto "${backup_item}" "${BACKUP_DIR}"; \cp -Rfp --parents --reflink=auto "${backup_item}" "${BACKUP_DIR}" && chmod --reference="${backup_item}" "${BACKUP_DIR}${backup_item}" && exec_command="cp"; } &>/dev/null; then
							printf " with $exec_command command - ${GC}OK${NC}\n"
						else
							printf " with $exec_command command - ${RC}FAIL${NC}\n"
						fi
					else
						printf "${YC}BACKUP WARNING:${NC} ${backup_item} / ${backup_item_size} - more than 2G, backup was skipped\n"
					fi
				fi
			done

			\cp -Rfp --parents --reflink=auto "/opt/php"*"/etc/" "$BACKUP_DIR" &> /dev/null
		else
			printf "${YC}BACKUP ERROR:${NC} Cannot create $BACKUP_ROOT_DIR\n\n"
		        read -p "Proceed anyway ? [y/N]" -n 1 -r
		        echo
		
		        if ! [[ $REPLY =~ ^([Yy]|$'\xd0\xbd'|$'\xd0\x9d')$ ]]; then
		            exit 1
		        fi
		fi

	else
		printf "${YC}BACKUP ERROR:${NC} Low free space\n\n"
	        read -p "Proceed anyway ? [y/N]" -n 1 -r
	        echo
	
	        if ! [[ $REPLY =~ ^([Yy]|$'\xd0\xbd'|$'\xd0\x9d')$ ]]; then
	            exit 1
	        fi
	fi
}

# Update PowerDNS MySQL DB
isp_pdns_ipchanger() {
    if [[ -f "/usr/sbin/pdns_server" ]]; then
        printf "\n${GC}Updating MySQL PowerDNS DB pdns ${NC}"
        mysql -D pdns -e "update records set content=replace(content,'${args[0]}', '${args[1]}');" >/dev/null 2>/dev/null
        mysql -D powerdns -e "update records set content=replace(content,'${args[0]}', '${args[1]}');" >/dev/null 2>/dev/null
        printf " - ${GC}OK${NC}\n"
    fi
}

# ISP Manager changes
proceed_with_isp() {
    printf "\nSetting ihttpd listen all ips\n"
    if [[ $ISP_LIC_BAD = "0" ]];then
        $ISP5_PANEL_FILE -m core ihttpd.edit ip=any elid=${args[0]} sok=ok >/dev/null 2>/dev/null
    fi

    printf "\nCleaning ISP Manager cache\n"
    rm -rf /usr/local/mgr5/var/.xmlcache/*
    rm -f /usr/local/mgr5/etc/ispmgr.lic /usr/local/mgr5/etc/ispmgr.lic.lock /usr/local/mgr5/var/.db.cache.*

    printf "\nRestarting ISP Manager\n\n"
    if [[ $ISP_LIC_BAD = "0" ]];then
        $ISP5_PANEL_FILE -m ispmgr -R&
    fi
}

# Proceed without ISP Manager
proceed_without_isp() {
    read -p "Continue IP change (files) [Y/n]" -n 1 -r
    echo
    if ! [[ $REPLY =~ ^([Nn]|$'\xd1\x82'|$'\xd0\xa2')$ ]]; then

        printf "\n${GC}Current network settings:${NC}\n\n"
        ip a
        echo
        ip r

        printf "\n${GC}Starting IP change systemwide${NC}\n"

        # Network manager check
        if which nmcli &> /dev/null && [[ ! -z "$(ls -A '/etc/NetworkManager/system-connections/')" ]]; then
            printf "\n${GC}NetworkManager detected${NC}\nConfiguration in /etc/NetworkManager/system-connections/\n"
        fi

        # Netplan check
        if which netplan &> /dev/null && [[ ! -z "$(ls -A '/etc/netplan/')" ]]; then
            printf "\n${GC}Netplan detected${NC}\nConfiguration in /etc/netplan/\n"
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

        if [[ $REPLY =~ ^([Yy]|$'\xd0\xbd'|$'\xd0\x9d')$ ]]; then
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
        if [[ $GATEWAYCHANGE == "YES" ]]; then
            printf "\n${GC}Changing gateway address${NC}\n"

            GATEWAYCONFIG_PATH_LIST=("/etc/NetworkManager/system-connections/*" "/etc/netplan/*" "/etc/network/interfaces" "/etc/network/interfaces.d/*" "/etc/sysconfig/network*")

            for gateway_config_item in "${GATEWAYCONFIG_PATH_LIST[@]}"; do
                echo "Processing ${gateway_config_item}"
                grep --no-messages --devices=skip -rIil --exclude={*.log,*.log.*,*.run,*random*,*.jpg,*.jpeg,*.webp} ${args[2]} ${gateway_config_item} | xargs sed -i "s@${args[2]}@${args[3]}@gi" &> /dev/null
            done

            GATEWAYCHANGED=YES
            unset GATEWAYCHANGE
        else
            printf "\n${YC}3 and 4 script's arguments were empty ${NC}\n"
            printf "If default gateway IP address / subnet mask need to be changed, do it manually\n"
        fi

        if [[ "$ISP5_RTG" = "1" ]]; then
            printf "\n${YC}To update ISP Manager license, run:${NC}\ncurl -X POST -F \"func=soft.edit\" -F \"elid=$ISP5_LITE_ELID\" -F \"out=text\" -F \"ip=${args[1]}\" -F \"sok=ok\" -ks \"https://api.ispmanager.com/billmgr\" -F \"authinfo=support@provider:password\"\n"

        fi

        echo

        printf "${GC}${args[0]} -> ${args[1]} was changed${NC}\n"
        if [[ $GATEWAYCHANGED == "YES" ]]; then
            printf "${GC}Gateway IP ${args[2]} -> ${args[3]} was changed${NC}\n"
            printf "\n${YC}You should check subnet mask correctness ${NC}\n"
        fi

        printf "Adjust the network ${YC}mask${NC} if necessary and reboot this system (${YC}run init 6${NC}) manually to apply all changes\n"

        unset GATEWAYCHANGED
    else
        printf "\n${GC}Nothing was done. Come back, bro!${NC}\n"
        exit 1
    fi
}

# ISP panel proccessing
isp_manager_processing() {

                # ISP Manager in SQLite
                if [[ -f "$ISP5_LITE_MAIN_DB_FILE" ]]; then

                    if ! which sqlite3; then apt update; apt -y install sqlite3 || yum -y install sqlite3; fi > /dev/null 2>&1

                    if which sqlite3 > /dev/null 2>&1; then

                        printf "\n${GC}DB backup${NC} - ${BACKUP_DIR}/usr/local/mgr5/etc/ispmgr.db \n"

                        printf "\nUpdating db file (changing ${args[0]} with ${args[1]})\n"

                        sqlite3 $ISP5_LITE_MAIN_DB_FILE "update webdomain_ipaddr set value='${args[1]}' where value='${args[0]}';"
                        sqlite3 $ISP5_LITE_MAIN_DB_FILE "update emaildomain set ip='${args[1]}' where ip='${args[0]}';"
                        sqlite3 $ISP5_LITE_MAIN_DB_FILE "update domain_auto set name=replace(name, '${args[0]}', '${args[1]}') where name like '%${args[0]}%';"
                        sqlite3 $ISP5_LITE_MAIN_DB_FILE "update global_index set field_value='${args[1]}' where field_value='${args[0]}';"
                        sqlite3 $ISP5_LITE_MAIN_DB_FILE "update db_server set host = '${args[1]}' || substr(host, instr(host, ':')) where host like '${args[0]}:%';"
                        sqlite3 $ISP5_LITE_MAIN_DB_FILE "update db_mysql_servers set hostname = '${args[1]}' where hostname = '${args[0]}';"
                        sqlite3 $ISP5_LITE_MAIN_DB_FILE "delete from ipaddr where name='${args[0]}';"

                        printf "\n${GC}Update completed${NC}\n"

                    else
                        printf "\n${RC}ERROR:${NC} sqlite3 not found and cannot be installed. Install it manually and restart script.\n\n"
			return 1
                    fi
                fi

                # ISP Manager in MySQL
                if mysql -D ispmgr -e "select * from webdomain_ipaddr;" >/dev/null 2>/dev/null; then
                    if mysqldump --insert-ignore --complete-insert --events --routines --triggers --single-transaction --max_allowed_packet=1G --quick --lock-tables=false ispmgr > /root/support/$TSTAMP/ispmgr.sql; then

                        printf "\n${GC}DB backup file - /root/support/$TSTAMP/ispmgr.sql${NC}\n"

                        printf "\n${GC}Updating MySQL DB (changing ${args[0]} with ${args[1]})${NC}\n"

                        mysql -v -D ispmgr -e "update webdomain_ipaddr set value='${args[1]}' where value='${args[0]}';"
                        mysql -v -D ispmgr -e "update emaildomain set ip='${args[1]}' where ip='${args[0]}';"
                        mysql -v -D ispmgr -e "update domain_auto set name=replace(name, '${args[0]}', '${args[1]}') where name like '%${args[0]}%';"
                        mysql -v -D ispmgr -e "update global_index set field_value='${args[1]}' where field_value='${args[0]}';" 
                        mysql -v -D ispmgr -e "update db_server set host = concat('${args[1]}', substring(host, locate(':', host))) where host like '${args[0]}:%';" 
                        mysql -v -D ispmgr -e "update db_mysql_servers set hostname = '${args[1]}' where hostname = '${args[0]}';" 
                        mysql -v -D ispmgr -e "delete from ipaddr where name='${args[0]}';"

                        printf "\n${GC}Update completed${NC}\n"

                    else
                        printf "\n${RC}ERROR:${NC} MySQL DB ispmgr backup has failed. Update skipped\n"
                    fi
	fi

        isp_pdns_ipchanger
        proceed_with_isp
        proceed_without_isp
}

printf "${YC}This will change${RC} ${args[0]}${NC} with${GC} ${args[1]}${NC}"
if [[ ! -z "${3}" ]]; then GATEWAYCHANGE=YES; printf " and ${RC}${args[2]}${NC} with${GC} ${args[3]}${NC}"; fi
printf " systemwide.\n"

read -p "Proceed? [Y/n]" -n 1 -r
echo
if [[ ! $REPLY =~ ^([Nn]|$'\xd1\x82'|$'\xd0\xa2')$ ]]; then

     txt1="Let's do this my brave "; txt2="g"; txt3="a"; txt4="n"; txt5="g"; txt6="s"; txt7="t"; txt8="a"; for ((i=0;i<${#txt1};i++)); do printf "%s" "${txt1:i:1}"; sleep 0.009; done; printf "%b" "${PPC}${txt2}${NC}"; sleep 0.009; printf "%b" "${RC}${txt3}${NC}"; sleep 0.009; printf "%b" "${OOC}${txt4}${NC}"; sleep 0.009; printf "%b" "${YC}${txt5}${NC}"; sleep 0.009; printf "%b" "${GC}${txt6}${NC}"; sleep 0.009; printf "%b" "${BBC}${txt7}${NC}"; sleep 0.009; printf "%b" "${PPC}${txt8}${NC}"; sleep 0.009; sleep 0.3; total_len=$((${#txt1}+${#txt2}+${#txt3}+${#txt4}+${#txt5}+${#txt6}+${#txt7}+${#txt8})); for ((i=total_len;i>0;i--)); do printf "\b \b"; sleep 0.010; done

     txt1="Initializing "; txt2="virus"; txt3=" encryption system"; txt4=" ...... "; txt5="done"; for ((i=0;i<${#txt1};i++)); do printf "%s" "${txt1:i:1}"; sleep 0.009; done; printf "%b" "${RC}${txt2}${NC}"; for ((i=0;i<${#txt3};i++)); do printf "%s" "${txt3:i:1}"; sleep 0.009; done; for ((i=0;i<${#txt4};i++)); do printf "%s" "${txt4:i:1}"; sleep 0.1; done; for ((i=0;i<${#txt5};i++)); do printf "%s" "${txt5:i:1}"; sleep 0.009; done; sleep 0.3; for ((i=${#txt1}+${#txt2}+${#txt3}+${#txt4}+${#txt5};i>0;i--)); do printf "\b \b"; sleep 0.010; done

    # Doing backup
    backup

    # Check ISP4 panel
    if [[ -f "/usr/local/ispmgr/bin/ispmgr" ]]; then
        printf "${YC}ISP 4${NC} panel detected"
        ISP5_RTG=0
        sleep 2s
        proceed_without_isp
    fi

    # Variables
    if [[ -f "$MGRBIN" ]]; then
        ISP5_PANEL_FILE="$MGRBIN"
        ISP5_LITE_ELID=$(timeout 4 $MGRCTL license.info | sed -n -e "s@^.*licid=@@p")
        ISP5_LITE_LIC=$(timeout 4 $MGRCTL license.info | sed -n -e "s@^.*panel_name=@@p")
    fi

    mkdir -p /root/support/$TSTAMP

    if [[ -f "$ISP5_PANEL_FILE" ]]; then
        shopt -s nocasematch

        # processing ISP Manager disabled sites
        grep --no-messages --devices=skip -rIil --exclude={*.log,*.log.*,*.run,*random*,*.jpg,*.jpeg,*.webp} ${args[0]} ${MGR_PATH}/var/usrtmp/ispmgr/* | xargs sed -i "s@${args[0]}@${args[1]}@gi" >/dev/null 2>/dev/null

        case "$ISP5_LITE_LIC" in
            *busines*)
                printf "\n${RC}ERROR:${NC} ISPmanager Business panel license detected\n"
                ISP5_RTG=0
                sleep 2s
                proceed_without_isp
                ;;
            *lite*|*pro*|*host*|*trial*)
                printf "\n${GC}Lite or trial${NC} ISPmanager panel license detected\n"
                ISP5_RTG=1
                sleep 2s
		isp_manager_processing
                ;;
            *)
                printf "\n${RC}ERROR:${NC} Unknown panel license version detected - $ISP5_LITE_LIC\n"
                ISP5_RTG=0
		if [[ -f $ISP5_LITE_MAIN_DB_FILE ]]; then
		        printf "\n${YC}WARNING:${NC} something not good with panel license detection, maybe rescue loaded\n"
			echo
		        read -p "Replace in $ISP5_LITE_MAIN_DB_FILE anyway ? [y/N]" -n 1 -r
		        echo
		        if ! [[ $REPLY =~ ^([Yy]|$'\xd0\xbd'|$'\xd0\x9d')$ ]]; then
		            ISP_LIC_BAD=1
		            proceed_without_isp
		        fi
			isp_manager_processing
		fi
                sleep 2s
                proceed_without_isp
                ;;
        esac
    else
        printf "${YC}No ISP5 panel detected${NC}\n"
        proceed_without_isp
    fi
else
    printf "\n${GC}Nothing was done. Come back, bro!${NC}\n"
    exit 0
fi