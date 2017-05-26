#!/usr/bin/env tclsh

package require ndv

package require tcltest
namespace import -force ::tcltest::*

source [file join [file dirname [info script]] .. libns.tcl]

source [file join [file dirname [info script]] .. libdot.tcl]

# sometimes useful for debugging.
source [file join [file dirname [info script]] .. breakpoint.tcl]

source [file join [file dirname [info script]] .. CLogger.tcl]
set_log_global info

use libio

# [2016-07-22 10:13] Two arguments to the test function should be enough: expression and expected result.
proc testndv {args} {
  global testndv_index
  incr testndv_index
  test test-$testndv_index test-$testndv_index {*}$args
}

# create a .dot file, call dot functions to make a .png, return size of .png
proc test_make_dot {} {
  set dotfilename /tmp/test-libdot.dot
  set pngfilename /tmp/test-libdot.png
  set f [open $dotfilename w]
  write_dot_header $f
  set node1 [puts_node_stmt $f "node1"]
  set node2 [puts_node_stmt $f "node2"]
  set node3 [puts_node_stmt $f "node3" style filled fillcolor lightblue shape rectangle]
  # wat als je 2 nodes met dezelfde naam maakt?
  # [2016-11-18 12:11] lijkt idd maar 1 node te worden, mooi.
  set node3a [puts_node_stmt $f "node3"]
  puts $f [edge_stmt $node1 $node2 color red]
  puts $f [edge_stmt $node1 $node3 label label1]
  puts $f [edge_stmt_once $node3a $node2 label "test3a"]
  puts $f [edge_stmt_once $node3a $node2 label "test3a"]
  write_dot_footer $f
  close $f
  do_dot $dotfilename $pngfilename
  # [2016-11-18 11:48] size is 11598, or 11623, or ...
  return [expr [file size $pngfilename] >= 11000]
}

testndv {test_make_dot} 1

# [2016-11-18 20:20] kleine test om popup te krijgen.
# testndv {expr 0} 1

cleanupTests

