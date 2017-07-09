# viderrfix
TVHeadEnd post processing script to fix _basic_ container recording errors

Sometimes recordings aren't perfect. Even if you have great reception and typically conditions are excellent; inevitably there will be a fart in the solar wind and you will get errors in your recording. This script is to help with those. It uses ffmpeg to create a stream copy of recording which is usually enough to fix most container errors. It isn't a "video fix" end-all be-all by any means, but it is better than nothing. If your recording was too terrible then there's nothing that can be done.

This script runs in the bash shell and is called on by tvheadend as a post-processor command. It compares the amount of data errors to a threshold you set and if met it will process the recording and then overwrite the original recording with your processed copy. This generally makes the file a little bigger (seems to be about 5-8% larger), but it does help troublesome files to play more reliably. 

Presently this will only work with standard recordings, which are in mpeg2 transport stream format (mpegts). In tvheadend this is the default recording method (aka pass-thru).

## How to use

### Prerequisites

Obviously the BASH shell as this is a BASH script, though I haven't tested BASH 3 so some updates may be required if you wanted to run this on an older version.

You **must** have `ffmpeg` installed and in the PATH of the user running the script (such as 'tvheadend').

You *should* have `inotifywait` installed and in the PATH of the user running the script, as then you won't overwrite a recording you may already be watching!

_Ubunutu / Debian_

```
apt-get install ffmpeg inotifywait
```
_RHEL / CentOS_
```
yum install ffmpeg inotifywait
```

### Download the script and place it somewhere accessible to the user running the tvheadend application 

_I'm partial to /usr/local/bin_

```
cd /usr/local/bin
wget https://raw.githubusercontent.com/NumberB/viderrfix/master/viderrfix.sh
chmod 755 viderrfix.sh
```
Optional: `chown tvheadend.tvheadend /usr/local/bin/viderrfix.sh` (put in the correct ownership information for your system!)

### Edit the basic settings towards the top of the script
```
nano /usr/local/bin/viderrfix.sh
(or)
vim /usr/local/bin/viderrfix.sh
(or whatever editor you prefer)
```
- Specify the root of the tvheadend config directory `tvhhome="/home/tvheadend"`

- Specify how many data errors will trigger the script to process the video `dvrerrorthreshold=20`

- If you want, change where the log file resides `logloc="${tvhhome}/viderrfix.log"`

- If you want, turn on debugging in the log `logdebug=0` (1 turn's it on)

- If this is your first run or you are still testing, leave `testrun="yes"` as "yes", but when you are ready to use the script remove "yes" or change it to "no" (_This is set to "yes" by default for your protection_)

### When the script is setup (and tested), set it to run in tvheadend:

Open up the tvheadend web console, and navigate to `Configuration > Recordings > Digital Video Recording Profiles`

_If you wish, create a new profile to test the post-processing script_

Select the profile you want to set this script to run under, and in the box "Post-Processor Command:" enter in:
```
/usr/local/bin/viderrfix.sh "%f" "%e"
```
With the correct path to where you placed the viderrfix.sh script

**Yes, you _MUST_ quote the "%f" argument for file paths to process correctly!**

Click `Save`

That's it!



## How to test

You should test this first obviously, and here's how you can do that:

1. Set required variables in the script
    1. Tvheadend home (where the config directory resides)
    2. Data error threshold (set to 0 to always process)
    3. Leave testrun set to "yes"
    4. If you have any issues or just want to turn on debug `logdebug=1`
    
2. Find a recording you know has a few data errors (or just pick one recent as this is a test)

3. Become the user that tvheadend runs as
    1. If this isn't possible due to the user not having a shell set, skip to step 6
```
sudo su - tvheadend
```

4. Run the script manually:
```
/usr/local/bin/viderrfix.sh "/rec/dailyshows/Jeopardy!-45.1 WBFFDT2017-07-05-.E3775.ts" "Test"
```

5. Go look through the log and see what happened! You want to see it there are any warnings or errors or if variables aren't getting set (debug will show you this). By default the log will be in the tvheadend home directory you set.
```
less /home/tvheadend/viderrfix.log
```

6. If you can't run step 3 as the user in the shell, that's alright, we can tell sudo to run it as that user:
    1. The "tvheadend" at the end of the command is the user to run this command as
```
sudo su -s /bin/bash  -c '/usr/local/bin/viderrfix.sh "/rec/dailyshows/Jeopardy!-45.1 WBFFDT2017-07-05-.E3775.ts" "Test"' tvheadend
```

7. When testing is all done change testrun  to "no" and the processed file will overwrite the original recording (and we won't have to do anything to tvheadend because it doesn't know any better in regards to the file on the system)

