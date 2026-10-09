#!/usr/bin/env bash
#
# vef.sh | Revision 4
#
# Post Processing script for tvheadend on recorded .ts files (mpeg2)
#
####################
# USAGE INSTRUCTIONS

# 1) ADD THE PROCESSING TO THE CRONTAB!
# "crontab -e -u ${hts/tvheadend}" #that is, the user that is running tvheadend
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

### User set variables
##############################################################################

# Where does your base tvheadend config reside
declare -r tvhhome="/var/lib/tvheadend/"
# At how many data errors do we process the video?
declare -r -i dvrerrorthreshold=20

# Where would you like this script to log to?
declare -r logloc="${tvhhome}/vef.log"
declare -r -i logdebug=0 # 0 = no debug log, 1 = yes debug log

# Uncomment and set this if you want to change where temporary files are set while being processed
declare tmpdirloc="/tvhtmp"

# Queue and queue log location directory
declare -r qloc="${tvhhome}/.vef"
declare -r qdir="${qloc}/queue"
declare -r plogloc="${qloc}/processed.log"
declare -r lockfile="${qloc}/vef.lock"

# Remove a queue file if it doesn't appear to exist?
declare rmemptyqueuefile=true

# Is this a testrun?
# If yes, we will process as usual but NOT overwrite the original recording (we won't keep the processed video either)
declare -r testrun="no"

# Do we wait if the video is currently being used to overwrite it with our processed version?
declare -r writewait="yes"      #yes or no

# ffmpeg log level
declare ffmpegloglevel="error"
if [ ${logdebug} = 1 ]; then
  declare ffmpegloglevel="warning"
fi

### Comskip Configuration
##############################################################################
declare enable_comskip="yes"
declare comskip_ini_default="${tvhhome}/comskip-profiles/comskip-default.ini"
declare -r comskip_ini_dir="${tvhhome}/comskip-profiles"

# Rules for Smart Profile Matching
# Format: "MatchKey | Comma,Separated,Matches | IniFilename"
# MatchKey options: title | channelname | alltext | default
# Note: "alltext" will search title, subtitle & description
declare -a comskip_rules=(
  "title | nfl football,super bowl,mlb baseball,Stanley Cup Final,NHL Hockey,United Football League | comskip-sports.ini"
  "channelname | PBS,MPT | comskip-pbs.ini"
  "default | * | comskip-default.ini"
)

### Functions
##############################################################################

function logdate () {
  date "+%Y/%m/%d  %H:%M:%S"
}

function veflog () {
  echo $(logdate) [${mypid}] "${1}" >> ${logloc}
}

function debug () {
  if [ ${logdebug} = 1 ]; then
    if [ -n "${1}" ]
    then
      IN="${1}"
    else
      read IN
    fi
    echo $(logdate) [${mypid}] "_DEBUG_ ${IN}" >> ${logloc}
  fi
}

function show_usage () {
  cat << 'EOF'
Usage: vef.sh [OPTION] | [FILEPATH]

vef.sh - Post-processing script for Tvheadend on recorded .ts files.

Options:
  -p, --process    Process the queue of recorded files.
  -l, --list       List queued files.
  -r, --repair     (Manual) Run ONLY the ffmpeg video repair stream copy.
  -c, --comskip    (Manual) Run ONLY Comskip commercial detection in-place.
  -b, -f, --both   (Manual) Run Both video repair and Comskip.
  -h, -u, --help   Display this usage information.

Tvheadend Integration:
  1) ADD THE PROCESSING TO THE CRONTAB!
     "crontab -e -u hts" (or the user running tvheadend)
     # VEF Processing every half hour
     2,32 * * * * /usr/local/bin/vef.sh -p

  2) ADD THE SCRIPT PATH TO EACH RECORDING PROFILE
     - In the tvheadend web ui, go to "Configuration > Recording > Digital Video Recording Profiles"
     - Under "Miscellaneous Settings > Post-processor command", input:
       /usr/local/bin/vef.sh "%f"
     - Click "Save"
EOF
  exit 0
}

function clean() {
    # BASH 4+ function
    local a=${1//[^[:alnum:]]/}
    echo "${a,,}"
}

function listqueuedfiles () {
  # Load directory contents into an array to safely check if it's empty
  local files=("${qdir}"/*)
  if [ ! -e "${files[0]}" ]; then
    echo "The queue is currently empty."
    return
  fi

  echo -e "\n=== Currently Queued Files ==="
  for qfile in "${qdir}"/*; do
    if [ -f "${qfile}" ]; then
      local qfilename="${qfile##*/}"
      local recloc="$(cat "${qfile}")"
      echo "[Queue File]: ${qfilename}"
      echo "  -> Target:  ${recloc}"
    fi
  done
  echo -e "==============================\n"
}

function checkifprocessing () {
  exec 9> "${lockfile}"
  if ! flock -n 9; then
    veflog "A vef.sh process is already running (lock active), exiting..."
    exit 1
  fi
}

function checklog () {
  if [ ! -f "${logloc}" ];then
    touch ${logloc} || { echo "Cannot create log file!"; exit 1; }
    sleep 1
    veflog "Script log file __${logloc}__ does not exist; creating it."
  fi
}

function verifymeta () {
  if [ ! -d "${qloc}" ];then
    veflog "Metadata directory __${qloc}__ does not exist; creating it."
    mkdir -p "${qloc}" || { echo "Cannot create __${qloc}__ directory! Check path, filename & permissions!!!"; exit 1; }
    chmod 750 "${qloc}"
  fi
  if [ ! -d "${qdir}" ];then
    veflog "Queue directory __${qdir}__ does not exist; creating it."
    mkdir -p "${qdir}" || { echo "Cannot create __${qdir}__ directory! Check path, filename & permissions!!!"; exit 1; }
    chmod 750 "${qdir}"
  fi
  if [ ! -f "${plogloc}" ];then
    veflog "Process log file __${plogloc}__ does not exist; creating it."
    touch "${plogloc}" || { echo "Cannot create process log file! Check path, filename & permissions!!!"; exit 1; }
  fi
}

function checkplogproc () {
  grep "^Processed" "${plogloc}" | grep -F -q "${filepath}"
}

function checkplogqueue () {
  grep "^Queued:" "${plogloc}" | grep -F -q "${filepath}"
}

function buildqueuefile () {
  declare timestamp="$(date '+%y%m%d%H%M%S')"
  declare justfilename="${filepath##*/}"
  declare cleanedfilenamestart="$(clean ${justfilename:0:8})"
  declare cleanedfilenameend="$(clean ${justfilename:0-6})"
  declare queuefile="${timestamp}_${cleanedfilenamestart}_${cleanedfilenameend}"

  if [ -f ${queuefile} ];then
    veflog "! queuefile already exists??? __${queuefile}__ exists somehow, exiting"
    exit 2
  else
    echo "${filepath}" > ${qdir}/${queuefile}
    echo "Queued:${timestamp},${filepath}" >> ${plogloc}
    veflog "Queued as __${queuefile}__"
  fi
}

function queuefile () {
  if [ -f "${filepath}" ];then
    checkplogproc
    if [ "$?" -gt 0 ];then
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
    echo "Error: Filepath does not exist. Run '$(basename "${0}") -h' for usage instructions." >&2
    exit 1
  fi
}

### Process queue functions

function queuereadlast () {
  local queuefile=$(/bin/ls -tr ${qdir} | /bin/head -1)
  if [ -z "${queuefile}" ]; then
    printf "queuenull"
  else
    printf "${queuefile}"
  fi
}

function getdvruuid () {
  find "${tvhdvrlog}" -type f -exec grep -l -F "${filerecloc}" {} + 2>/dev/null | head -n 1
}

function getcount () {
  local re='"([^"]*)": ([0-9]+),'
  local search=${1:-"data_errors"}
  debug "func getcount: search = ${search}"
  debug "func getcount filerecloc = ${filerecloc}"
  debug "func getdvruuid command = grep -l ${filerecloc} ${tvhdvrlog}/*"
  local dvruuid="$(getdvruuid)"

  if [ -z "${dvruuid}" ]; then
    veflog "Warning: DVR log not found for this recording."
    return 1
  fi

  if [[ $(grep "${search}" "${dvruuid}") =~ ${re} ]]; then
    local count="${BASH_REMATCH[2]}"
  fi
    debug "func getcount: ${search} = ${count}"
  printf "%s" "${count}"
}

# Extracts strings from the DVR log using jq, handling both flat and nested objects dynamically
function getdvrstring () {
  local search="${1}"
  local dvruuid="$(getdvruuid)"
  if [ -z "${dvruuid}" ]; then
    return 1
  fi
  jq -r ".\"${search}\" | if type == \"object\" then .[] else . end" "${dvruuid}" 2>/dev/null | head -n 1
}

function checkifopen () {
  /bin/inotifywait -t 2 "${1}" >/dev/null 2>&1
  echo $?
}

function settemp () {
  if [ -z "${tmpdirloc}" ];then
    thistmpdir="${tmpdirloc}"
  else
    thistmpdir="${recdir}"
  fi
  tmpdir=$(mktemp -d "${thistmpdir}/.XXXXXXXXXXXX")
  debug "Temporary directory set at ${tmpdir}"
}

function rmtemp () {
  if [ ! -z "${tmpdir}" ]; then
    debug "Long listing of tmpdir: (post move, pre directory removal)"
    debug "$(ls -l "${tmpdir}")" # This tells you if anything was in the directory being removed
    rm -rf "${tmpdir}"
    debug "Temporary directory ${tmpdir} removed"
    unset tmpdir
  fi
}

function process () {
  if [ ! -d "${tmpdir}" ]; then
    veflog "Temp directory doesn't exist - can't process video."
    exit 4
  fi

  veflog "Begin ffmpeg stream copy: ${recfile}"
  ffmpeg -nostdin -err_detect ignore_err -loglevel "${ffmpegloglevel}" -f mpegts -i "${filerecloc}" -c copy "${tmpdir}/${recfile}" >> "${logloc}" 2>&1 || { veflog "Warning: Something happened during ffmpeg processing"; }
  veflog "Finished ffmpeg processing"
}

# Helper trim function to strip whitespace around pipe/comma delimiters
function trim() {
  local var="${1}"
  var="${var#"${var%%[![:space:]]*}"}"
  var="${var%"${var##*[![:space:]]}"}"
  echo "${var}"
}

function get_comskip_ini () {
  if [ "${enable_comskip}" != "yes" ]; then
    return
  fi

  local channelname="$(getdvrstring "channelname")"
  local title="$(getdvrstring "title")"
  local subtitle="$(getdvrstring "subtitle")"
  local desc="$(getdvrstring "description")"
  local alltext="${title} ${subtitle} ${desc}"

  local matched_ini=""

  for rule in "${comskip_rules[@]}"; do
    IFS='|' read -r raw_key raw_matches raw_ini <<< "${rule}"
    local key="$(trim "${raw_key}")"
    local matches="$(trim "${raw_matches}")"
    local ini="$(trim "${raw_ini}")"

    local target_text=""
    case "${key,,}" in
      title)       target_text="${title}" ;;
      channelname) target_text="${channelname}" ;;
      alltext)     target_text="${alltext}" ;;
      default)
        matched_ini="${ini}"
        break
        ;;
    esac

    IFS=',' read -ra match_array <<< "${matches}"
    for pattern in "${match_array[@]}"; do
      pattern="$(trim "${pattern}")"
      local pattern_lower="${pattern,,}"
      local target_lower="${target_text,,}"
      if [ -n "${pattern}" ] && [[ "${target_lower}" =~ ${pattern_lower} ]]; then
        matched_ini="${ini}"
        break 2
      fi
    done
  done

  # Fallback to default variable if no match was found
  if [ -z "${matched_ini}" ]; then
    echo "${comskip_ini_default}"
    return
  fi

  # Construct full path if a relative filename was provided in the rule
  if [[ "${matched_ini}" != /* ]]; then
    echo "${comskip_ini_dir}/${matched_ini}"
  else
    echo "${matched_ini}"
  fi
}

function run_comskip () {
  local target_file="${1}"
  local output_dir="${2}"

  if [ "${enable_comskip}" != "yes" ]; then
    return
  fi

  local base="${target_file%.*}"
  local bname="${base##*/}"
  if [ -f "${output_dir}/${bname}.edl" ] || [ -f "${output_dir}/${bname}.txt" ]; then
    veflog "Warning: Overwriting existing Comskip sidecar files for ${bname}"
  fi

  local selected_ini="$(get_comskip_ini)"
  veflog "Running Comskip on '${bname}' with profile: ${selected_ini}"

  if [ -f "${selected_ini}" ]; then
    comskip --ini="${selected_ini}" --output="${output_dir}" "${target_file}" >> "${logloc}" 2>&1
  else
    veflog "Warning: Comskip ini file not found at ${selected_ini}. Running with defaults."
    comskip --output="${output_dir}" "${target_file}" >> "${logloc}" 2>&1
  fi
  veflog "Finished Comskip processing"
}

function movefile () {
  if [ "${writewait}" == "yes" ]; then
    local -i ifopen="$(checkifopen "${filerecloc}")"
    if [ "${ifopen}" != "2" ]; then
      veflog "Recording appears to be open. Waiting for it to close..."
      inotifywait -e close "${filerecloc}" >/dev/null 2>&1
      sleep 3
      veflog "Recording has closed"
    fi
  fi

  if [ ! -s "${tmpdir}/${recfile}" ]; then
    veflog "The processed video appears empty or inaccessible. Exiting."
    exit 5
  fi

  if [ "${testrun}" == "yes" ]; then
    veflog "Test run! ---> skipping overwrite! < ---"
  else
    veflog "Overwriting recording with processed video file"
    /bin/mv "${tmpdir}/${recfile}" "${filerecloc}" || veflog "Warning: Error code moving video!"

    # Move any generated Comskip sidecar files
    for sidecar in "${tmpdir}"/*; do
      if [ -f "${sidecar}" ]; then
        local fname="${sidecar##*/}"
        if [ "${fname}" != "${recfile}" ]; then
          if [ -f "${recdir}/${fname}" ]; then
            veflog "Warning: Queue run overwriting existing Comskip sidecar file: ${fname}"
          fi
          /bin/mv "${sidecar}" "${recdir}/${fname}"
        fi
      fi
    done
  fi
}

function processqueue () {
  procqueuefile="$(queuereadlast)"
  local loopbreak=0
  local looplimit=5

  while [ "${procqueuefile}" != "queuenull" ]; do
    declare filerecloc="$(/bin/cat "${qdir}/${procqueuefile}")"
    declare nullfile=false
    declare timestamp="$(date '+%y%m%d%H%M%S')"

    declare recdir=${filerecloc%/*}
    declare recfile=${filerecloc##*/}

    errorcount=$(getcount)
    if [ -z "${errorcount}" ]; then
      veflog "!Warning! No error count found. File was probably deleted from tvheadend."
      if [ "${rmemptyqueuefile}" = true ]; then
        declare nullfile=true
        debug "Var rmemptyqueuefile is set to true"
        veflog "Removing empty queue file: ${procqueuefile}"
        rm "${qdir}/${procqueuefile}" && echo "RemovedEmptyQueueFile:${timestamp},${procqueuefile},${filerecloc}" >> "${plogloc}"
      fi
    fi

    if [ "${nullfile}" = false ]; then

      # Path A: Error threshold met, repair needed
      if [ "${errorcount}" -ge "${dvrerrorthreshold}" ]; then
        veflog "Error count (${errorcount}) meets threshold (${dvrerrorthreshold}), processing..."
        settemp
        process
        run_comskip "${tmpdir}/${recfile}" "${tmpdir}"
        movefile
        rmtemp

        if [ "${testrun}" == "yes" ]; then
          echo "TESTRUN:::(wouldhave)Processed-Both:${timestamp},QUEUE,${filerecloc}" >> "${plogloc}"
        else
          echo "Processed-Both:${timestamp},QUEUE,${filerecloc}" >> "${plogloc}"
        fi

      # Path B: Below threshold, Comskip only in-place
      elif [ "${enable_comskip}" == "yes" ]; then
        veflog "Error count (${errorcount}) below threshold. Skipping repair."

        run_comskip "${filerecloc}" "${recdir}"

        echo "Processed-Comskip:${timestamp},QUEUE,${filerecloc}" >> "${plogloc}"

      else
        veflog "Error count (${errorcount}) below threshold and Comskip disabled. Skipping."
      fi

      if [ "${testrun}" == "yes" ]; then
        veflog "Test run! ---> exiting queue loop to avoid endless loop"
        exit 0
      else
        if ! rm "${qdir}/${procqueuefile}"; then
          ((loopbreak+=1))
          veflog "Could not remove queue file for some reason [${loopbreak}]"
        fi
      fi

      if [ "${loopbreak}" -gt "${looplimit}" ]; then
        veflog "!ERROR! Looplimit iteration reached, breaking loop."
        exit 5
      fi
    fi

    procqueuefile="$(queuereadlast)"
  done
}

function process_single_file () {
  local action="${1}" # -r, -c, or -b/-f
  local targetfile="${2}"

  if [ ! -f "${targetfile}" ]; then
    echo "Error: Target file '${targetfile}' does not exist." >&2
    exit 1
  fi

  declare filerecloc="${targetfile}"
  declare recdir="${filerecloc%/*}"
  declare recfile="${filerecloc##*/}"

  veflog "Manual processing triggered [${action}] for: ${filerecloc}"

  # Pre-Flight Safety 1: Active recording (Write Locks)
  if lsof -F a "${targetfile}" 2>/dev/null | grep -q "^a.*[wu]"; then
    echo "Error: Target file is actively being written to (recording in progress). Aborting."
    exit 1
  fi

  # Pre-Flight Safety 2: Warnings (Logs & Sidecars)
  local prompt_needed=0
  local warn_msg=""

  if grep -q -F "${targetfile}" "${plogloc}"; then
    warn_msg+=" - File is already logged in processed.log.\n"
    prompt_needed=1
  fi

  if [[ "${action}" == "-c" || "${action}" == "-b" || "${action}" == "-f" ]]; then
    local base="${targetfile%.*}"
    if ls "${base}".* >/dev/null 2>&1; then
       local sidecars=$(ls "${base}".* | grep -v -F "${targetfile}")
       if [ -n "${sidecars}" ]; then
         warn_msg+=" - Existing sidecar files found and will be overwritten.\n"
         prompt_needed=1
       fi
    fi
  fi

  if [ "${prompt_needed}" -eq 1 ]; then
    echo -e "\nWarnings:\n${warn_msg}"
    read -p "Do you want to proceed? (Y/n) " resp
    if [[ ! "${resp}" =~ ^[Yy]$ ]] && [[ ! -z "${resp}" ]]; then
      echo "Aborting."
      exit 0
    fi
  fi

  # Action Logging
  declare timestamp="$(date '+%y%m%d%H%M%S')"
  local action_log="Processed-Unknown"
  if [[ "${action}" == "-r" ]]; then action_log="Processed-Repair"; fi
  if [[ "${action}" == "-c" ]]; then action_log="Processed-Comskip"; fi
  if [[ "${action}" == "-b" || "${action}" == "-f" ]]; then action_log="Processed-Both"; fi

  # Active Playback detection (Read Locks)
  local read_open=0
  if lsof -F a "${targetfile}" 2>/dev/null | grep -q "^a.*[ru]"; then
    read_open=1
  fi

  # Backgrounding instructions for read holds
  if [ "${read_open}" -eq 1 ] && [ "${writewait}" == "yes" ]; then
    echo "${action_log}:${timestamp},MANUAL_OVERRIDE,${targetfile}" >> "${plogloc}"

    # Release flock so cron can resume
    exec 9>&-

    if [[ "${action}" == "-r" || "${action}" == "-b" || "${action}" == "-f" ]]; then
      echo -e "\nFile is currently open for reading (active playback)."
      echo "The script will process the file but will wait to swap the video until playback finishes."
      echo "Tip: Press Ctrl+Z, then type 'bg' to run this wait in the background."
    fi
  fi

  # Flow Execution
  if [[ "${action}" == "-c" ]]; then
    run_comskip "${targetfile}" "${recdir}"
    if [ "${read_open}" -eq 0 ]; then
      echo "${action_log}:${timestamp},MANUAL_OVERRIDE,${targetfile}" >> "${plogloc}"
    fi

  elif [[ "${action}" == "-r" ]]; then
    settemp
    process
    movefile
    rmtemp
    if [ "${read_open}" -eq 0 ]; then
      echo "${action_log}:${timestamp},MANUAL_OVERRIDE,${targetfile}" >> "${plogloc}"
    fi

  elif [[ "${action}" == "-b" || "${action}" == "-f" ]]; then
    settemp
    process
    run_comskip "${tmpdir}/${recfile}" "${tmpdir}"
    movefile
    rmtemp
    if [ "${read_open}" -eq 0 ]; then
      echo "${action_log}:${timestamp},MANUAL_OVERRIDE,${targetfile}" >> "${plogloc}"
    fi
  fi

  echo "Finished manual processing of ${recfile}"
}

function check_deps () {
  local missing=0
  command -v ffmpeg >/dev/null 2>&1 || { veflog "Error: 'ffmpeg' missing."; missing=1; }
  command -v jq >/dev/null 2>&1 || { veflog "Error: 'jq' missing."; missing=1; }
  command -v lsof >/dev/null 2>&1 || { veflog "Error: 'lsof' missing."; missing=1; }

  if ! command -v comskip >/dev/null 2>&1; then
    veflog "Warning: 'comskip' not found. Disabling commercial detection."
    enable_comskip="no"
  fi

  if [ "${missing}" -eq 1 ]; then
    echo "Required dependencies are missing. Check log for details." >&2
    exit 1
  fi
}

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
trap closeup EXIT
trap sig_closeup INT QUIT TERM

### Script variables & validation
##############################################################################
declare -r mypid="$$"
declare -r tvhdvrlog="${tvhhome}/config/dvr/log"

command -v flock >/dev/null 2>&1 || { echo "Error: 'flock' is required but not installed." >&2; exit 1; }
command -v inotifywait >/dev/null 2>&1 || { writewait="no"; veflog "Script requires 'inotifywait' to delay overwrites. Setting writewait to no."; }

##############################################################################
#  Main
##############################################################################
debug "### Script run begin ###"
checklog
verifymeta

if [ -z "${1}" ]; then
  show_usage
fi

case "${1}" in
  -h | -u | --help | --usage )
    show_usage
    ;;
  -l | --list )
    listqueuedfiles
    ;;
  -r | --repair )
    if [ -z "${2}" ]; then echo "Error: Must provide a filepath." >&2; exit 1; fi
    checkifprocessing
    check_deps
    process_single_file "-r" "${2}"
    ;;
  -c | --comskip )
    if [ -z "${2}" ]; then echo "Error: Must provide a filepath." >&2; exit 1; fi
    checkifprocessing
    check_deps
    process_single_file "-c" "${2}"
    ;;
  -f | --file | -b | --both )
    if [ -z "${2}" ]; then echo "Error: Must provide a filepath." >&2; exit 1; fi
    checkifprocessing
    check_deps
    process_single_file "-b" "${2}"
    ;;
  -p | --process )
    checkifprocessing
    check_deps
    processqueue
    ;;
  * )
    declare filepath="${1}"
    queuefile
    ;;
esac
