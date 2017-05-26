# libfp.tcl - functional programming in Tcl
# primary goals: make as easy to use as possible, compare Clojure
# secondary goals: make fast, always correct.

# @note partly based on things found on wiki.tcl.tk
# @note also based on previous attempts to usable FP methods/procs/functions.
# @note use Tcltest to validate functionality, also usable as documentation.
# @note try to use CLojure function names (and arguments) as basis. 
#       If name conflicts with existing tcl name, use another name, eg if -> ifp 
# @note basic closures work, need to test more complicated test cases.
# @note ? and - are possible in proc names. ':' also, already used for dict accessors, see libdict.
# @note what to do with lazy handling, eg in if-proc.
# @note use Tcl syntax/formatting and Clojure-like formatting both, most applicable.
# @note order is as in clojure: if a function A uses another function B, B should be defined before A.

# import math operators and functions as first class procs
# [2016-07-22 10:11] maybe should not have this dependency; however, don't need to require a package, so really part of the 'core'.
# need to have this both in main and in namespace:
# * main: so functions can be called externally (export + does not work)
# * ns  : so + can be used directly, although ::+ also fails.
# namespace path {::tcl::mathop ::tcl::mathfunc}

# [2016-07-23 16:12] only mathop, don't want log function as a proc.
namespace path {::tcl::mathop}

namespace eval ::libfp {
  namespace export = != and or ifp seq empty? cond_1 cond not not= \
      str identity fn comp lstride regsub_fn map filter any? reduce repeat range \
      lambda_to_proc proc_to_lambda find_proc first second count rest -> \
      complement

  # namespace path {::tcl::mathop ::tcl::mathfunc}
  namespace path {::tcl::mathop}

# @note some easy, helper functions first
proc = {a b} {
  if {$a == $b} {
    return 1
  } else {
    return 0
  }
}

proc != {a b} {
  expr ![= $a $b]
}

proc and {args} {
  foreach exp $args {
    if {![uplevel 1 [list expr $exp]]} {
      return 0
    }
  }
  return 1
}

proc or {args} {
  foreach exp $args {
    if {[uplevel 1 [list expr $exp]]} {
      return 1
    }
  }
  return 0
}

# some mathematical functions, maybe already provided by mathlib.
proc max_old {args} {
  if {[llength $args] == 1} {
    set lst [lindex $args 0]
  } else {
    set lst $args
  }
  set res [lindex $lst 0]
  foreach el $lst {
    if {$el > $res} {
      set res $el
    }
  }
  return $res
}

# this is the if from clojure, don't want to override the std Tcl def.
# @todo handle expressions as first argument? Or should have been evaluated before?
# how to handle nil or empty list?
# 0 is truthy in clojure, but would not be handy in Tcl.
# nil is falsy, but '() and [] are seen as truthy, seq function used to convert '() to nil.
# @note 'yes' and 'no' will be evaluated lazily, only when condition is met.
# @note therefore the yes and no values should be enclosed in {}.
# @note OTOH this makes function less handy to use, and would violate a starting point.
# @note so should either use the standard if (which is 'lazy') or create own other variant.
# @note or find a way to distinguish between expression and value: is this possible? how handled in clojure? (probably special form/macro with if)
proc ifp {test yes no} {
  if {$test == "nil"} {
    return $no
    # eval $no
    # uplevel 1 $no - default is level 1
    # uplevel $no
  } elseif {$test} {
    return $yes
    # eval $yes
  } else {
    return $no
    # eval $no
  }
}

# @note seq for now just to translate empty list to nil, and this becomes falsy in [not] and [ifp]
proc seq {l} {
  ifp [= [string length $l] 0] nil $l
}

proc empty? {l} {
  ifp [= [seq $l] nil] 1 0  
}

proc cond_1 {args} {
  lassign $args test result rest
  puts "cond called with $args"
  # ifp [empty? $args] 0 [ifp $test $result [cond {*}$rest]]
  ifp [empty? $args] 0 {[ifp $test $result [cond {*}$rest]]}
}

# @note ifp not usable, as it is not lazy.
proc cond {args} {
  set rest [lassign $args test result]
  # puts "cond called with $args"
  # ifp [empty? $args] 0 [ifp $test $result [cond {*}$rest]]
  # ifp [empty? $args] 0 {[ifp $test $result [cond {*}$rest]]}
  if {[expr [llength $args] % 2] == 1} {
    error "cond should be called with an even number of arguments, got $args" 
  }
  if {[empty? $args]} {
    return 0 
  } elseif {$test} {
    return $result 
  } else {
    cond {*}$rest 
  }
}

proc not {a} {
  ifp $a 0 1
}

proc not= {a b} {
  # @todo not {= $a $b} should also work?
  not [= $a $b]  
}

proc str {args} {
  join $args ""
}

# clj fn is also called identity, not iden or id
proc identity {a} {
  return $a 
}

# [2016-07-30 10:06] TODO: add clj sequence functions like first, rest, second, count.
# those instead of current :# :0 and :1 as defined in libdict.tcl.
proc count {l} {
  llength $l
}

proc first {l} {
  lindex $l 0
}

proc second {l} {
  lindex $l 1
}

proc rest {l} {
  lrange $l 1 end
}

# @todo functies om een lambda naar een proc om te zetten en vice versa
# deze ook functioneel kunnen inzetten, ofwel return value moet direct bruikbaar zijn.
proc proc_to_lambda {procname} {
  list args "$procname {*}\$args"
}

# resultaat van lambda_to_proc mee te geven aan struct::list map en filter bv.
# eerst even simpel met een counter
# vb: struct::list map {1 2 3 4} [lambda_to_proc {x {expr $x * 3}}] => {3 6 9 12}
# vb: struct::list filter {1 2 3 4} [lambda_to_proc {x {expr $x >= 3}}]
# TODO: find a way to clean up those procs. According to wiki.tcl.tk this is one of the
# harder problems. Maybe start/stop "transaction" or exeution-timeline. If the timeline finishes, all created procs within can be removed. Maybe something with namespaces: put als temp procs in a namespace, and forget the namespace when you're done.
# rename <proc> "" can be used to delete a proc.
# TODO: maybe could use a watch on the generated proc name, to see when it goes out of scope. But should be careful when procname is given to another var.

# Opties:
# * fully qualified name teruggeven, dus met libfp:: ervoor.-> [2016-07-30 09:31] lijkt wel prima, huidige keuze
# * aanmaken in main namespace: proc ::$procname
# * aanmaken in callende namespace: kan dit?

set proc_counter 0
proc lambda_to_proc {lambda} {
  global proc_counter
  incr proc_counter
  # set procname "zzlambda$proc_counter"
  set procname "::libfp::zzlambda$proc_counter"
  proc $procname {*}$lambda ; # combi van args en body
  return $procname
}

# anonymous function
# simple one, without closures.
proc fn_old {params body} {
  lambda_to_proc [list $params $body]
}

# anonymous functie with closures eval-ed.
proc fn {params body} {
  lambda_to_proc [list $params [eval_closure $params $body]]
}

# [2016-07-22 14:17] from http://wiki.tcl.tk/17444
# [2016-07-22 14:19] does not work here in combination with the rest, maybe find out why
# benefit could be the absence of need to create a proc, and it's smaller.
proc fn_alt1 {params body} { list ::apply [list $params [list expr $body] ::] }

# comp(ose) as in clojure
# TODO: more than 2 procs, also 0 or 1 procs. 0=identity?
proc comp {pr1 pr2} {
  # fn args {pr1 [pr2 args]}
  # fn args [list $pr1 [list $pr2 \$args]]
  fn args [syntax_quote {~$pr1 [~$pr2 {*}$args]}]
}


# http://wiki.tcl.tk/17475 - [2016-07-22 14:28] Monads, could also be useful.

# eval vars in closure of the proc, leave params alone.
# first find all occurences of $var and replace by actual value in uplevel, iff
# var does not occur in params.
# TODO: check ${var}, maybe also [set var]
# TODO: check if resulting value should be surrounded by quotes or braces. [2016-07-21 20:56] for now seems ok.
# TODO: [2016-07-22 10:52] when a string with spaces is replaced, something is needed.
# TODO: This probably fails if body is more complicated, and contains another method call with closure.
proc eval_closure {params body} {
  set indices [regexp -all -indices -inline {\$([A-Za-z0-9_]+)} $body]
  # begin at the end, so when changing parts at the end, the indices at the start stay the same.
  # instead of checking if var usage in body occurs in param list, could also try to eval the var and if it succeeds, take the value. However, the current method seems more right.
  foreach {range_name range_total} [lreverse $indices] {
    set varname [string range $body {*}$range_name]
    if {[lsearch -exact $params $varname] < 0} {
      upvar 2 $varname value
      # set body [string replace $body {*}$range_total $value]
      # TODO: or check value and decide what needs to be done, surround with quotes, braces, etc.
      set body [string replace $body {*}$range_total [list $value]]
    }
  }
  return $body
}

# from: http://wiki.tcl.tk/1239
proc lstride {list n} {
  set res {}
  for {set i 0; set j [expr {$n-1}]} {$i < [llength $list]} {incr i $n; incr j $n} {
    lappend res [lrange $list $i $j]
  }
  return $res
}

# use technique above with regexp to make a regsub which will replace found items
# with the result of a function on these items. something like:
# regsub_fn {re} $str [fn x {string length $x}]
# done something like this before with FB/vugen script.
# in regsub there is an example doing something similar.
# then maybe could use this function in the above eval_closure def, but could be recursive explosion.
# the regexp could contain parens, handle correctly. The x in the function could always
# been the whole found string, but could also use fn with more params to bind them to
# substrings (with parens) in regexp.
# mgrp can be specified to replace not the whole regexp found, but the matching group.
# implementation:
# * begin at the end, so when changing parts at the end, the indices at the start stay the same.
proc regsub_fn {re str fn {mgrp 0}} {
  set indices [regexp -all -indices -inline $re $str]
  set nsubs [+ 1 [lindex [regexp -about $re] 0]]
  foreach match_ranges [lreverse [lstride $indices $nsubs]] {
    set values [map [fn x {string range $str {*}$x}] $match_ranges]
    set new_value [$fn {*}$values]
    set str [string replace $str {*}[lindex $match_ranges $mgrp] $new_value]
  }
  return $str
}

proc regsub_fn_old {re str fn} {
  set indices [regexp -all -indices -inline $re $str]
  # begin at the end, so when changing parts at the end, the indices at the start stay the same.
  # really need number of matching groups, or indices should return something else.
  # could check range-values, if one is contained in the other.
  # could have a helper function to group the ranges.
  # for now assume no matching groups.
  # could use regexp -about, first returned element is nr of groups/subexpressions.
  foreach range [lreverse $indices] {
    set value [string range $str {*}$range]
    set new_value [$fn $value]
    set str [string replace $str {*}$range $new_value]
  }
  return $str
}

# something like clojure lambda shortcuts, like #(+ 1 %)

# find proc in either current or global namespace.
# if procname is already namespace qualified, check if it exists: if so, return the name, otherwise {}
# if it is not ns qualified, first check without namespace, then in global namespace.
proc find_proc {procname} {
  set res [info proc $procname]
  if {$res != {}} {
    return $res
  }
  info proc ::$procname
}

# @todo handle more than one map-var, for traversing more than one map at the same time? -> [2016-07-30 09:33] NOT.
# @note should handle 2 forms:
# (map var list expression-with-var) -> [2016-07-30 09:33] this one deprecated?
# (map lambda list), where lambda is {var expr-with-var}
# @todo [2016-07-30 09:34] check if apply can be be used instead of lambda_to_proc, to prevent memory leaks.
proc map {args} {
  if {[llength $args] == 2} {
    lassign $args arg1 arg2
    set procname [find_proc $arg1]
    # if {[info proc $arg1] != {}} {}
    if {$procname != {}} {
      set res {}
      foreach el $arg2 {
        lappend res [$procname $el]
      }
      return $res
    } else {
      # assume lambda with 2 elements
      if {[llength $arg1] == 2} {
        map [lambda_to_proc $arg1] $arg2  
      } else {
        error "proc not found and not a lambda: $arg1"
      }
    }
  } elseif {[llength $args] == 3} {
    # [2016-07-16 12:48] TODO: maybe should not support this, to stay similar to reduce
    # function, which has optional start parameter.
    lassign $args arg1 arg2 arg3
    map [lambda_to_proc [list $arg1 $arg2]] $arg3
  } else {
    error "No 2 or 3 args: $args"
  }
}

# filter is vergelijkbaar met map, toch soort van dubbele code, voorlopig ok.
proc filter {args} {
  # puts "filter called: $args"
  if {[llength $args] == 2} {
    lassign $args arg1 arg2
    set procname [find_proc $arg1]
    if {$procname != {}} {
      # puts "body: [info body $arg1]"
      set res {}
      foreach el $arg2 {
        if {[$procname $el]} {
          lappend res $el
        }
      }
      return $res
    } else {
      # assume lambda with 2 elements
      filter [lambda_to_proc $arg1] $arg2
    }
  } elseif {[llength $args] == 3} {
    lassign $args arg1 arg2 arg3
    filter [lambda_to_proc [list $arg1 $arg2]] $arg3
  } else {
    error "No 2 or 3 args: $args"
  }
}


# first only with fn and list, later also with start value
proc reduce {args} {
  if {[llength $args] == 2} {
    lassign $args fn lst
    if {[info proc $fn] != {}} {
      # TODO: [2016-07-16 12:51] fill in, but not needed now
    } else {
      reduce [lambda_to_proc $fn] $lst
    }
  } else {
    error "!= 2 args not supported: $args"
  }
}

# return 1 iff [$f $el] returns != 0 for at least one el in lst
# similar to non-official clojure version, only have not-any?, some and some?,
# which are all slightly different.
proc any? {f lst} {
  > [count [filter $f $lst]] 0
}

# lib function, could also use struct::list repeat
proc repeat {n x} {
  set res {}
  for {set i 0} {$i < $n} {incr i} {
    lappend res $x 
  }
  return $res
}

# Returns a list of nums from start (inclusive) to end
# (exclusive), by step, where step defaults to 1
# also copied from clojure def.
proc range {start end {step 1}} {
  set res {}
  for {set i $start} {$i < $end} {incr i $step} {
    lappend res $i 
  }
  return $res
}

# Threading operators, start very simple, only functions with one argument.
proc -> {startval args} {
  set val $startval
  foreach f $args {
    # maybe use uplevel?
    set val [$f $val]
  }
  return $val
}

# [2016-12-07 20:34] complement function, as in Clojure
#(defn complement [f]
# (comp not f))
proc complement {f} {
  comp not $f
}


} ; # end-of-namespace
