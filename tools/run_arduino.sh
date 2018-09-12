#!/usr/bin/env bash
#
# Copyright 2018 (c) Brian T. Park <brian@xparks.net>
# MIT License

set -eu

# Can't use $(realpath $(dirname $0)) because realpath doesn't exist on MacOS
DIRNAME=$(dirname $0)

function usage() {
    cat <<'END'
Usage: run_arduino.sh [--help] [--verbose] [--upload | --test]
                      [--env env] [--board board] [--port port] [--baud baud]
                      [--pref key=value] [--summary_file file]
                      file.ino

Helper shell wrapper around the 'arduino' commandline binary and the
'serial_monitor.py' script. This allows the 'auniter.sh' to wrap a flock(1)
command around the serial port to prevent concurrent access to the arduino
board. This script is not meant to be used by the end-user.

Flags:
    --upload    Compile and upload the given program.
    --test      Verify the AUnit test after uploading the program.
    --env env   Name of the current build environment, for error messages.
    --board board
                Fully qualified board specifier.
    --port      Serial port device (e.g. /dev/ttyUSB0).
    --baud      Speed of the serial port.
    --pref key=value
                Passed directly to the Arduino IDE binary. Multiple flags
                allowed.
    --summary_file file
                Send error logs to 'file'.
END
    exit 1
}

function verify_or_upload() {
    local file=$1

    local board_flag="--board $board"
    local port_flag=${port:+"--port $port"}
    if [[ "$mode" == 'upload' || "$mode" == 'test' ]]; then
        local arduino_cmd_mode='upload'
    else
        local arduino_cmd_mode='verify'
    fi

    local cmd="$AUNITER_ARDUINO_BINARY --$arduino_cmd_mode \
        $verbose $board_flag $port_flag $prefs $file"

    echo '$' $cmd
    if ! $cmd; then
        echo "FAILED $arduino_cmd_mode: $env $port $file" \
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
        echo "PASSED $mode: $env $port $file" | tee -a $summary_file
    else
        echo "FAILED $mode: $env $port $file" | tee -a $summary_file
    fi
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
        --verbose) verbose='--verbose' ;;
        --env) shift; env=$1 ;;
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

verify_or_upload $1
if [[ "$mode" == 'test' ]]; then
    validate_test $1
fi
