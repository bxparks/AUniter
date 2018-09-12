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
                      [--env {env}] [--board {board}] [--port {port}]
                      [--baud {baud}] [--sketchbook {path}]
                      [--preprocessor {flags}]
                      [--summary_file file] file.ino

Helper shell wrapper around the 'arduino' commandline binary and the
'serial_monitor.py' script. This allows the 'auniter.sh' to wrap a flock(1)
command around the serial port to prevent concurrent access to the arduino
board. This script is not meant to be used by the end-user.

Flags:
    --upload        Compile and upload the given program.
    --test          Verify the AUnit test after uploading the program.
    --env {env}     Name of the current build environment, for error messages.
    --board {fqbn} Fully qualified board specifier.
    --port {port}   Serial port device (e.g. /dev/ttyUSB0).
    --baud {baud}   Speed of the serial port.
    --sketchbook {path}
                    Home directory of the sketch, for resolving libraries.
    --preprocessor {flags}
                    Comma-separated list of CPP macros.
    --summary_file {file}
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

    if [[ "$sketchbook" != '' ]]; then
        local sketchbook_flag="--pref sketchbook.path=$sketchbook"
    else
        local sketchbook_flag=
    fi

    # Convert comma-separated macros into space-separated list
    # of "-Dmacro -Dmacro=value ...".
    local cpp_flags=
    if [[ "$preprocessor" != '' ]]; then
        cpp_flags=$(echo $preprocessor | sed -e 's/,/ -D/g')
        cpp_flags="--pref compiler.cpp.extra_flags='-D$cpp_flags'"
    fi

    local cmd="$AUNITER_ARDUINO_BINARY \
        --$arduino_cmd_mode \
        $verbose \
        $board_flag \
        $port_flag \
        $sketchbook_flag \
        $cpp_flags \
        $file"

    echo '$' $cmd
    # Use 'eval' to interpret the single-quotes in $cpp_flags
    if ! eval $cmd; then
        echo "FAILED $arduino_cmd_mode: $env $port $file" \
            | tee -a $summary_file
        return
    fi

    # The verbose mode or upload (on some boards) sometimes leave a dangling
    # line w/o a newline.
    if [[ "$verbose" != '' || "$arduino_cmd_mode" == 'upload' ]]; then
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
sketchbook=
preprocessor=
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
        --sketchbook) shift; sketchbook=$1 ;;
        --preprocessor) shift; preprocessor=$1 ;;
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
