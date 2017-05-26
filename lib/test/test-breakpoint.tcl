#!/usr/bin/env tclsh861

# not to run automatically, but in a separate test, to see if arrow keys etc work
# as long as tclsh is added in front, editing works fine, then rlwrap is included.
# just with ./test-breakpoint.tcl rlwrap is not included, and arrow keys don't work.

# [2016-10-29 14:38] only test from test-all.tcl when manual option is set:
# for now only check if value is full or something else. Default is not-full, so always.
#@test manual

package require ndv
breakpoint

