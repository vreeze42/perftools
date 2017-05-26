# @todo alles in ndv namespace.

#
# random.tcl - very random number generator in tcl.
#
# Copyright 1995 by Roger E. Critchlow Jr., San Francisco, California.
# All rights reserved.  Fair use permitted.  Caveat emptor.
#
# This code implements a very long period random number
# generator.  The following symbols are "exported" from
# this module:
#
#	[random] returns 31 bits of random integer.
#	[srandom <integer!=0>] reseeds the generator.
#	$RAND_MAX yields the maximum number in the
#	  range of [random] or maybe one greater.
#
# The generator is one George Marsaglia, geo@stat.fsu.edu,
# calls the Mother of All Random Number Generators.
#
# The coefficients in a2 and a3 are corrections to the original
# posting.  These values keep the linear combination within the
# 31 bit summation limit.
#
# And we are truncating a 32 bit generator to 31 bits on
# output.  This generator could produce the uniform distribution
# on [INT_MIN .. -1] [1 .. INT_MAX]
#
namespace eval random {
    set a1 { 1941 1860 1812 1776 1492 1215 1066 12013 };
    set a2 { 1111 2222 3333 4444 5555 6666 7777   827 };
    set a3 { 1111 2222 3333 4444 5555 6666 7777   251 };
    set m1 { 30903 4817 23871 16840 7656 24290 24514 15657 19102 };
    set m2 { 30903 4817 23871 16840 7656 24290 24514 15657 19102 };

    proc srand16 {seed} {
	set n1 [expr $seed & 0xFFFF];
	set n2 [expr $seed & 0x7FFFFFFF];
	set n2 [expr 30903 * $n1 + ($n2 >> 16)];
	set n1 [expr $n2 & 0xFFFF];
	set m  [expr $n1 & 0x7FFF];
	foreach i {1 2 3 4 5 6 7 8} {
	    set n2 [expr 30903 * $n1 + ($n2 >> 16)];
	    set n1 [expr $n2 & 0xFFFF];
	    lappend m $n1;
	}
	return $m;
    }
    
    proc rand16 {a m} {
	set n [expr \
		   [lindex $m 0] + \
		   [lindex $a 0] * [lindex $m 1] + \
		   [lindex $a 1] * [lindex $m 2] + \
		   [lindex $a 2] * [lindex $m 3] + \
		   [lindex $a 3] * [lindex $m 4] + \
		   [lindex $a 4] * [lindex $m 5] + \
		   [lindex $a 5] * [lindex $m 6] + \
		   [lindex $a 6] * [lindex $m 7] + \
		   [lindex $a 7] * [lindex $m 8]];
	
	return [concat [expr $n >> 16] [expr $n & 0xFFFF] [lrange $m 1 7]];
    }
}

#
# Externals
# 
set RANDOM_MAX 0x7FFFFFFF;
    
proc srandom {seed} {
    global random::m1 random::m2;
    set random::m1 [random::srand16 $seed];
    set random::m2 [random::srand16 [expr 4321+$seed]];
    return {};
}

proc random {} {
    global random::m1 random::m2 random::a1 random::a2;
    set random::m1 [random::rand16 [set random::a1] [set random::m1]];
    set random::m2 [random::rand16 [set random::a2] [set random::m2]];
    return [expr (([lindex [set random::m1] 1] << 16) + [lindex [set random::m2] 1]) & 0x7FFFFFFF];
}

# return random number between 0 (incl) and 1 (excl)
proc random1 {} {
  global RANDOM_MAX
  return [expr 1.0 * [random] / $RANDOM_MAX] 
}

# return random number between 0 (incl) and max (excl)
proc random_int {max} {
  return [expr int([random1] * $max)]
}

# return a random element from the given list
proc random_list {lst} {
  return [lindex $lst [random_int [llength $lst]]]
}

