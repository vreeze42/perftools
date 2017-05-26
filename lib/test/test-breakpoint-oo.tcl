#!/usr/bin/env tclsh861

# Goal: in the past some problems with using breakpoint within a class.
# not sure if class was Itcl or something else. Testing here with std Tcl 8.6 OO system.
# 5-5-2016 made working with a simple catch.
package require ndv

# [2016-10-29 14:38] only test from test-all.tcl when manual option is set:
# for now only check if value is full or something else. Default is not-full, so always.
#@test manual

proc test_no_class {par1} {
  puts "In test_no_class, par1: $par1"
  set x 1
  breakpoint
  puts "Finished"
}

test_no_class 42

oo::class create summation {
  variable v
  constructor {} {
    set v 0
  }
  method add x {
    breakpoint
    incr v $x
  }
  method value {} {
    return $v
  }
  destructor {
    puts "Ended with value $v"
  }
}
set sum [summation new]
puts "Start with [$sum value]"
for {set i 1} {$i <= 10} {incr i} {
  puts "Add $i to get [$sum add $i]"
}
summation destroy
