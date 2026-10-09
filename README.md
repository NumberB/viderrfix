# viderrfix (vef.sh)

A robust Tvheadend post-processing script written in BASH to repair _basic_ container recording errors using `ffmpeg` and perform automated commercial detection using `comskip`.

Sometimes recordings aren't perfect. Even with great reception, signal drops can introduce audio/video data errors into MPEG-TS (`.ts`) files. `vef.sh` checks Tvheadend DVR logs, stream-copies corrupted files to repair timestamp/container issues, and optionally runs Comskip using smart EPG profile matching—all with kernel-level process safety and non-blocking playback protection.

---

## What's New in v4

1. **Comskip Integration & Smart Profiling**:
   * Automated commercial scanning using `comskip`.
   * **Smart Profile Matching**: Dynamically selects specific `comskip.ini` profiles based on EPG metadata rules (`title`, `channelname`, or `alltext` which checks title, subtitle, and description).
   * **Sidecar File Management**: Automatically moves generated `.edl`, `.txt`, or `.vdr` files to the recording directory alongside the video.
2. **Two-Flow Queue Architecture**:
   * **Path A (Errors ≥ Threshold)**: Stream-copies video into a temporary folder to fix errors, runs Comskip on the clean file in `tmpdir`, then swaps the video and moves sidecars together.
   * **Path B (Errors < Threshold)**: Skips `ffmpeg` repair entirely and runs Comskip in-place directly on the recording file.
3. **Enhanced Concurrency & Safety**:
   * Replaced `pidof` with kernel-level `flock` locks to prevent duplicate cron runs.
   * Uses `lsof` pre-flight checks to detect active write locks (preventing premature processing of active recordings).
   * Language-agnostic DVR log parsing using `jq`.
4. **Expanded CLI Controls**:
   * Added `-r` (Repair Only), `-c` (Comskip Only), and `-b` / `-f` (Both).
   * Consolidated interactive CLI prompts for previously processed files or overwriting existing sidecars.
   * Backgrounding support (`Ctrl+Z`, then `bg`) when waiting for active playback locks (`inotifywait`) to close.

## AI use disclosure
I've worked on this script off and on since 2018, long before AI use became mainstream. All the core logic and commands on this script have been tested for years against my own setup, but I wanted to disclose that I did use AI assistance with this v4 update to include comskip integration and other recent updates. I know some are sensitive to this but I wouldn't have time to update this otherwise.
   
---

## Prerequisites

* **BASH** (4.0 or newer)
* **`ffmpeg`**: Required for video container stream-copy repair.
* **`jq`**: Required for parsing Tvheadend DVR log JSON files.
* **`lsof`**: Required for pre-flight active write/read handle checks.
* **`flock`** (part of `util-linux`): Required for script concurrency locking.
* **`inotifywait`** (optional but recommended): Prevents overwriting files while actively being watched.
* **`comskip`** (optional): Required for commercial detection. If missing, commercial scanning is auto-disabled.

### Installation of Dependencies

**Debian / Ubuntu**:
```bash
sudo apt-get update
sudo apt-get install ffmpeg inotifywait jq lsof util-linux comskip
```
Note: "comskip" typically isn't included with Debian packages and will likely need to be compiled from source.

**RHEL / Fedora / Rocky**
```bash
sudo dnf install ffmpeg inotify-tools jq lsof util-linux comskip
```


### Download the script and place it somewhere accessible to the user running the tvheadend application 

_I'm partial to /usr/local/bin_

```bash
cd /usr/local/bin
wget https://raw.githubusercontent.com/NumberB/viderrfix/master/vef.sh
chmod 755 vef.sh
```
Optional: `chown tvheadend.tvheadend /usr/local/bin/vef.sh` (put in the correct ownership information for your system!)

### Edit the basic settings towards the top of the script
```bash
nano /usr/local/bin/vef.sh
#(or)
vim /usr/local/bin/vef.sh
#(or whatever editor you prefer)
```
- Specify the root of the tvheadend config directory `tvhhome="/home/tvheadend"`
- Specify how many data errors will trigger the script to process the video `dvrerrorthreshold=20`
- Disable comskip by changing: enable_comskip="yes"
- Set comskip default ini: comskip_ini_default="$tvhhome/comskip-profiles/comskip-default.ini"
- Set comskip profile dir: comskip_ini_dir="$tvhhome/comskip-profiles"
- Update comskip smartmatching rules under `declare -a comskip_rules=(`
    NOTE: "alltext" searches "title", "subtitle" & "description"
- If you want, change where the log file resides `logloc="${tvhhome}/viderrfix.log"`
- If you want, turn on debugging in the log `logdebug=0` (1 turn's it on)
- If this is your first run or you are still testing, leave `testrun="yes"` as "yes", but when you are ready to use the script remove "yes" or change it to "no" (_This is set to "yes" by default for your protection_)

### When the script is setup (and tested), set it to run in tvheadend:

Open up the tvheadend web console, and navigate to `Configuration > Recordings > Digital Video Recording Profiles`

_If you wish, create a new profile to test the post-processing script_

Select the profile you want to set this script to run under, and in the box "Post-Processor Command:" enter in:
```bash
/usr/local/bin/vef.sh "%f"
```
With the correct path to where you placed the vef.sh script

**Yes, you _MUST_ quote the "%f" argument for file paths to process correctly!**

Click `Save`

### Update the crontab to process the queue
```bash
crontab -e -u ${hts/tvheadend}
#Example: "crontab -e -u tvheadend"
```
That is, the user that is running tvheadend, which is typically 'hts' or 'tvheadend'.

Insert these lines into the crontab of the tvheadend user and then save
```bash
#VEF Processing every half hour
2,32 * * * * /usr/local/bin/vef.sh -p
```
Feel free to update the processing time to whatever you prefer. This is going to process 2 minutes and 32 minutes after the hour every hour.

## Usage
```bash
Usage: vef.sh [OPTION] [FILEPATH]

Automated Queue Execution:
  vef.sh "%f"                  Queue a recording file from Tvheadend.
  -p, --process                Process all queued recordings (used by cron).
  -l, --list                   List all files currently in the queue.

Manual Execution Overrides:
  -r, --repair <file>          Run ONLY the ffmpeg video repair stream copy.
  -c, --comskip <file>         Run ONLY Comskip commercial detection in-place.
  -b, -f, --both <file>        Run BOTH video repair and Comskip on the target file.
  -h, --help                   Display usage information.
```


## Testing & Manual Processing

You can test the script manually on any existing recording without waiting for Tvheadend post-processor events.

1. Run a Manual Check (Both Repair & Comskip):
```Bash
/usr/local/bin/vef.sh -b "/path/to/recording.ts"
```

2. Run Comskip Only on a Clean Recording:
```Bash
/usr/local/bin/vef.sh -c "/path/to/recording.ts"
```

3. Active Playback Behavior:
If a file is currently being watched while you trigger a manual repair (`-r` or `-b`), `vef.sh` will process the file in a temporary folder and pause at the swap stage. It will output:
```Plaintext
File is currently open for reading (active playback).
The script will process the file but will wait to swap the video until playback finishes.
Tip: Press Ctrl+Z, then type 'bg' to run this wait in the background.
```

This releases the global process lock so cron jobs can continue processing in the background while the manual job waits for the viewer to finish.


## Testing the process 
NOTE: These instructions have been adapted for the most recent version but not tested!

1. Set required variables in the script
    1. Tvheadend home (where the config directory resides)
    2. Data error threshold (set to 0 to always process)
    3. Leave testrun set to "yes"
    4. If you have any issues or just want to turn on debug `logdebug=1`
    
2. Find a recording you know has a few data errors (or just pick one recent as this is a test)

3. Become the user that tvheadend runs as
    1. If this isn't possible due to the user not having a shell set, skip to step 6
```bash
sudo su - tvheadend
# or commonly 'hts'
```

4. Run the script manually:
```bash
/usr/local/bin/vef.sh -b "/rec/dailyshows/Jeopardy!-45.1 WBFFDT2017-07-05-.E3775.ts"
```

5. Go look through the log and see what happened! You want to see it there are any warnings or errors or if variables aren't getting set (debug will show you this). By default the log will be in the tvheadend home directory you set.
```bash
less /home/tvheadend/vef.log
```

6. If you can't run step 3 as the user in the shell, that's alright, we can tell sudo to run it as that user:
    1. The "tvheadend" at the end of the command is the user to run this command as
```bash
sudo su -s /bin/bash  -c '/usr/local/bin/vef.sh -b "/rec/dailyshows/Jeopardy!-45.1 WBFFDT2017-07-05-.E3775.ts"' tvheadend
```

7. When testing is all done change testrun  to "no" and the processed file will overwrite the original recording.
