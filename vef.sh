#!/usr/bin/env bash
#
# vef.sh, which is: viderrfix.sh | Revision 3
#
# Post Processing script for tvheadend on recorded .ts files (mpeg2)
# (but could be updated to process however you want)
#
# Usage (TODO)

####################
# USAGE INSTRUCTIONS

# 1) ADD THE PROCESSING TO THE CRONTAB!
# "crontab -e -u ${hts/tvheadend}" #that is, the user that is running tvheadend, which is typically 'hts' or 'tvheadend'
#VEF Processing every half hour
#2,32 * * * * /usr/local/bin/vef.sh -p

# 2) ADD THE SCRIPT PATH AND FULL PATH TO RECORDING VARIABLE TO EACH RECORDING PROFILE
# In the tvheadend web ui, go to "Configuration > Recording > Digital Video Recording Profiles"
# In each profile you want to have video processed:
#  Go to "Miscellaneous Settings > Post-processor command:"
#  In that field, input: /usr/local/bin/vef.sh "%f"
#  Click "Save"
#  Repeat for other profiles
# Note for post-processor commands: https://tvheadend.org/projects/tvheadend/wiki/Tvheadend_post_recording_scripts
####################

### User set variables (You need to fill these out!!!)
##############################################################################

# Where does your base tvheadend config reside
declare -r tvhhome="/var/lib/tvheadend/"
# At how many data errors do we process the video?
declare -r -i dvrerrorthreshold=20

# Where would you like this script to log to?
declare -r logloc="${tvhhome}/vef.log"
declare -r -i logdebug=1 # 0 = no debug log, 1 = yes debug log

# Uncomment and set this if you want to change where temporary files are set while being processed
declare tmpdirloc="/tvhtmp"

# Queue and queue log location directory
declare -r qloc="${tvhhome}/.vef"
declare -r qdir="${qloc}/queue"
declare -r plogloc="${qloc}/processed.log"

# Is this a testrun?
# We will process as usual but NOT overwrite the original recording (we won't keep the processed video either)
declare -r testrun="no" 
# Do we wait if the video is currently being used to overwrite it with our processed version?
# If "no" then the recording will be overwritten immediately after processing is finished
declare -r writewait="yes"      #yes or no

# ffmpeg log level
declare ffmpegloglevel="error"
if [ ${logdebug} = 1 ]; then
  declare ffmpegloglevel="warning"
fi




### Functions
##############################################################################

#
# Date
# For the logger
function logdate () {
  date "+%Y/%m/%d  %H:%M:%S"
}

# Logger
function veflog () {
  echo $(logdate) [${mypid}] "${1}" >> ${logloc}
}

function debug () {
  if [ ${logdebug} = 1 ]; then
    if [ -n "${1}" ]
    then
      IN="${1}"
    else
      read IN # Reads a string from stdin and stores it in a variable
    fi

    echo $(logdate) [${mypid}] "_DEBUG_ ${IN}" >> ${logloc}
  fi
}

function clean() {
    # BASH 4+ function
    local a=${1//[^[:alnum:]]/}
    echo "${a,,}"
}

function checkifproccessing () {
    if pidof -o %PPID -x "vef.sh">/dev/null; then
      veflog "A vef.sh process has been found already running, exiting..."
      exit 1
    fi
}

# Check log file
# If it doesn't exist, create a blank file to use, and if that fails, exit script
function checklog () {
  if [ ! -f "${logloc}" ];then
    touch ${logloc} || { echo "Cannot create log file! Check path, filename & permissions!!!"; exit 1; }
    sleep 1
    veflog "Script log file __${logloc}__ does not exist; creating it."
  fi
}

function verifymeta () {
  if [ ! -d "${qloc}" ];then
    veflog "Metadata directory __${qloc}__ does not exist; creating it."
    mkdir -p ${qloc} || { echo "Cannot create __${qloc}__ directory! Check path, filename & permissions!!!"; exit 1; }
    chmod 750 ${qloc} || { echo "Error changing permissions on __${qloc}__ directory! Check path, filename & permissions!!!"; }
  fi
  if [ ! -d "${qdir}" ];then
    veflog "Queue directory __${qdir}__ does not exist; creating it."
    mkdir -p ${qdir} || { echo "Cannot create __${qdir}__ directory! Check path, filename & permissions!!!"; exit 1; }
    chmod 750 ${qdir} || { echo "Error changing permissions on __${qdir}__ directory! Check path, filename & permissions!!!"; }
  fi
  if [ ! -f "${plogloc}" ];then
    veflog "Processs log file __${plogloc}__ does not exist; creating it."
    touch ${plogloc} || { echo "Cannot create process log file! Check path, filename & permissions!!!"; exit 1; }
  fi
}

#function checkplog () {
#  debug "Checking if file is in the processed log"
#  grep -q "${filepath}" ${plogloc}
#}

function checkplogproc () {
  debug "Checking the processed log for if this file has been processed"
  grep -E -q "^Processed:.*${filepath}$" ${plogloc}
}

function checkplogqueue () {
  debug "Checking the processed log for if this file has been queued"
  grep -E -q "^Queued:.*${filepath}$" ${plogloc}
}

function buildqueuefile () {
  declare timestamp="$(date '+%y%m%d%H%M%S')" 
  #declare -r recfile="$(basename "${filerecloc}")" # actual filename of the recording (alternative method)
  declare justfilename="${filepath##*/}" # actual filename of the recording [BASH]
  declare cleanedfilenamestart="$(clean ${justfilename:0:8})" # send first 8 characters of filename to the clean function [BASH]
  declare cleanedfilenameend="$(clean ${justfilename:0-6})" # send last 6 characters of filename to the clean function [BASH]
  declare queuefile="${timestamp}_${cleanedfilenamestart}_${cleanedfilenameend}"

  if [ -f ${queuefile} ];then
    veflog "! queuefile already exists??? __${queuefile}__ exists somehow, so we are going to exit"
    exit 2
  else
    echo "${filepath}" > ${qdir}/${queuefile}
    echo "Queued:${timestamp},${filepath}" >> ${plogloc} # Record the the processed log that this is queued so we can avoid multiples that could break things
    veflog "Queued as __${queuefile}__"
    debug "Full path: Queued ${qdir}/${queuefile}"
  fi
}


### Queue input file
function queuefile () {
  if [ -f "${filepath}" ];then

    # check plog for previous processing
    checkplogproc
    if [ "$?" -gt 0 ];then
      # check plog for previous queueing of this file (don't double queue!)
      checkplogqueue
      if [ "$?" -gt 0 ];then
        veflog "Queue file __${filepath}__ for processing"
        buildqueuefile
      else
        veflog "File __${filepath}__ logged as queued already, skipping"
      fi
    else
      veflog "File __${filepath}__ logged as processed already, skipping"
    fi
      
  else
    veflog "File path __${filepath}__ does not appear to exist so it will not be queued"
    debug "! Check to see if the script is being passed a properly quoted path/filename"
    #(TODO) remove queue file and log it instead of failing
    #usage (TODO)
    exit 1
  fi
}


### Process queue functions

# Read the oldest file in the queue, or report queuenull
function queuereadlast () {
  local queuefile=$(/bin/ls -tr ${qdir} | /bin/head -1)
  if [ -z "${queuefile}" ]; then
    printf "queuenull"
  else
    printf "${queuefile}"
  fi
}

# Get DVR Log file UUID
function getdvruuid () {
  /bin/grep -l "${filerecloc}" "${tvhdvrlog}"/* 2>&1
  #if [ "$?" -gt "0" ]; then
  #  veflog "Warning: Something might be wrong with the dvr log files permissions OR the script might not be parsing the file output correctly OR there might not be a log for this recording. Is the correct tvheadend path set and/or does this user have the proper permissons?"
  #  debug "func getdvruuid filerecloc = ${filerecloc}"
  #  debug "func getdvruuid command = grep -l ${filerecloc} ${tvhdvrlog}/*"
  #fi
}

# 'getcount'
# We are looking through the dvr log file to pull a numerical value from the matching field
# By default this is "data_errors" because that's how many audio/video errors are in the recorded file
# You _could_ supply a different search pattern to this function to retrive other dvr log variables,
# but this regex is only for numbers
function getcount () {
  local re='"([^"]*)": ([0-9]+),' # Regex to parse tvheadend dvr log format, looking for numbers
  local search=${1:-"data_errors"} # set our search term that we are going to parse
  debug "func getcount: search = ${search}"
  debug "func getcount filerecloc = ${filerecloc}"
  debug "func getdvruuid command = grep -l ${filerecloc} ${tvhdvrlog}/*"
  local dvruuid="$(getdvruuid)"
    if [ "$?" -gt "0" ]; then
      veflog "Warning: Something might be wrong with the dvr log files permissions OR the script might not be parsing the file output correctly OR there might not be a log for this recording. Is the correct tvheadend path set and/or does this user have the proper permissons?"
    fi

    #debug "Bash rematch search through dvruuid file"
  [[ $(grep ${search} "${dvruuid}") =~ ${re} ]] && local count=${BASH_REMATCH[2]}
    debug "func getcount: ${search} = ${count}"
  printf ${count}
}

# check if open
# Uses `inotifywait` to see if the recording is open
# If the file is NOT open the exit code ("$?") returns 2 (as per the inotifywait man page)
# A filename MUST be provided as an argument
function checkifopen () {
  /bin/inotifywait -t 2 "${1}" >/dev/null 2>&1 # set it to watch for 2 seconds if anything is happening to the file
  echo $?
}

# settemp
# Setup our temp directory
function settemp () {
  if [ -z "${tmpdirloc}" ];then
    thistmpdir="${tmpdirloc}"
  else
    thistmpdir="${recdir}"
  fi
    
  tmpdir=$(mktemp -d "${thistmpdir}/.XXXXXXXXXXXX")
 # FOR TESTING! This line would put the temp dir in the same directory that this script runs
 # Comment out the above line if you are going to do this
  #tmpdir=$(mktemp -d "$( dirname "${BASH_SOURCE[0]}" )/.XXXXXXXXXXXX")
  debug "Temporary directory set at ${tmpdir}"
}

# rmtemp
# Removes the temp directory with all files inside if the tmpdir variable is set
function rmtemp () {
  if [ ! -z "${tmpdir}" ]; then
    debug "Long listing of tmpdir: (post move, pre directory removal)"
    debug "$(ls -l "${tmpdir}")" # This tells you if anything was in the directory being removed
    rm -rf "${tmpdir}"
    debug "Temporary directory ${tmpdir} removed"
    unset tmpdir
  fi
}

# Process the recording
function process () {
  # Verify our temp directory actually exists before starting
  if [ ! -d "${tmpdir}" ]; then
    veflog "The temp directory doesn't appear to exist - can't process video. Permissions issue?"
    exit 4
  fi

  debug "func process: recfile var = ${recfile}"
  # Process command
  # This is simply a "stream copy" to cleanup the video container meta-data, which is very fast and more times then not enough to make the video watchable, but doesn't help if the player can't work through the encoding errors
  veflog "Begin processing (ffmpeg stream copy) file: ${recfile}"

  ffmpeg -err_detect ignore_err -loglevel ${ffmpegloglevel} -f mpegts -i "${filerecloc}" -c copy "${tmpdir}/${recfile}" >>${logloc} 2>&1 || { veflog "Warning: Something happened when trying to process the recording"; }

  # options explained:
  #  "-err_detect ignore_err" is practically undocumented but apparently helps if there are filesystem errors (will ignore and keep going).
  #  "-loglevel" is the amount of ffmpeg output going into our log file. This setting keeps it to what would stop ffmpeg, like an error.
  #  "-f mpegts" is specifying that this recording is the format of "mpegts". This is necessary because certain filenames in recordings (such as "Jeopardy!" will break ffmpeg's auto detection of file type (the .ts on the end).
  #  "-i "${filerecloc}"" input file, which in our case is the actual location of our recording.
  #  "-c copy "${tmpdir}/${recfile}"" This specifies this is to be a stream copy and where to put the output file.
  #  ">>${logloc} 2>&1" This is shell redirection, it means all ffmpeg output goes into our logfile, and all errors (stderr) go into normal output (stdout), but in ffmpeg's case all output is stderr I believe. This should be minimal to nothing with the loglevel set to fatal.
  veflog "Finished processing"
}


# After processing is finished, overwrite the original recording with our freshly processed one
function movefile () {
  # Check to see if the recording is open if "writewait=yes"
  if [ "${writewait}" == "yes" ]; then
    local -i ifopen="$(checkifopen "${filerecloc}")"
    if [ "${ifopen}" != "2" ]; then
      veflog "Recording appears to be open. Waiting for it to close..."
      inotifywait -e close "${filerecloc}" >/dev/null 2>&1 # inotifywait is _blocking_ until the file closes
      sleep 3 # short break after file closes
      veflog "Recording has closed"
    else
      veflog "Recording not open, proceding"
      debug "Long listing of tmpdir: (pre move; the processed video should show here)"
      debug "$(ls -l "${tmpdir}")" # This should list the video file before it gets moved
    fi
  fi

  # Verify our new file exists before moving forward
  if [ ! -f "${tmpdir}/${recfile}" ]; then
    veflog "The processed video doesn't appear to exist or is inaccessble, exiting."
    exit 5
  elif [ ! -s "${tmpdir}/${recfile}" ]; then
    veflog "The processed video appears to be empty - enable debug and check if ffmpeg is working. Exiting."
    exit 5
  fi

  # Test run?
  if [ "${testrun}" == "yes" ]; then
    veflog "Test run! ---> skipping overwrite! < ---"
  else
    # Overwrite old video with our processed video
    # This get's around having to interact with tvheadend
    veflog "Overwriting recording with processed video file"
    /bin/mv "${tmpdir}/${recfile}" "${filerecloc}" || veflog "Warning: Error code after moving the video, it might not have overwritten!"
  fi
}


# Process Queue
function processqueue () {
  # The 'queuereadlast' function will spit out the oldest queued filename until there isn't one, in which case it returns "queuenull". We'll loop through that queue directory until we hit the null queue.
  procqueuefile="$(queuereadlast)" 
  local loopbreak=0 #To break out of any endless loops
  local looplimit=5 #Arbitrary number

  while [ "${procqueuefile}" != "queuenull" ]; do
    declare filerecloc="$(/bin/cat ${qdir}/${procqueuefile})"

    #declare -r recdir="$(dirname "${filerecloc}")" # directory where the recording resides (alternative method)
    declare recdir=${filerecloc%/*} # directory where the recording resides [BASH]
    #declare -r recfile="$(basename "${filerecloc}")" # actual filename of the recording (alternative method)
    declare recfile=${filerecloc##*/} # actual filename of the recording [BASH]

    # Get recording error count
    errorcount=$(getcount)
    if [ -z ${errorcount} ]; then
      veflog "!ERROR! No error count found in the dvr log for the video file, so the recorded file was probably deleted from tvheadend"
      debug "In func processqueue after calling on func getcount"
      exit 1
	#TODO: REPLACE this error with a check to see if the rec still exists and log and remove queuefile if it no longer exists, and then move on. Otherwise this gets stuck in an endless loop of erroring here on the same file.
    fi
  
    # Does this recording have more errors then our threshold count? If so, process. If not, don't.
    if [ "${errorcount}" -ge "${dvrerrorthreshold}" ]; then
      veflog "Error count (${errorcount}) meets or exceeds set threshold (${dvrerrorthreshold}), processing..."
      settemp # create our temp directory to store the processed video
      process # process the video, putting it into the temp directory
      movefile # overwrite the processed video over the original video
      rmtemp
      # record that we've processed this video file in the process log
      declare timestamp="$(date '+%y%m%d%H%M%S')"
      if [ "${testrun}" == "yes" ]; then
        echo "TESTRUN:::(wouldhave)Processed:${timestamp},${procqueuefile},${filerecloc}" >> ${plogloc}
      else
        echo "Processed:${timestamp},${procqueuefile},${filerecloc}" >> ${plogloc}
      fi
    else
      veflog "Error count (${errorcount}) is less than set threshold (${dvrerrorthreshold}), or there is an error somewhere, skipping processing"
      #echo "Skipped   ${queuefile} :: ${filerecloc}" >> ${plogloc}
    fi

    #Remove the queue file, because it is either now processed or skipped
    if [ "${testrun}" == "yes" ]; then
      veflog "Test run! ---> skipping removal of queue file! < ---" 
      veflog "Test run! ---> exiting, or else will be in an endless loop of this oldest queue file"
      exit
    else
      rm ${qdir}/${procqueuefile} || { ((${loopbreak}+=1)); veflog "Could not remove queue file for some reason, so something is wrong [${loopbreak}]"; }
    fi

    if [ ${loopbreak} -gt ${looplimit} ]; then
      break
      veflog "!ERROR! Something is wrong! Looplimit (${looplimit}) iteration reached, so we are breaking the endless loop and exiting the script"
      exit 5
    fi

    #queue next file
    procqueuefile="$(queuereadlast)"
  done #end while loop
}

function checkffmpeg () {
  command -v ffmpeg >/dev/null 2>&1 || { veflog "This script requires the `ffmpeg` program to process video. Exiting. "; exit 1; }
}

# Cleanup functions

function closeup () {
  rmtemp
  debug "### Script run complete ###"
  exit
}

function sig_closeup () {
  veflog "Caught signal to close NOW, exiting..."
  closeup
}



### TRAP
##############################################################################
# Because we don't like to leave behind a mess

trap closeup EXIT
trap sig_closeup INT QUIT TERM


### Script variables & validation
##############################################################################

declare -r mypid="$$" # used for logging
declare -r tvhdvrlog="${tvhhome}/config/dvr/log" # need to know where to find the dvr logs


# Validate necessary external applications
command -v inotifywait >/dev/null 2>&1 || { writewait="no"; veflog "This script requires the `inotifywait` program to wait to overwrite the recording with the processed video. Setting to not wait."; }




##############################################################################
#  Main
##############################################################################
checklog #to ensure logging works
verifymeta #to ensure our metadata directory and file exist

case "${1}" in
  -l | --list )
    echo "List queued files"
    echo "not implemented yet" #(TODO)
    ;;
  -f | --file )
    # Validate $2
    # Process file
    echo "not implemented yet" #(TODO)
    ;;
  -p | --process )
    # read from queue until no more queue or error out
    checkifproccessing
    checkffmpeg
    processqueue
    ;;
  * )
    declare filepath="${1}"
    queuefile
    ;;
esac
