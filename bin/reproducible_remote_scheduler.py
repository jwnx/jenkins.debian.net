#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2015 Mattia Rizzolo <mattia@mapreri.org>
# Licensed under GPL-2
#
# Depends: python3
#
# A secure script to be called from remote hosts

import time
import argparse


parser = argparse.ArgumentParser(
    description='Reschedule packages to re-test their reproducibility',
    epilog='The build results will be announced on the #debian-reproducible' +
           ' IRC channel.')
group = parser.add_mutually_exclusive_group()
group.add_argument('-a', '--artifacts', default=False, action='store_true',
                   help='Save artifacts (for further offline study)')
group.add_argument('-n', '--no-notify', default=False, action='store_true',
                   help='Do not notify the channel when the build finish')
parser.add_argument('-s', '--suite', required=True,
                    help='Specify the suite to schedule in')
parser.add_argument('-m', '--message', default='', nargs='+',
                    help='A text to be sent to the IRC channel when notifying' +
                    ' about the scheduling')
parser.add_argument('packages', metavar='package', nargs='+',
                    help='list of packages to reschedule')
scheduling_args = parser.parse_known_args()[0]

# these are here as an hack to be able to parse the command line
from reproducible_common import *
from reproducible_html_indexes import generate_schedule


class bcolors:
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'
    RED = '\033[91m'
    GOOD = '\033[92m'
    WARN = '\033[93m' + UNDERLINE
    FAIL = RED + BOLD + UNDERLINE
    ENDC = '\033[0m'


# this variable is expected to come from the remote host
try:
    requester = os.environ['LC_USER']
except KeyError:
    log.critical(bcolors.FAIL + 'You should use the provided script to '
                 'schedule packages. Ask in #debian-reproducible if you have '
                 'trouble with that.' + bcolors.ENDC)
    sys.exit(1)
# this variable is setted by reproducible scripts, and it's clearly available
# only on calls made by the local host
try:
    local = True if os.environ['LOCAL_CALL'] == 'true' else False
except KeyError:
    local = False

suite = scheduling_args.suite
reason = ' '.join(scheduling_args.message)
packages = scheduling_args.packages
artifacts = scheduling_args.artifacts
notify = not scheduling_args.no_notify  # note the notify vs no-notify

log.debug('Requester: ' + requester)
log.debug('Reason: ' + reason)
log.debug('Artifacts: ' + str(artifacts))
log.debug('Notify: ' + str(notify))
log.debug('Architecture: ' + defaultarch)
log.debug('Suite: ' + suite)
log.debug('Packages: ' + ' '.join(packages))

if suite not in SUITES:
    log.critical('The specified suite is not being tested.')
    log.critical('Please chose between ' + ', '.join(SUITES))
    sys.exit(1)

if len(packages) > 50 and notify:
    log.critical(bcolors.RED + bcolors.BOLD)
    call(['figlet', 'No.'])
    log.critical(bcolors.FAIL + 'Do not reschedule more than 50 packages ' +
                 'with notification.\nIf you really need to spam the IRC ' +
                 'channel this much use a loop to achive that.' + bcolors.ENDC)
    sys.exit(1)

if scheduling_args.artifacts:
    log.info('The artifacts of the build(s) will be saved to the location '
             'mentioned at the end of the build log(s).')

ids = []
pkgs = []

query1 = 'SELECT id FROM sources WHERE name="{pkg}" AND suite="{suite}"'
query2 = '''SELECT p.date_build_started
            FROM sources AS s JOIN schedule as p ON p.package_id=s.id
            WHERE s.name="{pkg}" AND suite="{suite}"'''
for pkg in packages:
    # test whether the package actually exists
    result = query_db(query1.format(pkg=pkg, suite=suite))
    try:
        # tests whether the package is already building
        result2 = query_db(query2.format(pkg=pkg, suite=suite))
        try:
            if not result2[0][0]:
                ids.append(result[0][0])
                pkgs.append(pkg)
            else:
                log.warning(bcolors.WARN + 'The package ' + pkg + ' is ' +
                    'already building, not scheduling it.' + bcolors.ENDC)
        except IndexError:
            ids.append(result[0][0])
            pkgs.append(pkg)
    except IndexError:
        log.critical('The package ' + pkg + ' is not available in ' + suite)
        sys.exit(1)

blablabla = '✂…' if len(' '.join(pkgs)) > 257 else ''
packages_txt = ' packages ' if len(pkgs) > 1 else ' package '
artifacts_txt = ' - artifacts will be preserved' if artifacts else ''

message = str(len(ids)) + packages_txt + 'scheduled in ' + suite + ' by ' + \
    requester
if reason:
    message += ' (reason: ' + reason + ')'
message += ': ' + ' '.join(pkgs)[0:256] + blablabla + artifacts_txt


# these packages are manually scheduled, so should have high priority,
# so schedule them in the past, so they are picked earlier :)
# the current date is subtracted twice, so it sorts before early scheduling
# schedule on the full hour so we can recognize them easily
epoch = int(time.time())
yesterday = epoch - 60*60*24
now = datetime.now()
days = int(now.strftime('%j'))*2
hours = int(now.strftime('%H'))*2
minutes = int(now.strftime('%M'))
time_delta = timedelta(days=days, hours=hours, minutes=minutes)
date = (now - time_delta).strftime('%Y-%m-%d %H:%M')
log.debug('date_scheduled = ' + date + ' time_delta = ' + str(time_delta))


# a single person can't schedule more than 50 packages in the same day; this
# is actually easy to bypass, but let's give some trust to the Debian people
query = '''SELECT count(*) FROM manual_scheduler
           WHERE requester = "{}" AND date_request > "{}"'''
try:
    amount = int(query_db(query.format(requester, int(time.time()-86400)))[0][0])
except IndexError:
    amount = 0
log.debug(requester + ' already scheduled ' + str(amount) + ' packages today')
if amount + len(ids) > 50 and not local:
    log.error(bcolors.FAIL + 'You have exceeded the maximum number of manual ' +
              'reschedulings allowed for a day. Please ask in ' +
              '#debian-reproducible if you need to schedule more packages.' +
              bcolors.ENDC)
    sys.exit(1)


# do the actual scheduling
to_schedule = []
save_schedule = []
for id in ids:
    artifacts_value = 1 if artifacts else 0
    to_schedule.append((id, date, artifacts_value, str(notify).lower(), requester))
    save_schedule.append((id, requester, epoch))
log.debug('Packages about to be scheduled: ' + str(to_schedule))

query1 = '''REPLACE INTO schedule
    (package_id, date_scheduled, date_build_started, save_artifacts, notify, scheduler)
    VALUES (?, ?, "", ?, ?, ?)'''
query2 = '''INSERT INTO manual_scheduler
    (package_id, requester, date_request) VALUES (?, ?, ?)'''

cursor = conn_db.cursor()
cursor.executemany(query1, to_schedule)
cursor.executemany(query2, save_schedule)
conn_db.commit()

log.info(bcolors.GOOD + message + bcolors.ENDC)
if requester != "jenkins maintenance job" and not local:
    irc_msg(message)

generate_schedule()  # the html page
