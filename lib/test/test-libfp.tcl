#!/usr/bin/env tclsh

# test-libfp.tcl - test functionality of libfp.tcl

# @note don't package require libfp, but source it, easier to test.

# this one could interfere with the source-cmd below.
# [2016-07-21 20:54] but it does seem to work

# [2016-11-03 21:56] code below used to determine why package require ndv fails under gosleep.
# reason is another tclsh (/usr/bin/tclsh) is used.
#set who [exec whoami]
#puts "user executing test: $who"
#puts "pwd: [pwd]"
#puts "tcl_pkgPath: $tcl_pkgPath"
#puts "auto_path: $auto_path"
#puts "executable: [info nameofexecutable]"
# parray env

package require ndv

#package require tcltest
#namespace import -force ::tcltest::*

use libtest

source [file join [file dirname [info script]] .. libns.tcl]

# source ../libfp.tcl
source [file join [file dirname [info script]] .. libfp.tcl]

# sometimes useful for debugging.
source [file join [file dirname [info script]] .. breakpoint.tcl]

use libfp ; # all libfp functions now in namespace
use libfp ; # should be idempotent.

## test easy, basic functions
# test add-1 {simple addition} {add 3 4} 7
tcltest::test eq-1 {equals 1} {= 1 1} 1
tcltest::test eq-2 {equals 2} {= abc abc} 1
tcltest::test eq-3 {equals 3} {= {abc def} [list abc def]} 1

tcltest::test eq-4 {equals 4} {= 1 2} 0
tcltest::test eq-5 {equals 5} {= abc abcd} 0
tcltest::test eq-6 {equals 6} {= {abc def ghi} [list abc def]} 0

# should = handle or less than 2 arguments?
tcltest::test eq-7 {equals 7} -body {=} -returnCodes error -result {wrong # args: should be "= a b"}
tcltest::test eq-8 {equals 8} -body {= 1} -returnCodes error -result {wrong # args: should be "= a b"}
tcltest::test eq-9 {equals 9} -body {= 1 1 1} -returnCodes error -result {wrong # args: should be "= a b"}
tcltest::test eq-10 {equals 10} -body {= 1 1 13} -returnCodes error -result {wrong # args: should be "= a b"}

tcltest::test not-1 {not 1} {not 1} 0
tcltest::test not-2 {not 2} {not 0} 1
tcltest::test not-3 {not 3} {not nil} 1

tcltest::test not-eq-1 {not equals 1} {not= 0 0} 0
tcltest::test not-eq-1 {not equals 1} {not= 0 1} 1

tcltest::test str-1 {str 1} {str a b} ab
tcltest::test str-2 {str 2} {str} ""
tcltest::test str-3 {str 3} {str "abc"} "abc"
tcltest::test str-4 {str 4} {str 12 "abc" 3} "12abc3"

tcltest::test iden-1 {iden 1} {identity 42} 42
tcltest::test iden-2 {iden 2} {identity {}} {}
tcltest::test iden-3 {iden 3} {identity ""} ""

tcltest::test ifp-1 {ifp 1} {ifp 0 1 2} 2
tcltest::test ifp-1 {ifp 1} {ifp 1 1 2} 1
tcltest::test ifp-1 {ifp 1} {ifp nil 1 2} 2

tcltest::test seq-1 {seq 1} {seq {}} nil
tcltest::test seq-2 {seq 2} {seq {a b c}} {a b c}

tcltest::test empty-1 {empty 1} {empty? nil} 1
tcltest::test empty-2 {empty 2} {empty? {}} 1
tcltest::test empty-3 {empty 3} {empty? {a b}} 0

tcltest::test cond-1 {cond 1} {cond} 0
tcltest::test cond-3 {cond 3} {cond 1 2} 2
tcltest::test cond-4 {cond 4} {cond 0 2} 0
tcltest::test cond-5 {cond 5} {cond 1 2 3 4} 2
tcltest::test cond-6 {cond 6} {cond 0 2 3 4} 4
tcltest::test cond-2 {cond 2} -body {cond 1} -returnCodes error -result {cond should be called with an even number of arguments, got 1}

# [2016-07-22 10:13] Two arguments to the test function should be enough: expression and expected result.
proc testndv_old {args} {
  global testndv_index
  incr testndv_index
  # test test-$testndv_index test-$testndv_index {*}$args
  test test-$testndv_index test-$testndv_index {*}$args
}

proc testndv_old2 {body result} {
  global testndv_index
  incr testndv_index
  # test test-$testndv_index test-$testndv_index {*}$args
  test test-$testndv_index test-$testndv_index -body $body -result $result
}

testndv {= 1 1} 1
testndv {!= 1 1} 0
testndv {!= {a 1} {a 2}} 1

# [2016-07-16 12:42] some math functions
testndv {max 1 2 3} 3
testndv {max 2} 2

# [2016-07-22 16:48] this is now the max as exported by tcl::mathfunc
testndv {max {*}{1 2 3}} 3
testndv {max {*}{1}} 1

testndv {max {*}[map {x {string length $x}} {"a" "abc" "-" "ab"}]} 3

testndv {and 1 1} 1
testndv {and 1 0} 0
testndv {and {1==1} {1==2}} 0
testndv {and {1==1} {2==2}} 1

testndv {set s1 1; set s2 2; and {$s1 != {}} {$s2 != {}} {$s1 != $s2}} 1
testndv {set s1 1; set s2 2; and [!= $s1 {}] [!= $s2 {}] [!= $s1 $s2]} 1

testndv {or 0 1} 1
testndv {or 0 0 0} 0
testndv {or {1==0} {1==1}} 1
testndv {or {0==1} {1==0}} 0

testndv {cond 0 2 1 42} 42

set f [lambda_to_proc {x {expr $x * 2}}]
testndv {global f; $f 12} 24

testndv {[lambda_to_proc {x {expr $x * 2}}] 12} 24

# 2 params, first is a proc, second a list
proc plus1 {x} {expr $x + 1}
testndv {map plus1 {1 2 3}} {2 3 4}

# 3 params, first is a var(list), second a body, 3rd a list
testndv {map x {expr $x * 2} {1 2 3}} {2 4 6}

# 2 params, first is a lambda (?), second a list.
testndv {map {x {expr $x * 2}} {1 2 3}} {2 4 6}

# 7-5-2016 map in combi with fn/lambda_to_proc
testndv {map [fn x {expr $x * 2}] {1 2 3}} {2 4 6}

testndv {* 1 2 3} 6

testndv {map [fn x {* $x 2}] {1 2 3}} {2 4 6}

# iets met apply/lambda, nu 16-1-2016 wel vaag.
# @note more tests with lambda, use with apply?  
  
## test filter ##
proc is_ok {x} {regexp {ok} $x}
testndv {filter is_ok {ok false not_ok yes}} {ok not_ok}

# 3 params, first is a var(list), second a body, 3rd a list
testndv {filter x {regexp {ok} $x} {ok false not_ok yes}} {ok not_ok}

# 2 params, first is a lambda (?), second a list.
testndv {filter {x {regexp {ok} $x}} {ok false not_ok yes}} {ok not_ok}

proc is_gt3 {x} {expr $x > 3}
testndv {is_gt3 2} 0
testndv {is_gt3 5} 1

testndv {filter is_gt3 {1 2 3 4 5}} {4 5}

testndv {filter x {expr $x >= 3} {1 2 3 4 5}} {3 4 5}

proc > {x y} {expr $x > $y}
testndv {> 3 4} 0
testndv {> 4 3} 1

testndv {filter x {> $x 3} {1 2 3 4 5}} {4 5}

# One with a closure:
# first test with a specific version of fn
proc find_items {items re} {
  filter [fn x {regexp $re $x}] $items
}

testndv {find_items {abc ab abd ac gh baab} ab} {abc ab abd baab}
testndv {find_items {abc ab abd ac gh baab} {ab}} {abc ab abd baab}

## test fold ##


## test curry/partial ##

## test iden ##

## test str ##

## later: logging around procs

## test lstride, also in fp, could/should be in a list package.
testndv {lstride {a b c d e f g h i} 3} {{a b c} {d e f} {g h i}}
testndv {lstride {{0 2} {1 2} {5 7} {6 7}} 2} {{{0 2} {1 2}} {{5 7} {6 7}}}

# if n == 1, should put all items in a list of their own:
testndv {lstride {{0 2} {1 2} {5 7} {6 7}} 1} {{{0 2}} {{1 2}} {{5 7}} {{6 7}}}

# regsub_fn uses math operators as first class procs (using tcl::mathop)
# just a few tests
testndv {+ 1 2} 3
testndv {+ 4 5 6} 15
testndv {+ 1} 1
testndv {+} 0

# matches should not overlap, so this one returns 2 groups of 3 items each, flattened:
testndv {regexp -all -indices -inline {.(.)(.)} "abcdefgh"} \
    {{0 2} {1 1} {2 2} {3 5} {4 4} {5 5}}

# test regsub_fn, to regsub using functions on parameters
# also some form of closure needed, use [fn ]
# replace all series of a's with a<length>
testndv {regsub_fn {a+} "aaa b djjd a jdu aa kj" \
             [fn x {identity "a[string length $x]"}]} \
    "a3 b djjd a1 jdu a2 kj"

# one with a closure/proc handling the replace
proc sub_value {val} {
  if {$val == "a"} {
    return "z"
  } elseif {$val == "z"} {
    return "y"
  } else {
    return $val
  }
}

testndv {regsub_fn {.} "abcxyz" sub_value} "zbcxyy"

# Another one with matching groups in regexp
proc sub_value_grp {whole part1 part2} {
  return "=$part1="
}

testndv {regsub_fn {.(.)(.)} "abcdefgh" sub_value_grp} "=b==e=gh"

# just replace a subgroup:
testndv {regsub_fn {.(.)(.)} "abcdefgh" sub_value_grp 1} "a=b=cd=e=fgh"

# also test if this one still works when no subgroups are given
testndv {regsub_fn {.{1,3}} "abcdefgh" [fn x {string length $x}]} "332"

testndv {filter [comp not empty?] {1 2 "" 3 {} 4}} {1 2 3 4}

# [2016-10-15 16:12] Combination of map and dict accessor
# set rows {{Depth 5895 QueueName error} {Depth 0 QueueName Col}}

testndv {:QueueName [first {{Depth 5895 QueueName error} {Depth 0 QueueName Col}}]} error

testndv {make_dict_accessor get_qn QueueName; map get_qn {{Depth 5895 QueueName error} {Depth 0 QueueName Col}}} {error Col}

testndv {map [make_dict_accessor get_qn2 QueueName] {{Depth 5895 QueueName error} {Depth 0 QueueName Col}}} {error Col}

testndv {map [make_dict_accessor QueueName] {{Depth 5895 QueueName error} {Depth 0 QueueName Col}}} {error Col}


# testndv {map :QueueName {{Depth 5895 QueueName error} {Depth 0 QueueName Col}}} {error Col}

# threading operator
testndv {-> 12} 12
testndv {-> 1234 [fn x {string length $x}]} 4
testndv {-> 1234 [fn x {string length $x}] [fn x {+ $x $x}]} 8

# any? operator
proc even? {x} {
  = 0 [expr $x % 2]
}

testndv {any? even? {1 2 3}} 1
testndv {any? even? {1 3 5}} 0
testndv {any? [fn x {= 0 [expr $x % 2]}] {1 2 3}} 1

proc square {x} {expr $x * $x}
set odd? [comp not even?]

# complement and compose, use even? and square. not already available.
# [2016-12-07 20:33] comp was already defined.
testndv {[comp not even?] 2} 0
testndv {[comp not even?] 3} 1
testndv {${odd?} 7} 1
testndv {${odd?} 4} 0

testndv {[complement even?] 4} 0
testndv {[complement even?] 5} 1

testndv {filter [complement even?] {1 2 3 4}} {1 3}

cleanupTests

