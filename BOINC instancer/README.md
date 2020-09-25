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
-E $ARG - enable local environment, load config from file/URL
-S $ARG - start specified instance
-T $ARG - stop/terminate specified instance
-D $ARG - delete specified instance (detach projects, remove instance)
```

Internally Bash's getopts parses the options and invokes the required routines. Small letter options require no further input, while capital options require further information.

A host just needs the script itself and an archive containing client and account configuration files. BOINC must be installed, so that *boinc* and *boinccmd* are available via %PATH. Beyond that, there is no interaction with the default BOINC installation. 

#### Example 
```
INSTANCE        PID    State   CPU  GPU  NET NCPU  CPU%   BUFFER PRJ  WUs  DL* ACT  UPL  RTR boincmgr call                                                        
boinc_20002 2149420  Running  SUSP  ATP  ATP  124                  0    0   0    0    0    0 cd /opt/boinc/instance_homes/boinc_20002; boincmgr -m -g 20002 -d /opt/boinc/instance_homes/boinc_20002 &
boinc_29315 2155415  Running   ACT SUSP  ACT  128  10.0 10.0/5.0   2    0   0    0    0    0 cd /opt/boinc/instance_homes/boinc_29315; boincmgr -m -g 29315 -d /opt/boinc/instance_homes/boinc_29315 &
boinc_31416 2120013  Running   ACT  ACT  ACT   24  92.0 10.0/0.0  16 1918   0   23    0    2 cd /opt/boinc/instance_homes/boinc_31416; boincmgr -m -g 31416 -d /opt/boinc/instance_homes/boinc_31416 &
boinc_39106             Down
boinc_43448             Down
boinc_49094             Down
Load average: 22.80/23.02/23.20                                      1918   0   23    0    2

 ACT = Active (Run always)
 ACP = Run based on preferences
 ATP = Network access based on preferences
SUSP = suspended
 RTR = Ready to report
```


#### Limitations
- starts BOINC instances under root for now (*to be fixed*)

[...]
More documentation to come during next days!
