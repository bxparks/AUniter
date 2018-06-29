#!/usr/bin/env bash
#
# auniter.sh
#
#   A shell wrapper around the arduino(1) commandline program which can verify
#   and upload an Arduino sketch, and validate an AUnit unit test.
#
#   Copyright 2018 (c) Brian T. Park <brian@xparks.net>
#
#   MIT License
#
# Usage:
#
#   $ auniter.sh [--help] [--config file] [--verbose]
#       [--verify | --upload | --test | --monitor | --list_ports]
#       [--board {package}:{arch}:{board}[:parameters]]
#       [--port port] [--baud baud]
#       [--boards {alias}[:{port}],...]
#       [--pref key=value] (file.ino | dir) [...]
#
# Flags:
#
#   --verify Verify the compile of the given sketch files. (Default)
#   --upload Upload the sketch to the given board at port.
#   --test Upload an AUnit unit test, and verify pass or fail. Automatically
#       invokes the --upload flag.
#   --monitor Use serial_monitor.py to read and echo the serial output.
#   --port /dev/ttyXxx Location of the board.
#   --baud baud Speed of the port for serial_montor.py. (Default: 115200)
#   --board Fully qualified board name (fqbn) of the target board.
#   --boards {alias}[:{port}],... Comma-separated list of {alias}:{port} pairs.
#   --verbose Verbose output from the Arduino binary
#   --pref key=value Set the Arduino command line preferences. Multiple
#       flags may be given.
#   --config file Read configs from 'file' instead of $HOME/.auniter.conf
#
#   If the directory is given, then the script looks for a sketch file under
#   the directory with the same name but ending with '.ino'. For example,
#   './auniter.sh CommonTest' is equivalent to './auniter.sh
#   CommonTest/CommonTest.ino' if CommonTest is a directory.
#
# Dependencies:
#
#   * run_arduino.sh
#   * serial_monitor.py

set -eu

# Can't use $(realpath $(dirname $0)) because realpath doesn't exist on MacOS
DIRNAME=$(dirname $0)

# Default config file in the absence of --config flag.
DEFAULT_CONFIG_FILE=$HOME/.auniter.conf

# Number of seconds that flock(1) should wait on a serial port.
PORT_TIMEOUT=120

# Status code returned by flock(1) if it times out.
FLOCK_TIMEOUT_CODE=10

function usage() {
    cat <<'END'
Usage: auniter.sh [--help] [--config file] [--verbose]
    [--verify | --upload | --test | --monitor | --list_ports]
    [--board {package}:{arch}:{board}[:parameters]]
    [--port port] [--baud baud]
    [--boards {alias}[:{port}],...]
    [--pref key=value]
    (file.ino | directory) [...]
END
    exit 1
}

# Find the *.ino file, even if only the directory was given, e.g. "CommonTest"
function get_ino_file() {
    local file=$1

    # Ends in '.ino', just return it.
    if [[ "$file" =~ .*\.ino ]]; then
        echo $file
        return
    fi

    # Not a directory, don't know what to do with it, just return it
    if [[ ! -d $file ]]; then
        echo $file
        return
    fi

    # Strip off any trailing '/'
    local dir=$(echo $file | sed -e 's/\/*$//')
    local file=$(basename $dir)
    echo "${dir}/${file}.ino"
}

# Find the given $key in a $section from the $config file.
# Usage: get_config config section key
#
# The config file is expected to be in an INI file format:
#   [section]
#       {key} = {value}
#       ...
#   [...]
#       ...
#
function get_config() {
    local config_file=$1
    local section=$2
    local key=$3

    # If config_file does not exist then no aliases are defined.
    if [[ ! -f "$config_file" ]]; then
        return
    fi

    # Use "one-liner" sed script given in
    # https://stackoverflow.com/questions/6318809, with several changes:
    # 1) Fix bug if the key does not exist in the matching [$section] but
    # exists in a subsequent section.
    # 2) Support multiple sections of the same name. Entries of duplicate
    # sections are merged together.
    # 3) Works on MacOS sed as well as GNU sed.
    sed -n -E -e \
        ":label_s;
        /^\[$section\]/ {
            n;
            :label_k;
            /^ *$key *=/ {
                s/[^=]*= *//; p; q;
            };
            /^\[.*\]/ b label_s;
            n;
            b label_k;
        }" \
        "$config_file"
}

function process_sketches() {
    if [[ "$boards" != '' ]]; then
        process_boards "$@"
    else
        process_files "$@"
    fi
}

function process_boards() {
    local alias_ports=$(echo "$boards" | sed -e 's/,/ /g')
    for alias_port in $alias_ports; do
        # Split {alias}:{port} into two fields.
        local board_alias=$(echo $alias_port \
                | sed -E -e 's/([^:]*):?([^:]*)/\1/')
        local board_port=$(echo $alias_port \
                | sed -E -e 's/([^:]*):?([^:]*)/\2/')

        echo "======== Processing board=$board_alias, port=$board_port"
        local board_value=$(get_config "$config_file" 'boards' "$board_alias")
        if [[ "$board_value" == '' ]]; then
            echo "FAILED: Unknown board alias '$board_alias'" \
                | tee -a $summary_file
            continue
        fi
        if [[ "$board_port" == '' && "$mode" != 'verify' ]]; then
            echo "FAILED $mode: Unknown port for '$board_alias'" \
                | tee -a $summary_file
            continue
        fi

        board=$board_value
        port=$board_port
        process_files "$@"
    done
}

function process_files() {
    local file
    for file in "$@"; do
        local ino_file=$(get_ino_file $file)
        if [[ ! -f $ino_file ]]; then
            echo "FAILED $mode: file not found: $ino_file" \
                | tee -a $summary_file
            continue
        fi

        process_file $ino_file
    done
}

function process_file() {
    local file=$1
    echo "==== Processing $file"

    if [[ "$board" == '' ]]; then
        echo "FAILED $mode: board not defined: $file" \
            | tee -a $summary_file
        return
    fi
    if [[ "$port" == '' && "$mode" != 'verify' ]]; then
        echo "FAILED $mode: port for '$board' not defined: $file" \
            | tee -a $summary_file
        return
    fi

    if [[ "$mode" == 'verify' ]]; then
        # Allow multiple --verify commands to run at the same time.
        $DIRNAME/run_arduino.sh \
            --$mode \
            --board $board \
            $prefs \
            $verbose \
            --summary_file $summary_file \
            $file
    else
        # flock(1) returns status 1 if the lock file doesn't exist, which
        # prevents distinguishing that from failure of run_arduino.sh.
        if [[ ! -e $port ]]; then
            echo "FAILED $mode: $port does not exist for $file" \
                | tee -a $summary_file
            return
        fi

        # Use flock(1) to prevent multiple uploads to the same board at the same
        # time.
        local status=0; flock --timeout $PORT_TIMEOUT \
                --conflict-exit-code $FLOCK_TIMEOUT_CODE \
                $port \
                $DIRNAME/run_arduino.sh \
                --$mode \
                --board $board \
                --port $port \
                $prefs \
                $verbose \
                --summary_file $summary_file \
                $file || status=$?

        if [[ "$status" == $FLOCK_TIMEOUT_CODE ]]; then
            echo "FAILED $mode: could not obtain lock on $port for $file" \
                | tee -a $summary_file
        elif [[ "$status" != 0 ]]; then
            echo "FAILED $mode: run_arduino.sh failed on $file" \
                | tee -a $summary_file
        fi
    fi
}

function clean_temp_files() {
    if [[ "$summary_file" != '' ]]; then
        rm -f $summary_file
    fi
}

function create_temp_files() {
    summary_file=
    trap "clean_temp_files" EXIT
    summary_file=$(mktemp /tmp/auniter_summary_XXXXXX)
}

function print_summary_file() {
    echo '======== Summary'
    cat $summary_file
    if ! grep --quiet FAILED $summary_file; then
        echo 'ALL PASSED'
        return 0
    else
        echo 'FAILURES found'
        return 1
    fi
}

function check_environment_variables() {
    # Check for AUNITER_ARDUINO_BINARY
    if [[ -z ${AUNITER_ARDUINO_BINARY+x} ]]; then
        echo "AUNITER_ARDUINO_BINARY environment variable is not defined"
        exit 1
    fi
    if [[ ! -x $AUNITER_ARDUINO_BINARY ]]; then
        echo "AUNITER_ARDUINO_BINARY=$AUNITER_ARDUINO_BINARY is not executable"
        exit 1
    fi
}

function interrupted() {
    echo 'Interrupted'
    print_summary_file
    exit 1
}

# Parse command line flags
mode='verify'
board=
boards=
port=
baud=115200
verbose=
config=
prefs=
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h) usage ;;
        --config) shift; config=$1 ;;
        --verbose) verbose='--verbose' ;;
        --verify) mode='verify' ;;
        --upload) mode='upload' ;;
        --test) mode='test' ;;
        --monitor) mode='monitor' ;;
        --list_ports) mode='list_ports' ;;
        --board) shift; board=$1 ;;
        --port) shift; port=$1 ;;
        --baud) shift; baud=$1 ;;
        --boards) shift; boards=$1 ;;
        --pref) shift; prefs="$prefs --pref $1" ;;
        -*) echo "Unknown option '$1'"; usage ;;
        *) break ;;
    esac
    shift
done
if [[ "$mode" != 'list_ports' && $# -eq 0 ]]; then
    echo 'Must provide file or directory'
    usage
fi

# Determine the location of the config file.
config_file=${config:-$DEFAULT_CONFIG_FILE}

# Must install a trap for Control-C because the script ignores almost all
# interrupts and continues processing.
trap interrupted INT

check_environment_variables
create_temp_files
if [[ "$mode" == 'list_ports' ]]; then
    $DIRNAME/serial_monitor.py --list
else
    process_sketches "$@"
    print_summary_file
fi
