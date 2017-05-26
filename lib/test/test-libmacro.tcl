#!/usr/bin/env tclsh861

package require tcltest
package require Tclx

namespace import -force ::tcltest::*

source [file join [file dirname [info script]] .. libns.tcl]
source [file join [file dirname [info script]] .. libmacro.tcl]

use libmacro

# this one in libtest.tcl?
proc testndv {args} {
  global testndv_index
  incr testndv_index
  test test-$testndv_index test-$testndv_index {*}$args
}

# without ~, should return the same, identity
testndv {syntax_quote {proc testa {x} {return $x}}} {proc testa {x} {return $x}}

testndv {set table trans; syntax_quote {proc testa {x} {format "%s %s" ~$table $x}}} \
    {proc testa {x} {format "%s %s" trans $x}}

# should fail without the use of list in syntax_quote
testndv {set table "trans abcd"; syntax_quote {proc testa {x} {format "%s %s" ~$table $x}}} \
    {proc testa {x} {format "%s %s" {trans abcd} $x}}


# [2016-08-09 21:43] splicing also needed
set init {set a 1}
proc test_splice {x} [syntax_quote {~@$init
  expr $a + $x
}]

testndv {test_splice 12} 13

set init2 {}
proc test_splice2 {x} [syntax_quote {~@$init2
  expr 1 + $x
}]

testndv {test_splice2 12} 13

# TODO: also unquote procs, needed as below:
# syntax_quote {set generated_datetime ~[dt/now]}
# should then find corresponding end-bracket, might be hard, need a full parser then?
# workaround is to call proc before the syntax quote and save result in a var.

# TODO: maybe format returned code, always start at 0 indent?
# if it's just to be executed, doesnt't really matter, so should be separate function.
# separate function could have start-index parameter.

# test format-code on libmacro.tcl itself. Should remain the same
set srcfile [file join [file dirname [info script]] .. libmacro.tcl]
set src [read_file -nonewline $srcfile]
# set src_new [format_code $src]
# write_file "/tmp/libmacro.tcl" [format_code $src]
testndv {global src; format_code $src} $src

cleanupTests

