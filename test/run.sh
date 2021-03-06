#!/bin/sh

usage() {
  echo "$0 <logfile> [<test list> | -x <exclusion list>]"
}


contains() {
  local haystack=$1
  local needle=$2

  for elem in $haystack
  do
    if [ $(readlink --canonicalize $elem) = $(readlink --canonicalize $needle) ]; then
      return 0
    fi
  done

  return 1
}


logfile=$1
if [ -z $logfile ]; then
  usage
  exit 1
fi
if ! echo "$logfile" | grep -q ^/; then
  logfile=$(pwd)/$(basename $logfile)
fi

shift
exclusions=""
if [ x$1 = "x-x" ]; then
  shift
  exclusions=$@
else
  testsuite=$@
fi
exclusions="$exclusions $CVMFS_TEST_EXCLUDE"
if [ -z "$testsuite" ]; then
  testsuite=$(find src -mindepth 1 -maxdepth 1 -type d | sort)
fi

TEST_ROOT=$(readlink -f $(dirname $0))
export TEST_ROOT

echo "Start test suite for cvmfs $(cvmfs2 --version)" > $logfile
date >> $logfile

. ./test_functions
num_failures=0
for t in $testsuite
do
  cvmfs_clean || exit 2
  workdir="${CVMFS_TEST_SCRATCH}/workdir/$t"
  rm -rf "$workdir" && mkdir -p "$workdir" || exit 3
  cvmfs_test_autofs_on_startup=true # might be overwritten by some tests
  . $t/main || exit 4
  echo "-- Testing $t (${cvmfs_test_name})" >> $logfile
  echo -n "Testing ${cvmfs_test_name}... "
  
  contains "$exclusions" $t
  exclude=$?

  if [ $exclude -eq 1 ]; then
    if $cvmfs_test_autofs_on_startup; then
      autofs_switch on >> $logfile 2>&1 || exit 5
    else
      autofs_switch off >> $logfile 2>&1 || exit 5
    fi

    sh -c ". ./test_functions && . $t/main && cd $workdir && cvmfs_run_test $logfile && retval=$? && kill_all_perl_services && exit $retval"
    RETVAL=$?
    if [ $RETVAL -eq 0 ]; then
      rm -rf "$workdir"
      echo "OK"
    else
      echo "Failed!"
      echo "Test failed with RETVAL $RETVAL" >> $logfile
      sudo cp $CVMFS_TEST_SYSLOG_TARGET $workdir
      num_failures=$(($num_failures+1))
    fi
  else
    rm -rf "$workdir"
    echo "Skipped"
  fi
done

date >> $logfile
echo "Finished test suite" >> $logfile

if [ $num_failures -ne 0 ]; then
  echo "$num_failures tests failed!"
fi

exit $num_failures

