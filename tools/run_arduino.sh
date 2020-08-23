#!/usr/bin/env bash
#
# Copyright 2018 (c) Brian T. Park <brian@xparks.net>
# MIT License

set -eu

# Can't use $(realpath $(dirname $0)) because realpath doesn't exist on MacOS
DIRNAME=$(dirname $0)

function usage() {
    cat <<'END'
Usage: run_arduino.sh [--help] [--verbose] [--verify | --upload | --test]
                      [--env {env}] [--board {board}] [--port {port}]
                      [--baud {baud}] [--sketchbook {path}]
                      [--preprocessor {flags}] [--preserve]
                      [--summary_file file] file.ino

Helper shell wrapper around the 'arduino' commandline binary and the
'serial_monitor.py' script. This allows the 'auniter.sh' to wrap a flock(1)
command around the serial port to prevent concurrent access to the arduino
board. This script is not meant to be used by the end-user.

Flags:
    --upload        Compile and upload the given program.
    --test          Verify the AUnit test after uploading the program.
    --env {env}     Name of the current build environment, for error messages.
    --board {fqbn}  Fully qualified board name (fqbn).
    --port {port}   Serial port device (e.g. /dev/ttyUSB0).
    --baud {baud}   Speed of the serial port.
    --sketchbook {path}
                    Home directory of the sketch, for resolving libraries.
    --preprocessor {flags}
                    Build flags of the form '-DMACRO -DMACRO=value' as a single
                    argument (must be quoted if multiple macros).
    --preserve      Preserve /tmp/arduino* temp files for further analysis.
    --summary_file {file}
                    Send error logs to 'file'.
END
    exit 1
}

# The Arduino IDE 'upload' command does both a 'compile' and 'upload'.
function verify_or_upload_using_ide() {
    local mode=$1
    local file=$2

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

    # Don't use 'eval' to avoid problems with single-quote embedded within
    # the $preprocessor variable. This unfortunately means that we duplicate the
    # Arduino IDE command twice, once to echo to the user, and another to
    # actually execute the command.
    echo '$' $AUNITER_ARDUINO_BINARY \
        --$arduino_cmd_mode \
        $verbose \
        $board_flag \
        $port_flag \
        $sketchbook_flag \
        $preserve \
        --pref "'compiler.cpp.extra_flags=-DAUNITER $preprocessor'" \
        $file
    if ! $AUNITER_ARDUINO_BINARY \
            --$arduino_cmd_mode \
            $verbose \
            $board_flag \
            $port_flag \
            $sketchbook_flag \
            $preserve \
            --pref "compiler.cpp.extra_flags=-DAUNITER $preprocessor" \
            $file; then
        echo "FAILED $arduino_cmd_mode: $env $port $file" \
            | tee -a $summary_file
        return 1
    fi

    # The verbose mode or upload (on some boards) sometimes leave a dangling
    # line w/o a newline.
    if [[ "$verbose" != '' || "$arduino_cmd_mode" == 'upload' ]]; then
        echo # blank line
    fi
}

# The Arduino-CLI 'upload' command only does the 'upload', not the 'compile'.
# Usage: verify_or_upload_using_cli (upload|test|verify) file
function verify_or_upload_using_cli() {
    local mode=$1
    local file=$2

    local board_flag="--fqbn $board"
    local port_flag=${port:+"--port $port"}
    if [[ "$mode" == 'upload' || "$mode" == 'test' ]]; then
        local arduino_cmd_mode='upload'
        local build_properties_flag=''
    else
        local arduino_cmd_mode='compile'
        local build_properties_flag="--build-properties \
'compiler.cpp.extra_flags=-DAUNITER $preprocessor'"
    fi

    # Arduino-CLI (as of v0.12.0-rc3) 'upload' command does not accept a
    # relative path to the program (??), so append $PWD if necessary.
    if [[ ! $file =~ ^/ ]]; then
        local full_path="$file"
    else
        local full_path="$PWD/$file"
    fi

    local cmd="$AUNITER_ARDUINO_BINARY \
$verbose \
$arduino_cmd_mode \
$board_flag \
$port_flag \
$build_properties_flag \
$full_path"
    echo "\$ $cmd"
    if ! eval $cmd; then
        echo "FAILED $arduino_cmd_mode: $env $port $file" \
            | tee -a $summary_file
        return 1
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
preserve=
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
        --preprocessor) shift; preprocessor="$1" ;;
        --preserve-temp-files) preserve='--preserve-temp-files' ;;
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

# Determine whether to use the Arduino IDE or the Arduino-CLI.
if [[ "$AUNITER_ARDUINO_BINARY" =~ arduino-cli ]]; then
    # Arduino-CLI 'upload' must do a manual 'compile', unlike the Arduino IDE
    # which does it automatically.
    verify_or_upload_using_cli verify $1
    if [[ $mode == 'upload' || $mode == 'test' ]]; then
        verify_or_upload_using_cli upload $1
    fi
elif [[ "$AUNITER_ARDUINO_BINARY" =~ [aA]rduino ]]; then
    verify_or_upload_using_ide $mode $1
else
    echo "Unsupported \$AUNITER_ARDUINO_BINARY: $AUNITER_ARDUINO_BINARY"
    usage
fi

if [[ "$mode" == 'test' ]]; then
    validate_test $1
fi
