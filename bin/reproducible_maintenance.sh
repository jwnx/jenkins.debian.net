#!/bin/bash

# Copyright 2014-2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

DIRTY=false

# prepare backup
REP_RESULTS=/srv/reproducible-results
mkdir -p $REP_RESULTS/backup
cd $REP_RESULTS/backup

# keep 30 days and the 1st of the month
DAY=(date -d "30 day ago" '+%d')
DATE=$(date -d "30 day ago" '+%Y-%m-%d')
if [ "$DAY" != "01" ] &&  [ -f reproducible_$DATE.db.xz ] ; then
	rm -f reproducible_$DATE.db.xz
fi

# actually do the backup
DATE=$(date '+%Y-%m-%d')
if [ ! -f reproducible_$DATE.db.xz ] ; then
	cp -v $PACKAGES_DB .
	DATE=$(date '+%Y-%m-%d')
	mv -v reproducible.db reproducible_$DATE.db
	xz reproducible_$DATE.db
fi

# provide copy for external backups
cp -v $PACKAGES_DB /var/lib/jenkins/userContent/

# delete old temp directories
OLDSTUFF=$(find $REP_RESULTS -maxdepth 1 -type d -name "tmp.*" -mtime +2 -exec ls -lad {} \;)
if [ ! -z "$OLDSTUFF" ] ; then
	echo
	echo "Warning: old temp directories found in $REP_RESULTS"
	find $REP_RESULTS -maxdepth 1 -type d -name "tmp.*" -mtime +2 -exec rm -rv {} \;
	echo "These old directories have been deleted."
	echo
	DIRTY=true
fi

# find old schroots
OLDSTUFF=$(find /schroots/ -maxdepth 1 -type d -name "reproducible-*-*" -mtime +2 -exec ls -lad {} \;)
if [ ! -z "$OLDSTUFF" ] ; then
	echo
	echo "Warning: old schroots found in /schroots, which have been deleted:"
	find /schroots/ -maxdepth 1 -type d -name "reproducible-*-*" -mtime +2 -exec sudo rm -rf --one-file-system {} \;
	echo "$OLDSTUFF"
	echo
	DIRTY=true
fi

# find and warn about pbuild leftovers
OLDSTUFF=$(find /var/cache/pbuilder/result/ -mtime +1 -exec ls -lad {} \;)
if [ ! -z "$OLDSTUFF" ] ; then
	# delete known files, see #777537
	cd /var/cache/pbuilder/result/
	echo "Attempting file detection..."
	for i in $(find . -maxdepth 1 -mtime +1 -type f -exec basename {} \;) ; do
		case $i in
			stderr|stdout)	rm -v $i
					;;
			seqan-*.bed)	rm -v $i	# leftovers reported in #766741
					;;
			bootlogo)	rm -v $i
					;;
			org.daisy.paper.CustomPaperCollection.obj)		rm -v $i
					;;
			debian-faq.pdf.gz|debian-faq.ps.gz|debian-faq.txt.gz)	rm -v $i
					;;
			sumo_doxygen_lastrun.log)				rm -v $i
					;;
			*)		;;
		esac
	done
	cd - > /dev/null
	# report the rest
	OLDSTUFF=$(find /var/cache/pbuilder/result/ -mtime +1 -exec ls -lad {} \;)
	if [ ! -z "$OLDSTUFF" ] ; then
		echo "Warning: old files or directories found in /var/cache/pbuilder/result/"
		echo "$OLDSTUFF"
		echo "Please cleanup manually."
	fi
	echo
	DIRTY=true
fi

# find failed builds due to network problems and reschedule them
# only grep through the last 5h (300 minutes) of builds...
# (ignore "*None.rbuild.log" because these are build which were just started)
# this job runs every 4h
FAILED_BUILDS=$(find /var/lib/jenkins/userContent/rbuild -type f ! -name "*None.rbuild.log" ! -mmin +300 -exec egrep -l -e 'E: Failed to fetch.*(Connection failed|Size mismatch|Cannot initiate the connection to)' {} \; || true)
if [ ! -z "$FAILED_BUILDS" ] ; then
	echo
	echo "Warning: the following failed builds have been found"
	echo "$FAILED_BUILDS"
	echo
	echo "Rescheduling packages: "
	for SUITE in $(echo $FAILED_BUILDS | sed "s# #\n#g" | cut -d "/" -f7 | sort -u) ; do
		CANDIDATES=$(for PKG in $(echo $FAILED_BUILDS | sed "s# #\n#g" | grep "/$SUITE/" | cut -d "/" -f9 | cut -d "_" -f1) ; do echo -n "$PKG " ; done)
		check_candidates
		if [ $TOTAL -ne 0 ] ; then
			echo " - in $SUITE: $CANDIDATES"
			# '0' here means the artifacts will not be saved
			schedule_packages 0 $PACKAGE_IDS
		fi
	done
	DIRTY=true
fi

# find+terminate processes which should not be there
HAYSTACK=$(mktemp)
RESULT=$(mktemp)
TOKILL=$(mktemp)
PBUIDS="1234 1111 2222"
ps axo pid,user,size,pcpu,cmd > $HAYSTACK
for i in $PBUIDS ; do
	for PROCESS in $(pgrep -u $i -P 1 || true) ; do
		# faked-sysv comes and goes...
		grep ^$PROCESS $HAYSTACK | grep -v faked-sysv >> $RESULT 2> /dev/null || true
	done
done
if [ -s $RESULT ] ; then
	for PROCESS in $(cat $RESULT | cut -d " " -f1 | xargs echo) ; do
		AGE=$(ps -p $PROCESS -o etimes= || echo 0)
		# a single build may only take half a day, so...
		if [ $AGE -gt 43200 ] ; then
			echo "$PROCESS" >> $TOKILL
		fi
	done
	if [ -s $TOKILL ] ; then
		DIRTY=true
		PSCALL=""
		echo
		echo "Warning: processes found which should not be there, killing them now:"
		for PROCESS in $(cat $TOKILL) ; do
			PSCALL=${PSCALL:+"$PSCALL,"}"$PROCESS"
		done
		ps -F -p $PSCALL
		echo
		for PROCESS in $(cat $TOKILL) ; do
			echo sudo kill -9 $PROCESS 2>&1
			#echo "'kill -9 $PROCESS' done."  # FIXME re-enable once we're sure this new code is fine
		done
		echo "Please kill processes manually for now."
		echo
	fi
fi
rm $HAYSTACK $RESULT $TOKILL

# find packages which build didnt end correctly
QUERY="
	SELECT s.id, s.name, p.date_scheduled, p.date_build_started
		FROM schedule AS p JOIN sources AS s ON p.package_id=s.id
		WHERE p.date_scheduled != ''
		AND p.date_build_started != ''
		AND p.date_build_started < datetime('now', '-36 hours')
		ORDER BY p.date_scheduled
	"
PACKAGES=$(mktemp)
sqlite3 -init $INIT ${PACKAGES_DB} "$QUERY" > $PACKAGES 2> /dev/null || echo "Warning: SQL query '$QUERY' failed." 
if grep -q '|' $PACKAGES ; then
	echo
	echo "Warning: packages found where the build was started more than 36h ago:"
	sqlite3 -init $INIT -header -column ${PACKAGES_DB} "$QUERY" 2> /dev/null || echo "Warning: SQL query '$QUERY' failed."
	echo
	for PKG in $(cat $PACKAGES | cut -d "|" -f1) ; do
		echo "sqlite3 ${PACKAGES_DB}  \"DELETE FROM schedule WHERE package_id = '$PKG';\""
		sqlite3 -init $INIT ${PACKAGES_DB} "DELETE FROM schedule WHERE package_id = '$PKG';"
	done
	echo "Packages have been removed from scheduling."
	echo
	DIRTY=true
fi
rm $PACKAGES

# find packages which have been removed from the archive
PACKAGES=$(mktemp)
QUERY="SELECT name, suite, architecture FROM removed_packages
		LIMIT 25"
sqlite3 -init $INIT ${PACKAGES_DB} "$QUERY" > $PACKAGES 2> /dev/null || echo "Warning: SQL query '$QUERY' failed."
if grep -q '|' $PACKAGES ; then
	DIRTY=true
	echo
	echo "Warning: found files relative to old packages, no more in the archive:"
	echo "Removing these removed packages from database:"
	cat $PACKAGES
	echo
	for pkg in $(cat $PACKAGES) ; do
		PKGNAME=$(echo "$pkg" | cut -d '|' -f 1)
		SUITE=$(echo "$pkg" | cut -d '|' -f 2)
		ARCH=$(echo "$pkg" | cut -d '|' -f 3)
		QUERY="DELETE FROM removed_packages
			WHERE name='$PKGNAME' AND suite='$SUITE' AND architecture='$ARCH'"
		sqlite3 -init $INIT ${PACKAGES_DB} "$QUERY"
		cd /var/lib/jenkins/userContent
		find rb-pkg/$SUITE/$ARCH  rbuild/$SUITE/$ARCH notes/ dbd/$SUITE/$ARCH buildinfo/$SUITE/$ARCH -name "${PKGNAME}_*" | xargs echo rm -v
	done
	cd - > /dev/null
fi
rm $PACKAGES

# delete jenkins html logs from reproducible_builder_* jobs as they are mostly redundant
# (they only provide the extended value of parsed console output, which we dont need here.)
OLDSTUFF=$(find /var/lib/jenkins/jobs/reproducible_builder_* -maxdepth 3 -mtime +0 -name log_content.html  -exec rm -v {} \; | wc -l)
if [ ! -z "$OLDSTUFF" ] ; then
	echo
	echo "Removed $OLDSTUFF jenkins html logs."
	echo
fi

# remove artifacts older than 3 days
ARTIFACTS=$(find /var/lib/jenkins/userContent/artifacts/* -maxdepth 1 -type d -mtime +3 -exec ls -lad {} \; || true)
if [ ! -z "$ARTIFACTS" ] ; then
	echo
	echo "Removed old artifacts:"
	find /var/lib/jenkins/userContent/artifacts/* -maxdepth 1 -type d -mtime +3 -exec rm -rv {} \;
	echo
fi

# find + chmod files with bad permissions
BADPERMS=$(find /var/lib/jenkins/userContent/{buildinfo,dbd,rbuild,artifacts,unstable,experimental,testing,rb-pkg} ! -perm 644 -type f)
if [ ! -z "$BADPERMS" ] ; then
    DIRTY=true
    echo
    echo "Warning: Found files with bad permissions (!=644):"
    echo "Please fix permission manually"
    echo "$BADPERMS" | xargs echo chmod -v 644
    echo
fi

if ! $DIRTY ; then
	echo "Everything seems to be fine."
	echo
fi
