#!/bin/sh

set -u

CHECKPATCH=./checkpatch.pl

suite_status=0

# @number - expected exit code
# @string - checkpatch.pl options
run_test() {
    expected_exit_code=$1
    checkpatch_opts=$2

    shift
    cmd="$CHECKPATCH $checkpatch_opts"
    test_output=$($cmd 2>&1 > /dev/null)
    rc=$?
    test_status="NOT OK"
    if [ "$rc" -eq "$expected_exit_code" ]; then
        test_status="OK"
    else
        suite_status=1
    fi
    printf "%8s %s\n" "[$test_status]" "$cmd"
}

run_test 0 "patches/test1.patch"
run_test 0 "patches/test2.patch"

exit $suite_status
