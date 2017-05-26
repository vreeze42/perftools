#!/usr/bin/env tclsh861

# test-libdatetime.tcl - test functionality of libdatetime.tcl
package require ndv

# @note don't package require libdatetime, but source it, easier to test.

package require tcltest
namespace import -force ::tcltest::*

source [file join [file dirname [info script]] .. libdatetime.tcl]

use libdatetime

proc testndv {args} {
  global testndv_index
  incr testndv_index
  test test-$testndv_index test-$testndv_index {*}$args
}

# DLST dates in summer:
# [2016-07-31 11:46] parse_cet is seriously deprecated, cet does not make sense in summer, should be cest then.
# [2016-07-31 11:51] delete parse_cet function.
#testndv {parse_cet "2016-06-09 15:52:22.096"} 1465480342.096
#testndv {parse_cet "2016-06-09 15:52:22"} 1465480342
#testndv {parse_cet "abc2016-06-09 15:52:22.096"} -1

testndv {parse_ts "2016-06-09 15:52:22.096"} 1465480342.096
testndv {parse_ts "2016-06-09 15:52:22"} 1465480342

# [2016-07-31 11:29] new info: CET is only used in winter, CEST only in summer, S=Summer.
# see: https://www.timeanddate.com/time/zones/cest
# and: https://www.timeanddate.com/time/zones/cet
set sec 1452351142
testndv {parse_ts "2016-01-09 15:52:22"} $sec
testndv {parse_ts "2016-01-09 15:52:22 +0100"} $sec
testndv {parse_ts "2016-01-09 15:52:22 CET"} $sec
testndv {parse_ts "2016-01-09 14:52:22 UTC"} $sec
testndv {parse_ts "2016-01-09 14:52:22 +0000"} $sec

# CEST does not make sense in winter:
# testndv {parse_ts "2016-01-09 15:52:22 CEST"} 1452351142

testndv {parse_ts "abc2016-06-09 15:52:22.096"} -1

# surprise: month 16 is seen as month 4 in the next year
# also too high values for day, hour, minute, second still 'work'
testndv {parse_ts "2016-16-09 15:52:22.096"} 1491745942.096
testndv {parse_ts "2016-06-35 15:52:22.096"} 1467726742.096

# CET does not make sense in Summer.
# testndv {parse_ts "2016-06-09 15:52:22 CET"} 1465480342

set sec 1465480342
testndv {parse_ts "2016-06-09 15:52:22 CEST"} $sec
testndv {parse_ts "2016-06-09 13:52:22 UTC"} $sec
testndv {parse_ts "2016-06-09 15:52:22 +0200"} $sec
testndv {parse_ts "2016-06-09 13:52:22 +0000"} $sec

# msec and both utc and cet timezones
set sec_msec 1465480342.096
testndv {parse_ts "2016-06-09 15:52:22.096 CEST"} $sec_msec
testndv {parse_ts "2016-06-09 13:52:22.096 UTC"} $sec_msec
testndv {parse_ts "2016-06-09 15:52:22.096 +0200"} $sec_msec
testndv {parse_ts "2016-06-09 13:52:22.096 +0000"} $sec_msec

# [2016-07-16 11:45] just check if now can be called.
# [2016-11-19 15:38] now includes msec, so 4 chars more.
testndv {string length [now]} 29
testndv {string length [now -filename]} 20

cleanupTests
