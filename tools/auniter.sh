#!/usr/bin/env bash
#
# Copyright 2018 (c) Brian T. Park <brian@xparks.net>
# MIT License
#
# Dependencies:
#
#   * ./run_arduino.sh
#   * ./serial_monitor.py
#   * Python3 (3.7 or 3.8 should work)
#       * $ sudo apt install python3 python3-pip (Linux)
#       * $ brew install python3 (MacOS)
#   * Python serial
#       * $ pip3 install --user serial
#   * picocom
#       * $ sudo apt install picocom (Linux)
#       * $ brew install picocom (MacOS)
#   * MacOS only
#       * $ brew install coreutils gsed

set -eu

# Find the GNU version of various binaries on MacOS.
case $(uname -s) in
    Darwin*)
        SED=gsed
        REALPATH=grealpath
        ;;
    Linux*)
        SED=sed
        REALPATH=realpath
        ;;
    *)
        echo 'Unsupported Unix-like OS'
        ;;
esac


# Can't use $(realpath $(dirname $0)) because realpath doesn't exist on MacOS
DIRNAME=$(dirname $0)

# Default config file in the absence of --config flag.
CONFIG_FILE=$HOME/.auniter.ini

# Number of seconds that flock(1) will wait on a serial port.
# Can be overridden by "[auniter] port_timeout" parameter.
PORT_TIMEOUT=120

# Default baud rate of the serial port.
PORT_BAUD=115200

# Status code returned by flock(1) if it times out.
FLOCK_TIMEOUT_CODE=10

function usage_common() {
    cat <<'END'
Usage: auniter.sh [-h] [auniter_flags] command [command_flags] [args ...]
       auniter.sh config
       auniter.sh envs
       auniter.sh ports
       auniter.sh verify {env} files ...
       auniter.sh compile {env} files ...
       auniter.sh upload {env}:{port},... files ...
       auniter.sh test {env}:{port},... files ...
       auniter.sh monitor|mon [{env}:]{port}
       auniter.sh upmon [(--output|-o) outfile] [--eof {eof}] {env}:{port} file
END
}

function usage() {
    usage_common
    exit 1
}

function usage_long() {
    usage_common

    cat <<'END'

AUniter Flags (auniter_flags):
    --help          Print this help page.
    --config {file} Read configs from 'file' instead of $HOME/.auniter.conf'.
    --ide           Use the Arduino IDE binary (arduino or Arduino) defined
                    by $AUNITER_ARDUINO_BINARY.
    --cli           Use the Arduino-CLI binary (arduino-cli) defined by
                    $AUNITER_ARDUINO_CLI.
    --verbose       Verbose output from various subcommands.
    --preserve      Preserve /tmp/arduino* files for further analysis.

Commands (command):
    config  Print location of the auto-detected config file.
    envs    List the environments defined in the CONFIG_FILE.
    ports   List the tty ports and the associated Arduino boards.
    verify  Verify the compile of the sketch file(s).
    compile Alias for 'verify'.
    upload  Upload the sketch(es) to the given board at port.
    test    Upload the AUnit unit test(s), and verify pass or fail.
    monitor Run the serial terminal defined in aniter.conf on the given port.
    mon     Alias for 'monitor'.
    upmon   Upload the sketch and run the monitor upon success. If the --output
            (or -o) flag is given, the output is saved to the given output file.
            The default EOF string is '' which means only the 10 second timeout
            will terminate the file. If --eof is given, the program will return
            to the user right after the EOF string is detected. The EOF string
            will be included in the output file.

Command Flags (command_flags):
    --baud baud
        (monitor, upmon) Speed of the serial port for serial_montor.py.
        (Default: 115200. The default value can be changed in CONFIG_FILE.)
    --sketchbook {path}
        (verify, upload, test, upmon) Set the Arduino sketchbook directory to
        {path}. Useful in Jenkinsfile to tell the Arduino IDE binary to use a
        different directory as the sketchbook home.
    --skip_missing_port
        (upload, test) Just perform a 'verify' if --port or {:port} is missing.
        Useful in Continuous Integration on multiple boards where only some
        boards are actually connected to a serial port.
    -D MACRO=value
        Add the 'MACRO' to the C-preprocessor with the 'value'. Multiple -D
        flags can be given. The space after the -D is required.

Files:
    Multiple *.ino files and directories may be given. If a directory is given,
    then the script looks for an Arduino sketch file under the directory with
    the same name but ending with '.ino'. For example, './auniter.sh CommonTest'
    is equivalent to './auniter.sh CommonTest/CommonTest.ino' if CommonTest is a
    directory.
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
    local dir=$(echo $file | $SED -e 's/\/*$//')
    local file=$(basename $dir)
    echo "${dir}/${file}.ino"
}

# Find the auniter.ini file, in the following order:
# 1) Return the value of --config flag given as an argument, else
# 2) Look for 'auniter.ini' in the current directory, else
# 3) Look for 'auniter.ini' in parent directories, else
# 4) Look for '$HOME/auniter.ini', else
# 5) Look for '$HOME/.auniter.ini'.
#
# Usage: find_config_file {config_path}
# If "config_path" is empty, then use the algorithm above to find the
# auniter.ini file.
function find_config_file() {
    # Check if the --config flag was given
    local config=$1
    if [[ "$config" != '' ]]; then
        echo "$config"
        return
    fi

    # Look for 'auniter.ini' in the current directory or any parent directory
    local save_dir=$PWD
    local found=0
    while true; do
        if [[ -e auniter.ini ]]; then
            echo "$PWD/auniter.ini"
            found=1
            break
        fi

        if [[ "$PWD" == '/' ]]; then
            break
        fi

        cd ..
    done
    cd $save_dir
    if [[ $found == '1' ]]; then
        return
    fi

    # Check for $HOME/auniter.ini
    if [[ -e "$HOME/auniter.ini" ]]; then
        echo "$HOME/auniter.ini"
        return
    fi

    # Finally check for $HOME/.auniter.ini, mostly for backwards compatibility.
    if [[ -e "$HOME/.auniter.ini" ]]; then
        echo "$HOME/.auniter.ini"
        return
    fi

    echo ''
}


# Find the given $key in a $section from the $config file.
#
# Usage: get_config config section key
#
# The config file is expected to be in an INI file format:
#   [section]
#       {key} = {value}
#       ...
#   [...]
#       ...
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
    $SED -n -E -e \
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

# List the environments defined in the CONFIG FILE. Environment names
# have the format '[env:{name}]' in the ini file.
# Usage: list_envs config_file
function list_envs() {
    local config_file=$1
    if [[ ! -f "$config_file" ]]; then
        return
    fi
    $SED -n -e 's/^\[env:\(.*\)\]/\1/p' "$config_file"
}

# Parse the {env}:{port} specifier, setting the following global variables:
#   - $env - name of the environment
#   - $env_search - non-empty indicates the env was found in auniter.ini
#   - $board_alias - board alias in auniter.ini
#   - $board - fully qualified board spec
#   - $port - /dev/ttyXXX
#   - $locking - (true|false) whether flock(1) should lock the /dev/ttyXXX
#   - $exclude - egrep pattern of files to skip
#   - $preprocessor - '-D' flags to pass to the cpp C-preprocessor
function process_env_and_port() {
    local env_and_port=$1

    # Split {env}:{port} into two fields.
    env=$(echo $env_and_port \
            | $SED -E -e 's/([^:]*):?([^:]*)/\1/')
    port=$(echo $env_and_port \
            | $SED -E -e 's/([^:]*):?([^:]*)/\2/')

    env_search=$(list_envs $config_file | grep $env || true)
    if [[ "$env_search" == '' ]]; then
        return
    fi

    board_alias=$(get_config "$config_file" "env:$env" board)
    board=$(get_config "$config_file" boards "$board_alias")

    port=$(resolve_port "$port")

    # No flock(1) on MacOS.
    if [[ $(uname -s) =~ Darwin.* ]]; then
        echo "Cannot lock '$port' on MacOS. Continuing without locking..."
        locking=false
    else
        locking=$(get_config "$config_file" "env:$env" locking)
        locking=${locking:-true} # set to 'true' if empty
    fi

    exclude=$(get_config "$config_file" "env:$env" exclude)
    exclude=${exclude:-'^$'} # if empty, exclude nothing, not everything

    # Get the CPP macros from auniter.ini.
    preprocessor=$(get_config "$config_file" "env:$env" preprocessor)
}

# If a port is not fully qualified (i.e. start with /), then append
# "/dev/tty" to the given port. On Linux, all serial ports seem to start
# with this prefix, so we can specify "/dev/ttyUSB0" as just "USB0". If
# port is "none", then just return "none".
function resolve_port() {
    local port_alias=$1
    if [[ $port_alias =~ ^/ ]]; then
        echo $port_alias
    elif [[ "$port_alias" == 'none' ]]; then
        echo 'none'
    elif [[ "$port_alias" == '' ]]; then
        echo ''
    else
        echo "/dev/tty$port_alias"
    fi
}

# Requires $envs to define the target environments as a comma-separated list
# of {env}:{port}.
function process_envs() {
    local env_and_ports=$(echo "$envs" | $SED -e 's/,/ /g')
    for env_and_port in $env_and_ports; do
        process_env_and_port $env_and_port

        echo "======== Processing environment '$env_and_port'"
        if [[ "$env_search" == '' ]]; then
            echo "FAILED $mode: Unknown environment '$env'" \
                | tee -a $summary_file
            continue
        fi
        if [[ "$board" == '' ]]; then
            echo "FAILED $mode: board '$board_alias' not found" \
                | tee -a $summary_file
            continue
        fi
        if [[ "$port" == '' && "$mode" != 'verify' ]]; then
            if [[ "$skip_missing_port" == 0 ]]; then
                echo "FAILED $mode: Unknown port for $env" \
                    | tee -a $summary_file
            else
                echo "SKIPPED $mode: Unknown port for $env" \
                    | tee -a $summary_file
            fi
            continue
        fi

        # Determine the effective $preprocessor for the current environment by
        # adding the '-D macro' flags given on the 'auniter.sh' command line.
        preprocessor="$preprocessor $cli_preprocessor"

        process_files "$@"
    done
}

# Requires $board and $port to define the target environment.
function process_files() {
    local file
    for file in "$@"; do
        local ino_file=$(get_ino_file $file)
        if [[ ! -f $ino_file ]]; then
            echo "FAILED $mode: $env: file not found: $ino_file" \
                | tee -a $summary_file
            continue
        fi

        if $REALPATH $ino_file | egrep --silent "$exclude"; then
            echo "SKIPPED $mode: $env: excluding $file" \
                | tee -a $summary_file
            continue
        fi

        process_file $ino_file
    done
}

# Requires $board and $port to define the target environment.
function process_file() {
    local file=$1
    echo "-------- Processing file '$file'"

    if [[ "$mode" == 'verify' || "$mode" == 'compile' ]]; then
        # Allow multiple verify commands to run at the same time.
        $DIRNAME/run_arduino.sh \
            --$cli_option \
            --verify \
            --env $env \
            --board $board \
            --preprocessor "$preprocessor" \
            $clean \
            $sketchbook_flag \
            $verbose \
            $preserve \
            --summary_file $summary_file \
            $file
    else # $mode == 'test' | 'upload'
        # flock(1) returns status 1 if the lock file doesn't exist, which
        # prevents distinguishing that from failure of run_arduino.sh.
        if [[ "$port" != 'none' && ! -e "$port" ]]; then
            echo "FAILED $mode: $env: cannot find port $port: $file" \
                | tee -a $summary_file
            return
        fi

        # Use flock(1) to prevent multiple uploads to the same board at the same
        # time.
        local timeout=${port_timeout:-$PORT_TIMEOUT}
        if [[ "$locking" == 'true' ]]; then
            echo "Enabling flock on serial port $port"
            local flock="flock --timeout $timeout --conflict-exit-code \
                $FLOCK_TIMEOUT_CODE $port"
        else
            echo "Disabling flock on serial port $port"
            local flock=''
        fi
        local status=0; $flock $DIRNAME/run_arduino.sh \
            --$cli_option \
            --$mode \
            --env $env \
            --board $board \
            --port $port \
            --baud $baud \
            $sketchbook_flag \
            --preprocessor "$preprocessor" \
            $verbose \
            $preserve \
            --summary_file $summary_file \
            "$file" || status=$?

        if [[ "$status" == $FLOCK_TIMEOUT_CODE ]]; then
            echo "FAILED $mode: $env: could not obtain lock on $port: $file" \
                | tee -a $summary_file
        elif [[ "$status" != 0 ]]; then
            echo "FAILED $mode: $env: run_arduino.sh failed on $file" \
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
    local cli_option=$1

    # Check for AUNITER_ARDUINO_BINARY
    if [[ "$cli_option" == 'ide' ]]; then
        if [[ -z ${AUNITER_ARDUINO_BINARY+x} ]]; then
            echo "AUNITER_ARDUINO_BINARY environment variable is not defined"
            exit 1
        fi
        if [[ ! -x $AUNITER_ARDUINO_BINARY ]]; then
            echo "AUNITER_ARDUINO_BINARY=$AUNITER_ARDUINO_BINARY \
is not executable"
            exit 1
        fi

        echo "Using IDE: AUNITER_ARDUINO_BINARY=$AUNITER_ARDUINO_BINARY"
    fi

    # Check for AUNITER_ARDUINO_CLI
    if [[ "$cli_option" == 'cli' ]]; then
        if [[ -z ${AUNITER_ARDUINO_CLI+x} ]]; then
            echo "AUNITER_ARDUINO_CLI environment variable is not defined"
            exit 1
        fi
        if [[ ! -x $AUNITER_ARDUINO_CLI ]]; then
            echo "AUNITER_ARDUINO_CLI=$AUNITER_ARDUINO_CLI is not executable"
            exit 1
        fi

        echo "Using CLI: AUNITER_ARDUINO_CLI=$AUNITER_ARDUINO_CLI"
    fi
}

function interrupted() {
    echo 'Interrupted'
    print_summary_file
    exit 1
}

# Process the build command (verify, upload, or test). Depends on 'mode' to be
# set properly ('verify', 'upload', 'test').
function handle_build() {
    cli_preprocessor=
    sketchbook_flag=
    skip_missing_port=0
    while [[ $# -gt 0 ]]; do
        case $1 in
            --clean) clean='--clean' ;;
            -D) shift; cli_preprocessor="$cli_preprocessor -D $1" ;;
            --sketchbook) shift; sketchbook_flag="--sketchbook $1" ;;
            --skip_missing_port) skip_missing_port=1 ;;
            -*) echo "Unknown build option '$1'"; usage ;;
            *) break ;;
        esac
        shift
    done

    handle_envs_and_files "$@"
}

# Usage: handle_envs_and_files {env:xxx},{env:yyy} [file ...]
# The environments are given as a comma-separated list.
# The files are given as a space-separated list.
# If the file is missing, look for a '*.ino' file in the current directory.
function handle_envs_and_files() {
    if [[ $# -lt 1 ]]; then
        echo 'No environment given'
        usage
    fi
    envs=$1
    shift

    local files
    if [[ $# -lt 1 ]]; then
        # Check for a sketch file named *.ino in the current directory.
        local current_dir=$(basename $PWD)
        files=${current_dir}.ino
        if [[ ! -e "$files" ]]; then
            echo "No sketch file given and *.ino not found in current directory"
            usage
        fi
    else
        files="$@"
    fi

    process_envs $files
    print_summary_file
}

function list_ports() {
    $DIRNAME/serial_monitor.py --list
}

# Usage: run_monitor $port $buad $monitor
# Determine the external terminal program and run it with $port and $baud.
function run_monitor() {
    local port=$1
    local baud=$2
    local monitor=$3
    if [[ "$monitor" == '' ]]; then
        echo "Property 'monitor' must be defined in $config_file"
        usage
    fi

    # Execute the monitor command as listed in the CONFIG_FILE.
    eval "$monitor"
}

# Run the serial monitor on the given port specifier. The port can be
# given as "{env}:{port}" or just "{port}". The command for the serial monitor
# comes from the 'monitor' property in section '[auniter]'. An example that
# works well for me is:
# [auniter]
#   monitor = picocom -b $baud --omap crlf --imap lfcrlf --echo $port
function handle_monitor() {
    # Process flags.
    while [[ $# -gt 0 ]]; do
        case $1 in
            --baud) shift; baud=$1 ;;
            -*) echo "Unknown monitor option '$1'"; usage ;;
            *) break ;;
        esac
        shift
    done

    # Get the port from the next arg.
    if [[ $# -lt 1 ]]; then
        echo 'No port given for 'monitor' command'
        usage
    fi
    port=$1
    shift

    # If the port_specifier is {env}:{port}, extract the {port}. If there
    # is no ':', then assume that it's just the port.
    if [[ "$port" =~ : ]]; then
        process_env_and_port "$port"
    else
        port=$(resolve_port $port)
    fi

    if [[ "$port" == '' ]]; then
        echo 'No port given for 'monitor' command'
        usage
    fi

    run_monitor $port $baud "$monitor"
}

# Save the serial output to an output file, instead of displaying it on the
# screen.
function run_save() {
    local port=$1
    local baud=$2
    local eof="$3"
    local output="$4"

    $DIRNAME/serial_monitor.py --monitor --port $port --eof "$eof" |
        tee "$output"
}

# Combination of 'upload' then 'monitor' if upload goes ok. Simiilar to
# handle_build() but supports additional flags: --output and --eof.
function handle_upmon() {
    local eof=''
    local output=''
    cli_preprocessor=
    sketchbook_flag=
    skip_missing_port=0
    while [[ $# -gt 0 ]]; do
        case $1 in
            --eof) shift; eof="$1" ;;
            --output|-o) shift; output="$1" ;;
            -D) shift; cli_preprocessor="$cli_preprocessor -D $1" ;;
            --sketchbook) shift; sketchbook_flag="--sketchbook $1" ;;
            --skip_missing_port) skip_missing_port=1 ;;
            -*) echo "Unknown upmon flag '$1'"; usage ;;
            *) break ;;
        esac
        shift
    done

    if [[ $# -lt 1 ]]; then
        echo 'No environment given'
        usage
    fi
    envs=$1
    shift
    if [[ "$envs" =~ , ]]; then
        echo "Multiple environments not allowed in 'upmon' command"
        usage
    fi
    if [[ $# -gt 1 ]]; then
        echo "Multiple files not allowed in 'upmon' command"
        usage
    fi

    mode=upload
    handle_envs_and_files $envs "$@"

    if [[ "$output" != '' ]]; then
        mode=save # setting mode not needed, but preserves consistency
        run_save $port $baud "$eof" "$output"
    else
        mode=monitor
        run_monitor $port $baud "$monitor"
    fi
}

# Read in the default flags in the [auniter] section of the config file.
# Set the following global variables:
#   * monitor
#   * baud
#   * port_timeout
function read_default_configs() {
    echo "Reading config: $config_file"

    monitor=$(get_config "$config_file" 'auniter' 'monitor')

    local baud_value=$(get_config "$config_file" 'auniter' 'baud')
    baud=${baud_value:-$PORT_BAUD}

    local port_timeout_value=$(get_config "$config_file" 'auniter' \
        'port_timeout')
    port_timeout=${port_timeout_value:-$PORT_TIMEOUT}
}

# Print the current config file
function print_config() {
    local config_file="$1"
    echo "+ cat $config_file"
    cat "$config_file"
}

# Parse auniter command line flags
function main() {
    local config=

    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h) usage_long ;;
            --config) shift; config=$1 ;;
            --cli) cli_option='cli' ;;
            --ide) cli_option='ide' ;;
            --verbose) verbose='--verbose' ;;
            --preserve) preserve='--preserve-temp-files' ;;
            -*) echo "Unknown auniter option '$1'"; usage ;;
            *) break ;;
        esac
        shift
    done
    if [[ $# -lt 1 ]]; then
        echo 'Must provide a command (verify, upload, test, monitor, ports)'
        usage
    fi
    mode=$1
    shift

    # Determine the location of the config file.
    config_file=$(find_config_file "$config")
    if [[ "$config_file" == '' ]]; then
        echo 'Cannot find auniter.ini in any directory'
        usage
        exit 1
    fi

    # Must install a trap for Control-C because the script ignores almost all
    # interrupts and continues processing.
    trap interrupted INT

    read_default_configs
    check_environment_variables $cli_option
    create_temp_files
    case $mode in
        config) print_config $config_file;;
        envs) list_envs $config_file;;
        ports) list_ports ;;
        verify|compile) mode='verify'; handle_build "$@" ;;
        upload) handle_build "$@" ;;
        test) handle_build "$@" ;;
        monitor|mon) handle_monitor "$@" ;;
        upmon) handle_upmon "$@" ;;
        *) echo "Unknown command '$mode'"; usage ;;
    esac
}

# Define the initial set of global variables. A whole bunch more are defined by
# process_env_and_port() function.
#
# TODO(brian): Too many global variables are used in this script, indicating
# that this has probably outgrown the reasonable limits of bash(1). I should
# probably migrate this to something else, like Python. But the Python
# deployment story is so freaking complicated. Too many Python versions, too
# many python environments, needing to support different Operating Systems.
mode=
verbose=
preserve=
clean=
cli_option='ide'
config_file=
summary_file=
cli_preprocessor=
sketchbook_flag=
skip_missing_port=0
main "$@"
