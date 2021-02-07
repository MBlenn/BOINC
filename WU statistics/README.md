## get_validated 
This rather simple script downloads a set number of WUs from the results page of a BOINC host.
It computes the average run time, average credit, total daily credit per core and the overall system credits from this.  
The number of CPU cores, CPU information and OS are scraped from the show_host_detail.php

No support for multithreaded WUs or parallel running GPU apps.

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
