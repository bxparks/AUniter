#!/usr/bin/env bash
#
# run_arduino.sh
#
#   Shell wrapper around the Arduino command line binary. This allows the
#   calling script (auniter.sh) to wrap a flock(1) around the serial port of a
#   given arduino board to prevent concurrent access to the arduino board.
#
# Usage:
#   run_arduino.sh [--help] [--verbose] [--upload] [--test] [--monitor]
#       [--board board] [--port port] [--baud baud[ [--pref key=value]
#       [--summary_file file] file.ino

set -eu

# Can't use $(realpath $(dirname $0)) because realpath doesn't exist on MacOS
DIRNAME=$(dirname $0)

function usage() {
    cat <<'END'
Usage: run_arduino.sh [--help] [--verbose] [--upload | --test | --monitor]
    [--board board] [--port port] [--baud baud[ [--pref key=value]
    [--summary_file file] file.ino
END
    exit 1
}

function run_arduino_cmd() {
    local file=$1

    local board_flag="--board $board"
    local port_flag=${port:+"--port $port"}
    if [[ "$mode" == 'upload' || "$mode" == 'monitor' \
            || "$mode" == 'test' ]]; then
        local arduino_cmd_mode='upload'
    else
        local arduino_cmd_mode='verify'
    fi

    local cmd="$AUNITER_ARDUINO_BINARY --$arduino_cmd_mode \
$verbose $board_flag $port_flag $prefs $file"

    echo "\$ $cmd"
    if ! $cmd; then
        echo "FAILED $arduino_cmd_mode: $board $port $file" \
            | tee -a $summary_file
        return
    fi

    # The verbose mode sometimes leaves a dangling line w/o a newline
    if [[ "$verbose" != '' ]]; then
        echo # blank line
    fi
}

# Run the serial monitor in AUnit test validation mode.
function validate_test() {
    local file=$1

    echo # blank line
    local cmd="$DIRNAME/serial_monitor.py --test --port $port --baud $baud"
    echo "\$ $cmd"
    if $cmd; then
        echo "PASSED $mode: $board $port $file" | tee -a $summary_file
    else
        echo "FAILED $mode: $board $port $file" | tee -a $summary_file
    fi
}

# Run the serial monitor in echo mode.
function monitor_port() {
    echo # blank line
    local cmd="$DIRNAME/serial_monitor.py --monitor --port $port --baud $baud"
    echo "\$ $cmd"
    $cmd || true # prevent failure from exiting the entire script
}

mode=
board=
port=
verbose=
prefs=
summary_file=
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h) usage ;;
        --verify) mode='verify' ;;
        --upload) mode='upload' ;;
        --test) mode='test' ;;
        --monitor) mode='monitor' ;;
        --verbose) verbose='--verbose' ;;
        --board) shift; board=$1 ;;
        --port) shift; port=$1 ;;
        --baud) shift; baud=$1 ;;
        --pref) shift; prefs="$prefs --pref $1" ;;
        --summary_file) shift; summary_file=$1 ;;
        -*) echo "Unknown option '$1'"; usage ;;
        *) break ;;
    esac
    shift
done
if [[ $# -eq 0 ]]; then
    echo 'No *.ino file specified'
    exit 1
fi

run_arduino_cmd $1
if [[ "$mode" == 'test' ]]; then
    validate_test $1
elif [[ "$mode" == 'monitor' ]]; then
    monitor_port
fi
