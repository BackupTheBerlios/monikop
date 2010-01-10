#! /bin/bash

# Debian: install packages bc, time

TESTDIR=/tmp/monikop-test
DEV=$TESTDIR/dev
MNT=$TESTDIR/mnt
LOG=$TESTDIR/log
TEST_COUNT=0
FAIL_COUNT=0
FAILED_TESTS=""

# make_test_drive <name> <size>
function make_test_drive {
    mkdir -p $MNT/$1
    dd if=/dev/zero of=$DEV/$1 bs=1024 count=$2 2> /dev/null
    /sbin/mkfs.ext3 -m 0 -Fq $DEV/$1
}

# make_test_file <name> <size> <date>
function make_test_file {
    dd if=/dev/zero of=$1 bs=1024 count=$2 2> /dev/null
    echo ++++++++++++++++++++++++++$RANDOM***$3---$1 >> $1
    touch -t $3 $1
}

# find_and_compare <origin_dir> <origin_dir> ... :: <copy_dir> <copy_dir> ...
function find_and_compare {
    origin_dirs=$1; shift;
    until [[ $1 == "::" ]]; do
        origin_dirs="$origin_dirs $1"; shift;
    done
    shift
    missing=""
    diverging=""
    diverging_mtime=""
    return_value=0
    for i in `find $origin_dirs -type f 2> /dev/null`; do
        found=`find $@ -path "$MNT/*/measuring_data/${i#$MNT/*/data/}"`
        if [[ $found == "" ]] ; then
            missing="$missing $i";
        elif ! cmp --quiet $i $found; then
            diverging="$diverging $i"
        elif [[ `stat --printf="%Y" $i` != `stat --printf="%Y" $found` ]]; then
            diverging_mtime="$diverging_mtime $i"
        fi
    done
    if [[ $missing != "" ]]; then
        return_value=1
        echo "MISSING: $missing"
    fi
    if [[ $diverging != "" ]]; then
        return_value=$((return_value + 2))
        echo "DIVERGING: $diverging"
    fi
    if [[ $diverging_mtime != "" ]]; then
        return_value=$((return_value + 4))
        echo "DIVERGING MTIME: $diverging_mtime"
    fi
    return $return_value
}

# run_test <expected_return> <command>
function run_test {
    TEST_COUNT=$(( TEST_COUNT + 1 ))
    $2
    RETURN_VALUE=$?
    if [[ $RETURN_VALUE -ne $1 ]]; then
        FAIL_COUNT=$(( FAIL_COUNT + 1 ))
        FAILED_TESTS="$FAILED_TESTS$2($1? $RETURN_VALUE!)\n"
        echo "$2 should have returned $1 but returned $RETURN_VALUE instead."
    fi
}

umount $MNT/* 2> /dev/null
rm -rf $DEV $MNT $LOG
mkdir -p $DEV $MNT

# Create and mount test drives:
for i in 01 02 03 04; do
    make_test_drive $i 102400
    if ! mount $MNT/$i 2> /dev/null; then
        echo "# Can't mount $DEV/$i to $MNT/$i."
        echo "# Redo from start after adding the following line to your /etc/fstab:"
        echo 
        echo "   $DEV/$i $MNT/$i ext3 loop,user,noauto 0 0"
        echo
        MOUNTING_PROBLEM=1
    fi
done
if [[ $MOUNTING_PROBLEM == 1 ]]; then exit; fi


# Prepare data sources:
mkdir -p $MNT/01/data/d1/d2
mkdir -p $MNT/02/data/d1/d2
for i in f1 f2 f3; do
    make_test_file $MNT/01/data/$i 25000 200703250845.33
done
for i in f10 f11 f12; do
    make_test_file $MNT/02/data/$i 25000 200703250845.33
done
for i in f4 f5 f6; do
    make_test_file $MNT/01/data/d1/$i 2000 200703250845.33
    make_test_file $MNT/01/data/d1/d2/$i 2000 200703250845.33
done
for i in f7 f8 f9; do
    make_test_file $MNT/02/data/d1/$i 2000 200703250845.33
    make_test_file $MNT/02/data/d1/d2/$i 2000 200703250845.33
done


# Check how fast we are:

T1=`/usr/bin/time --format="%e" rsync --recursive --times $MNT/01/data/ $MNT/03/ 2>&1 &`
T2=`/usr/bin/time --format="%e" rsync --recursive --times $MNT/02/data/ $MNT/04/ 2>&1 &`
INTERRUPTION_TIME_0=`echo "($T1 + $T2) * 1.5" | bc`
INTERRUPTION_TIME_1=`echo "($T1 + $T2) * .16" | bc`
INTERRUPTION_TIME_2=`echo "($T1 + $T2) * .82" | bc`
echo $INTERRUPTION_TIME_1
rm -rf $MNT/03/* $MNT/04/*

# Stuff one of the destinations a bit:
# make_test_file $MNT/03/stuffing 25000 199903250845

function test_monikop_simple {
    ../monikop ../test/monikop.config.test & sleep $INTERRUPTION_TIME_1; /bin/kill -TERM $!
    find_and_compare /tmp/monikop-test/mnt/01/data /tmp/monikop-test/mnt/02/data :: /tmp/monikop-test/mnt/04/measuring_data /tmp/monikop-test/mnt/03/measuring_data
}

run_test 0 test_monikop_simple
run_test 0 test_monikop_simple

echo $TEST_COUNT
echo $FAIL_COUNT
echo -e $FAILED_TESTS

exit
../monikop ../test/monikop.config.test & sleep $INTERRUPTION_TIME_2; /bin/kill -TERM $!
sleep 2
find_and_compare /tmp/monikop-test/mnt/01/data /tmp/monikop-test/mnt/02/data :: /tmp/monikop-test/mnt/04/measuring_data /tmp/monikop-test/mnt/03/measuring_data
if [[ $? -eq 0 ]]; then
    echo "Shouldn't be finished at this stage!"
else
    echo "This is nothing to worry about."
fi
../monikop ../test/monikop.config.test & sleep $INTERRUPTION_TIME_2; /bin/kill -TERM $!
sleep 2
../monikop ../test/monikop.config.test & sleep $INTERRUPTION_TIME_2; /bin/kill -TERM $!
find_and_compare /tmp/monikop-test/mnt/01/data /tmp/monikop-test/mnt/02/data :: /tmp/monikop-test/mnt/04/measuring_data /tmp/monikop-test/mnt/03/measuring_data
echo $?
#../monikop monikop.config.test & sleep $INTERRUPTION_TIME_1; kill $!
# ../monikop ../test/pokinom.config.test & sleep $INTERRUPTION_TIME_1; killall rsync (make sure we kill only our rsyncs)
#
#
#