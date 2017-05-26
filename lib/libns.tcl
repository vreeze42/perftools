package require ndv

# import procs from namespace into the main/global namespace.
# what can be a list of items/procs to import
proc use {ns {what *}} {
  if {$what == "*"} {
    namespace import ::${ns}::*
  } else {
    foreach el $what {
      namespace import ::${ns}::$el
    }
  }
}

# [2016-10-29 15:13] not really needed, package require ndv also takes care of this.
use libmacro

# example: require libdatetime dt
# makes all commands in ns available as <as>/command
# same as Clojure; / is easier to type than ::
# eg: libdatetime::now is a command. After previous call, dt/now will be available

# should be able to find all exported commands in a namespace.
# until then:
proc require_old {ns as} {
  namespace import ::${ns}::*
  foreach el [namespace import] {
    set el_org [namespace origin $el]
    if {[namespace qualifiers $el_org] == "::$ns"} {
      # puts "Making alias for $el_org"
      interp alias {} "${as}/$el" {} $el_org
      # todo
      namespace forget $el
    } else {
      # puts "From other package, ignoring: $el_org"
    }
  }
}

# TODO: possibly use info command ${ns}::*
# there was/is no namespace sub command to provide this info.
proc require {ns as} {
  foreach el [get_ns_imports $ns] {
    interp alias {} "${as}/$el" {} ${ns}::${el}
  }
}


# [2016-09-24 12:12] 
# get names of exported commands in namespace.
# namespace import should support this, but have not found a way to just query
proc get_ns_imports {ns} {
  namespace eval ::__TEMPNS__ [syntax_quote {
    namespace import ::~$ns::*
    #set l [namespace import]
    #puts "l: $l"
    set ::__TEMP_IMPORT__ [namespace import]
    # return $l
  }]
  # puts "abc"
  namespace delete ::__TEMPNS__
  return $::__TEMP_IMPORT__
}

