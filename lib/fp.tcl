# Functional Programming functions
# Also look in ::struct::list

package require struct::list

package provide ndv 0.1.1

namespace eval ::ndv {

	namespace export times times_old lindices iden lambda_negate lambda_and regexp_lambda \
	         lst_partition partition_all proc_to_lambda lambda_to_proc iden id if_else map mapfor \
	         filter filterfor iota multimap transpose when_set set_if_empty variables

  # 16-1-2016 deze std map/filter uit struct::list voldoen niet goed genoeg.
  # interp alias {} map {} ::struct::list map
  interp alias {} mapfor {} ::struct::list mapfor
  
  # interp alias {} filter {} ::struct::list filter
  interp alias {} filterfor {} ::struct::list filterfor
  
  interp alias {} iota {} ::struct::list iota
	
  proc times_old {ntimes pr args} {
    set result {}
    for {set i 0} {$i < $ntimes} {incr i} {
      lappend result [$pr {*}$args] 
    }
    return $result
  }
  
  proc times {ntimes block} {
    set result {}
    for {set i 0} {$i < $ntimes} {incr i} {
      # lappend result [$pr {*}$args]
      lappend result [uplevel $block]
    }
    return $result
  }   

  # multiple of lindex: return multiple elements of a list
  # example: lindices $lst 0 2 4
  proc lindices {lst args} {
    return [struct::list mapfor el $args {lindex $lst $el}] 
  }

  proc iden {param} {
    return $param 
  }

  proc id {val} {
    return $val
  }
  
  proc lambda_negate {lambda} {
    list [lindex $lambda 0] "![lindex $lambda 1]"
  }
  
  # niet zeker of deze werkt.
  proc lambda_and {lambda1 lambda2} {
    if {[lindex $lambda1 0] != [lindex $lambda2 0]} {
      error "Lambda1 en 2 should have the same param name"
    }
    # list [lindex $lambda1 0] "([lindex $lambda1 1]) && ([lindex $lambda2 1])"
    list [lindex $lambda1 0] "[lindex $lambda1 1] && [lindex $lambda2 1]"
  }
  
  # 6-7-2010 dingen met list geprobeerd, maar dan teveel braces. Mis hier echte closure en/of macro.
  # verder wat vogelen met quotes en braces om te zorgen dat de list 2 elementen heeft.
  proc regexp_lambda {re} {
    return "x {\[regexp -nocase -- {$re} \$x\]}"
  }

  # divide list in sublists based on a lambda function. The result of the function determines the element in the partition.
  # @todo? also put the function result in the partition?
  # onderstaande een library function.
  proc lst_partition {lst lambda} {
    array set ar {} ; # empty array
    foreach el $lst {
      lappend ar([apply $lambda $el]) $el
    }
    # array get ar: geeft ook element name, wil ik niet.
    struct::list mapfor el [array names ar] {set ar($el)} 
  }

  # same name as clojure-fn
  proc partition_all {n coll} {
    set res {}
    set lst {}
    set i 0
    foreach el $coll {
      lappend lst $el
      incr i
      if {$i >= $n} {
        lappend res $lst
        set lst {}
        set i 0
      }
    }
    if {$lst != {}} {
      lappend res $lst
    }
    return $res
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
  set proc_counter 0
  proc lambda_to_proc {lambda} {
    global proc_counter
    incr proc_counter
    set procname "zzlambda$proc_counter"
    proc $procname {*}$lambda ; # combi van args en body
    return $procname
  }

  # sometimes need in FP functions
  proc iden {arg} {
    return $arg 
  }

  # functional equivalent of if statement.
  # not sure if uplevel/expr always works as expected.
  # idea stolen from R.
  proc ifelse {expr iftrue {iffalse ""}} {
    if {[uplevel 1 expr $expr]} {
      return $iftrue 
    } else {
      return $iffalse 
    }
  }

  # apply procname to each corresponding member in lst_lsts
  # return (single) list with results
  # procname should expect the same number of arguments as there are lists in lst_lsts
  # @todo deze al in ndv-lib?
  proc multimap {procname lst_lsts} {
    set res {}
    set n [llength [lindex $lst_lsts 0]]
    for {set i 0} {$i < $n} {incr i} {
      lappend res [$procname {*}[mapfor lst $lst_lsts {
        lindex $lst $i
      }]]
    }
    return $res
  }
  
  # ook transpose, hier niet nodig, verder wel handig, zie ook clojure
  proc transpose {lst_lsts} {
    multimap list $lst_lsts 
  }
  
  # set var_name to value if value is non-empty. Keep unchanged otherwise.
  proc when_set {var_name value} {
    upvar $var_name var
    if {$value != ""} {
      set var $value 
    }
  }
   
  # give a var a value if it does not already have a value (not set, or set to "" or {})
  # compared to the previous proc, this one checks the actual value of var_name, the previous checks value.
  proc set_if_empty {var_name value} {
    upvar $var_name var
    if {[info exists var]} {
      if {($var == "") || ($var == {})} {
        set var $value 
      } else {
        # already set to a value, do nothing. 
      }
    } else {
      set var $value 
    }  
  }

  # wrapper around variable, to define more than 1 variable without settings its value
  proc variables {args} {
    foreach arg $args {
      uplevel variable $arg 
    }
  }
  
}

