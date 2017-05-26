#!/usr/bin/env tclsh

package require ndv

package require tcltest
namespace import -force ::tcltest::*

source [file join [file dirname [info script]] .. libns.tcl]

# source ../libfp.tcl
source [file join [file dirname [info script]] .. libio.tcl]

# sometimes useful for debugging.
source [file join [file dirname [info script]] .. breakpoint.tcl]

use libio
use libfp

# [2016-07-22 10:13] Two arguments to the test function should be enough: expression and expected result.
proc testndv {args} {
  global testndv_index
  incr testndv_index
  test test-$testndv_index test-$testndv_index {*}$args
}

proc test_read_file {par} {
  set filename /tmp/test-withfile.txt
  write_file $filename "abc\ndef"
  set sep "-"
  set res ""
  with_file f [open $filename r] {
    while {[gets $f line] >= 0} {
      if {$par == 2} {
        error "Test with par = $par"
      }
      if {$line != ""} {
        append res "$line$sep"        
      }
    }
  }
  return $res
}

testndv {test_read_file 1} "abc-def-"
# TODO: test with errors/catch.
# testndv {test_read_file 2} "abc-def-"

testndv {glob_rec [file dirname [info script]] \
             [fn {path} {
               if {[file type $path] == "file"} {
                 regexp -- {^test-libio} [file tail $path]
               } else {
                 return 1;      # all subdirs
               }}]} [list [file normalize [info script]]]

cleanupTests

