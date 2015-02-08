#!/bin/bash
# {{ ansible_managed }}
######################################################################
# Creation: 2014-10-24 - Mathieu MD
# Changelog:
#   2012-07-28 - MathieuMD: Added separate network handling
#   2012-08-26 - MathieuMD: Split config to separate .conf file
#   2013-05-04 - MathieuMD: Absolute path to arp
#   2014-10-24 - MathieuMD: Switched from ZoneMinder to motionEye
######################################################################
# Description:
#
# Enable a Motion monitor if no known smartphone's IP is pingable.
#
# NOTE: If IPs are on a separate network, their MAC are not verifiable, and
# this script will therefore only validate the IP.
#
######################################################################

# Motion's both states options, pipe separated: "enabled|disabled"
# NOTE: '/' must be escaped (as these values are used by sed)
MOTION_OPTIONS[0]="# @motion_detection on|# @motion_detection off"
MOTION_OPTIONS[1]="output_normal on|output_normal off"
MOTION_OPTIONS[2]="ffmpeg_cap_new on|ffmpeg_cap_new off"
#MOTION_OPTIONS[3]="jpeg_filename %Y-%m-%d\/%Y-%m-%dT%H-%M-%S|jpeg_filename "
#MOTION_OPTIONS[4]="ffmpeg_bps 1024000|ffmpeg_bps 400000"
#MOTION_OPTIONS[5]="threshold 5000|threshold 1500"

# To enable debug, set the environment variable DEBUG=1
DEBUG=${DEBUG:-0}

myname="$(basename $0)"
CONF="$(dirname $0)/$(echo $myname|sed 's/.sh/.conf/')"

ARP=$(which arp)

######################################################################

if [ -r $CONF ]; then
    source $CONF
else
    echo "ERR: Configuration file '$CONF' not readable."
    exit 1
fi

######################################################################

MONITOR_PORT=${MONITOR_PORT:-$(grep "^control_port " $MOTIONEYE_DIR/conf/motion.conf | sed 's/^control_port \([0-9]\+\)/\1/')}

MOTION_URL="http://${MONITOR_IP}:${MONITOR_PORT}"

######################################################################
# Functions
######################################################################

are_we_at_home() {
    prev_at_home=$at_home
    debug "prev_at_home=$prev_at_home"
    SP_ID=0
    while [ $SP_ID -lt $(echo $((${#SP_IPS[*]}))) ]; do
        this_ip=${SP_IPS[$SP_ID]}
        this_mac=${SP_MACS[$SP_ID]}
        debug "- Ping check to $this_ip"
        ping_replied=$(ping -c1 $this_ip | grep -c "bytes from $this_ip")
        debug "-> reply=$ping_replied"
        if [ "${ping_replied}" -eq "0" ]; then
            at_home=0
        else
            # Confirm it's really the device we known
            # (only possible if it's on the same network!)
            if [ $(is_same_net $this_ip) -eq 1 ]; then
                debug "-> - Arp check to $this_ip for $this_mac"
                known_mac=$($ARP -an $this_ip | grep -c "$this_mac")
                debug "-> -> reply=$known_mac"
                if [ "${known_mac}" -eq "0" ]; then
                    at_home=0
                else
                    at_home=1
                    break
                fi
            else
                debug "-> - Arp check not possible on separate network"
                debug "-> -> forcing IP validation!"
                at_home=1
                break
            fi
        fi
        SP_ID=$(($SP_ID+1))
    done
    debug "at_home=$at_home"
}

is_same_net() {
    check_ip=$1
    myeth=${myeth:-"$(/sbin/route -n | grep -v "^0." | grep eth | awk '{print $8}')"}
    myip=${myip:-"$(/sbin/ifconfig $myeth | grep 'inet addr' | cut -d: -f2 | awk '{print $1}')"}
    if [ "x$(echo $myip | cut -d. -f1-3)" == "x$(echo $check_ip | cut -d. -f1-3)" ]; then
        echo 1
    else
        echo 0
    fi
}

switch_monitor() {
    if [ $at_home -eq 0 ]; then
        # Everybody left home
        for id in $MONITOR_IDS; do
            enable_monitor $id
        done
    else
        # Welcome back
        for id in $MONITOR_IDS; do
            disable_monitor $id
        done
    fi
}

motion_reload() {
    log "Sending SIGHUP signal to motion daemon pid=$(pgrep -f /usr/bin/motion)"
    kill -s SIGHUP $(pgrep -f /usr/bin/motion)
}

enable_monitor() {
    id=$1
    f=$MOTIONEYE_DIR/conf/thread-${id}.conf
    changed_conf=0
    log "INFO: Enabling monitoring on Monitor $id:"
    for line in "${MOTION_OPTIONS[@]}"; do
        #debug "line: $line"
        l_enabled="$(echo "$line" | cut -d'|' -f1)"
        l_disabled="$(echo "$line" | cut -d'|' -f2)"
        if grep -q "^${l_disabled}$" $f; then
            sed -i "s/^${l_disabled}$/$l_enabled/" $f
            changed_conf=1
            log "+ Configuration file updated: $l_enabled"
        fi
    done
    if lwp-request $MOTION_URL/${id}/detection/status | grep PAUSE -q; then
        debug "lwp-request $MOTION_URL/${id}/detection/start"
        lwp-request $MOTION_URL/${id}/detection/start > /dev/null
        log "+ Motion detection started."
    fi
    if [ $changed_conf -eq 1 ]; then
        motion_reload
    fi
    log "INFO: Monitor $id ENABLED."
}

disable_monitor() {
    id=$1
    f=$MOTIONEYE_DIR/conf/thread-${id}.conf
    changed_conf=0
    log "INFO: Disabling monitoring on Monitor $id:"
    for line in "${MOTION_OPTIONS[@]}"; do
        #debug "line: $line"
        l_enabled="$(echo "$line" | cut -d'|' -f1)"
        l_disabled="$(echo "$line" | cut -d'|' -f2)"
        if grep -q "^${l_enabled}$" $f; then
            sed -i "s/^${l_enabled}$/$l_disabled/" $f
            changed_conf=1
            log "+ Configuration file updated: $l_disabled"
        fi
    done
    if lwp-request $MOTION_URL/${id}/detection/status | grep ACTIVE -q; then
        debug "lwp-request $MOTION_URL/${id}/detection/pause"
        lwp-request $MOTION_URL/${id}/detection/pause > /dev/null
        log "+ Motion detection paused."
    fi
    if [ $changed_conf -eq 1 ]; then
        motion_reload
    fi
    log "INFO: Monitor $id DISABLED."
}

log() {
    if [ $LOG -eq 1 ]; then
        logger -t "$myname[$(echo $$)]" "$@"
    fi
    debug $@
}

debug() {
    if [ $DEBUG -eq 1 ]; then
        echo "$(date +%T) $@" 1>&2
    fi
}

######################################################################
# Program
######################################################################

IPS=$(echo $IPS | sed 's/,/ /g')
IPS_NB=$(echo $IPS | wc -w)
MACS=$(echo $MACS | sed 's/,/ /g')
MACS_NB=$(echo $MACS | wc -w)

# SmartPhones IP and MAC into two tables with same indexes
SP_ID="0"
for ip in $IPS; do
    debug "SP_IPS[$SP_ID]=$ip"
    SP_IPS[$SP_ID]=$ip
    SP_ID=$(( $SP_ID + 1 ))
done
SP_ID="0"
for mac in $MACS; do
    debug "SP_MACS[$SP_ID]=$mac"
    SP_MACS[$SP_ID]=$mac
    SP_ID=$(( $SP_ID + 1 ))
done

if [ $IPS_NB -ne $MACS_NB ]; then
    log "ERROR: Need same number of IP and MAC! I quit."
    exit 1
fi

if [ $(netstat -tlnp | grep -v grep | grep "${MONITOR_IP}:${MONITOR_PORT}" -c) -eq 1 ]; then
    are_we_at_home
    debug "INFO: Enforcing status ($prev_at_home --> $at_home)"
    switch_monitor
else
    log "ERROR: Motion is not running on "${MONITOR_IP}:${MONITOR_PORT}"! Exiting."
    exit
fi
