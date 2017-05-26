#! /usr/bin/env tclsh

# test-liboptions.tcl - test functionality of liboptions.tcl
package require ndv

# @note don't package require libdatetime, but source it, easier to test.

package require tcltest
namespace import -force ::tcltest::*

source [file join [file dirname [info script]] .. liboptions.tcl]

proc testndv {args} {
  global testndv_index
  incr testndv_index
  test test-$testndv_index test-$testndv_index {*}$args
}

# array set ar_argv [::cmdline::getoptions argv $options $usage]

# return dictionary of parsed options
proc test_options {argv} {
  set options {
    {db.arg "auto" "Read data from a database with this name (auto (=search current dir), default (data.db) or explicit)"}
    {table.arg "auto" "Read data in the named table (auto (=all) or explicit)"}
    {graphdir.arg "auto" "Put graphs in this directory (auto or explicit)"}
    {clean "Clean the graph output dir before making graphs."}
    {npoints.arg 200 "Number of points to plot."}
    {ggplot "Use ggplot for (single line) graphs"}
    {flatlines "Do make graph if it would be a flatline (min=max)"}
    {start.arg "auto" "Start time of graph"}
    {end.arg "auto" "End time of graph"}
    {loglevel.arg "" "Set global log level"}
  }
  set usage ": [file tail [info script]] \[options] sqlite.db"
  getoptions argv $options $usage
}


testndv {dict get [test_options ""] clean} 0
testndv {dict get [test_options "-clean"] clean} 1
testndv {dict get [test_options "-db testdb"] db} testdb
testndv {dict get [test_options ""] graphdir} auto

cleanupTests
