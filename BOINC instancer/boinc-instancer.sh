#!/bin/bash
# 
# v20200929
#

INSTALL_ROOT=/opt/boinc
INSTANCE_HOME=${INSTALL_ROOT}/instance_homes
CONFIG_REPOSITORY=${INSTALL_ROOT}/config_repo
BOINC_PORT_RANGE="10000-65535"
PARENT_COMMAND=$(ps -o comm= $PPID)
FILENAME=$0


help() {
	echo "-h - help (this)"
	echo "-l - list BOINC instances"
	echo "-n - new BOINC instance"
	echo "-d - delete instance picked from list"
	echo "-r - refresh all config files"
	echo "-e - enable minimal local environment, no config files" 
	echo "-s - start all BOINC instances"
	echo "-E \$ARG - enable local environment, load config from file/URL" 
	echo "-S \$ARG - start specified instance"
	echo "-T \$ARG - stop/terminate specified instance"
	echo "-D \$ARG - delete specified instance (detach projects, remove instance)"
}

f_new_boinc_port() {
	while true; do 
		PORT=$(shuf -i ${BOINC_PORT_RANGE} -n 1)
		if [ ! -e ${INSTANCE_HOME}/boinc_${PORT} ]; then 
			echo ${PORT}; 
			return 1; 
		fi
	done
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

f_download_config() {
	if [[ "$1" =~ "http://" ]]; then
		#
		# Download quietly with wget, save under static name
		#
		wget -q $1 -O ${CONFIG_REPOSITORY}/instancer_config.tar 
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

start_boinc() {
        if [[ $1 == "boinc_31416" || $1 == "31416" ]]; then
                echo "Refusing to start the default instance, use proper OS commands"
                exit 2
        fi

        INSTANCE_PORT=$(echo $1 | sed 's/boinc_//')
        INSTANCE_DIR=${INSTANCE_HOME}/boinc_${INSTANCE_PORT}

	ps -ef | grep -v "$$" | grep -q "dir "${INSTANCE_DIR}
	if [[ $? == "0" ]]; then 
		echo "boinc_${INSTANCE_PORT} already running, not starting again";
		echo
        	${FILENAME} -l
		exit 4
	else
        	echo "Starting BOINC instance ${INSTANCE_PORT}"
	fi

        boinc --allow_multiple_clients --daemon --dir ${INSTANCE_DIR} --gui_rpc_port ${INSTANCE_PORT} && echo "Started (RC=$?), sleeping 5 seconds."
        sleep 5

        # print overview
        echo;
        ${FILENAME} -l
}

f_stop_boinc() {
        if [[ $1 == "boinc_31416" || $1 == "31416" ]]; then
                echo "Refusing to stop the default instance, use proper OS commands"
                exit 7
        fi

        INSTANCE_PORT=$(echo $1 | sed 's/boinc_//')
        INSTANCE_DIR=${INSTANCE_HOME}/boinc_${INSTANCE_PORT}
	CDIR=$(pwd)

	cd ${INSTANCE_DIR}
        echo "Stopping BOINC instance ${INSTANCE_PORT}"
        boinccmd --host localhost:${INSTANCE_PORT} --quit && echo "Stopped (RC=$?), sleeping 5 seconds." || echo "Couldn't shut down ${INSTANCE_PORT}, investigate if you care."
        sleep 5

	cd ${CDIR}
        # print overview
        echo;
        ${FILENAME} -l
}

instance_list() {
	printf "%-12s" "INSTANCE";
	printf "%7s" "PID";
	printf "%9s" "State";
	printf "%6s" "CPU";
	printf "%5s" "GPU";
	printf "%5s" "NET";
	printf "%5s" "NCPU";
	printf "%6s" " CPU%";
	printf "%9s" "BUFFER";
	printf "%4s" "PRJ";
	printf "%5s" "WUs";
	printf "%4s" "DL";
	printf "%1s" "*";
	printf "%4s" "ACT";
	printf "%5s" "UPL";
	printf "%5s" "RTR";
	printf "%-70s" " boincmgr call"
	echo
	TOTAL_WU=0
	TOTAL_DL=0
	TOTAL_ACT=0
	TOTAL_UPL=0
	TOTAL_RTR=0

	for INSTANCE_DIR in $(ls ${INSTANCE_HOME} | egrep "boinc_[10000-65000]"); do 
		INSTANCE_PORT=$(echo $INSTANCE_DIR | awk -F"_" '{ print $2 }'); 
		printf "%-12s" "$INSTANCE_DIR"
		if [[ $(ps -ef | grep "\-\-dir ${INSTANCE_HOME}/${INSTANCE_DIR} --gui_rpc_port ${INSTANCE_PORT}") || ${INSTANCE_PORT} == "31416" ]]; then
			if [[ ${INSTANCE_PORT} == "31416" ]]; then
				PID=$(ps -ef | grep -v grep | grep /usr/bin/boinc | awk '{ print $2 }' | head -1)
			else
				PID=$(ps -ef | grep "\-\-dir ${INSTANCE_HOME}/${INSTANCE_DIR} --gui_rpc_port ${INSTANCE_PORT}" | awk '{ print $2 }' | head -1) 
			fi
			printf "%7s" "$PID";
			printf "%9s" "Running"
			BOINCCMD="boinccmd --host localhost:${INSTANCE_PORT}"
			RC_CONNCHECK=$(${BOINCCMD} --get_host_info 2>/dev/null 1>/dev/null; echo $?)
			if [[ $RC_CONNCHECK == "0" ]]; then
				NUM_ACTIVE_WU="0"
				CPU_MODE=$(${BOINCCMD} --get_cc_status | awk '/CPU status/ { getline; getline; if ($3=="always") print "ACT"; if ($3=="never") print "SUSP"; if ($3=="according") print "ATP";}')
				GPU_MODE=$(${BOINCCMD} --get_cc_status |  awk '/GPU status/ { getline; getline; if ($3=="always") print "ACT"; if ($3=="never") print "SUSP"; if ($3=="according") print "ATP";}')
				NETWORK_MODE=$(${BOINCCMD} --get_cc_status | awk '/Network status/ { getline; getline; if ($3=="always") print "ACT"; if ($3=="never") print "SUSP"; if ($3=="according") print "ATP";}')
				NUM_PROJECTS=$(${BOINCCMD} --get_project_status | grep -c "master URL:")
				NUM_WUS=$(${BOINCCMD} --get_tasks | grep -c "WU name")
				NUM_DL_WU=$(${BOINCCMD} --get_tasks | grep -c "state: downloading")
				NUM_DL_WU_PEND=$(${BOINCCMD} --get_file_transfers | awk '/direction: download/ { if($2=="download"); getline; getline; print}' | grep -c "xfer active: no")
				NUM_ACTIVE_WU=$(${BOINCCMD} --get_tasks | grep -c "active_task_state: EXECUTING")
				NUM_UPL_WU=$(${BOINCCMD} --get_tasks | grep -c "  state: uploading")
				NUM_RTR_WU=$(${BOINCCMD} --get_tasks | grep -c "ready to report: yes")
				NCPUS=$(awk -F"<|>" '/ncpus/ {print $3 }' ${INSTANCE_HOME}/${INSTANCE_DIR}/cc_config.xml)

				if [ -f ${INSTANCE_HOME}/${INSTANCE_DIR}/global_prefs_override.xml ] ; then 
					BUFFER=$(awk -F"<|>" '/work_buf_min_days|work_buf_additional_days/ { print sprintf("%.1f",$3) }' ${INSTANCE_HOME}/${INSTANCE_DIR}/global_prefs_override.xml | xargs | sed 's/ /\//g')
					CPUpct=$(awk -F"<|>" '/max_ncpus_pct/ { print sprintf("%.1f",$3) }' ${INSTANCE_HOME}/${INSTANCE_DIR}/global_prefs_override.xml)
				elif [ -f ${INSTANCE_HOME}/${INSTANCE_DIR}/global_prefs.xml ]; then 
					BUFFER=$(awk -F"<|>" '/work_buf_min_days|work_buf_additional_days/ { print sprintf("%.1f",$3) }' ${INSTANCE_HOME}/${INSTANCE_DIR}/global_prefs.xml | xargs | sed 's/ /\//g')
					CPUpct=$(awk -F"<|>" '/max_ncpus_pct/ { print sprintf("%.1f",$3) }' ${INSTANCE_HOME}/${INSTANCE_DIR}/global_prefs.xml | head -1)
				fi
				printf "%6s" "${CPU_MODE}";
				printf "%5s" "${GPU_MODE}";
				printf "%5s" "${NETWORK_MODE}";
				printf "%5s" "${NCPUS}";
				printf "%6s" "${CPUpct}";
				printf "%9s" "${BUFFER}";
				printf "%4s" "${NUM_PROJECTS}"
				printf "%5s" "${NUM_WUS}"
				printf "%4s" "${NUM_DL_WU}"
 				if [ ${NUM_DL_WU_PEND} -gt "0" ]; then printf "%1s" "!"; else printf "%1s" " "; fi
				printf "%4s" "${NUM_ACTIVE_WU}"
				printf "%5s" "${NUM_UPL_WU}"
				printf "%5s" "${NUM_RTR_WU}"
				printf "%-70s" " cd ${INSTANCE_HOME}/${INSTANCE_DIR}; boincmgr -m -g ${INSTANCE_PORT} -d ${INSTANCE_HOME}/${INSTANCE_DIR} &"
				echo
				TOTAL_WU=$(echo ${TOTAL_WU}+${NUM_WUS} | bc)
				TOTAL_DL=$(echo ${TOTAL_DL}+${NUM_DL_WU} | bc)
				TOTAL_ACT=$(echo ${TOTAL_ACT}+${NUM_ACTIVE_WU} | bc)
				TOTAL_UPL=$(echo ${TOTAL_UPL}+${NUM_UPL_WU} | bc)
				TOTAL_RTR=$(echo ${TOTAL_RTR}+${NUM_RTR_WU} | bc)

                                NUM_ACTIVE_WU="0"
				NUM_DL_WU_PEND="0"
			elif [[ $RC_CONNCHECK == "1" ]]; then
				if [ -f gui_rpc_auth.cfg ]; then 
					echo "running but unreachable, gui_rpc_auth.cfg exists in current directory $(pwd), remove and retry! "
				else
					echo "running but unreachable"
				fi
				
			fi
		else
			printf "%7s" "";
			printf "%9s" "Down"
			echo
		fi
	done
	printf "%-40s" "Load average: $(awk '{ print $1"/"$2"/"$3 }' /proc/loadavg)";
	printf "%-28s" "";
	printf "%5s" "${TOTAL_WU}";
	printf "%4s" "${TOTAL_DL}";
	printf "%5s" "${TOTAL_ACT}";
	printf "%5s" "${TOTAL_UPL}";
	printf "%5s" "${TOTAL_RTR}";

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
	
	# find suitable port
	INSTANCE_PORT=$(f_new_boinc_port)
	INSTANCE_DIR=${INSTANCE_HOME}/boinc_${INSTANCE_PORT}
        BOINCCMD="boinccmd --host localhost:${INSTANCE_PORT}"
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
	
	#chown
	chown -R root:root ${INSTANCE_DIR}

	#launch
	boinc --allow_multiple_clients --daemon --dir ${INSTANCE_DIR} --gui_rpc_port ${INSTANCE_PORT} && echo "Started, RC=$?" || return 1
	echo "Created new instance ${INSTANCE_PORT}. Sleeping 5s."
	sleep 5
	${BOINCCMD} --set_host_info BOINC_${INSTANCE_PORT}
	${BOINCCMD} --set_run_mode never
	#cp -pr ${CONFIG_REPOSITORY}/app_config.xml ${INSTANCE_DIR}/projects/universeathome.pl_universe/
	${BOINCCMD} --read_cc_config
        cd ${CDIR}
	${FILENAME} -l	
}

setup_environment() {
	# 
	# instancer config should be in $1 when invoked via -E 
	# 
	IC_URL=$1
	echo "(Re)creating all needed directories..."
	mkdir -p ${INSTALL_ROOT} && echo "	Created ${INSTALL_ROOT}"
	mkdir -p ${INSTALL_ROOT}/config_repo && echo "	Created ${INSTALL_ROOT}/config_repo"
	mkdir -p ${INSTALL_ROOT}/config_repo/boinc_accounts && echo "	Created ${INSTALL_ROOT}/config_repo/boinc_accounts"
	mkdir -p ${INSTANCE_HOME} && echo "	Created ${INSTANCE_HOME}"
	ln -f -s /var/lib/boinc-client/ /opt/boinc/instance_homes/boinc_31416 &&  echo "	Created link to default BOINC 31416"

	echo


	cd ${CONFIG_REPOSITORY}
	if [[ ! -z ${IC_URL} ]]; then
		IC_FILE=$(basename ${IC_URL})

		#
		# f_download_config downloads the config via wget or copies it from a local/NFS path
		#
		f_download_config ${IC_URL}

		tar --skip-old-files -xvf instancer_config.tar

		if [[ ! -e remote_hosts.cfg ]]; then
			#
			# Archive didn't contain remote_hosts.cfg, creating a new one based on gateway in default route
			# 
                	printf "Creating new remote_hosts.cfg based on local network config - "
                	f_new_remote_hosts  && echo "OK"
                	echo
		fi
		echo "Copy (additional) account config files to ${CONFIG_REPOSITORY}/boinc_accounts"
	else
	        # create remote_hosts.cfg based on gateway in default route
		printf "Creating new remote_hosts.cfg based on local network config - "
        	f_new_remote_hosts  && echo "OK"
		echo

		echo "Copy your gui_rpc_auth.cfg, cc_config.xml and global_prefs_override.xml to ${CONFIG_REPOSITORY}"
		echo "Copy account config files to ${CONFIG_REPOSITORY}/boinc_accounts"
	fi

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
        BOINCCMD="boinccmd --host localhost:${INSTANCE_PORT}"
	for MASTER_URL in $(${BOINCCMD} --get_project_status | awk '/master URL:/ { print $3 }'); do
		echo "Detaching ${MASTER_URL}"	
		${BOINCCMD} --project ${MASTER_URL} detach;
	done

	cd ${INSTALL_ROOT}
	sleep 2
	f_stop_boinc ${INSTANCE_PORT} 
	echo
	printf "deleting ${INSTANCE_DIR} - "
	rm -rf ${INSTANCE_DIR} && echo "OK" || echo "Unsuccessful"
	echo
	${FILENAME} -l	
}

choose_delete_instance() {
        echo "Choose which instance to delete!"
        ${FILENAME} -l
	echo
        read -p "Specify instance: " -e REPLY
        delete_instance ${REPLY}
}


refresh_config() {
        for INSTANCE_DIR in $(ls -1 ${INSTANCE_HOME} | egrep "boinc_[10000-65000]"); do
                INSTANCE_PORT=$(echo $INSTANCE_DIR | awk -F"_" '{ print $2 }');
                if [[ $(ps -ef | grep "\-\-dir ${INSTANCE_HOME}/${INSTANCE_DIR} --gui_rpc_port ${INSTANCE_PORT}") ]]; then
			printf "$INSTANCE_DIR "
                        BOINCCMD="boinccmd --host localhost:${INSTANCE_PORT}"
			cd ${INSTANCE_HOME}/${INSTANCE_DIR}
			${BOINCCMD} --read_cc_config && echo "Config refreshed";
			cd ${INSTALL_ROOT}
		fi
	done

}



####################################
# done defining functions
####################################

if [ -e ${INSTALL_ROOT} ]; then
        cd ${INSTALL_ROOT}
else
        if [[ ! $0 =~ ${PARENT_COMMAND} ]]; then
        	echo "Initialize environment first to set up directories, etc..."
		echo
        	${FILENAME} -h
		echo
	fi
fi


if [[ $# -eq 0 ]]; then
	${FILENAME} -h
	exit 0
fi

while getopts lndreschD:S:T:E: opt
do
   case $opt in
	l) instance_list;;
	n) create_new_boinc_instance;;
	d) choose_delete_instance;;
	r) refresh_config;;
	e) setup_environment;;
	s) start_all;;
	E) setup_environment $OPTARG;;
	S) start_boinc $OPTARG;;
	T) f_stop_boinc $OPTARG;;
	D) delete_instance $OPTARG;;
	h) help;;
	*) help;;
   esac
done


####################################
# GoodBye
####################################
