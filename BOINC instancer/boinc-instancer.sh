#!/bin/bash
#
# v20240507
#	- another fix to ignore niu_max_ncpus_pct in global_prefs, v20240307 should have already fixed it
# v20240308
#	- removed 7.24 dependency for sched. CPU counting
# v20240307
#	- option -w added to watch -n X boinc-instancer.sh -l
#	- narrow down search for CPUpct to skip "not in use" CPUpct
#	- display used/scheduled CPUs per instance & total
# v20230523
#   - fixed removal of instance directory
#   - don't list out instances that have no instance directory
# v20230507
#   - -l instance listing now includes memory usage
# v20230502
#   - start/stop BOINC default instance as well
#   - support for device_name in cc_config.xml, requires BOINC 7.18
#   - improved new port choice during instance creation
#	- plenty of indentation fixes after moving from vi to VS Code
# v20220511
# 	- use hostname instead of localhost in -l overview, make it easier to work with instances on remote hosts
#	- fixed wrong offset of total WU counts in overview
# v20211013
#	- check/change BOINC user shell in existing deployments as well
# v20211012
#	- script auto update fixed
# v20211011
#	- run boinc under non root user
#	- enable bash shell for boinc user if not already done
#	- more resiliant handling of http/https URLs for config download
# v20210525
#   - begin of versioning
#

BOINCUSER=boinc
BOINCGROUP=boinc
INSTALL_ROOT=/opt/boinc
INSTANCE_HOME=${INSTALL_ROOT}/instance_homes
CONFIG_REPOSITORY=${INSTALL_ROOT}/config_repo
BOINC_PORT_RANGE="9000-65535"
PARENT_COMMAND=$(ps -o comm= $PPID)
FILENAME=$(dirname $(readlink -f $0))/$(basename -- "$0")
UNAME_N=$(uname -n)
LANG=C
export LANG
watchInterval=10

help() {
	echo "-h - help (this)"
	echo "-l - list BOINC instances"
	echo "-n - new BOINC instance"
	echo "-d - delete instance picked from list"
	echo "-r - refresh all config files"
	echo "-e - enable minimal local environment, no config files" 
	echo "-s - start all BOINC instances"
	echo "-u - update boinc-instancer from Github"
	echo "-t - terminate (stop) all instances"
	echo "-w - watch boinc-instancer -l periodically"
	echo "-E \$ARG - enable local environment, load config from file/URL" 
	echo "-S \$ARG - start specified instance"
	echo "-R \$ARG - restart specified instance"
	echo "-T \$ARG - stop/terminate specified instance"
	echo "-U \$ARG - update preferences of specified instance"
	echo "-D \$ARG - delete specified instance (detach projects, remove instance)"
}

f_new_boinc_next_port() {
	#
	# Determine port by looking at last used BOINC port, then check whether free via netstat. Increment port number by +1 indefinitly until free port is found
	#
	OFFSET=0
	OFFSET=$1
    LAST_PORT=$(ls ${INSTANCE_HOME} -1 | grep "boinc_" | sed 's/boinc_//' | sort -n | tail -1)
    NEW_PORT=$(($LAST_PORT+$OFFSET+1))
    
    RC_netstat=$(netstat -an | grep -q ":${NEW_PORT} "; echo $?)
    if [[ ${RC_netstat} -ne 0 ]] ; then
		echo ${NEW_PORT}
		return 0
    else
		OFFSET=$(($OFFSET+1))
		f_new_boinc_next_port $OFFSET
    fi
}

f_new_boinc_random_port() {
	while true; do 
		PORT=$(shuf -i ${BOINC_PORT_RANGE} -n 1)
		if [ ! -e ${INSTANCE_HOME}/boinc_${PORT} ]; then 
			echo ${PORT}; 
			return 1; 
		fi
	done
}

boincwatch() {
	watch -n ${watchInterval} $(basename -- "$0") -l 
}

f_new_remote_hosts() {
	NETWORK_BASE=$(ip route show | sed 's/ /./g' | awk -F"." '/default/ { print $3"."$4"."$5 }')
	cat /dev/null > ${CONFIG_REPOSITORY}/remote_hosts.cfg
	NUM=1;
	END=255; 
	while [[ $NUM -lt $END ]]; do 
		echo $NETWORK_BASE.$NUM >> ${CONFIG_REPOSITORY}/remote_hosts.cfg
		NUM=$((NUM+1)); 
	done
}

f_get_boincpwd() {
	GUI_RPC_AUTH=$1
	if [ "$(basename -- ${GUI_RPC_AUTH})" == "gui_rpc_auth.cfg" ] ; then
		if [ -e ${GUI_RPC_AUTH} ] ; then
			BOINCPWD=$(cat ${GUI_RPC_AUTH})
			if [[ ${BOINCPWD} != "" ]]; then
				echo "--passwd "${BOINCPWD}" "
        			return 0
			fi
		fi
	fi
	return 1
}

f_download_config() {
	if [[ "$@" =~ "http://" || "$@" =~ "https://" ]]; then
		#
		# Download quietly with wget, save under static name
		#
		echo wget "$@" -O ${CONFIG_REPOSITORY}/instancer_config.tar 
		wget "$@" -O ${CONFIG_REPOSITORY}/instancer_config.tar 
		if [[ $? == "0" ]]; then
			echo "Saved into ${CONFIG_REPOSITORY}/instancer_config.tar" 
			ls -ld ${CONFIG_REPOSITORY}/instancer_config.tar
		else
			echo "Download failed, exiting..."
			exit 5
		fi
		echo
	elif [[ "$1" =~ "/" ]]; then
		if [ -e $1 ]; then
			cp -pr $1 ${CONFIG_REPOSITORY}/instancer_config.tar	
		else
			echo "The specified file does not exist, try again with correct path."
			exit 17
		fi
	else
		echo "Unknown path to file, can't handle this yet..."
	fi
}

f_check_change_shell() {
	#
	# If we can't get the users name back from whoami, their shell is usually nologin. We'll change it to bash
	#
	if [[ $(su - ${BOINCUSER} -c 'whoami') != ${BOINCUSER} ]]; then 	
		echo "Changing login shell for user ${BOINCUSER}"; 
		printf "Current shell defined in /etc/passwd: "; 
		awk -F":" -v user=${BOINCUSER} '{ if($1==user) print $7 }' /etc/passwd; 
		usermod --shell /bin/bash ${BOINCUSER}; 
		printf "New shell defined in /etc/passwd: "; 
		awk -F":" -v user=${BOINCUSER} '{ if($1==user) print $7 }' /etc/passwd; 
	fi
}

start_boinc() {
	SLEEP=5
    if [[ $1 == "boinc_31416" || $1 == "31416" ]]; then
        service boinc-client start
	else
     	INSTANCE_PORT=$(echo $1 | sed 's/boinc_//')
       	INSTANCE_DIR=${INSTANCE_HOME}/boinc_${INSTANCE_PORT}

		f_check_change_shell

		ps -ef | grep -v "$$" | grep -q "dir "${INSTANCE_DIR}
		if [[ $? == "0" ]]; then 
			echo "boinc_${INSTANCE_PORT} already running, not starting again";
			echo
        	instance_list_header
        	list_instance ${INSTANCE_PORT}
		else
			# make sure ownership of all files in ${INSTANCE_DIR} is correct
			chown -R ${BOINCUSER}:${BOINCGROUP} ${INSTANCE_DIR}

        	echo "Starting BOINC instance ${INSTANCE_PORT}"
        	su - ${BOINCUSER} -c "boinc --allow_multiple_clients --daemon --dir ${INSTANCE_DIR} --gui_rpc_port ${INSTANCE_PORT}" && printf "Started (RC=$?), sleeping ${SLEEP} seconds"
			sleep_counter ${SLEEP}
        	# print overview
        	echo;
        	instance_list_header
        	list_instance boinc_${INSTANCE_PORT}

		fi
    fi
}

f_stop_boinc() {
    if [[ $1 == "boinc_31416" || $1 == "31416" ]]; then
        service boinc-client stop
	else
    	INSTANCE_PORT=$(echo $1 | sed 's/boinc_//')
		INSTANCE_DIR=${INSTANCE_HOME}/boinc_${INSTANCE_PORT}
        if [[ ${INSTANCE_PORT} -lt 10000 ]]; then
            PID=$(ps -ef | grep -v grep | grep "allow_remote_gui_rpc --gui_rpc_port ${INSTANCE_PORT}" | awk '{ print $2 }')
        else
            PID=$(ps -ef | grep "\-\-dir ${INSTANCE_DIR} --gui_rpc_port ${INSTANCE_PORT}" | awk '{ print $2 }' | head -1)
        fi

		if [[ ${PID} != "" ]]; then
			CDIR=$(pwd)

			cd ${INSTANCE_DIR}
    	    echo "Stopping BOINC instance ${INSTANCE_PORT}"
        	boinccmd --host localhost:${INSTANCE_PORT} --quit 
			RC=$?
			sleep 2
			if [[ ${RC} == "0" ]]; then
				echo "Stopped (RC=$?)"
			else
				echo "Couldn't shut down instance with port ${INSTANCE_PORT}, will simply kill it."
				kill ${PID}
			fi

			instance_list_header
			list_instance boinc_${INSTANCE_PORT}
		else
			echo "Instance boinc_${INSTANCE_PORT} is not running"
		fi
	fi
}

get_device_name() {
	INSTANCE_PORT=$(echo $1 | sed 's/boinc_//')
    INSTANCE_DIR="boinc_${INSTANCE_PORT}"
	DEVICE_NAME=$(awk -F"<|>" '/device_name/ {print $3 }' ${INSTANCE_HOME}/${INSTANCE_DIR}/cc_config.xml)
	echo ${DEVICE_NAME}
}

list_instance() {
	INSTANCE_DIR=$1
    INSTANCE_PORT=$(echo $INSTANCE_DIR | awk -F"_" '{ print $2 }');
	INSTANCE_PURPOSE=""
	
	if [[ ! -e ${INSTANCE_HOME}/${INSTANCE_DIR} ]]; then
		echo "BOINC instance $INSTANCE_DIR doesn't exist"
		return 10
	fi
	DEVICE_NAME=$(get_device_name ${INSTANCE_DIR})

    printf "%-12s" "$INSTANCE_DIR";
    printf "%-20s" "$DEVICE_NAME"
    if [[ $(ps -ef | grep -v grep | grep "\-\-dir ${INSTANCE_HOME}/${INSTANCE_DIR} --gui_rpc_port ${INSTANCE_PORT}") || $(ps -ef | grep -v grep | grep "allow_remote_gui_rpc --gui_rpc_port ${INSTANCE_PORT}") || ${INSTANCE_PORT} == "31416" ]]; then
		cd ${INSTANCE_HOME}/${INSTANCE_DIR}
        if [[ ${INSTANCE_PORT} == "31416" ]]; then
			PID=$(ps -ef | grep -v grep | grep /usr/bin/boinc | awk '{ print $2 }' | head -1)
            printf "%7s" "$PID";
        elif [[ ${INSTANCE_PORT} -lt 10000 ]]; then
            PID=$(ps -ef | grep -v grep | grep "allow_remote_gui_rpc --gui_rpc_port ${INSTANCE_PORT}" | awk '{ print $2 }')
            printf "%7s" "$PID";
        else
            PID=$(ps -ef | grep "\-\-dir ${INSTANCE_HOME}/${INSTANCE_DIR} --gui_rpc_port ${INSTANCE_PORT}" | awk '{ print $2 }' | head -1)
            printf "%7s" "$PID";
        fi
        printf "%9s" "Running"
        BOINCPWD=$(cat gui_rpc_auth.cfg)
        if [[ ${BOINCPWD} != "" ]]; then
           	BOINCCMD="boinccmd --host localhost:${INSTANCE_PORT} --passwd ${BOINCPWD} "
        else
            BOINCCMD="boinccmd --host localhost:${INSTANCE_PORT} "
        fi
		BOINCMGR=" ${UNAME_N}:${INSTANCE_PORT} "
        RC_CONNCHECK=$(${BOINCCMD} --get_host_info 2>/dev/null 1>/dev/null; echo $?)
        if [[ $RC_CONNCHECK == "0" ]]; then
			CPU_alloc=0.00
            NUM_ACTIVE_WU="0"
            CC_STATUS=$($BOINCCMD --get_cc_status)
            TASKS=$($BOINCCMD --get_tasks)
            CPU_MODE=$(echo "${CC_STATUS}" | awk '/CPU status/ { getline; getline; if ($3=="always") print "ACT"; if ($3=="never") print "SUSP"; if ($3=="according") print "ATP";}')
            GPU_MODE=$(echo "${CC_STATUS}" | awk '/GPU status/ { getline; getline; if ($3=="always") print "ACT"; if ($3=="never") print "SUSP"; if ($3=="according") print "ATP";}')
            NETWORK_MODE=$(echo "${CC_STATUS}" | awk '/Network status/ { getline; getline; if ($3=="always") print "ACT"; if ($3=="never") print "SUSP"; if ($3=="according") print "ATP";}')
            NUM_CPU_alloc2=$(${BOINCCMD} --get_tasks| grep -A 4 "active_task_state: EXECUTING" | awk '/resources:/ { if($3~"CPU") print $2 }'  | xargs | sed 's/ /+/g' | bc -l | awk '{printf "%.2f\n", $0}' | sed 's/,/./g' )
			if [[ ${NUM_CPU_alloc2} > ${NUM_CPU_alloc} ]]; then NUM_CPU_alloc=$NUM_CPU_alloc2; fi
			NUM_PROJECTS=$(${BOINCCMD} --get_project_status | grep -c "master URL:")
            NUM_WUS=$(echo "${TASKS}" | grep -c "WU name")
            NUM_DL_WU=$(echo "${TASKS}" | grep -c "state: downloading")
            NUM_DL_WU_PEND=$(${BOINCCMD} --get_file_transfers | awk '/direction: download/ { if($2=="download"); getline; getline; print}' | grep -c "xfer active: no")
            NUM_ACTIVE_WU=$(echo "${TASKS}" | grep -c "active_task_state: EXECUTING")
            NUM_UPL_WU=$(echo "${TASKS}" | grep -c "  state: uploading")
            NUM_RTR_WU=$(echo "${TASKS}" | grep -c "ready to report: yes")
            NUM_READY_WU=$(echo ${NUM_WUS}-${NUM_ACTIVE_WU}-${NUM_UPL_WU}-${NUM_RTR_WU} |bc)
            NCPUS=$(awk -F"<|>" '/ncpus/ {print $3 }' ${INSTANCE_HOME}/${INSTANCE_DIR}/cc_config.xml)
			if [ -f ${INSTANCE_HOME}/${INSTANCE_DIR}/instance_purpose ]; then
				INSTANCE_PURPOSE=$(cat ${INSTANCE_HOME}/${INSTANCE_DIR}/instance_purpose)
			fi
            if [ -f ${INSTANCE_HOME}/${INSTANCE_DIR}/global_prefs_override.xml ] ; then
                BUFFER=$(awk -F"<|>" '/work_buf_min_days|work_buf_additional_days/ { print sprintf("%.1f",$3) }' ${INSTANCE_HOME}/${INSTANCE_DIR}/global_prefs_override.xml | xargs | sed 's/ /\//g')
                CPUpct=$(awk -F"<|>" '/<max_ncpus_pct>/ { print sprintf("%.1f",$3) }' ${INSTANCE_HOME}/${INSTANCE_DIR}/global_prefs_override.xml)
            elif [ -f ${INSTANCE_HOME}/${INSTANCE_DIR}/global_prefs.xml ]; then
                BUFFER=$(awk -F"<|>" '/work_buf_min_days|work_buf_additional_days/ { print sprintf("%.1f",$3) }' ${INSTANCE_HOME}/${INSTANCE_DIR}/global_prefs.xml | xargs | sed 's/ /\//g')
                CPUpct=$(awk -F"<|>" '/<max_ncpus_pct>/ { print sprintf("%.1f",$3) }' ${INSTANCE_HOME}/${INSTANCE_DIR}/global_prefs.xml | head -1)
            fi
            printf "%6s" "${CPU_MODE}";
            printf "%5s" "${GPU_MODE}";
            printf "%5s" "${NETWORK_MODE}";
            printf "%5s" "${NCPUS}";
            printf "%6s" "${CPUpct}";
			printf "%10s" "${NUM_CPU_alloc}";
			printf "%10s" "${BUFFER}";
            printf "%4s" "${NUM_PROJECTS}"
            printf "%5s" "${NUM_WUS}"
            printf "%6s" "${NUM_READY_WU}"
            printf "%4s" "${NUM_DL_WU}"
            #if [ ${NUM_DL_WU_PEND} -gt "0" ]; then printf "%1s" "!"; else printf "%1s" " "; fi
            printf "%5s" "${NUM_ACTIVE_WU}"
            printf "%5s" "${NUM_UPL_WU}"
            printf "%5s" "${NUM_RTR_WU}"
            printf "%-19s" "${BOINCMGR}"
			printf "%-30s" "${INSTANCE_PURPOSE}"
            echo

        elif [[ $RC_CONNCHECK == "1" ]]; then
            if [ -f gui_rpc_auth.cfg ]; then
                echo " Unreachable, gui_rpc_auth.cfg exists with passwd ${BOINCPWD}. Try restarting BOINC. "
            else
                echo " Running but unreachable"
          	fi

        fi
	else
		printf "%7s" "";
		printf "%9s" "Down"
		echo
	fi
}

instance_list_header() {
        printf "%-12s" "INSTANCE";
        printf "%-20s" "DEVICE_NAME";
        printf "%7s" "PID";
        printf "%9s" "State";
        printf "%6s" "CPU";
        printf "%5s" "GPU";
        printf "%5s" "NET";
        printf "%5s" "NCPU";
        printf "%6s" " CPU%";
	printf "%10s" "CPUalloc";
        printf "%10s" "BUFFER";
        printf "%4s" "PRJ";
        printf "%5s" "WUs";
        printf "%6s" "READY"
        printf "%4s" "DL";
        #printf "%1s" "*";
        printf "%5s" "ACT";
        printf "%5s" "UPL";
        printf "%5s" "RTR";
        printf "%-19s" " boincmgr"
        printf "%-30s" "purpose"
        echo
}
 
instance_list() {
	#
	# Print header
	#
	instance_list_header

	TOTAL_WU=0
	TOTAL_READY=0
	TOTAL_DL=0
	TOTAL_ACT=0
	TOTAL_UPL=0
	TOTAL_RTR=0
	TOTAL_CPU_ALLOC="0"

	#
	# Cycle through all instances and display them via list_instance
	#	
	for INSTANCE_DIR in $(ls ${INSTANCE_HOME} | egrep "boinc_[$BOINC_PORT_RANGE]"); do 
        NUM_WUS="0"
        NUM_READY_WU="0"
        NUM_ACTIVE_WU="0"
        NUM_DL_WU="0"
		NUM_CPU_alloc="0"
        NUM_DL_WU_PEND="0"
		NUM_UPL_WU="0"
		NUM_RTR_WU="0"

		list_instance ${INSTANCE_DIR}
		TOTAL_CPU_ALLOC=$(echo "${TOTAL_CPU_ALLOC}+${NUM_CPU_alloc}" | bc -l )
		TOTAL_WU=$((${TOTAL_WU}+${NUM_WUS}))
		TOTAL_READY=$((${TOTAL_READY}+${NUM_READY_WU}))
		TOTAL_DL=$((${TOTAL_DL}+${NUM_DL_WU}))
		TOTAL_ACT=$((${TOTAL_ACT}+${NUM_ACTIVE_WU}))
		TOTAL_UPL=$((${TOTAL_UPL}+${NUM_UPL_WU}))
		TOTAL_RTR=$((${TOTAL_RTR}+${NUM_RTR_WU}))
	done

	TIME=$(date "+%H:%M:%S")
	MEMUSE=$(echo "scale=1; $(free | awk '/Mem:/ { print 100"*"$3"/"$2 }')" | bc -l)
	#printf "%-89s" "Load average (@${TIME}): $(awk '{ print $1"/"$2"/"$3 }' /proc/loadavg), Memory: ${MEMUSE}%";
	printf "%-75s" "time: ${TIME}, load average: $(awk '{ print $1"/"$2"/"$3 }' /proc/loadavg), memory: ${MEMUSE}%";
	printf "%10s" "${TOTAL_CPU_ALLOC}";

    printf "%10s" "";
    printf "%4s" "    ";
	printf "%5s" "${TOTAL_WU}";
	printf "%6s" "${TOTAL_READY}";
	printf "%4s" "${TOTAL_DL}";
    #printf "%1s" "*";
	printf "%5s" "${TOTAL_ACT}";
	printf "%5s" "${TOTAL_UPL}";
	printf "%5s" "${TOTAL_RTR}";

	#
	# Display explanations for certain states
	#
	if [[ ! $0 =~ ${PARENT_COMMAND} ]]; then
		echo
		echo
		echo " ACT = Active (Run always)"
		echo " ACP = Run based on preferences"
		echo " ATP = Network access based on preferences"
		echo "SUSP = suspended"
		echo " RTR = Ready to report"
	fi
	echo
}

create_new_boinc_instance () {
	SLEEP=5
	
	# find suitable port
	INSTANCE_PORT=$(f_new_boinc_next_port)
	read -p "[R]andom or Port \"${INSTANCE_PORT}\" : " -i "${INSTANCE_PORT}" -e REPLY
	if [ "$REPLY" = "R" ] ; then
	    INSTANCE_PORT=$(f_new_boinc_random_port)
	fi
	INSTANCE_DIR=${INSTANCE_HOME}/boinc_${INSTANCE_PORT}
	CDIR=$(pwd)
	
	# create instance directory
	mkdir ${INSTANCE_DIR}
    cd ${INSTANCE_DIR}

	#copy skeleton configuration to new instance
	cp -pr ${CONFIG_REPOSITORY}/gui_rpc_auth.cfg ${INSTANCE_DIR}
	cp -pr ${CONFIG_REPOSITORY}/remote_hosts.cfg ${INSTANCE_DIR}
	cp -pr ${CONFIG_REPOSITORY}/cc_config.xml ${INSTANCE_DIR}
	cp -pr ${CONFIG_REPOSITORY}/global_prefs_override.xml ${INSTANCE_DIR}
	chmod +r ${INSTANCE_DIR}/gui_rpc_auth.cfg

	for PROJECT in $(ls ${CONFIG_REPOSITORY}/boinc_accounts/account*xml); do 
		AC_FILE=$(basename ${PROJECT})
		read -p "Enable ${AC_FILE}? [Y|n] " -i "Y" -e REPLY
		if [[ ${REPLY} == "" || ${REPLY} == "Y"  || ${REPLY} == "y" ]]; then
			echo "Enabled"
			cp -pr ${PROJECT} ${INSTANCE_DIR}
		else
			echo "Skipped"
		fi
	done
	
    # make sure ownership of all files in ${INSTANCE_DIR} is correct
    chown -R ${BOINCUSER}:${BOINCGROUP} ${INSTANCE_DIR}


	BOINCPWD=$(f_get_boincpwd "${INSTANCE_HOME}/${INSTANCE_DIR}/gui_rpc_auth.cfg")
	BOINCCMD="boinccmd --host localhost:${INSTANCE_PORT} ${BOINCPWD}"

	# launch new instance
    echo "Starting BOINC instance ${INSTANCE_PORT}"
    su - ${BOINCUSER} -c "boinc --allow_multiple_clients --daemon --dir ${INSTANCE_DIR} --gui_rpc_port ${INSTANCE_PORT}" && printf "Started (RC=$?), sleeping ${SLEEP} seconds"
	echo "Created new instance ${INSTANCE_PORT}. Sleeping 5s."
    sleep_counter ${SLEEP}

	${BOINCCMD} --set_host_info BOINC_${INSTANCE_PORT} 
	${BOINCCMD} --set_run_mode never

	# Start BOINC benchmark, should have finished once the instance is configured
	${BOINCCMD} --run_benchmarks
	echo
	echo "Customize new instance boinc_${INSTANCE_PORT} or confirm defaults with ENTER:"
	${FILENAME} -U boinc_${INSTANCE_PORT}
	${BOINCCMD} --read_cc_config

	# jump to directory we have been in before creating the new instance
    cd ${CDIR}

}

setup_environment() {
	# 
	# instancer config should be in $1 when invoked via -E 
	# 
	IC_URL="$@"
	echo ${IC_URL}
	echo "(Re)creating all needed directories..."
	mkdir -p ${INSTALL_ROOT} && echo "	Created ${INSTALL_ROOT}"
	mkdir -p ${INSTALL_ROOT}/config_repo && echo "	Created ${INSTALL_ROOT}/config_repo"
	mkdir -p ${INSTALL_ROOT}/config_repo/boinc_accounts && echo "	Created ${INSTALL_ROOT}/config_repo/boinc_accounts"
	mkdir -p ${INSTANCE_HOME} && echo "	Created ${INSTANCE_HOME}"
	
	# Ubuntu
	if [ -d /var/lib/boinc-client ] ; then
    	ln -f -s /var/lib/boinc-client/ /opt/boinc/instance_homes/boinc_31416 &&  echo "	Created link to default BOINC 31416"
    fi
    # Fedora
	if [ -d /var/lib/boinc ] ; then
    	ln -f -s /var/lib/boinc/ /opt/boinc/instance_homes/boinc_31416 &&  echo "	Created link to default BOINC 31416"
    fi
	
	echo

	cd ${CONFIG_REPOSITORY}
	if [[ ! -z ${IC_URL} ]]; then
		IC_FILE=$(basename ${IC_URL})

		#
		# f_download_config downloads the config via wget or copies it from a local/NFS path
		#
		f_download_config "${IC_URL}"

		tar --skip-old-files -xvf instancer_config.tar

		if [[ ! -e remote_hosts.cfg ]]; then
			#
			# Archive didn't contain remote_hosts.cfg, creating a new one based on gateway in default route
			# 
            printf "Creating new remote_hosts.cfg based on local network config - "
            f_new_remote_hosts  && echo "OK"
            echo
		fi
		echo "Please copy (additional) account config files to ${CONFIG_REPOSITORY}/boinc_accounts"
	else
	    # create remote_hosts.cfg based on gateway in default route
		printf "Creating new remote_hosts.cfg based on local network config - "
        f_new_remote_hosts && echo "OK"
		echo

		echo "Please copy your gui_rpc_auth.cfg, cc_config.xml and global_prefs_override.xml to ${CONFIG_REPOSITORY}"
		echo "Please copy account config files to ${CONFIG_REPOSITORY}/boinc_accounts"
	fi

	#
	# Check whether we can su to ${BOINCUSER}. If not, change shell to bash.
	#
	f_check_change_shell

	echo
}

delete_instance() {
	if [[ $1 == "boinc_31416" || $1 == "31416" ]]; then
		echo "Refusing to remove the default instance"
		exit 2
	fi
	echo "Removing instance $1"
	INSTANCE_PORT=$(echo $1 | sed 's/boinc_//')
	INSTANCE_DIR=${INSTANCE_HOME}/boinc_${INSTANCE_PORT}
    CDIR=$(pwd)

	if [[ ! -e "${INSTANCE_DIR}" ]]; then
		echo "The specified instance does not exist, check your input..."
		exit 10
	fi

    cd ${INSTANCE_DIR}

    BOINCPWD=$(f_get_boincpwd "${INSTANCE_HOME}/${INSTANCE_DIR}/gui_rpc_auth.cfg")
	BOINCCMD="boinccmd --host localhost:${INSTANCE_PORT} ${BOINCPWD}"

	for MASTER_URL in $(${BOINCCMD} --get_project_status | awk '/master URL:/ { print $3 }'); do
		echo "Detaching ${MASTER_URL}"	
		${BOINCCMD} --project ${MASTER_URL} detach;
	done

	cd ${INSTANCE_HOME}
	sleep 5
	f_stop_boinc ${INSTANCE_PORT} 
	sleep 5
	echo

	cd ${INSTANCE_HOME}
		ls -la ${INSTANCE_DIR} 
		printf "deleting ${INSTANCE_DIR} - "
	rm -rf ${INSTANCE_DIR} && echo "OK" || echo "Unsuccessful"
	echo

    instance_list_header
    list_instance boinc_${INSTANCE_PORT}
}

choose_delete_instance() {
    echo "Choose which instance to delete!"
    ${FILENAME} -l
	echo
    read -p "Specify instance: " -e REPLY
    delete_instance ${REPLY}
}

update_prefs_w_input() {
    INSTANCE_PORT=$(echo $1 | sed 's/boinc_//')
    INSTANCE_DIR="boinc_${INSTANCE_PORT}"
    if [[ -e ${INSTANCE_HOME}/${INSTANCE_DIR} ]]; then
		update_prefs ${INSTANCE_DIR}
	else
	    echo "Not a valid instance: ${INSTANCE_DIR}"
	fi

}
update_prefs() {
	#
	# -U boinc_XXXXX jumps directly to the configuration of the specified instance
	#

	if [[ $1 =~ "boinc_" ]]; then
		 INSTANCE_DIR="$1"
	fi
	COLUMNWIDTH=50
	update_device_name ${INSTANCE_DIR}
	update_ncpus ${INSTANCE_DIR}
	update_max_ncpus_pct ${INSTANCE_DIR}
	update_work_buf_min_days ${INSTANCE_DIR}
	update_work_buf_additional_days ${INSTANCE_DIR}
	set_cpu_mode ${INSTANCE_DIR}
	set_gpu_mode ${INSTANCE_DIR}
	set_network_mode ${INSTANCE_DIR}
	update_purpose_file ${INSTANCE_DIR}
	echo
    refresh_config ${INSTANCE_DIR}
	echo
    instance_list_header
    list_instance boinc_${INSTANCE_PORT}
}

update_device_name() {
	# 
	# overwrite device name reported to BOINC server to allow for instancing on older BOINC server releases
	#
	INSTANCE_PORT=$(echo $1 | sed 's/boinc_//')
    INSTANCE_DIR="boinc_${INSTANCE_PORT}"
	HOSTHASH=$(hostname | cksum | awk '{ print $1 }')
	DEVICE_NAME_CURRENT=$(awk -F"<|>" '/device_name/ { print $3 }' ${INSTANCE_HOME}/${INSTANCE_DIR}/cc_config.xml)
	DEVICE_NAME_GEN="${HOSTHASH}_${INSTANCE_PORT}"
	if [[ $DEVICE_NAME_CURRENT == "" ]]; then
		read -p "instance name (generated)                         " -i "${DEVICE_NAME_GEN}" -e REPLY
	else
		read -p "instance name (generated: ${DEVICE_NAME_GEN})       " -i "${DEVICE_NAME_CURRENT}" -e REPLY
	fi
	#if [[ $DEVICE_NAME_CURRENT != $DEVICE_NAME_NEW ]]; then
		#DEVICE_NAME_NEW=$DEVICE_NAME_CURRENT
	#fi
	#echo "reply: $REPLY"
	RC_options=$(grep -q '<options>' ${INSTANCE_HOME}/${INSTANCE_DIR}/cc_config.xml; echo $?)
	RC_devname=$(grep -q '<device_name>' ${INSTANCE_HOME}/${INSTANCE_DIR}/cc_config.xml; echo $?)
	if [[ ${RC_options} -ne 0 ]]; then
		# <options> section doesnt exist yet (implies device_name also doesn't exist)
		# create <options> section start and finish, insert device_name after start of <options>
		sed -i '/<\/cc_config>.*/i \ \ <options>' ${INSTANCE_HOME}/${INSTANCE_DIR}/cc_config.xml
		sed -i '/<options>/a \\t<device_name>'${REPLY}'</device_name>' ${INSTANCE_HOME}/${INSTANCE_DIR}/cc_config.xml
		sed -i '/<\/cc_config>.*/i \ \ </options>' ${INSTANCE_HOME}/${INSTANCE_DIR}/cc_config.xml
	elif [[ ${RC_options} -eq 0 && ${RC_devname} -eq 0 ]]; then
		# <options> section & device_name exist
		# replace existing device_name
		#echo		sed -i 's/<device_name>'${DEVICE_NAME}'</<device_name>'${REPLY}'</' ${INSTANCE_HOME}/${INSTANCE_DIR}/cc_config.xml
		sed -i 's/<device_name>'${DEVICE_NAME_CURRENT}'</<device_name>'${REPLY}'</' ${INSTANCE_HOME}/${INSTANCE_DIR}/cc_config.xml
	elif [[ ${RC_options} -eq 0 && ${RC_devname} -ne 0 ]]; then
		# <options> section exists, but device_name is unknown
		# insert device name after start of <options> section
		sed -i '/<options>/a \\t<device_name>'${REPLY}'</device_name>' ${INSTANCE_HOME}/${INSTANCE_DIR}/cc_config.xml
	else	
		echo "Unhandled. Please report to maintainer."
	fi
}


update_purpose_file() {
	#
	# Adds short description to each instance to not confuse them
	#
    INSTANCE_PORT=$(echo $1 | sed 's/boinc_//')
    INSTANCE_DIR="boinc_${INSTANCE_PORT}"

    if [ -e ${INSTANCE_HOME}/${INSTANCE_DIR}/instance_purpose ]; then
		INSTANCE_PURPOSE=$(cat ${INSTANCE_HOME}/${INSTANCE_DIR}/instance_purpose)
	else
		touch ${INSTANCE_HOME}/${INSTANCE_DIR}/instance_purpose
		INSTANCE_PURPOSE=""
    fi
    read -p "Instance purpose                                  " -i "${INSTANCE_PURPOSE}" -e REPLY
	echo "${REPLY}" > ${INSTANCE_HOME}/${INSTANCE_DIR}/instance_purpose
}

f_tr_mode_number() {
	MODE=$1
	if [ "${MODE}" = "always" ]; then
		echo 1
		return 0
	elif [ "${MODE}" = "auto" ]; then
		echo 2
		return 0
	elif [ "${MODE}" = "never" ]; then
		echo 3
		return 0
	fi
	return 1
}

f_tr_number_mode() {
    MODE=$1
    if [ "${MODE}" == "1" ]; then
        echo "always"
        return 0
    elif [ "${MODE}" == "2" ]; then
        echo "auto"
        return 0
    elif [ "${MODE}" == "3" ]; then
        echo "never"
        return 0
    fi
    return 1
}

set_cpu_mode() {
    INSTANCE_PORT=$(echo $1 | sed 's/boinc_//')
    INSTANCE_DIR="boinc_${INSTANCE_PORT}"

	#cd ${INSTANCE_HOME}/${INSTANCE_DIR}
        
	BOINCPWD=$(f_get_boincpwd "${INSTANCE_HOME}/${INSTANCE_DIR}/gui_rpc_auth.cfg")
	BOINCCMD="boinccmd --host localhost:${INSTANCE_PORT} ${BOINCPWD}"
	CPU_MODE=$(${BOINCCMD} --get_cc_status | awk '/CPU status/ { getline; getline; if ($3=="always") print $3; if ($3=="never") print $3; if ($3=="according") print "auto";}')
	MODE=$(f_tr_mode_number ${CPU_MODE})
	if [ "${CPU_MODE}" = "always" ]; then
		REPLY=always
                read -p "CPU mode        (1. [ALWAYS], 2. auto, 3. never): " -i "${MODE}" -e REPLY_NUM
	elif [ "${CPU_MODE}" = "auto" ]; then
		REPLY=auto
		read -p "CPU mode        (1. always, 2. [AUTO], 3. never): " -i "${MODE}" -e REPLY_NUM
	elif [ "${CPU_MODE}" = "never" ]; then
		REPLY=never
		read -p "CPU mode        (1. always, 2. auto, 3. [NEVER]): " -i "${MODE}" -e REPLY_NUM
	else
		echo "Something wrong here, exiting..."
		exit 1
	fi

	if [ "${REPLY_NUM}" = "" ]; then
		REPLY=${CPU_MODE}
	else
		# check for valid reply
		if [[ ${REPLY_NUM} -eq 1  || ${REPLY_NUM} -eq 2 || ${REPLY_NUM} -eq 3 ]]; then 	
			REPLY=$(f_tr_number_mode ${REPLY_NUM})
		else
			echo "Invalid reply, skipping..."
		fi
	fi

	#
	# If changed, set via boinccmd
	#
	if [ ! "${REPLY}" = "${CPU_MODE}" ]; then
		${BOINCCMD} --set_run_mode ${REPLY}
	fi
}

set_gpu_mode() {
    INSTANCE_PORT=$(echo $1 | sed 's/boinc_//')
    INSTANCE_DIR="boinc_${INSTANCE_PORT}"

	#cd ${INSTANCE_HOME}/${INSTANCE_DIR}
        
	BOINCPWD=$(f_get_boincpwd "${INSTANCE_HOME}/${INSTANCE_DIR}/gui_rpc_auth.cfg")
	BOINCCMD="boinccmd --host localhost:${INSTANCE_PORT} ${BOINCPWD}"
    GPU_MODE=$(${BOINCCMD} --get_cc_status | awk '/GPU status/ { getline; getline; if ($3=="always") print $3; if ($3=="never") print $3; if ($3=="according") print "auto";}')
    MODE=$(f_tr_mode_number ${GPU_MODE})
    if [ "${GPU_MODE}" = "always" ]; then
        REPLY=always
		read -p "GPU mode        (1. [ALWAYS], 2. auto, 3. never): " -i "${MODE}" -e REPLY_NUM
    elif [ "${GPU_MODE}" = "auto" ]; then
        REPLY=auto
		read -p "GPU mode        (1. always, 2. [AUTO], 3. never): " -i "${MODE}" -e REPLY_NUM
    elif [ "${GPU_MODE}" = "never" ]; then
        REPLY=never
		read -p "GPU mode        (1. always, 2. auto, 3. [NEVER]): " -i "${MODE}" -e REPLY_NUM
    else
        echo "Something wrong here, exiting..."
        exit 1
    fi

    if [ "${REPLY_NUM}" = "" ]; then
        REPLY=${GPU_MODE}
    else
        # check for valid reply
        if [[ ${REPLY_NUM} -eq 1  || ${REPLY_NUM} -eq 2 || ${REPLY_NUM} -eq 3 ]]; then              
            REPLY=$(f_tr_number_mode ${REPLY_NUM})
        else
            echo "Invalid reply, skipping..."
        fi
    fi


    #
    # If changed, set via boinccmd
    #
    if [ ! ${REPLY} == ${GPU_MODE} ]; then
        ${BOINCCMD} --set_gpu_mode ${REPLY}
    fi
}

set_network_mode() {
    INSTANCE_PORT=$(echo $1 | sed 's/boinc_//')
    INSTANCE_DIR="boinc_${INSTANCE_PORT}"

	#cd ${INSTANCE_HOME}/${INSTANCE_DIR}

	BOINCPWD=$(f_get_boincpwd "${INSTANCE_HOME}/${INSTANCE_DIR}/gui_rpc_auth.cfg")
	BOINCCMD="boinccmd --host localhost:${INSTANCE_PORT} ${BOINCPWD}"

    NETWORK_MODE=$(${BOINCCMD} --get_cc_status | awk '/Network status/ { getline; getline; if ($3=="always") print $3; if ($3=="never") print $3; if ($3=="according") print "auto";}')

    MODE=$(f_tr_mode_number ${NETWORK_MODE})
    if [ "${NETWORK_MODE}" = "always" ]; then
        REPLY=always
		read -p "Network mode    (1. [ALWAYS], 2. auto, 3. never): " -i "${MODE}" -e REPLY_NUM
    elif [ "${NETWORK_MODE}" = "auto" ]; then
        REPLY=auto
		read -p "Network mode    (1. always, 2. [AUTO], 3. never): " -i "${MODE}" -e REPLY_NUM
    elif [ "${NETWORK_MODE}" = "never" ]; then
        REPLY=never
		read -p "Network mode    (1. always, 2. auto, 3. [NEVER]): " -i "${MODE}" -e REPLY_NUM
    else
        echo "Something wrong here, exiting..."
        exit 1
    fi

    if [ "${REPLY_NUM}" = "" ]; then
        REPLY=${NETWORK_MODE}
    else
        # check for valid reply
        if [[ ${REPLY_NUM} -eq 1  || ${REPLY_NUM} -eq 2 || ${REPLY_NUM} -eq 3 ]]; then              
            REPLY=$(f_tr_number_mode ${REPLY_NUM})
        else
            echo "Invalid reply, skipping..."
        fi
    fi


	#
    # If changed, set via boinccmd
	#
    if [ ! ${REPLY} == ${NETWORK_MODE} ]; then
       ${BOINCCMD} --set_network_mode ${REPLY}
    fi
}

update_ncpus() {
    INSTANCE_PORT=$(echo $1 | sed 's/boinc_//')
    INSTANCE_DIR=boinc_${INSTANCE_PORT}

    ncpus=$(sed 's/[<|>]/ /g' ${INSTANCE_HOME}/${INSTANCE_DIR}/cc_config.xml | awk '/ncpu/ { print $2 }' );
    read -p "ncpus                                             " -i "${ncpus}" -e REPLY
	if [ $(grep ncpu ${INSTANCE_HOME}/${INSTANCE_DIR}/cc_config.xml) ]; then 
		# ncpus exists in cc_config.xml
        	sed -i "s/<ncpus>$ncpus/<ncpus>${REPLY}/" ${INSTANCE_HOME}/${INSTANCE_DIR}/cc_config.xml
	else 
		# ncpus doesn't exist in cc_config.xml
		# will add it directly after <options> with choosen value
		sed -i '/<options>/a <ncpus>4</ncpus>' ${INSTANCE_HOME}/${INSTANCE_DIR}/cc_config.xml; 
	fi
}

update_max_ncpus_pct() {
	INSTANCE_PORT=$(echo $1 | sed 's/boinc_//')
    INSTANCE_DIR=boinc_${INSTANCE_PORT}

	if [ -e ${INSTANCE_HOME}/${INSTANCE_DIR}/global_prefs_override.xml ]; then	
		prefs_override_file=${INSTANCE_HOME}/${INSTANCE_DIR}/global_prefs_override.xml
	elif [ -e ${INSTANCE_HOME}/${INSTANCE_DIR}/global_prefs.xml ]; then
		prefs_override_file=${INSTANCE_HOME}/${INSTANCE_DIR}/global_prefs.xml
	fi

	max_ncpus_pct=$(awk -F "[<|>]" '/<max_ncpus_pct/ { print $3"/1" }' ${prefs_override_file} | bc ); 
	read -p "Maximum CPU %                                     " -i "${max_ncpus_pct}" -e REPLY
	sed -i "s/<max_ncpus_pct>$max_ncpus_pct/<max_ncpus_pct>${REPLY}/" ${prefs_override_file}	
}

update_work_buf_min_days() {
    INSTANCE_PORT=$(echo $1 | sed 's/boinc_//')
    INSTANCE_DIR=boinc_${INSTANCE_PORT}

	if [ -e ${INSTANCE_HOME}/${INSTANCE_DIR}/global_prefs_override.xml ]; then	
		prefs_override_file=${INSTANCE_HOME}/${INSTANCE_DIR}/global_prefs_override.xml
	elif [ -e ${INSTANCE_HOME}/${INSTANCE_DIR}/global_prefs.xml ]; then
		prefs_override_file=${INSTANCE_HOME}/${INSTANCE_DIR}/global_prefs.xml
	fi

	work_buf_min_days=$(awk -F "[<|>]" '/<work_buf_min_days/ { print $3 }' ${prefs_override_file});
    read -p "Minimum work buffer                               " -i "${work_buf_min_days}" -e REPLY
	sed -i "s/<work_buf_min_days>.*/<work_buf_min_days>$REPLY<\/work_buf_min_days>/"  ${prefs_override_file}
}

update_work_buf_additional_days() {
    INSTANCE_PORT=$(echo $1 | sed 's/boinc_//')
    INSTANCE_DIR=boinc_${INSTANCE_PORT}

	if [ -e ${INSTANCE_HOME}/${INSTANCE_DIR}/global_prefs_override.xml ]; then	
		prefs_override_file=${INSTANCE_HOME}/${INSTANCE_DIR}/global_prefs_override.xml
	elif [ -e ${INSTANCE_HOME}/${INSTANCE_DIR}/global_prefs.xml ]; then
		prefs_override_file=${INSTANCE_HOME}/${INSTANCE_DIR}/global_prefs.xml
	fi
    work_buf_additional_days=$(awk -F "[<|>]" '/<work_buf_additional_days>/ { print $3 }' ${prefs_override_file});
    read -p "Additional work buffer                            " -i "${work_buf_additional_days}" -e REPLY
	sed -i "s/<work_buf_additional_days>.*/<work_buf_additional_days>$REPLY<\/work_buf_additional_days>/"  ${prefs_override_file}
}


refresh_config_all() {
    for INSTANCE_DIR in $(ls -1 ${INSTANCE_HOME} | egrep "boinc_[10000-65000]"); do
        INSTANCE_PORT=$(echo $INSTANCE_DIR | awk -F"_" '{ print $2 }');
        if [[ $(ps -ef | grep "\-\-dir ${INSTANCE_HOME}/${INSTANCE_DIR} --gui_rpc_port ${INSTANCE_PORT}") ]]; then
			printf "${INSTANCE_DIR} "
			refresh_config ${INSTANCE_DIR}
		fi
	done
}

refresh_config() {
	INSTANCE_DIR=$1
    INSTANCE_PORT=$(echo $INSTANCE_DIR | awk -F"_" '{ print $2 }');

	BOINCPWD=$(f_get_boincpwd "${INSTANCE_HOME}/${INSTANCE_DIR}/gui_rpc_auth.cfg")
	BOINCCMD="boinccmd --host localhost:${INSTANCE_PORT} ${BOINCPWD}"

    ${BOINCCMD} --read_cc_config && echo "Refreshed cc_config!";
    ${BOINCCMD} --read_global_prefs_override && echo "Refreshed global_prefs_override!";
    cd ${INSTALL_ROOT}
}


start_all() {
	for INSTANCE_DIR in $(ls -1 ${INSTANCE_HOME} | egrep "boinc_[10000-65000]"); do
		start_boinc ${INSTANCE_DIR}		
	done
}

stop_all() {
    for INSTANCE_DIR in $(ls -1 ${INSTANCE_HOME} | egrep "boinc_[10000-65000]"); do
        f_stop_boinc ${INSTANCE_DIR}
    done
}

sleep_counter() {
	INTERVAL=$1
    printf " - "
    COUNT=0
    while [[ ${COUNT} -lt ${INTERVAL} ]]; do
		COUNT=$((${COUNT}+1))
        printf "${COUNT} "
        sleep 1
    done
	echo

}
restart_boinc() {
    INSTANCE_PORT=$(echo $1 | sed 's/boinc_//')
    INSTANCE_DIR="boinc_${INSTANCE_PORT}"
	SLEEP=5

	check_pid_running() {
		ps -ef | grep -v grep | grep -q "\-\-dir ${INSTANCE_HOME}/${INSTANCE_DIR} --gui_rpc_port ${INSTANCE_PORT}" && return 0
		ps -ef | grep -v grep | grep -q "allow_remote_gui_rpc --gui_rpc_port ${INSTANCE_PORT}" && return 0
		return 1
	}


	check_pid_running
	RC=$?

    if [[ ${RC} -eq 0 ]]; then
		echo "${INSTANCE_DIR} is running, going to stop it:"

		f_stop_boinc ${INSTANCE_DIR}
		printf "Will sleep ${SLEEP} seconds"
		sleep_counter ${SLEEP}

		echo
		start_boinc ${INSTANCE_DIR}

	else
		echo "${INSTANCE_DIR} is not running, will start it:"
		start_boinc ${INSTANCE_DIR}
	fi
}

update_instancer() {
	#
	# once the boinc-instancer runs under non-root users, this can be extended to check existing ownerships vs. the executing user
	# for now only root can update the script
	#
	if [[ $(id -u) -ne 0 ]]; then
		echo "You need to be root to perform this operation. aborting..."
	else
		instancer_download="https://raw.githubusercontent.com/MBlenn/BOINC/master/BOINC%20instancer/boinc-instancer.sh"
		wget -O ${FILENAME}_tmp ${instancer_download}
		VERSION_OLD=$(awk '/^# v20/ { print $2 }' ${FILENAME} | sed 's/v//' | head -1)
		VERSION_NEW=$(awk '/^# v20/ { print $2 }' ${FILENAME}_tmp | sed 's/v//' | head -1)
		echo "OLD: $VERSION_OLD"
		echo "NEW: $VERSION_NEW"

		if [[ $VERSION_NEW -gt $VERSION_OLD ]]; then
			chmod +x ${FILENAME}_tmp
			mv ${FILENAME}_tmp ${FILENAME}
		else
			echo "Local is same or newer version than on the repo!"
		fi
			
	fi
}


####################################
# done defining functions
####################################

while getopts lndreschutwD:L:R:S:T:E:U: opt
do
   case $opt in
        l) instance_list;;
        n) create_new_boinc_instance;;
        d) choose_delete_instance;;
        r) refresh_config_all;;
        e) setup_environment;;
        s) start_all;;
		u) update_instancer;;
		t) stop_all;;
		w) boincwatch;;
        E) setup_environment $OPTARG;;
		L) list_instance $OPTARG;;
        S) start_boinc $OPTARG;;
        R) restart_boinc $OPTARG;;
        T) f_stop_boinc $OPTARG;;
        D) delete_instance $OPTARG;;
        U) update_prefs_w_input $OPTARG;;
        h) help;;
        *) help;;
   esac
done


if [ -e ${INSTALL_ROOT} ]; then
        cd ${INSTALL_ROOT}
else
        if [[ ! $0 =~ ${PARENT_COMMAND} ]]; then
        	echo "Initialize environment first to set up directories, etc..."
		echo
	fi
fi


if [[ $# -eq 0 ]]; then
	${FILENAME} -h
	exit 0
fi



####################################
# GoodBye
####################################
