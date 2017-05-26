#!/usr/bin/env tclsh861

package require tcltest
namespace import -force ::tcltest::*

source [file join [file dirname [info script]] .. libns.tcl]

namespace eval ::libtestns {

  namespace export now

  proc now {} {
    return "now"
  }

}

proc testndv {args} {
  global testndv_index
  incr testndv_index
  test test-$testndv_index test-$testndv_index {*}$args
}

namespace forget now
use libtestns
testndv {now} "now"

namespace forget now
require libtestns t
testndv {t/now} "now"

# test sourcing 2 files and using return var, a namespace
set lns [list]
set srcdir [file normalize [file dirname [info script]]]
puts "srcdir for source: $srcdir"
lappend lns [source $srcdir/test-libns-file1.tcl]
lappend lns [source $srcdir/test-libns-file2.tcl]

foreach ns $lns {
  set res [${ns}::can_read logfile.txt]
  puts "Result of canread for $ns -> $res"
}

cleanupTests

