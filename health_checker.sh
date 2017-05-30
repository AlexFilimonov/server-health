#!/bin/bash

#set -x

#Functions
display_usage(){
	echo "This script must be run with root privileges." 
	echo -e "\nUsage:\n$0 [-d] server_name [server_name] ...\n" 
}
#Function for output state of service
#	more 90% - High
#	80% till 90% - Middle
#	less 80% - Low
#Format input variables
#	$1-Message
#	$2-Value
#	$3- Type
#		type_1 for digital function
#		type_2 for boolean function
#		type_3 for information function
#		type_4 for cluster state
output_state(){
	case $3 in
		"type_1")
			if [[ $2 -le 80 ]];then
				echo -e "$1\033[50G\033[32m[ Low $2% ]\033[0m"
			elif [[ $2 -gt 80 && $2 -le 90 ]];then
				echo -e "$1\033[50G\033[33m[ Middle $2% ]\033[0m"
			else
				echo -e "$1\033[50G\033[31m[ High $2%]\033[0m"
			fi
		;;
		"type_2")
			if [[ $2 == "true" ]];then
				echo -e "$1\033[50G\033[32m[ OK ]\033[0m"
			else
				echo -e "$1\033[50G\033[31m[FAIL]\033[0m"
			fi
		;;
		"type_3")
			echo -e "$1\033[50G\033[33m[PSB]\033[0m"
		;;
		"type_4")
			if [[ "$2" = "ST_STABLE" ]];then
				echo -e "$1\033[50G\033[32m[$2]\033[0m"
			elif [[ "$2" = "PSB" ]];then
				echo -e "$1\033[50G\033[33m[$2]\033[0m"
			else
				echo -e "$1\033[50G\033[31m[$2]\033[0m"	
			fi
		;;
	esac
}

get_linux_information(){
	/bin/ssh $host"_mgmt" <<LINUX 2>/dev/null
		#get utilities
		HOST=\$(/usr/bin/which hostname)
		UP=\$(/usr/bin/which uptime)
		AWK=\$(/usr/bin/which awk)
		CAT=\$(/usr/bin/which cat)
		SED=\$(/usr/bin/which sed)

		#
		name=\$(\${HOST} -s)
		days=\$(\${UP} | \${AWK} '{if (\$3 ~ ":") printf ("%s %s",\$3,"hours");else printf ("%s %s",\$3,\$4)}' | \${SED} 's/\,//')
		echo "\$name        uptime \$days"
		\${CAT} /etc/system-release
LINUX
}

get_aix_information(){
	/bin/ssh $host"_mgmt" <<UNIX 2>/dev/null
		#get utilities
        HOST=\$(/usr/bin/which hostname)
        UP=\$(/usr/bin/which uptime)
        AWK=\$(/usr/bin/which awk)
        OSLEVEL=\$(/usr/bin/which oslevel)
		SED=\$(/usr/bin/which sed)

        #
        name=\$(\${HOST} -s)
        days=\$(\${UP} | \${AWK} '{if (\$3 ~ ":") printf ("%s %s",\$3,"hours");else printf ("%s %s",\$3,\$4)}' | \${SED} 's/\,//')
        echo "\$name        uptime \$days"
        echo "AIX \$(\${OSLEVEL})"
UNIX
}

get_linux_health(){
	/bin/ssh $host"_mgmt" <<LINUX 2>/dev/null
		#get utilities
		GREP=\$(/usr/bin/which grep)
		AWK=\$(/usr/bin/which awk)
		FREE=\$(/usr/bin/which free)
		PS=\$(/usr/bin/which ps)
		WC=\$(/usr/bin/which wc)
		NETSTAT=\$(/usr/bin/which netstat)
		PING=\$(/usr/bin/which ping)
		EGREP=\$(/usr/bin/which egrep)
		BLKID=\$(/usr/bin/which blkid)
		VASTOOL="/opt/quest/bin/vastool"
		NTPSTAT=\$(/usr/bin/which ntpstat)
		RPM=\$(/usr/bin/which rpm)
		OPENSSL=\$(/usr/bin/which openssl)
		
		#get CPU utilization
		CPU=\$(\${GREP} "cpu " /proc/stat | \${AWK} '{usage=(\$2+\$4)*100/(\$2+\$4+\$5)} END {printf "%d\n",usage}')

		#get Memory utilization
		MEMORY=\$(\${FREE} -m | \${GREP} "Mem:" | \${AWK} '{usage=(\$3/\$2)*100} END {printf "%d\n",usage}')

		#get Swap utilization
		SWAP=\$(\${FREE} -m | \${GREP} "Swap:" | \${AWK} '{usage=(\$3/\$2)*100} END {printf "%d\n",usage}')

		#get SSHD status
		sshd_count=\$(\${PS} -eo %p,%P,%a | \${GREP} "/usr/sbin/sshd" | \${GREP} -v grep | \${WC} -l)
		if [ \$sshd_count -ge 1 ];then
        	SSHD_STATE="true"
		else
        	SSHD_STATE="false"
		fi

		#get VASD status
		vasd_count=\$(\${PS} -eo %p,%P,%a | \${GREP} "/opt/quest/sbin/.vasd" | \${GREP} -v grep | \${WC} -l)
		if [ \$vasd_count -ge 1 ];then
			if \${VASTOOL} -q status;then	        
				VASD_STATE="true"
			else
				VASD_STATE="false"
			fi
        else
    	    VASD_STATE="false"
        fi

		#get NTP status
		ntpd_count=\$(\${PS} -eo %p,%P,%a | \${GREP} "ntpd" | \${GREP} -v grep | \${WC} -l)
		if [ \$ntpd_count -ge 1 ];then
			if \${NTPSTAT} 1>/dev/null 2>&1;then
        	    NTPD_STATE="true"
	        else
    	        NTPD_STATE="false"
	        fi
        else
     	    NTPD_STATE="false"
        fi

		#check default gateway
		#def_gateway=\$(\${NETSTAT} -rn | \${AWK} '\$4 == "UG" {print \$2}')
		def_gateway=\$(\${NETSTAT} -rn | \${AWK} '\$1 == "0.0.0.0" && \$3 == "0.0.0.0" {print \$2}')
	    if \${PING} -c4 \$def_gateway 1>/dev/null 2>&1;then
	        GW_STATE="true"
	    else
			GW_STATE="false"
	    fi

		#check file systems
		\${EGREP} -v "^#|^$" /etc/fstab > /tmp/fs.state
	    while read line_fstab
	    do
	        STATUS=0
	        FSTYPE_FSTAB=\$(echo \$line_fstab | \${AWK} '{print \$3}')
	        POINT_FSTAB=\$(echo \$line_fstab | \${AWK} '{print \$2}')
        	FSOPT_FSTAB=\$(echo \$line_fstab | \${AWK} '{print \$4}')
	        if [[ \$FSTYPE_FSTAB != "nfs" && \$FSTYPE_FSTAB != "cifs" && \$FSTYPE_FSTAB != "swap" && \$FSTYPE_FSTAB != "tmpfs" && \$FSTYPE_FSTAB != "devpts" && \$FSTYPE_FSTAB != "sysfs" && \$FSTYPE_FSTAB != "proc" ]];then
				if [[ \${POINT_FSTAB: -1} = "/" && \${#POINT_FSTAB} -gt 1 ]];then
					POINT_FSTAB=\${POINT_FSTAB::-1}
				fi
	            line_mounts=\$(\${GREP} "[[:space:]]\$POINT_FSTAB[[:space:]]" /proc/mounts | \${GREP} -v rootfs)
				[ -n "\$line_mounts" ] || STATUS=1
            	FSOPT_MOUNTS=\$(echo \$line_mounts | \${AWK} '{print \$4}')
    	        #check RO state
        	    if [[ \$FSOPT_MOUNTS =~ "ro," ]];then
	                [[ \$FSOPT_FSTAB =~ "ro" ]] || STATUS=1
	            fi
	            #output of state
    	        if [ \$STATUS -ne 0 ];then
					if [ -n "\$LIST_FSs" ];then
						LIST_FSs="\$LIST_FSs, \"\$POINT_FSTAB\""
					else
						LIST_FSs="\"\$POINT_FSTAB\""
					fi
				fi
    	    elif [[ \$FSTYPE_FSTAB != "swap" && \$FSTYPE_FSTAB != "tmpfs" && \$FSTYPE_FSTAB != "devpts" && \$FSTYPE_FSTAB != "sysfs" && \$FSTYPE_FSTAB != "proc" ]];then
				if [[ \${POINT_FSTAB: -1} = "/" && \${#POINT_FSTAB} -gt 1 ]];then
                    POINT_FSTAB=\${POINT_FSTAB::-1}
                fi
	            if ! \${GREP} -q "[[:space:]]\$POINT_FSTAB[[:space:]]" /proc/mounts;then
	                STATUS=1
    	        fi
				if [ \$STATUS -ne 0 ];then
                    if [ -n "\$LIST_FSs" ];then
                        LIST_FSs="\$LIST_FSs, \"\$POINT_FSTAB\""
                    else
                        LIST_FSs="\"\$POINT_FSTAB\""
                    fi
                fi
    	    fi
        unset line_mounts
		unset FSTYPE_FSTAB
		unset POINT_FSTAB
		unset FSOPT_FSTAB
		unset FSOPT_MOUNTS
    	done < /tmp/fs.state
		STATE_FSs="{ \"vgname\":\"Linux\", \"failed_fs\": [ \$LIST_FSs ] }"
	    rm -f /tmp/fs.state

		#check cluster state
		if \${RPM} -qa | \${GREP} -q VRTSvcs;then
			CLUSTER_EXISTS="true"
			CLUSTER_STATE="PSB"
	        RG_STATE=\$(/opt/VRTSvcs/bin/hastatus -sum | \${OPENSSL} enc -base64)
	    else
			CLUSTER_EXISTS="false"
            CLUSTER_STATE="false"
	        RG_STATE="false"
		fi

		#Print results in JSON format
		echo "{ \"cpu\":\"\$CPU\", \"memory\":\"\$MEMORY\", \"swap\":\"\$SWAP\", \"ssh\":\"\$SSHD_STATE\", \"quest\":\"\$VASD_STATE\", \"ntp\":\"\$NTPD_STATE\", \"gateway\":\"\$GW_STATE\", \"fs\": [ \$STATE_FSs ], \"wpar\": { \"iswpar\":\"false\", \"pwpar\":\"false\" }, \"paths\": [ \$failed_paths ], \"errpt\": [ { \"state\":\"nonexist\", \"errors\":\"false\" } ], \"cluster\": [ { \"exist\":\"\$CLUSTER_EXISTS\", \"state\":\"\$CLUSTER_STATE\", \"rg\":\"\$RG_STATE\" } ] }"
LINUX
}

get_aix_health(){
	/bin/ssh $host"_mgmt" <<UNIX  2>/dev/null
        #get utilities
		SAR=\$(/usr/bin/which sar)
		TAIL=\$(/usr/bin/which tail)
		HEAD=\$(/usr/bin/which head)
        GREP=\$(/usr/bin/which grep)
		EGREP=\$(/usr/bin/which egrep)
        AWK=\$(/usr/bin/which awk)
        SVMON=\$(/usr/bin/which svmon)
        PS=\$(/usr/bin/which ps)
        WC=\$(/usr/bin/which wc)
        NETSTAT=\$(/usr/bin/which netstat)
        PING=\$(/usr/bin/which ping)
		LSFS=\$(/usr/bin/which lsfs)
		LSVG=\$(/usr/bin/which lsvg)
		LSPATH=\$(/usr/bin/which lspath)
		VASTOOL="/opt/quest/bin/vastool"
		NTPQ=\$(/usr/bin/which ntpq)
		ERRPT=\$(/usr/bin/which errpt)
		DATE=\$(/usr/bin/which date)
		LSLPP=\$(/usr/bin/which lslpp)
		LSSRC=\$(/usr/bin/which lssrc)
		LSCFG=\$(/usr/bin/which lscfg)
		LSCONF=\$(/usr/bin/which lsconf)
		OPENSSL=\$(/usr/bin/which openssl)
		EXPR=\$(/usr/bin/which expr)
		SORT=\$(/usr/bin/which sort)
		UNIQ=\$(/usr/bin/which uniq)
		HOSTNAME=\$(/usr/bin/which hostname)

        #get CPU utilization
		CPU=\$(\${SAR} 1 5 | \${TAIL} -n 1 | \${AWK} '{print int(100-\$5)}')

        #get Memory utilization
		MEMORY=\$(\${SVMON} | \${GREP} memory | \${AWK} '{usage=(\$6/\$2)*100} END {printf "%d\n",usage}')

        #get Swap utilization
		SWAP=\$(\${SVMON} | \${GREP} "pg space" | \${AWK} '{usage=(\$4/\$3)*100} END {printf "%d\n",usage}')

        #get SSHD status
        sshd_count=\$(\${PS} -eo %p,%P,%a | \${GREP} "/usr/sbin/sshd" | \${GREP} -v grep | \${WC} -l)
        if [ \$sshd_count -ge 1 ];then
            SSHD_STATE="true"
        else
            SSHD_STATE="false"
        fi

        #get VASD status
        vasd_count=\$(\${PS} -eo %p,%P,%a | \${GREP} "/opt/quest/sbin/.vasd" | \${GREP} -v grep | \${WC} -l)
        if [ \$vasd_count -ge 1 ];then
			if \${VASTOOL} -q status;then
                VASD_STATE="true"
            else
                VASD_STATE="false"
            fi
        else
            VASD_STATE="false"
        fi

        #get NTP status
        ntpd_count=\$(\${PS} -eo %p,%P,%a | \${GREP} "ntpd" | \${GREP} -v grep | \${WC} -l)
        if [ \$ntpd_count -ge 1 ];then
			servers_count=\$(\${NTPQ} -np | grep ^* | wc -l)
			if [ \$servers_count -eq 1 ];then
	            NTPD_STATE="true"
			else
				NTPD_STATE="false"
			fi
        else
            NTPD_STATE="false"
        fi

        #check default gateway
        def_gateway=\$(\${NETSTAT} -rn | \${AWK} '\$1 == "default" {print \$2}')
        if \${PING} -c4 \$def_gateway 1>/dev/null 2>&1;then
            GW_STATE="true"
		else
            GW_STATE="false"
        fi

		#check fs state
		for vg in \$(\${LSVG} -o)
		do
			\${LSVG} -l \$vg | \${TAIL} -n +3 | \${AWK} '\$2 != "boot" && \$6 != "open/syncd" {print}' | while read lv
			do
				FS_POINT=\$(echo \$lv | \${AWK} '{print \$7}')
				if [ -n "\$LIST_FSs" ];then
					LIST_FSs="\$LIST_FSs, \"\$FS_POINT\""
				else
					LIST_FSs="\"\$FS_POINT\""	
				fi
			done
			if [ -n "\$STATE_FSs" ];then
                STATE_FSs="\$STATE_FSs, { \"vgname\":\"\$vg\", \"failed_fs\": [ \$LIST_FSs ] }"
            else
                STATE_FSs="{ \"vgname\":\"\$vg\", \"failed_fs\": [ \$LIST_FSs ] }"
            fi
			LIST_FSs=""
		done
		if \${LSLPP} -l cluster.es.client.rte >/dev/null 2>&1;then
			if \${LSSRC} -s clstrmgrES >/dev/null 2>&1;then
				LIST_RGs=\$(/usr/es/sbin/cluster/utilities/clRGinfo -c | \${GREP} "ONLINE" | \${GREP} \$(\${HOSTNAME} -s) | \${AWK} -F: '{print \$1}')
				for rg in "\$LIST_RGs"
				do
					LIST_VGs=\$(/usr/es/sbin/cluster/utilities/cllsvg -g \$rg | \${AWK} '{print \$2}')
					for vg in "\$LIST_VGs"
					do
						if ! \${LSVG} \$vg >/dev/null 2>&1;then
							STATE_FSs="\$STATE_FSs, { \"vgname\":\"\$vg\", \"failed_fs\": [ \"Clustered_VG_not_mounted\" ] }"
						fi
					done
				done
			fi
		fi

		#check IS WPAR
		WPAR=\$(\${LSCFG} -vl wio* | \${AWK} '{print \$2}')
		if [ ! -z \$WPAR ]
		then
	        if [ \$WPAR = "WPAR" ]
    	    then
        	    ISWPAR="true"
                PWPAR=\$(\${LSCONF} -L | \${AWK} '{print \$4}')
	        else
                ISWPAR="false"
				PWPAR="false"
	        fi
		else
            ISWPAR="false"
			PWPAR="false"
		fi

		#check failed paths
		count_failed_paths=\$(\${LSPATH} | \${GREP} -v sas | \${EGREP} -vi "enabled|available|defined" | \${WC} -l)
	    if [ \$count_failed_paths -ne 0 ];then
    	    for disk in \$(\${LSPATH} | \${GREP} -v sas | \${EGREP} -vi "enabled|available|defined" | \${AWK} '{print \$2}')
        	do
            	if [ -n "\$failed_paths" ];then
                	failed_paths="\$failed_paths, \"\$disk\""
	            else
    	            failed_paths="\"\$disk\""
        	    fi
	        done
    	fi

		#check ERRPT permanent errors
		errpt_daemon=\$(\${PS} -eo %p,%P,%a | \${GREP} "/usr/lib/errdemon" | \${GREP} -v grep | \${WC} -l)
	    if [ \$errpt_daemon -eq 1 ];then
			DAY=\$(\${EXPR} \$(\${DATE} +%d) - 3)
    	    PERMANENT_ERRORS=\$(\${ERRPT} -T PERM -s \$(\${DATE} +"%m\${DAY}0000%y") | \${WC} -l)
        	if [ \$PERMANENT_ERRORS -gt 1 ];then
            	ERRPT_STATE="false"
				ERRPT_ERRORS=\$(\${ERRPT} -T PERM -s \$(\${DATE} +"%m\${DAY}0000%y") | \${SORT} -rk1,2 | \${UNIQ} -f2 | \${OPENSSL} enc -base64)
	        else
    	        ERRPT_STATE="true"
				ERRPT_ERRORS="false"
        	fi
	    else
    	    ERRPT_STATE="false"
			ERRPT_ERRORS=\$(echo "Errdemon is not running..." | \${OPENSSL} enc -base64)
	    fi

		#check cluster state
		if \${LSLPP} -l cluster.es.client.rte >/dev/null 2>&1;then
			CLUSTER_EXISTS="true"
			if \${LSSRC} -s clstrmgrES >/dev/null 2>&1;then
				CLUSTER_STATE=\$(\${LSSRC} -ls clstrmgrES | \${HEAD} -n1 | \${AWK} '{print \$3}')
    	    	RG_STATE=\$(/usr/es/sbin/cluster/utilities/clRGinfo | \${OPENSSL} enc -base64)
			else
				CLUSTER_STATE="Not running"
				RG_STATE=\$( echo "Cluster is not running" | \${OPENSSL} enc -base64)
			fi
		else
			CLUSTER_EXISTS="false"
			CLUSTER_STATE="false"
			RG_STATE="false"
	    fi

		#Print results in JSON format
        echo "{ \"cpu\":\"\$CPU\", \"memory\":\"\$MEMORY\", \"swap\":\"\$SWAP\", \"ssh\":\"\$SSHD_STATE\", \"quest\":\"\$VASD_STATE\", \"ntp\":\"\$NTPD_STATE\", \"gateway\":\"\$GW_STATE\", \"fs\": [ \$STATE_FSs ], \"wpar\": { \"iswpar\":\"\$ISWPAR\", \"pwpar\":\"\$PWPAR\" }, \"paths\": [ \$failed_paths ], \"errpt\": [ { \"state\":\"\$ERRPT_STATE\", \"errors\":\"\$ERRPT_ERRORS\" } ], \"cluster\": [ { \"exist\":\"\$CLUSTER_EXISTS\", \"state\":\"\$CLUSTER_STATE\", \"rg\":\"\$RG_STATE\" } ] }"
UNIX
}

#Main script

#Check count of arguments
if [ $# -eq 0 ]
then
	display_usage
	exit 1
fi

#Check whether user had supplied -h or --help
if [[ $1 == "--help" ||  $1 == "-h" || $1 == "--usage" ]] 
then 
	display_usage
	exit 1
fi

#Check debug mode
if [[ $1 == "-d" ]]
then
	DEBUG_MODE="true"
	shift
fi

#Main cycle and getting of status
for host in $@
do
	OS=$(/bin/ssh $host"_mgmt" "/bin/uname" 2>/dev/null)
	#Exit in case of failure ssh
	if [ $? -ne 0 ];then
		exit 2
	fi

	if [ $OS = "Linux" ];then
		get_linux_information
		echo
		health=$(get_linux_health)
		if [ ! -z $DEBUG_MODE ];then
			echo ${health}
		fi
	elif [ $OS = "AIX" ];then
		get_aix_information
		echo
		health=$(get_aix_health)
		if [ ! -z $DEBUG_MODE ];then
			echo ${health}
		fi
	else
		echo -e "\033[31mUnknown OS\033[0m"
		exit 3
	fi
	if [ $(echo $health | /bin/jq -r ".wpar | .iswpar") != "true" ];then 
		output_state "CPU Usage" $(echo $health | /bin/jq -r ".cpu") "type_1"
	fi
    output_state "Mem Usage" $(echo $health | /bin/jq -r ".memory") "type_1"
    output_state "Swap Usage" $(echo $health | /bin/jq -r ".swap") "type_1"
    output_state "SSH Service" $(echo $health | /bin/jq -r ".ssh") "type_2"
    output_state "VASD Service" $(echo $health | /bin/jq -r ".quest") "type_2"
    output_state "NTP Service" $(echo $health | /bin/jq -r ".ntp") "type_2"
	if [ $(echo $health | /bin/jq -r ".wpar | .iswpar") != "true" ];then
	    output_state "Default Gateway" $(echo $health | /bin/jq -r ".gateway") "type_2"
	fi

	if [ $(echo $health | /bin/jq -r ".errpt | .[] | .state") != "nonexist" ];then
		if [ $(echo $health | /bin/jq -r ".errpt | .[] | .state") = "false" ];then
		    output_state "Errpt" "false" "type_2"
			errpt_fail="true"
		else
			output_state "Errpt" "true" "type_2"
		fi
	fi

	if [ $(echo $health | /bin/jq -r ".wpar | .iswpar") = "true" ];then
		output_state "It is WPAR server" "" "type_3"
		echo "Please check also $(echo $health | /bin/jq -r ".wpar | .pwpar")"
	fi

	disk_count=$(echo $health | /bin/jq -r ".paths | length")
    if [ $disk_count -gt 0 ];then
        output_state "Disks paths" "" "type_3"
        for i in $(echo $health | /bin/jq -r ".paths | .[]")
        do
            output_state "Disk $i" "false" "type_2"
        done
    else
        output_state "Disks paths" "true" "type_2"
    fi


	i=0
	while [ $i -lt $(echo $health | /bin/jq -r ".fs | length") ]
	do
		vg=$(echo $health | /bin/jq -r ".fs | .[$i] | .vgname")
		if [ $(echo $health | /bin/jq -r ".fs | .[$i] | .failed_fs | length") -gt 0 ];then
			output_state "VG $vg" "" "type_3"
			for fs in $(echo $health | /bin/jq -r ".fs | .[$i] | .failed_fs | .[]")
			do
				output_state "FS $fs" "false" "type_2"
			done
		else
			output_state "VG $vg" "true" "type_2"
		fi
		((i++))
	done

	if [ $(echo $health | /bin/jq -r ".cluster | .[] | .exist") = "true" ];then
		output_state "Cluster state" "$(echo $health | /bin/jq -r ".cluster | .[] | .state")" "type_4"
		echo
		echo $health | /bin/jq -r ".cluster | .[] | .rg" | /bin/tr " " "\n" | /bin/openssl enc -base64 -d
	fi

	if [ ! -z $errpt_fail ];then
		echo
		echo "Please note that you can see only UNIQUE errors for last 3 days"
		echo $health | /bin/jq -r ".errpt | .[] | .errors" | /bin/tr " " "\n" | /bin/openssl enc -base64 -d
	fi	
	echo "########################################"
done
