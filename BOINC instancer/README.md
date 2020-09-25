# BOINC instancer

This script helps to manage parallel BOINC instances on the same host.  
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

A host just needs the script itself and an archive containing client and account configuration files.



#### Limitations
- starts BOINC instances under root for now (*to be fixed*)

[...]
More documentation to come during next days!
