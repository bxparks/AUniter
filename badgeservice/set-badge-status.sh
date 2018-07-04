#!/usr/bin/env bash
#
# Create the {project}-PASSED or {project}-FAILED marker file on the indicated
# Google Cloud Storage bucket. That file will be used by the 'badge()' function
# running in Google Functions to determine the shields.io badge to redirect to.
#
# This script tries hard to make sure that only one of {project}-PASSED or
# {project}-FAILED exists at the same time.

set -eu

function usage() {
    cat << 'END'
Usage: set-badge-status.sh {bucket} {project} {FAILED | PASSED}
END
    exit 1
}

function clean_temp_files() {
    if [[ "$temp_file" != '' ]]; then
        rm -f $temp_file
    fi
}

# Create the status file.
function create_status() {
    local bucket=$1
    local project=$2
    local status=$3

    temp_file=
    trap "clean_temp_files" EXIT
    temp_file=$(mktemp /tmp/badge_status_XXXXXX)

    gsutil -q cp $temp_file "gs://$bucket/$project-$status"
    rm -f $temp_file
}

# Remove the status file. Works even if the file doesn't exist already.
function remove_status() {
    local bucket=$1
    local project=$2
    local status=$3
    gsutil -q rm "gs://$bucket/$project-$status" > /dev/null 2>&1 || true;
}

function set_status() {
    local bucket=$1
    local project=$2
    local status=$3

    if [[ "$status" == 'FAILED' ]]; then
        remove_status $bucket $project PASSED
        create_status $bucket $project FAILED
    else
        remove_status $bucket $project FAILED
        create_status $bucket $project PASSED
    fi
}

# Check command line arguments.
if [[ $# -ne 3 ]]; then
    usage
fi
if [[ $3 != 'PASSED' && $3 != 'FAILED' ]]; then
    echo 'Status must be PASSED or FAILED'
    usage
fi

set_status "$@"
