#!/usr/bin/env bash
#
# viderrfix.sh | Version 1
#
# Post Processing script for tvheadend on recorded .ts files (mpeg2)
# (but could be updated to process however you want)
#
# Usage:
# This script is setup to be called upon by tvheadend after a recording has completed. It uses two arguments: "%f" for the full path to the recording and "%e" for the error message.
# ex: /usr/local/bin/viderrfix.sh "%f" "%e"
# Yes, you MUST quote the arguments for file paths to process correctly!
#
# Some ideas inspired by the BASH3 Boilerplate
# http://bash3boilerplate.sh/#authors
#

# See shell execution commands - uncomment this below if you need to see *exactly* what the script is doing
# This is good for if you are manually running the script but not good if being spawned by tvheadend
#set -x

### User set variables (You need to fill these out!!!)
##############################################################################

# Where does your base tvheadend config reside
declare -r tvhhome="/home/tvheadend"

# At how many data errors do we process the video?
declare -r -i dvrerrorthreshold=20

# Where would you like this script to log to?
declare -r logloc="${tvhhome}/viderrfix.log"
declare -r -i logdebug=0 # 0 = no debug log, 1 = yes debug log

# Is this a testrun?
# We will process as usual but NOT overwrite the original recording (we won't keep the processed video either)
declare -r testrun="yes"

# Do we wait if the video is currently being used to overwrite it with our processed version?
# If "no" then the recording will be overwritten immediately after processing is finished
declare -r writewait="yes"      #yes or no






### Functions
##############################################################################

#
# Date
# For the logger
logdate () {
  date "+%Y/%m/%d  %H:%M:%S"
}

# Logger
function logger () {
  echo $(logdate) [${mypid}] "${1}" >> ${logloc}
}

function debug () {
  if [ ${logdebug} = 1 ]; then echo $(logdate) ${mypid} "_DEBUG_ ${1}" >> ${logloc};fi
}

# Check log file
# If it doesn't exist, create a blank file to use, and if that fails, exit script
function checklog () {
  if [ ! -f "${logloc}" ];then
    touch ${logloc} || { echo "Cannot create log file! Check path, filename & permissions!!!"; exit 1; }
    sleep 1
    logger "Opening new log file"
  fi
}



#
# Validate input variables
function validatevars () {
  [[ $# -gt 2 ]] && logger "Warning: More than two variables being passed"

  # Taking the easy way out and declaring these variables in a function (yeah yeah I know)
  filerecloc=${1}
  fileerrorstat=${2}
  debug "func validatevars: filerecloc = ${filerecloc}"
  debug "func validatevars: fileerrorstat = ${fileerrorstat}"

  # Does the specified recording file input variable exist?
  [[ -f "${filerecloc}" ]] || { logger "FATAL: File > ${filerecloc} < does not exist, exiting script "; exit 1; }

  # Log the tvheadend error message in our log
  logger "tvheadend recording error message: ${fileerrorstat}"

  # Check to see if our tvheadend DVR log directory is accessible
  [[ -d ${tvhdvrlog} ]] || { logger "FATAL: tvheadend config dvr directory not accessible or found. Is your tvheadned home variable set correctly? "; exit 1; }
}


#
# Get DVR Log file UUID
function getdvruuid () {
  grep -l "${filerecloc}" "${tvhdvrlog}"/* 2>/dev/null
  if [ "$?" -gt "0" ]; then
    logger "Warning: Something might be wrong with the dvr log files permissions OR there might not be a log for this recording. Is the correct tvheadend path set and/or does this user have the proper permissons?"
  fi
}

#
# getcount
# We are looking through the dvr log file to pull a numerical value from the matching field
# By default this is "data_errors" because that's how many audio/video errors are in the recorded file
# You _could_ supply a different search pattern to this function to retrive other dvr log variables,
# but this regex is only for numbers
function getcount () {
  local re='"([^"]*)": ([0-9]+),' # Regex to parse tvheadend dvr log format, looking for numbers
  local search=${1:-"data_errors"} # set our search term that we are going to parse
    debug "func getcount: search = ${search}"
  local dvruuid=$(getdvruuid)
    debug "func getcount: dvruuid = ${dvruuid}"

  [[ $(grep ${search} "${dvruuid}") =~ ${re} ]] && local count=${BASH_REMATCH[2]}
    debug "func getcount: ${search} = ${count}"
  printf ${count}
}


#
# check if open
# Uses `inotifywait` to see if the recording is open
# If the file is NOT open the exit cod ("$?") returns 2 (as per the inotifywait man page)
# A filename MUST be provided as an argument
function checkifopen () {
  inotifywait -t 2 "${1}" >/dev/null 2>&1  # set it to watch for 2 seconds if anything is happening to the file
  echo $?
}


#
# settemp
# Setup our temp directory
function settemp () {
  tmpdir=$(mktemp -d "${recdir}/.XXXXXXXXXXXX")
 # FOR TESTING! This line would put the temp dir in the same directory that this script runs
 # Comment out the above line if you are going to do this
  #tmpdir=$(mktemp -d "$( dirname "${BASH_SOURCE[0]}" )/.XXXXXXXXXXXX")
  debug "Temporary directory set at ${tmpdir}"
}


#
# rmtemp
# Removes the temp directory with all files inside if the tmpdir variable is set
function rmtemp () {
  if [ ! -z ${tmpdir} ]; then
    debug "Long listing of tmpdir:"
    debug "$(ls -l "${tmpdir}")" # This tells you if anything was in the directory being removed
    rm -rf "${tmpdir}"
    debug "Temporary directory ${tmpdir} removed"
    unset tmpdir
  fi
}


#
# process
# Process the recording
function process () {
  # Verify our temp directory actually exists before starting
  if [ ! -d "${tmpdir}" ]; then
    logger "The temp directory doesn't appear to exist - can't process video. Permissions issue?"
    exit 4
  fi

  debug "func process: recfile var = ${recfile}"
  # Process command
  # This is simply a "stream copy" to cleanup the video container meta-data, which is very fast and more times then not enough to make the video watchable, but doesn't help if the player can't work through the encoding errors
  logger "Begin processing (ffmpeg stream copy) file: ${recfile}"

  ffmpeg -err_detect ignore_err -loglevel fatal -f mpegts -i "${filerecloc}" -c copy "${tmpdir}/${recfile}" >>${logloc} 2>&1 || { logger "Warning: Something happened when trying to process the recording"; }

  # options explained:
  #  "-err_detect ignore_err" is practically undocumented but apparently helps if there are filesystem errors (will ignore and keep going).
  #  "-loglevel fatal" is the amount of ffmpeg output going into our log file. This setting keeps it to what would stop ffmpeg, like a fatal error.
  #  "-f mpegts" is specifying that this recording is the format of "mpegts". This is necessary because certain filenames in recordings (such as "Jeopardy!" will break ffmpeg's auto detection of file type (the .ts on the end).
  #  "-i "${filerecloc}"" input file, which in our case is the actual location of our recording.
  #  "-c copy "${tmpdir}/${recfile}"" This specifies this is to be a stream copy and where to put the output file.
  #  ">>${logloc} 2>&1" This is shell redirection, it means all ffmpeg output goes into our logfile, and all errors (stderr) go into normal output (stdout), but in ffmpeg's case all output is stderr I believe. This should be minimal to nothing with the loglevel set to fatal.
  logger "Finished processing"
}


#
# movefile
# After processing is finished, overwrite the original recording with our freshly processed one
function movefile () {
  # Check to see if the recording is open if "writewait=yes"
  if [ "${writewait}" == "yes" ]; then
    local -i ifopen="$(checkifopen "${filerecloc}")"
    if [ "${ifopen}" != "2" ]; then
      logger "Recording appears to be open. Waiting for it to close..."
      inotifywait -e close "${filerecloc}" >/dev/null 2>&1 # inotifywait is _blocking_ until the file closes
      sleep 3 # short break after file closes
      logger "Recording has closed"
    else
      logger "Recording not open, proceding"
    fi
  fi

  # Verify our new file exists before moving forward
  if [ ! -f "${tmpdir}/${recfile}" ]; then
    logger "The processed video doesn't appear to exist or is inaccessble, exiting"
    exit 5
  fi

  # Test run?
  if [ "${testrun}" == "yes" ]; then
    logger "Test run! ---> skipping overwrite! < ---"
  else
    # Overwrite old video with our processed video
    # This get's around having to interact with tvheadend
    logger "Overwriting recording with processed video file"
    /bin/mv "${tmpdir}/${recfile}" "${filerecloc}" || logger "Warning: Error code after moving the video, it might not have overwritten!"
  fi
}


# Cleanup functions

function closeup () {
  rmtemp
  logger "### Script complete ###"
  exit
}

function sig_closeup () {
  logger "Caught signal to close NOW, exiting..."
  closeup
}


### TRAP
##############################################################################
# Because we don't like to leave behind a mess

trap closeup EXIT
trap sig_closeup INT QUIT TERM


### Script variables & validation
##############################################################################

declare -r mypid="$$" # used for logging and mostly so if there are two runs at the same time we can tell them apart
declare -r tvhdvrlog="${tvhhome}/config/dvr/log" # need to know where to find the dvr logs
#declare -r recdir="$(dirname "${filerecloc}")" # directory where the recording resides (alternative method)
declare -r recdir="${filerecloc%/*}" # directory where the recording resides [BASH]
#declare -r recfile="$(basename "${filerecloc}")" # actual filename of the recording (alternative method)
declare -r recfile="${filerecloc##*/}" # actual filename of the recording [BASH]


checklog # check if we can log
logger "### Script invoked ###"
validatevars "$@" # validate input arguments and set them for the script

# Validate necessary external applications
command -v inotifywait >/dev/null 2>&1 || { writewait="no"; logger "This script requires the `inotifywait` program to wait to overwrite the recording with the processed video. Setting to not wait."; }
command -v ffmpeg >/dev/null 2>&1 || { logger "This script requires the `ffmpeg` program to run. "; exit 1; }





# Run
##############################################################################

# debug variables
debug "--- --- Debug Variable List --- ---"
debug "tvhhome = ${tvhhome}"
debug "dvrerrorthreshold = ${dvrerrorthreshold}"
debug "logloc = ${logloc}"
debug "writewait = ${writewait}"
debug "--- --- --- ---"
#

### Main

# Get recording error count
errorcount=$(getcount)

# Does this recording have more errors then our threshold count? If so, process. If not, don't.
if [ "${errorcount}" -ge "${dvrerrorthreshold}" ]; then
  logger "Error count (${errorcount}) meets or exceeds set threshold (${dvrerrorthreshold}), processing..."
  settemp # create our temp directory to store the processed video
  process # process the video, putting it into the temp directory
  movefile # overwrite the processed video over the original video
else
  logger "Error count (${errorcount}) is less than set threshold (${dvrerrorthreshold}), skipping processing"
fi

# End of Script Run
