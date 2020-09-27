# BOINC instancer

The BOINC instancer assists in managing parallel BOINC instances on the same host.  
It creates and removes instances, simplifies their start/stop and provides an overview about the number of projects & WUs per instance.
Lets start with the help to get an overview:
```
-h - help (this)
-l - list BOINC instances
-n - new BOINC instance
-d - delete instance picked from list
-r - refresh all config files
-e - enable minimal local environment, no config files
-E $ARG - enable local environment, load config from .tar file/URL
-S $ARG - start specified instance
-T $ARG - stop/terminate specified instance
-D $ARG - delete specified instance (detach projects, remove instance)
```

Internally Bash's getopts parses the options and invokes the required routines. Small letter options require no further input, while capital options require further information.

A host just needs the script itself and an archive containing client and account configuration files. BOINC must be installed, so that *boinc* and *boinccmd* are available via %PATH. Beyond that, there is no interaction with the default BOINC installation. 

#### Example

Lets have a look at several instance states:

```
INSTANCE        PID    State   CPU  GPU  NET NCPU  CPU%   BUFFER PRJ  WUs  DL* ACT  UPL  RTR boincmgr call                                                        
boinc_20002 2149420  Running  SUSP  ATP  ATP  24  100.0 10.0/5.0   1    390   0    0    0    0 cd /opt/boinc/instance_homes/boinc_20002; boincmgr -m -g 20002 -d /opt/boinc/instance_homes/boinc_20002 &
boinc_20008 2149421  Running  SUSP  ATP  ATP  24  100.0 10.0/5.0   1    277   0    0    0    0 cd /opt/boinc/instance_homes/boinc_20008; boincmgr -m -g 20008 -d /opt/boinc/instance_homes/boinc_20008 &
boinc_29315 2155415  Running   ACT ATP  SUSP  24  100.0 10.0/5.0   1    0   0    0    412    0 cd /opt/boinc/instance_homes/boinc_29315; boincmgr -m -g 29315 -d /opt/boinc/instance_homes/boinc_29315 &
boinc_31416 2120013  Running   ACT  ACT  ACT   24  92.0 10.0/0.0  16 1918   0   23    0    2 cd /opt/boinc/instance_homes/boinc_31416; boincmgr -m -g 31416 -d /opt/boinc/instance_homes/boinc_31416 &
boinc_39106             Down
boinc_43448             Down
boinc_49094             Down
Load average: 22.80/23.02/23.20                                      2585   0   23    412    2

 ACT = Active (Run always)
 ACP = Run based on preferences
 ATP = Network access based on preferences
SUSP = suspended
 RTR = Ready to report
```
Besides the default instance (boinc_31416) there are several additional instances.  
On the first two instances, CPU computing is suspended, these have plenty WUs in cache ready to crunch.  
boinc_29315 has already gone through 412 WUs, but their upload is pending since this clients network access is SUSPended.  
boinc_31416 is the default BOINC installation in /var/lib/boinc-client. This instance is currently crunching along on a huge stack of 1918 WUs in cache, from which 23 are in progress and 2 are ready to report (RTR). It can be displayed, but start/stop/delete won't work on this instance.  
For all instances the total number of configured CPUs (NCPU), the buffer settings as well as the active CPU percentage is displayed. Each line closes with a tailored boincmg command that opens a BOINC Manager window for this specific instance. This command should be issued from the user that runs the desktop.

#### Environment setup
The BOINC instancer can set up the environment from a config file in .tar format (-E), or just create the basic directory structure (-e). The later has then to be filled by the user.

```
root@hostname:~# /usr/local/bin/boinc-instancer.sh -E http://remotehttphost.com/instancer_config_cluster.tar
Initialize environment first to set up directories, etc...

(Re)creating all needed directories...
	Created /opt/boinc
	Created /opt/boinc/config_repo
	Created /opt/boinc/config_repo/boinc_accounts
	Created /opt/boinc/instance_homes
	Created link to default BOINC 31416

--2020-09-27 09:31:11--  http://remotehttphost.com/instancer_config_cluster.tar
Resolving remotehttphost.com (remotehttphost.com)... 5.189.161.137
Connecting to remotehttphost.com (remotehttphost.com)|5.189.161.137|:80... connected.
HTTP request sent, awaiting response... 200 OK
Length: 10240 (10K) [application/x-tar]
Saving to: ‘/opt/boinc/config_repo/instancer_config.tar’

/opt/boinc/config_repo/instancer_config.tar          100%[=====================================================================================================================>]  10.00K  --.-KB/s    in 0.001s  

2020-09-27 09:31:11 (16.3 MB/s) - ‘/opt/boinc/config_repo/instancer_config.tar’ saved [10240/10240]

./
tar: .: skipping existing file
./app_config.xml
./global_prefs_override.xml
./cc_config.xml
./gui_rpc_auth.cfg
./boinc_accounts/
tar: ./boinc_accounts: skipping existing file
./boinc_accounts/account_www.worldcommunitygrid.org.xml
Creating new remote_hosts.cfg based on local network config - OK

Copy (additional) account config files to /opt/boinc/config_repo/boinc_accounts
```
In the above example, the instancer first creates the basic directory structure, then downloads the configuration from http://remotehttphost.com/instancer_config_cluster.tar. A local .tar file could also be used instead. The archive is extracted, but existing files are not overwritten. Here an account configuratipon file for World Community Grid is included. Since the archive didn't exclude a remote_hosts.cfg, a new one is created allowing all hosts of the local network (computed from the default gateway). Additional account config files can be placed in the specified path, to be used by future instance creations.

#### Instance creation
```
root@hostname:~# /usr/local/bin/boinc-instancer.sh -n
Copy account config file account_www.worldcommunitygrid.org.xml? [Y/n]
Y
Enabling account_www.worldcommunitygrid.org.xml
Started, RC=0
Created new instance 13239. Sleeping 5s.
retval 0
INSTANCE        PID    State   CPU  GPU  NET NCPU  CPU%   BUFFER PRJ  WUs  DL* ACT  UPL  RTR boincmgr call                                                        
boinc_13239   17589  Running  SUSP  ATP  ATP   -1 100.0  2.0/1.0   0    0   0    0    0    0 cd /opt/boinc/instance_homes/boinc_13239; boincmgr -m -g 13239 -d /opt/boinc/instance_homes/boinc_13239 &
boinc_31416    4091  Running   ACT  ATP  ACT   -1 100.0  2.0/1.0  13   30   0    5    0    0 cd /opt/boinc/instance_homes/boinc_31416; boincmgr -m -g 31416 -d /opt/boinc/instance_homes/boinc_31416 &
Load average: 4.08/4.02/4.01                                           30   0    5    0    0
```

When creating a new instance, the instancer picks a free port (here 13239), which also becomes part of the directory structure. Per each account config file found, it queries the user whether this account should be enabled on the new instance. That way multiple account files could be stored, but only one or few used depending on the current need. The new BOINC instance is then started and suspended (this default may change though). One can now connect to the instance, check and unsuspend it.

#### Limitations
- starts BOINC instances under root for now (*to be fixed*)
- won't control default BOINC instance, maybe implement start/stop through system commands

[...]
Work in progress!
