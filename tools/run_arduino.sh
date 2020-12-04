#!/usr/bin/env bash
#
# Copyright 2018 (c) Brian T. Park <brian@xparks.net>
# MIT License

set -eu

# Can't use $(realpath $(dirname $0)) because realpath doesn't exist on MacOS
DIRNAME=$(dirname $0)

function usage() {
    cat <<'END'
Usage: run_arduino.sh [--help] [--verbose] [--cli | --ide]
    [--verify | --upload | --test]
    [--env {env}] [--board {board}] [--port {port}] [--baud {baud}]
    [--sketchbook {path}] [--preprocessor {flags}] [--preserve]
    [--summary_file file] file.ino

Helper shell wrapper around the 'arduino' commandline binary and the
'serial_monitor.py' script. This allows the 'auniter.sh' to wrap a flock(1)
command around the serial port to prevent concurrent access to the arduino
board. This script is not meant to be used by the end-user.

Flags:
    --ide           Use the Arduino IDE binary given by AUNITER_ARDUINO_BINARY.
    --cli           Use the Arduino-CLI binary given by AUNITER_ARDUINO_CLI.
    --verify        Verify the compile of the sketch file(s).
    --upload        Compile and upload the given program.
    --test          Verify the AUnit test after uploading the program.
    --env {env}     Name of the current build environment, for error messages.
    --board {fqbn}  Fully qualified board name (fqbn).
    --port {port}   Serial port device (e.g. /dev/ttyUSB0).
    --baud {baud}   Speed of the serial port.
    --sketchbook {path}
                    Home directory of the sketch, for resolving libraries.
    --preprocessor {flags}
                    Build flags of the form '-D MACRO -D MACRO=value' as a
                    single argument (must be quoted if multiple macros).
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
        --pref "'compiler.cpp.extra_flags=-D AUNITER $preprocessor'" \
        $file
    if ! $AUNITER_ARDUINO_BINARY \
            --$arduino_cmd_mode \
            $verbose \
            $board_flag \
            $port_flag \
            $sketchbook_flag \
            $preserve \
            --pref "compiler.cpp.extra_flags=-D AUNITER $preprocessor" \
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
#
# Arduino-CLI (as of v0.12.0-rc3) 'upload' command does not accept a
# relative path to the program (??), so append $PWD if necessary.
# Fortunately the 'compile --upload' variant will accept a relative path, so
# we no longer have to convert the file into its absolute path.
function verify_or_upload_using_cli() {
    local mode=$1
    local file=$2

    local board_flag="--fqbn $board"
    local port_flag=${port:+"--port $port"}
    local arduino_cmd_mode='compile'
    local upload_flag=''
    local extra_flags="-D AUNITER $preprocessor"
    local build_properties_value="compiler.cpp.extra_flags=$extra_flags"
    if [[ "$mode" == 'upload' || "$mode" == 'test' ]]; then
        upload_flag='--upload'
    fi

    echo "\$ $AUNITER_ARDUINO_CLI \
$verbose \
$arduino_cmd_mode \
$upload_flag \
$board_flag \
$port_flag \
--build-properties $build_properties_value \
$file"

    # Unfortunately, arduino-cli does not parse the --build-properties flag
    # properly if the value contains embedded quotes, which happens if the -D
    # symbol defines a c-string (in quotes). I've tried every combination of
    # escaping and backslashes in $build_properties_value, cannot get this to
    # work. The 'auniter.sh' will detect this condition and fail immediately
    # before this script is called.
    if ! $AUNITER_ARDUINO_CLI \
$verbose \
$arduino_cmd_mode \
$upload_flag \
$board_flag \
$port_flag \
--build-properties "$build_properties_value" \
$file; then
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
cli_option='ide'
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h) usage ;;
        --cli|-c) cli_option='cli' ;;
        --ide|-i) cli_option='ide' ;;
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
if [[ "$cli_option" == 'cli' ]]; then
    verify_or_upload_using_cli $mode $1
elif [[ "$cli_option" == 'ide' ]]; then
    verify_or_upload_using_ide $mode $1
else
    echo "Unsupported cli_option '$cli_option'"
    usage
fi

if [[ "$mode" == 'test' ]]; then
    validate_test $1
fi
