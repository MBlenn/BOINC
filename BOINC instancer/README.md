# BOINC instancer
### Introduction

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
-s - start all BOINC instances
-u - update preferences
-E $ARG - enable local environment, load config from .tar file/URL
-S $ARG - start specified instance
-T $ARG - stop/terminate specified instance
-U $ARM - update preferences of specified instance
-D $ARG - delete specified instance (detach projects, remove instance)
```

Internally Bash's getopts parses the options and invokes the required routines. Small letter options require no further input, while capital options require further information.

A host just needs the script itself and an archive containing client and account configuration files. BOINC must be installed, so that *boinc* and *boinccmd* are available via %PATH. Beyond that, there is no interaction with the default BOINC installation. 

### Instance overview

Lets have a look at several instance states:

```
INSTANCE        PID    State   CPU  GPU  NET NCPU  CPU%   BUFFER PRJ  WUs READY DL* ACT  UPL  RTR boincmgr call                                                        
boinc_20002 2149420  Running  SUSP  ATP  ATP  24  100.0 10.0/5.0   1  390  390  0    0    0    0 boincmgr -m -g 20002 &
boinc_20008 2149421  Running  SUSP  ATP  ATP  24  100.0 10.0/5.0   1  277  277  0    0    0    0 boincmgr -m -g 20008 &
boinc_29315 2155415  Running   ACT ATP  SUSP  24  100.0 10.0/5.0   1    0    0  0    0    412  0 boincmgr -m -g 29315 &
boinc_31416 2120013  Running   ACT  ACT  ACT   24  92.0 10.0/0.0  16 1918 1893  0   23    0    2 boincmgr -m -g 31416 &
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
boinc_31416 is the default BOINC installation in /var/lib/boinc-client. This instance is currently crunching along on a huge stack of 1918 WUs in cache, from which 1893 are ready to start, 23 are in progress and 2 are ready to report (RTR). It can be displayed, but start/stop/delete won't work on this instance.  
For all instances the total number of configured CPUs (NCPU), the buffer settings as well as the active CPU percentage is displayed. Each line closes with a tailored boincmg command that opens a BOINC Manager window for this specific instance. This command should be issued from the user that runs the desktop. However, this only works when no GUI RPC password is set.

### Environment setup
The BOINC instancer can set up the environment from a config file in .tar format (-E), or just create the basic directory structure (-e). The later has then to be filled by the user.

```
root@hostname:~# /usr/local/bin/boinc-instancer.sh -E http://remotehttphost.com/bic.tar
Initialize environment first to set up directories, etc...

(Re)creating all needed directories...
	Created /opt/boinc
	Created /opt/boinc/config_repo
	Created /opt/boinc/config_repo/boinc_accounts
	Created /opt/boinc/instance_homes
	Created link to default BOINC 31416

--2020-09-27 09:31:11--  http://remotehttphost.com/bic.tar
Resolving remotehttphost.com (remotehttphost.com)... 5.189.161.137
Connecting to remotehttphost.com (remotehttphost.com)|5.189.161.137|:80... connected.
HTTP request sent, awaiting response... 200 OK
Length: 10240 (10K) [application/x-tar]
Saving to: ‘/opt/boinc/config_repo/bic.tar’

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
In the above example, the instancer first creates the basic directory structure, then downloads the configuration from http://remotehttphost.com/bic.tar. A local .tar file could also be used instead. The archive is extracted, but existing files are not overwritten. Here an account configuratipon file for World Community Grid is included. Since the archive didn't exclude a remote_hosts.cfg, a new one is created allowing all hosts of the local network (computed from the default gateway). Additional account config files can be placed in the specified path, to be used by future instance creations.
A sample configuration archive is provided [here](bic.tar). It includes a working WCG account file (via weak account key), cc_config.xml, global_prefs_override.xml as well as an empty gui_rpc_auth.cfg. Create your own archive by replacing or adding further account files.

### Instance creation
```
root@hostname:/opt# boinc-instancer.sh -n
Enable account_www.worldcommunitygrid.org.xml? [Y|n] Y
Enabled
Started, RC=0
Created new instance 33528. Sleeping 5s.

Customize new instance boinc_33528 or confirm defaults with ENTER:
New ncpus:                            1
New max_ncpus_pct:                    100
New work_buf_min_days:                7.000000
New work_buf_additional_days:         3.000000
New CPU mode     [always|auto|never]: always
New GPU mode     [always|auto|never]: auto
New network mode [always|auto|never]: always

retval 0
Refreshed cc_config!
Refreshed global_prefs_override!

INSTANCE        PID    State   CPU  GPU  NET NCPU  CPU%   BUFFER PRJ  WUs READY  DL* ACT  UPL  RTR boincmgr call          
boinc_31416     691  Running   ACT  ATP  ACT    4 100.0  1.0/0.1  14   52    47   0    5    0    0 boincmgr -m -g 31416 &                                         
boinc_33528   21289  Running   ACT  ATP  ACT   -1 100.0  7.0/3.0   1    0     0   0    0    0    0 boincmgr -m -g 33528 &                                         
Load average: 4.87/5.06/4.95                                           52    47   0    5    0    0
```

When creating a new instance, the instancer picks a free port (here 33528), which also becomes part of the directory structure. Per each account config file found, it queries the user whether this account should be enabled on the new instance. That way multiple account files could be stored, but only one or few used depending on the current need. The new BOINC instance is then started and suspended. A configuration "dialogue" follows that allows to adjust ncpus, buffer settings and activate or suspend CPU/GPU & network activity. 

### Instance deletion
There are two ways to delete an instance.  
- Run boinc-instancer.sh with -d for it to display the list of instances, providing a prompt and then removing the specified instances.
- Specify the the instance directly after a capital -U, removal will start immediately.

```root@hostname:~# boinc-instancer.sh -D boinc_50132
Removing instance boinc_50132
Detaching http://www.worldcommunitygrid.org/
Stopping BOINC instance 50132
Stopped (RC=0), sleeping 5 seconds.

INSTANCE        PID    State   CPU  GPU  NET NCPU  CPU%   BUFFER PRJ  WUs READY  DL* ACT  UPL  RTR boincmgr call                                                   
boinc_22518   23795  Running  SUSP  ATP  ATP   -1  50.0  7.0/3.0   0    0     0   0    0    0    0 boincmgr -m -g 22518 &                                         
boinc_31416     691  Running   ACT  ATP  ACT    4 100.0  1.0/0.1  14   51    46   0    5    0    0 boincmgr -m -g 31416 &                                         
boinc_33528   21289  Running   ACT  ATP SUSP   -1  50.0  7.0/3.0   0    0     0   0    0    0    0 boincmgr -m -g 33528 &                                         
boinc_50132             Down
boinc_53852   22920  Running  SUSP  ATP  ATP   -1  50.0  7.0/3.0   0    0     0   0    0    0    0 boincmgr -m -g 53852 &                                         
Load average: 5.68/5.66/5.20                                           51    46   0    5    0    0

deleting /opt/boinc/instance_homes/boinc_50132 - OK

INSTANCE        PID    State   CPU  GPU  NET NCPU  CPU%   BUFFER PRJ  WUs READY  DL* ACT  UPL  RTR boincmgr call  
boinc_22518   23795  Running  SUSP  ATP  ATP   -1  50.0  7.0/3.0   0    0     0   0    0    0    0 boincmgr -m -g 22518 &  
boinc_31416     691  Running   ACT  ATP  ACT    4 100.0  1.0/0.1  14   51    46   0    5    0    0 boincmgr -m -g 31416 &                                         
boinc_33528   21289  Running   ACT  ATP SUSP   -1  50.0  7.0/3.0   0    0     0   0    0    0    0 boincmgr -m -g 33528 &                                         
boinc_53852   22920  Running  SUSP  ATP  ATP   -1  50.0  7.0/3.0   0    0     0   0    0    0    0 boincmgr -m -g 53852 &                                         
Load average: 5.68/5.66/5.20                                           51    46   0    5    0    0
```
As shown above, the script will cycle through all attached projects (here just WCG) and detach from them, then stop BOINC nicely and proceed to remove the instance directory.

### Limitations
- starts BOINC instances under root for now (*to be fixed*)
- won't control default BOINC instance, maybe implement start/stop through system commands

[...]
**Work in progress!**
