#!/usr/bin/env bash
#
# Copyright 2018 (c) Brian T. Park <brian@xparks.net>
# MIT License
#
# Dependencies:
#   * run_arduino.sh
#   * serial_monitor.py
#   * picocom (optional)

set -eu

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
Usage: auniter.sh [-h] [flags] command [flags] [args ...]
       auniter.sh config
       auniter.sh envs
       auniter.sh ports
       auniter.sh verify|compile {env} files ...
       auniter.sh upload {env}:{port},... files ...
       auniter.sh test {env}:{port},... files ...
       auniter.sh monitor [{env}:]{port}
       auniter.sh upmon {env}:{port} file
END
}

function usage() {
    usage_common
    exit 1
}

function usage_long() {
    usage_common

    cat <<'END'

Commands:
    config  Print location of the auto-detected config file.
    envs    List the environments defined in the CONFIG_FILE.
    ports   List the tty ports and the associated Arduino boards.
    verify  Verify the compile of the sketch file(s).
    compile Alias for 'verify'.
    upload  Upload the sketch(es) to the given board at port.
    test    Upload the AUnit unit test(s), and verify pass or fail.
    monitor Run the serial terminal defined in aniter.conf on the given port.
    upmon   Upload the sketch and run the monitor upon success.

AUniter Flags
    --help          Print this help page.
    --config {file} Read configs from 'file' instead of $HOME/.auniter.conf'.
    --verbose       Verbose output from various subcommands.
    --preserve-temp-files
                    Preserve /tmp/arduino* files for further analysis.

Command Flags:
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
    local dir=$(echo $file | sed -e 's/\/*$//')
    local file=$(basename $dir)
    echo "${dir}/${file}.ino"
}

function find_config_recursively() {
    local cur_dir=$(realpath $PWD)

}

# Find the auniter.ini file.
# 1) Return the value of --config flag given as an argument, else
# 2) Look for 'auniter.ini' in the current directoyr, else
# 3) Look for 'auniter.ini' in parent directories, else
# 4) Look for 'auniter.ini' in the $HOME directory, else
# 5) Look for '.auniter.ini' in the $HOME directory.
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

# List the environments defined in the CONFIG FILE. Environment names
# have the format '[env:{name}]' in the ini file.
# Usage: list_envs config_file
function list_envs() {
    local config_file=$1
    if [[ ! -f "$config_file" ]]; then
        return
    fi
    sed -n -e 's/^\[env:\(.*\)\]/\1/p' "$config_file"
}

# Parse the {env}:{port} specifier, setting the following global variables:
#   - $env - name of the environment
#   - $env_search - non-empty indicates the env was found in auniter.ini
#   - $board_alias - board alias in auniter.ini
#   - $board - fully qualified board spec
#   - $port - /dev/ttyXXX
#   - $locking - (true|false) whether flock(1) should lock the /dev/ttyXXX
#   - $exclude - egrep pattern of files to skip
function process_env_and_port() {
    local env_and_port=$1

    # Split {env}:{port} into two fields.
    env=$(echo $env_and_port \
            | sed -E -e 's/([^:]*):?([^:]*)/\1/')
    port=$(echo $env_and_port \
            | sed -E -e 's/([^:]*):?([^:]*)/\2/')

    env_search=$(list_envs $config_file | grep $env || true)
    if [[ "$env_search" == '' ]]; then
        return
    fi

    board_alias=$(get_config "$config_file" "env:$env" board)
    board=$(get_config "$config_file" boards "$board_alias")

    port=$(resolve_port "$port")

    locking=$(get_config "$config_file" "env:$env" locking)
    locking=${locking:-true} # set to 'true' if empty

    exclude=$(get_config "$config_file" "env:$env" exclude)
    exclude=${exclude:-'^$'} # if empty, exclude nothing, not everything

    preprocessor=$(get_config "$config_file" "env:$env" preprocessor)
}

# If a port is not fully qualified (i.e. start with /), then append
# "/dev/tty" to the given port. On Linux, all serial ports seem to start
# with this prefix, so we can specify "/dev/ttyUSB0" as just "USB0".
function resolve_port() {
    local port_alias=$1
    if [[ $port_alias =~ ^/ ]]; then
        echo $port_alias
    elif [[ "$port_alias" == '' ]]; then
        echo ''
    else
        echo "/dev/tty$port_alias"
    fi
}

# Requires $envs to define the target environments as a comma-separated list
# of {env}:{port}.
function process_envs() {
    local env_and_ports=$(echo "$envs" | sed -e 's/,/ /g')
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

        if realpath $ino_file | egrep --silent "$exclude"; then
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
            --verify \
            --env $env \
            --board $board \
            --preprocessor "$preprocessor" \
            $sketchbook_flag \
            $verbose \
            $preserve \
            --summary_file $summary_file \
            $file
    else
        # flock(1) returns status 1 if the lock file doesn't exist, which
        # prevents distinguishing that from failure of run_arduino.sh.
        if [[ ! -e $port ]]; then
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

# Process build (verify, upload, or test) commands.
function handle_build() {
    local single=0
    sketchbook_flag=
    skip_missing_port=0
    while [[ $# -gt 0 ]]; do
        case $1 in
            --single) single=1 ;;
            --sketchbook) shift; sketchbook_flag="--sketchbook $1" ;;
            --skip_missing_port) skip_missing_port=1 ;;
            -*) echo "Unknown build option '$1'"; usage ;;
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
    if [[ "$single" == 1 ]]; then
        if [[ "$envs" =~ , ]]; then
            echo "Multiple environments not allowed in 'upmon' command"
            usage
        fi
        if [[ $# -gt 1 ]]; then
            echo "Multiple files not allowed in 'upmon' command"
            usage
        fi
    fi
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

# Combination of 'upload' then 'monitor' if upload goes ok.
function handle_upmon() {
    mode=upload
    handle_build --single "$@"

    mode=monitor
    run_monitor $port $baud "$monitor"
}

# Read in the default flags in the [auniter] section of the config file.
function read_default_configs() {
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
    echo "$config_file"
}

# Parse auniter command line flags
function main() {
    mode=
    verbose=
    preserve=
    local config=
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h) usage_long ;;
            --config) shift; config=$1 ;;
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
    check_environment_variables
    create_temp_files
    case $mode in
        config) print_config $config_file;;
        envs) list_envs $config_file;;
        ports) list_ports ;;
        verify|compile) handle_build "$@" ;;
        upload) handle_build "$@" ;;
        test) handle_build "$@" ;;
        monitor) handle_monitor "$@" ;;
        upmon) handle_upmon "$@" ;;
        *) echo "Unknown command '$mode'"; usage ;;
    esac
}

main "$@"
