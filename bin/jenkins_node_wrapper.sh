#!/usr/bin/env bash

# Copyright (c) 2009, 2010, 2012, 2015 Peter Palfrader
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

set -e
set -u

MYLOGNAME="`basename "$0"`[$$]"

usage() {
	echo "local Usage: $0"
	echo "via ssh orig command:"
	echo "                      <allowed command>"
}

info() {
	echo >&2 "$MYLOGNAME $1"
	echo > ~/jenkins-ssh-wrap.log "$MYLOGNAME $1"
}

croak() {
	echo >&2 "$MYLOGNAME $1"
	echo > ~/jenkins-ssh-wrap.log "$MYLOGNAME $1"
	exit 1
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
	usage
	exit 0
fi

# check/parse remote command line
if [ -z "${SSH_ORIGINAL_COMMAND:-}" ] ; then
	croak "Did not find SSH_ORIGINAL_COMMAND"
fi
set "dummy" ${SSH_ORIGINAL_COMMAND}
shift

info "remote_host called with $*"

allowed_cmds=()

if [[ "$*" =~ rebootstrap_.* ]] ; then
	REBOOTSTRAPSH="/srv/jenkins/bin/chroot-run.sh sid minimal ./bootstrap.sh"
	REBOOTSTRAPSH="$REBOOTSTRAPSH HOST_ARCH=$(echo $1 | cut -d "_" -f2)"
	if [[ "$*" =~ .*_debbindiff.* ]] ; then
		REBOOTSTRAPSH="$REBOOTSTRAPSH ENABLE_DEBBINDIFF=yes"
	fi
	export LC_ALL=C
	exec $REBOOTSTRAPSH ; croak "Exec failed";
elif [ "$1" = "/srv/jenkins/bin/reproducible_build.sh" ] && ( [ "$2" = "1" ] || [ "$2" = "2" ] ) ; then
	exec /srv/jenkins/bin/reproducible_build.sh $2 $3 $4 $5 ; croak "Exec failed";
elif [[ "$*" =~ rsync\ --server\ --sender\ .*\ .\ /srv/reproducible-results/tmp.* ]] ; then
	exec rsync --server --sender $4 . $6 ; croak "Exec failed";
elif [[ "$*" =~ rm\ -r\ /srv/reproducible-results/tmp.* ]] ; then
	exec rm -r $3 ; croak "Exec failed";
elif   [ "$*" = "reproducible_setup_pbuilder_unstable_armhf_bpi0" ] ; then
	exec /srv/jenkins/bin/reproducible_setup_pbuilder.sh unstable ; croak "Exec failed";
elif [ "$*" = "reproducible_maintenance_armhf_bpi0" ] ; then
	exec /srv/jenkins/bin/reproducible_maintenance.sh ; croak "Exec failed";
elif [ "$*" = "reproducible_setup_schroot_unstable_debbindiff_armhf_bpi0" ] ; then
	exec /srv/jenkins/bin/schroot-create.sh reproducible reproducible-unstable-debbindiff unstable debbindiff locales-all ; croak "Exec failed";
elif [ "$*" = "reproducible_setup_schroot_unstable_armhf_bpi0" ] ; then
	exec /srv/jenkins/bin/schroot-create.sh reproducible reproducible-unstable unstable ; croak "Exec failed";
elif [ "$*" = "reproducible_setup_pbuilder_unstable_armhf_cbxi4pro0" ] ; then
	exec /srv/jenkins/bin/reproducible_setup_pbuilder.sh unstable ; croak "Exec failed";
elif [ "$*" = "reproducible_maintenance_armhf_cbxi4pro0" ] ; then
	exec /srv/jenkins/bin/reproducible_maintenance.sh ; croak "Exec failed";
elif [ "$*" = "reproducible_setup_schroot_unstable_debbindiff_armhf_cbxi4pro0" ] ; then
	exec /srv/jenkins/bin/schroot-create.sh reproducible reproducible-unstable-debbindiff unstable debbindiff locales-all ; croak "Exec failed";
elif [ "$*" = "reproducible_setup_schroot_unstable_armhf_cbxi4pro0" ] ; then
	exec /srv/jenkins/bin/schroot-create.sh reproducible reproducible-unstable unstable ; croak "Exec failed";
elif   [ "$*" = "reproducible_setup_pbuilder_unstable_armhf_hb0" ] ; then
	exec /srv/jenkins/bin/reproducible_setup_pbuilder.sh unstable ; croak "Exec failed";
elif [ "$*" = "reproducible_maintenance_armhf_hb0" ] ; then
	exec /srv/jenkins/bin/reproducible_maintenance.sh ; croak "Exec failed";
elif [ "$*" = "reproducible_setup_schroot_unstable_debbindiff_armhf_hb0" ] ; then
	exec /srv/jenkins/bin/schroot-create.sh reproducible reproducible-unstable-debbindiff unstable debbindiff locales-all ; croak "Exec failed";
elif [ "$*" = "reproducible_setup_schroot_unstable_armhf_hb0" ] ; then
	exec /srv/jenkins/bin/schroot-create.sh reproducible reproducible-unstable unstable ; croak "Exec failed";
elif   [ "$*" = "reproducible_setup_pbuilder_unstable_armhf_wbq0" ] ; then
	exec /srv/jenkins/bin/reproducible_setup_pbuilder.sh unstable ; croak "Exec failed";
elif [ "$*" = "reproducible_maintenance_armhf_wbq0" ] ; then
	exec /srv/jenkins/bin/reproducible_maintenance.sh ; croak "Exec failed";
elif [ "$*" = "reproducible_setup_schroot_unstable_debbindiff_armhf_wbq0" ] ; then
	exec /srv/jenkins/bin/schroot-create.sh reproducible reproducible-unstable-debbindiff unstable debbindiff locales-all ; croak "Exec failed";
elif [ "$*" = "reproducible_setup_schroot_unstable_armhf_wbq0" ] ; then
	exec /srv/jenkins/bin/schroot-create.sh reproducible reproducible-unstable unstable ; croak "Exec failed";
elif   [ "$*" = "reproducible_setup_pbuilder_testing_amd64_profitbricks1" ] ; then
	exec /srv/jenkins/bin/reproducible_setup_pbuilder.sh testing ; croak "Exec failed";
elif   [ "$*" = "reproducible_setup_pbuilder_unstable_amd64_profitbricks1" ] ; then
	exec /srv/jenkins/bin/reproducible_setup_pbuilder.sh unstable ; croak "Exec failed";
elif   [ "$*" = "reproducible_setup_pbuilder_experimental_amd64_profitbricks1" ] ; then
	exec /srv/jenkins/bin/reproducible_setup_pbuilder.sh experimental ; croak "Exec failed";
elif [ "$*" = "reproducible_maintenance_amd64_profitbricks1" ] ; then
	exec /srv/jenkins/bin/reproducible_maintenance.sh ; croak "Exec failed";
elif [ "$*" = "reproducible_setup_schroot_testing_debbindiff_amd64_profitbricks1" ] ; then
	exec /srv/jenkins/bin/schroot-create.sh reproducible reproducible-testing-debbindiff testing debbindiff locales-all ; croak "Exec failed";
elif [ "$*" = "reproducible_setup_schroot_unstable_debbindiff_amd64_profitbricks1" ] ; then
	exec /srv/jenkins/bin/schroot-create.sh reproducible reproducible-unstable-debbindiff unstable debbindiff locales-all ; croak "Exec failed";
elif [ "$*" = "reproducible_setup_schroot_testing_amd64_profitbricks1" ] ; then
	exec /srv/jenkins/bin/schroot-create.sh reproducible reproducible-testing testing ; croak "Exec failed";
elif [ "$*" = "reproducible_setup_schroot_unstable_amd64_profitbricks1" ] ; then
	exec /srv/jenkins/bin/schroot-create.sh reproducible reproducible-unstable unstable ; croak "Exec failed";
elif [ "$*" = "reproducible_setup_schroot_experimental_amd64_profitbricks1" ] ; then
	exec /srv/jenkins/bin/schroot-create.sh reproducible reproducible-experimental experimental ; croak "Exec failed";
elif   [ "$*" = "reproducible_setup_pbuilder_testing_amd64_profitbricks2" ] ; then
	exec /srv/jenkins/bin/reproducible_setup_pbuilder.sh testing ; croak "Exec failed";
elif   [ "$*" = "reproducible_setup_pbuilder_unstable_amd64_profitbricks2" ] ; then
	exec /srv/jenkins/bin/reproducible_setup_pbuilder.sh unstable ; croak "Exec failed";
elif   [ "$*" = "reproducible_setup_pbuilder_experimental_amd64_profitbricks2" ] ; then
	exec /srv/jenkins/bin/reproducible_setup_pbuilder.sh experimental ; croak "Exec failed";
elif [ "$*" = "reproducible_maintenance_amd64_profitbricks2" ] ; then
	exec /srv/jenkins/bin/reproducible_maintenance.sh ; croak "Exec failed";
elif [ "$*" = "reproducible_setup_schroot_testing_debbindiff_amd64_profitbricks2" ] ; then
	exec /srv/jenkins/bin/schroot-create.sh reproducible reproducible-testing-debbindiff testing debbindiff locales-all ; croak "Exec failed";
elif [ "$*" = "reproducible_setup_schroot_unstable_debbindiff_amd64_profitbricks2" ] ; then
	exec /srv/jenkins/bin/schroot-create.sh reproducible reproducible-unstable-debbindiff unstable debbindiff locales-all ; croak "Exec failed";
elif [ "$*" = "reproducible_setup_schroot_testing_amd64_profitbricks2" ] ; then
	exec /srv/jenkins/bin/schroot-create.sh reproducible reproducible-testing testing ; croak "Exec failed";
elif [ "$*" = "reproducible_setup_schroot_unstable_amd64_profitbricks2" ] ; then
	exec /srv/jenkins/bin/schroot-create.sh reproducible reproducible-unstable unstable ; croak "Exec failed";
elif [ "$*" = "reproducible_setup_schroot_experimental_amd64_profitbricks2" ] ; then
	exec /srv/jenkins/bin/schroot-create.sh reproducible reproducible-experimental experimental ; croak "Exec failed";
fi

croak "Command '$*' not found in allowed commands."
