# work in progress

## get_validated 
This rather simple script downloads a set number of WUs from the results page of a BOINC host.
It computes the average run time, average credit, total daily credit per core and the overall system credits from this.  
The number of CPU cores, CPU information and OS are scraped from the show_host_detail.php

No support for multithreaded WUs or parallel running GPU apps.
No support for Einstein@home (Drupal based) and Yoyo (ancient server code) yet.

Download the script and make it executable, then add the full URL in quotation marks:

```
./get_validated.sh "https://www.sidock.si/sidock/results.php?hostid=1045&offset=0&show_names=0&state=0&appid=2"
0 20 40 60 80 - download complete. Calculating...
Application:               CurieMarieDock on BOINC
CPU:           AMD Ryzen 9 3900X 12-Core Processor
OS:                Linux Ubuntu Ubuntu 20.04.1 LTS
Results fetched:                               100
Average duration (s):                       1662.8
Average credit:                              22.32
Number of reported cores:                       24
Per core per day:                             1158
Per system per day:                          27792
```

## get_wcg_averages

With WCG lacking host statistics comparable to normal BOINC installations, different scripting is required to do the job.  
the get_wcg_averages script requires the users user name and password, as well as the verification code to be configured in the script.  
By default, the script assumes 8 threads and prints out the hostname as known to WCG. Android hostnames like "android_da5ed620" make it difficult to find the actual device. A lookup table can hence be configured to use the correct amount of threads and show more descriptive host information.

```
R9-3900x_Linux64 (24 threads)
            Project: #WUs: ~Runtime: ~Credits: C/d/Core: C/d/Host:
                MCM1   294   7816.95     95.91   1059.80  25435.20
                OPN1    20   5177.03     65.59   1094.04  26256.96
                SCC1  1000   3182.44     61.02   1656.08  39745.92

Odroid_XU4_2_4xA15+4xA7 (8 threads)
            Project: #WUs: ~Runtime: ~Credits: C/d/Core: C/d/Host:
                OPN1     3  41142.55     75.24    158.00   1264.00
```

