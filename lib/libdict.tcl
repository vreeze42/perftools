# params: [-withname] dict <lijst van attr names>
# -withname geef attr-naam mee in de result
# in tcl toch maar - gebruiken als symbol qualifier, ipv :
proc dict_get_multi {args} {
  if {[lindex $args 0] == "-withname"} {
    set withname 1
    set args [lrange $args 1 end]
  } else {
    set withname 0 
  }
  set dict [lindex $args 0]
  set res {}
  foreach parname [lrange $args 1 end] {
    if {$withname} {
      if {[dict exists $dict $parname]} {
        lappend res $parname [dict get $dict $parname] 
      } else {
        lappend res $parname ""
      }
    } else {
      if {[dict exists $dict $parname]} {
        lappend res [dict get $dict $parname]
      } else {
        lappend res ""
      }
    }
  }
  return $res
}

# create a dict with each arg from args. args contains var-names, dict will contain names+values
proc vars_to_dict {args} {
  set res {}
  foreach arg $args {
    upvar $arg val
    if {![info exists val]} {
      error "no var: $arg, cannot read value"
    }
    # puts "$arg = $val"
    lappend res $arg $val
  }
  return $res
}

# 1-5-2016 deze waarsch niet nodig, vorige wel ok.
proc vars_to_dict_alternative {args} {
  set res {}
  foreach arg $args {
    upvar $arg val
    # puts "$arg = $val"
    if {[catch {lappend res $arg $val}]} {
      error "no var: $arg, cannot read value"
    }
  }
  return $res
}


# @param dct dictionary object
# @result var-names with values in calling stackframe based on dct.
proc dict_to_vars {dct} {
  foreach {nm val} $dct {
    upvar $nm val2
    set val2 $val
  }
}

proc dict_get {dct key {default {}}} {
  if {[dict exists $dct $key]} {
    dict get $dct $key
  } else {
    return $default 
  }
}

# dict lappend does not really work as I want, like dict set, with possibility to give >1 key. So this.
# @pre dict exists.
proc dict_lappend {args} {
  set dct_name [lindex $args 0]
  set keys [lrange $args 1 end-1]
  set val [lindex $args end]
  upvar $dct_name dct
  # breakpoint
  if {[dict exists $dct {*}$keys]} {
    set curval [dict get $dct {*}$keys] 
  } else {
    set curval {}
  }
  lappend curval $val
  dict set dct {*}$keys $curval
  return $dct
}

# return flattened dict, so eg {height {min 5 max 7}} becomes {height.min 5 height.max 7}
# @todo multilevel, first only single level. Repeatedly calling this function is a workaround.
# @note also keep orig (nested) value in dict, because of things like 'title "Scriptrun times"'. Tcl does not distinguish between these strings and actual dicts.
proc dict_flatten {dct {sep .}} {
  # maybe should use dict map, but then also still flatten needed, as the map-function may return more than one key (essence of this function).
  set res [dict create]
  foreach key [dict keys $dct] {
    set val [dict get $dct $key]
    if {[dict? $val]} {
      # sub-dict
      foreach subkey [dict keys $val] {
        dict set res "$key$sep$subkey" [dict get $val $subkey]
      }
    } 
    # single value, and also keep orig for nested values.
    dict set res $key $val
  }
  return $res
}

# returns 1 if x is (looks like) a dict. This cannot strictly be determined, so check if x is a list and has an even number of items.
proc dict? {x} {
  if {[string is list $x]} {    # Only [string is] where -strict has no effect
    if {[expr [llength $x]&1] == 0} {
      return 1
    }
  }
  return 0
}

# experimental: creating :accessor procs for dicts on the fly using unknown statement
# possible alternative is to create these accessors explicity.
# eg dict_make_accessors :bla :att {:lb lb}
# last one to create proc :lb, which used attribute lb (not :lb).
# also split in sub-functions.
# can this be done with interp alias? probably not, as it is not simply a prefix.

proc make_dict_accessors {args} {
  foreach arg $args {
    make_dict_accessor {*}$arg  
  }
}

proc make_dict_accessor {args} {
  if {[llength $args] == 1} {
    set procname $args
    set attname $args
  } elseif {[llength $args] == 2} {
    lassign $args procname attname
  } else {
    error "args does not have length 1 or 2: $args"
  }
  proc $procname {dct {default {}}} "
    dict_get \$dct $attname \$default
  "

  return $procname
}

# Save the original one so we can chain to it
rename unknown _original_unknown

proc unknown args {
  if {([llength $args] == 2) || ([llength $args] == 3)} {
    lassign $args procname dct default
    if {[string range $procname 0 0] == ":"} {
      if {[string is list $dct]} {    # Only [string is] where -strict has no effect
        if {[expr [llength $dct]&1] == 0} {
          # actual entry in dict may be with or without ":",
          # check current and make implementation dependent on the result.
          if {[dict exists $dct $procname]} {
            make_dict_accessor $procname
          } elseif {[dict exists $dct [string range $procname 1 end]]} {
            make_dict_accessor $procname [string range $procname 1 end]
          } else {
            #log warn "attribute not found in dictionary: $procname, with or without :" 
            #log warn "default: make accessor for item without :"
            make_dict_accessor $procname [string range $procname 1 end]
          }
          return [$procname $dct]
        }
      }
    }
  }
  # breakpoint
  # if the above does not apply, call the original.
  # [2016-05-15 13:44] don't log any message, orig unknown will handle this, and
  # ::tk::MessageBox uses the unknown feature.
  #log warn "WARNING: unknown command: [string range $args 0 100]"
  #log warn "calling original unknown for $args"
  uplevel 1 [list _original_unknown {*}$args]
}

# 26-2-2014 also some list helpers here. Should be in separate lib, but keep here, because names also start with :
# don't use #, 0, 1 without : => # is a comment, others would be too confusing.
# [2016-09-14 21:43] those should be deprecated, use count, first in libfp, similar to clojure.
proc :# {l} {
  llength $l
}

proc :0 {l} {
  lindex $l 0
}

proc :1 {l} {
  lindex $l 1
}

proc :k {d} {
  dict keys $d
}

# [2016-05-30 21:34] dict merge functions, no testcases yet.
proc dict_merge_append {d1 d2 args} {
  # soort curry/partial dit:
  dict_merge_fn concat $d1 $d2 {*}$args
}

# merge dicts as in dict merge, but don't let later values replace older ones, but apply fn to values
proc dict_merge_fn {fn d1 d2 args} {
  # first combine d1 and d2
  set res [dict create]
  dict for {k v} $d1 {
    if {[dict exists $d2 $k]} {
      # dict set res $k [concat $v [dict get $d2 $k]]
      dict set res $k [$fn $v [dict get $d2 $k]]
    } else {
      dict set res $k $v
    }
  }
  dict for {k v} $d2 {
    if {[dict exists $d1 $k]} {
      # nothing, already done
    } else {
      dict set res $k $v
    }
  }
  # if args != {}, combine result of d1/d2 with the rest
  if {$args != {}} {
    # tail call, oh well.
    dict_merge_fn $fn $res {*}$args
  } else {
    return $res
  }
}

# rename fields in lfrom to lto and return new dict.
proc dict_rename {d lfrom lto} {
  set res $d
  foreach f $lfrom t $lto {
    # [2016-08-02 13:38:19] could be keys in from are not available.
    dict set res $t [dict_get $d $f]
    dict unset res $f
  }
  return $res
}

