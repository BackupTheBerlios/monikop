#! /bin/bash

# Caveats: kills all killable rsyncs
#          don't disturb test timing by putting too much (extra) load on the machine

TESTDIR=/tmp/monikop-test
DEV=$TESTDIR/dev
MNT=$TESTDIR/mnt
LOG=$TESTDIR/log
RSYNC=$TESTDIR/rsync
MONIKOP_1="../monikop ../test/monikop.config.test.1"
MONIKOP_2="../monikop ../test/monikop.config.test.2"
MONIKOP_3="../monikop ../test/monikop.config.test.3"
POKINOM="../pokinom ../test/pokinom.config.test"
TEST_COUNT=0
FAIL_COUNT=0
FAILED_TESTS=""

function kill_rsyncd {
    kill `cat $TESTDIR/rsync/rsyncd.pid`
}

function start_rsyncd {
    kill_rsyncd 2> /dev/null
    rm -f $RSYNC/rsyncd.pid 2> /dev/null
    chmod o-rwx ../test/rsyncd.secrets.test
    rsync --daemon --config=../test/rsyncd.conf.test
}

# make_test_drive <name> <size>
function make_test_drive {
    mkdir -p $MNT/$1
    dd if=/dev/zero of=$DEV/$1 bs=1024 count=$2 2> /dev/null
    /sbin/mkfs.ext3 -m 0 -Fq $DEV/$1
    if ! mount $MNT/$1 2> /dev/null; then
        echo "# Can't mount $DEV/$1 to $MNT/$1."
        echo "# Redo from start after adding the following line to your /etc/fstab:"
        echo 
        echo "   $DEV/$1 $MNT/$1 ext3 loop,user,noauto 0 0"
        echo
        return 1
    fi
}

# make_test_file <name> <size> <date>
function make_test_file {
    mkdir -p `dirname "$1"`
    dd if=/dev/zero of="$1" bs=1024 count=$2 2> /dev/null
    echo "++++++++++++++++++++++++++$RANDOM***$3---$1" >> "$1"
    touch -t $3 $1
}

## # find_and_compare <origin_dir> <origin_dir> ... :: <copy_dir> <copy_dir> ...
## function find_and_compare {
##     ORIGIN_DIRS=$1; shift;
##     until [[ $1 == "::" ]]; do
##         ORIGIN_DIRS="$ORIGIN_DIRS $1"; shift;
##     done
##     shift
##     COPY_DIRS=$@
##     MISSING=""
##     DIVERGING=""
##     DIVERGING_MTIME=""
##     RETURN_VALUE=0
##     for ORIGIN_DIR in $ORIGIN_DIRS; do
##         find $ORIGIN_DIR -type f -print0 2> /dev/null | while read -d $'\000' ORIGIN_FILE; do
##             for COPY_DIR in $COPY_DIRS; do
##                 NAME_IN_COPY_DIR=$COPY_DIR/${ORIGIN_FILE#$ORIGIN_DIR/}
##                 FOUND=`find $COPY_DIR -path "$NAME_IN_COPY_DIR" -print 2> /dev/null`
##                 if [[ $FOUND != "" ]] ; then
##                     break
##                 fi
##             done
##             if [[ $FOUND == "" ]] ; then
##                 MISSING="$MISSING $ORIGIN_FILE";
##                 echo "M: $MISSING"
##             elif ! cmp --quiet "$ORIGIN_FILE" "$FOUND"; then
##                 DIVERGING="$DIVERGING $ORIGIN_FILE"
##             elif [[ `stat --printf="%Y" $ORIGIN_FILE` != `stat --printf="%Y" $FOUND` ]]; then
##                 DIVERGING_MTIME="$DIVERGING_MTIME $ORIGIN_FILE"
##             fi
##             echo "MM: $MISSING"
##         done
##         echo "MMM: $MISSING"
##     done
##     echo "MMMM: $MISSING"
## 
##     if [[ $MISSING != "" ]]; then
##         RETURN_VALUE=1
##         echo "MISSING: $MISSING"
##     fi
##     if [[ $DIVERGING != "" ]]; then
##         RETURN_VALUE=$((return_value + 2))
##         echo "DIVERGING: $DIVERGING"
##     fi
##     if [[ $DIVERGING_MTIME != "" ]]; then
##         RETURN_VALUE=$((return_value + 4))
##         echo "DIVERGING MTIME: $DIVERGING_MTIME"
##     fi
##     return $RETURN_VALUE
## }
## 

# find_and_compare <origin_dir> <origin_dir> ... :: <copy_dir> <copy_dir> ...
function find_and_compare {
    ORIGIN_DIRS=$1; shift;
    until [[ $1 == "::" ]]; do
        ORIGIN_DIRS="$ORIGIN_DIRS $1"; shift;
    done
    shift
    COPY_DIRS=$@
    MISSING=""
    DIVERGING=""
    DIVERGING_MTIME=""
    RETURN_VALUE=0
    for ORIGIN_DIR in $ORIGIN_DIRS; do
        for ORIGIN_FILE in `find $ORIGIN_DIR -type f 2> /dev/null`; do
            for COPY_DIR in $COPY_DIRS; do
                FOUND=`find $COPY_DIR -path "$COPY_DIR/${ORIGIN_FILE#$ORIGIN_DIR/}" 2> /dev/null`
                if [[ $FOUND != "" ]] ; then
                    break
                fi
            done
            if [[ $FOUND == "" ]] ; then
                MISSING="$MISSING $ORIGIN_FILE";
            elif ! cmp --quiet $ORIGIN_FILE $FOUND; then
                DIVERGING="$DIVERGING $ORIGIN_FILE"
            elif [[ `stat --printf="%Y" $ORIGIN_FILE` != `stat --printf="%Y" $FOUND` ]]; then
                DIVERGING_MTIME="$DIVERGING_MTIME $ORIGIN_FILE"
            fi
        done
    done
    if [[ $MISSING != "" ]]; then
        RETURN_VALUE=1
        echo "MISSING: $MISSING"
    fi
    if [[ $DIVERGING != "" ]]; then
        RETURN_VALUE=$((return_value + 2))
        echo "DIVERGING: $DIVERGING"
    fi
    if [[ $DIVERGING_MTIME != "" ]]; then
        RETURN_VALUE=$((return_value + 4))
        echo "DIVERGING MTIME: $DIVERGING_MTIME"
    fi
    return $RETURN_VALUE
}

# run_test <expected_return> <test-command> <comment>
function run_test {
    sleep 4
    killall monikop pokinom 2> /dev/null
    sleep 2
    killall -KILL monikop pokinom 2> /dev/null
    sleep 2
    echo "RUNNING $2 [$3]"
    TEST_COUNT=$(( TEST_COUNT + 1 ))
    $2
    RETURN_VALUE=$?
    if [[ $RETURN_VALUE -ne $1 ]]; then
        FAIL_COUNT=$(( FAIL_COUNT + 1 ))
        FAILED_TESTS="$FAILED_TESTS$2($1? $RETURN_VALUE!) [$3]\n"
        echo "$2 should have returned $1 but returned $RETURN_VALUE instead."
    fi
    sleep 2
}

umount $MNT/* #2> /dev/null
rm -rf $DEV $MNT $LOG
mkdir -p $DEV $MNT $RSYNC

# Create and mount test drives:
for i in 01 02 03 04; do
    make_test_drive $i 102400
    if [[ $? == 1 ]]; then
        MOUNTING_PROBLEM=1
    fi
done
make_test_drive 05 307200
if [[ $? == 1 ]]; then
    MOUNTING_PROBLEM=1
fi
if [[ $MOUNTING_PROBLEM == 1 ]]; then exit; fi

function fill_sources_with_big_files {
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
}

function fill_sources_with_hidden_files {
    for i in 01 02; do
        make_test_file $MNT/$i/data/.hidden_dir_$i/.hidden_file 20 200804250955.10
    done
}

function fill_destinations_with_few_small_files {
    for i in 03 04; do
        for j in file_one file_two file_three; do
            make_test_file $MNT/$i/measuring_data/$i/$j 20 200004250955.10
        done
    done
}

# Prepare data sources:
fill_sources_with_big_files

# Check how fast we are:

T1=`/usr/bin/time --format="%e" rsync --recursive --times $MNT/01/data/ $MNT/03/ 2>&1 &`
T2=`/usr/bin/time --format="%e" rsync --recursive --times $MNT/02/data/ $MNT/04/ 2>&1 &`
INTERRUPTION_TIME_0=`echo "($T1 + $T2) * 3" | bc`
INTERRUPTION_TIME_1=`echo "($T1 + $T2) * .08" | bc`
INTERRUPTION_TIME_2=`echo "($T1 + $T2) * .82" | bc`
echo $INTERRUPTION_TIME_0
rm -rf $MNT/0{1,2,3,4}/*

# Define tests:

function test_monikop_simple {
    sleep 4
    $MONIKOP_1 & sleep $INTERRUPTION_TIME_0; /bin/kill -TERM $!
    sleep 2
    find_and_compare $MNT/0{1,2}/data :: $MNT/0{3,4}/measuring_data
}

function test_monikop_simple_late_sources {
    kill_rsyncd
    $MONIKOP_1 & sleep $INTERRUPTION_TIME_2; start_rsyncd; sleep $INTERRUPTION_TIME_0; /bin/kill -TERM $!
    sleep 2
    find_and_compare $MNT/0{1,2}/data :: $MNT/0{3,4}/measuring_data
}

function test_monikop_short {
    $MONIKOP_1 & sleep $INTERRUPTION_TIME_1; /bin/kill -TERM $!
    sleep 2
    find_and_compare $MNT/0{1,2}/data :: $MNT/0{3,4}/measuring_data
}

function test_monikop_short_2 {
    $MONIKOP_2 & sleep $INTERRUPTION_TIME_1; /bin/kill -TERM $!
    sleep 2
    find_and_compare $MNT/0{1,2}/data :: $MNT/0{3,4,5}/measuring_data
}

function test_monikop_short_kill_rsync_first {
    $MONIKOP_2 & sleep $INTERRUPTION_TIME_1; /usr/bin/killall -KILL rsync; sleep 1; /bin/kill -TERM $!
    sleep 2
    find_and_compare $MNT/0{1,2}/data :: $MNT/0{3,4,5}/measuring_data
    RETURN=$?
    start_rsyncd
    sleep 2
    return $RETURN
}

function test_monikop_short_cut_sources {
    $MONIKOP_2 & sleep $INTERRUPTION_TIME_1; kill_rsyncd; sleep 1; /bin/kill -TERM $!
    sleep 2
    find_and_compare $MNT/0{1,2}/data :: $MNT/0{3,4,5}/measuring_data
    RETURN=$?
    start_rsyncd
    sleep 2
    return $RETURN
}

function test_monikop_simple_2 {
    $MONIKOP_2 & sleep $INTERRUPTION_TIME_0; /bin/kill -TERM $!
    sleep 2
    find_and_compare $MNT/0{1,2}/data :: $MNT/0{3,4,5}/measuring_data
}

function test_monikop_simple_3 {
    $MONIKOP_3 & sleep $INTERRUPTION_TIME_0; /bin/kill -TERM $!
    sleep 2
    find_and_compare $MNT/0{1,2}/data :: $MNT/0{3,4}/measuring_data/dir_0{1,2}
}

function test_monikop_overflow {
# Stuff one of the destinations a bit:
    make_test_file $MNT/03/stuffing 25000 199903250845
    $MONIKOP_1 & sleep $INTERRUPTION_TIME_0; /bin/kill -TERM $!
    sleep 2
    find_and_compare $MNT/0{1,2}/data :: $MNT/0{3,4}/measuring_data
}

function test_monikop_no_destination {
# We test basically if there is something to kill.
    umount $MNT/{03,04}
    $MONIKOP_1 & sleep $INTERRUPTION_TIME_2; /bin/kill -TERM $!
    RETURN=$?
    mount $MNT/03
    mount $MNT/04
    return $RETURN
}

function test_monikop_no_source {
# We test basically if there is something to kill.
    kill_rsyncd
    $MONIKOP_1 & sleep $INTERRUPTION_TIME_2; /bin/kill -TERM $!
    RETURN=$?
    start_rsyncd
    return $RETURN
}

function test_pokinom_clean_finish {
    $POKINOM & sleep $INTERRUPTION_TIME_0; /bin/kill -TERM $!
    sleep 2
    find_and_compare $MNT/0{1,2}/data :: $MNT/05/NEW_DATA
}

function test_pokinom_short {
    $POKINOM & sleep $INTERRUPTION_TIME_1; /bin/kill -TERM $!
    sleep 2
    find_and_compare $MNT/0{1,2}/data :: $MNT/05/NEW_DATA
}

function test_pokinom_late_destination {
    kill_rsyncd
    $POKINOM & sleep $INTERRUPTION_TIME_2; start_rsyncd; sleep $INTERRUPTION_TIME_0; /bin/kill -TERM $!
    sleep 2
    find_and_compare $MNT/0{1,2}/data :: $MNT/05/NEW_DATA
}

function test_dirs_backed_up {
    test -d $MNT/03/backed_up && test -d $MNT/04/backed_up
}

function test_monikop_deletes_being_deleted_dir {
    mkdir -p $MNT/0{3,4}/{being_deleted,backed_up}
    touch $MNT/0{3,4}/{being_deleted,backed_up}/some_file
    touch $MNT/0{3,4}/{being_deleted,backed_up}/.some_hidden_file
    $MONIKOP_1 & sleep $INTERRUPTION_TIME_2; /bin/kill -TERM $!
    test -d $MNT/03/being_deleted || test -d $MNT/04/being_deleted
}

function test_pokinom_deletes_being_deleted_dir {
    mkdir -p $MNT/0{3,4}/being_deleted
    touch $MNT/0{3,4}/being_deleted/some_file
    touch $MNT/0{3,4}/being_deleted/.some_hidden_file
    $POKINOM & sleep $INTERRUPTION_TIME_2; /bin/kill -TERM $!
    test -d $MNT/03/being_deleted || test -d $MNT/04/being_deleted
}

function test_pokinom_newer_files_win {
    fill_destinations_with_few_small_files    
    $POKINOM & sleep $INTERRUPTION_TIME_2; /bin/kill -TERM $!
    for i in 03 04; do
        mv $MNT/$i/backed_up $MNT/$i/measuring_data
        touch $MNT/$i/measuring_data/$i/*
    done
    $POKINOM & sleep $INTERRUPTION_TIME_2; /bin/kill -TERM $!
    sleep 2
    find_and_compare $MNT/0{3,4}/backed_up :: $MNT/05/NEW_DATA
}

function test_pokinom_older_files_lose {
    fill_destinations_with_few_small_files    
    $POKINOM & sleep $INTERRUPTION_TIME_2; /bin/kill -TERM $!
    for i in 03 04; do
        mv $MNT/$i/backed_up $MNT/$i/measuring_data
    done
    touch -t 198001011200.00 $MNT/03/measuring_data/03/file_one
    $POKINOM & sleep $INTERRUPTION_TIME_2; /bin/kill -TERM $!
    sleep 2
    find_and_compare $MNT/0{3,4}/backed_up :: $MNT/05/NEW_DATA
}

start_rsyncd

##########################
### Run tests: Monikop
##########################

fill_sources_with_big_files

run_test 1 test_monikop_deletes_being_deleted_dir "Monikop deletes left-over directory named being_deleted."

rm -rf $MNT/0{3,4}/* $LOG

chmod a-w,a-x $MNT/0{3,4}
run_test 1 test_monikop_simple "Unwritable destination"
chmod a+w,a+x $MNT/0{3,4}
run_test 0 test_monikop_simple "Unwritable destination"

rm -rf $MNT/0{3,4}/* $LOG

run_test 0 test_monikop_simple_3 "Source-specific directories on disks"

rm -rf $MNT/0{3,4}/* $LOG

run_test 0 test_monikop_simple_late_sources "Simple run, sources coming up late."

mv $MNT/03/measuring_data $MNT/03/backed_up
mv $MNT/04/measuring_data $MNT/04/backed_up
rm -rf $LOG

run_test 0 test_monikop_simple "Simple run, deletion."

rm -rf $MNT/0{3,4}/* $LOG

run_test 1 test_monikop_short "Interruption, finished.* or finished.*.bak deleted."
rm -f $LOG/finished.rsync___localhost_2000_test_01_data $LOG/finished.rsync___localhost_2000_test_02_data.bak
run_test 0 test_monikop_simple "Recovery after interruption, finished.* or finished.*.bak deleted."

rm -rf $MNT/0{3,4}/* $LOG

run_test 1 test_monikop_short "Interruption, finished.* and/or log.*  deleted."
rm -f $LOG/finished.rsync___localhost_2000_test_01_data $LOG/log.rsync___localhost_2000_test_01_data
rm -f $LOG/rm log.rsync___localhost_2000_test_02_data
run_test 0 test_monikop_simple "Recovery after interruption, finished.* and/or log.* deleted."

rm -rf $MNT/0{3,4}/* $LOG

run_test 1 test_monikop_short_2 "Repeated interruption."
run_test 1 test_monikop_short_2 "Repeated interruption (may pass unexpectedly due to test timing)."
run_test 0 test_monikop_simple_2 "Repeated interruption."

mv $MNT/03/measuring_data $MNT/03/backed_up
mv $MNT/04/measuring_data $MNT/04/backed_up
mv $MNT/05/measuring_data $MNT/05/backed_up
rm -rf $LOG

run_test 1 test_monikop_short_2 "Repeated interruption, deletion."
run_test 1 test_monikop_short_2 "Repeated interruption, deletion (may pass unexpectedly due to test timing)."
run_test 0 test_monikop_simple_2 "Repeated interruption, deletion."

rm -rf $MNT/0{3,4,5}/* $LOG

run_test 0 test_monikop_no_destination "No destination available."
run_test 0 test_monikop_no_source "No destination available."

rm -rf $MNT/0{3,4}/* $LOG

run_test 1 test_monikop_short_kill_rsync_first "Rsync killed."
ps aux | grep rsync
run_test 0 test_monikop_simple_2 "Rsync killed."

rm -rf $MNT/0{3,4,5}/* $LOG

run_test 1 test_monikop_short_cut_sources "Connection to source destroyed."
run_test 0 test_monikop_simple_2 "Connection to source destroyed."

rm -rf $MNT/0{3,4,5}/* $LOG

##############################
# Pokinom
##############################

run_test 1 test_pokinom_deletes_being_deleted_dir "Pokinom deletes left-over directory named being_deleted."

rm -rf $MNT/0{3,4,5}/*

run_test 0 test_pokinom_newer_files_win "Pokinom overwrites older files in Destination."

run_test 4 test_pokinom_older_files_lose "Pokinom discards older files on removable disk."

##############################
# Monikop and Pokinom together
##############################

rm -rf $MNT/0{1,2,3,4,5}/*
fill_sources_with_hidden_files

run_test 0 test_monikop_simple "Preparation for simple Pokinom test, hidden files."
run_test 0 test_pokinom_clean_finish "Simple Pokinom test, hidden files."
run_test 0 test_dirs_backed_up "Simple Pokinom test, hidden files."
run_test 1 test_monikop_short "After test with hidden files, this one should do nothing but delete backed_up."
run_test 1 test_dirs_backed_up "Deletion of backed_up with hidden files."

rm -rf $MNT/0{1,2,3,4,5}/*
fill_sources_with_big_files

run_test 0 test_monikop_simple "Simple run in preparation for simple Pokinom test."
run_test 0 test_pokinom_clean_finish "Simple Pokinom test."
run_test 0 test_dirs_backed_up "Simple Pokinom test: directories renamed?."

rm -rf $MNT/05/* $LOG

run_test 0 test_monikop_simple "Preparation for Pokinom's destination overfull."
# Stuff destination:
make_test_file $MNT/05/stuffing 200000 199903250845
run_test 1 test_pokinom_clean_finish "Pokinom's destination overfull."
rm $MNT/05/stuffing
run_test 0 test_pokinom_clean_finish "Pokinom's destination no longer overfull: recovering."

rm -rf $MNT/05/* $LOG

run_test 0 test_monikop_simple "Simple run in preparation for Pokinom, late destination."
run_test 0 test_pokinom_late_destination "Pokinom, late destination."

rm -rf $MNT/05/* $LOG

run_test 0 test_monikop_simple "Simple run in preparation for Pokinom stopped early."
run_test 1 test_pokinom_short "Pokinom stopped early."
run_test 0 test_monikop_simple "Simple run after Pokinom having been stopped early."
run_test 0 test_pokinom_clean_finish "Simple run after Pokinom having been stopped early."

rm -rf $MNT/05/* $LOG

run_test 0 test_monikop_simple "Simple run in preparation for \"file grown too large\""
rm $MNT/01/data/f3
cat $MNT/01/data/f1 >> $MNT/01/data/f2
run_test 2 test_monikop_simple "Repeated run, file grown too large."
run_test 2 test_pokinom_clean_finish "Repeated run, file grown too large."
run_test 1 test_monikop_simple "Repeated run, file grown too large."
run_test 0 test_pokinom_clean_finish "Repeated run, file grown too large."

rm -rf $MNT/05/* $LOG

run_test 1 test_monikop_overflow "Initially, too little room on disks."
run_test 1 test_pokinom_clean_finish "Initially, too little room on disks."
run_test 1 test_monikop_overflow "Previously, too little room on disks."
run_test 0 test_pokinom_clean_finish "Previously, too little room on disks."

rm -rf $MNT/0{3,4,5}/* $LOG

run_test 1 test_monikop_short "Unfinished by Monikop, then another full cycle."
run_test 1 test_pokinom_clean_finish "Unfinished by Monikop, then another full cycle (Outcome unpredictable)."
run_test 1 test_monikop_simple "Previously unfinished by Monikop, now another full cycle (Outcome unpredictable)."
run_test 0 test_pokinom_clean_finish "Previously unfinished by Monikop, now another full cycle."

# TODO: the following fails at least in part due to bugs in the tests themselves.
rm -rf $MNT/0{1,2,3,4,5}/* $LOG
make_test_file $MNT/01/data/d1/f1 10 200703250845.33
make_test_file $MNT/01/data/d2/f3 10 200703250845.33
make_test_file $MNT/01/data/d3/d4/f4 10 200703250845.33
make_test_file $MNT/01/data/f2 10 200703250845.33
make_test_file $MNT/01/data/f5 10 200703250845.33
mv $MNT/01/data/d1/f1 "$MNT/01/data/d1/Große Datei"
mv $MNT/01/data/d1 "$MNT/01/data/Schönes Verzeichnis"
mv $MNT/01/data/f2 "$MNT/01/data/{[cool]} file\ n\\a\\m\\e."
# Not sure if this will ever work:
mv $MNT/01/data/d2 $MNT/01/data/.rsync_partial
mv $MNT/01/data/d3/d4 $MNT/01/data/d3/.rsync_partial
run_test 0 test_monikop_simple "Weird file names."
run_test 0 test_pokinom_clean_finish "Weird file names."
run_test 1 test_monikop_short "Weird file names, second run: nothing to do."

########################################
# End of tests
########################################
kill_rsyncd

echo "TOTAL NUMBER OF TESTS: $TEST_COUNT"
echo "NUMBER OF FAILED TESTS: $FAIL_COUNT"
echo "FAILED TESTS:"
echo -e "$FAILED_TESTS"

exit $FAIL_COUNT
