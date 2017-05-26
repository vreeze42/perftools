# return a dictionary with all single elements directly in dct, and all single elements directly under keys in args.
proc dict_flat2 {dct args} {
  dict for {k v} $dct {
     
  }
}

# ook iets met pretty print?

# the functions below feel quite shaky, not stable. Any better way to determine the 'data' type?
# some options while parsing the json, but makes rest handling trickier, some metadata would be useful (clj again!).
# only use these functions while investigating the structure, not in production code to read the data, then know and assume the types.

# is dct a dictionary with atom keys, ie keys that are not lists/dicts?
proc is_dict_atom_keys {dct} {
  if {[is_dict $dct]} {
    # @todo do with filter/every or something like this
    set all_atom 1
    foreach el [dict keys $dct] {
      if {![is_atom $el]} {
        puts "not atom: $el (in $dct)"
        set all_atom 0 
      }
    }
    return $all_atom
  } else {
    return 0 
  }
}

# @todo how is the clj equiv function called?
proc is_atom {el} {
  if {[string is graph $el]} {    # Only [string is] where -strict has no effect
    return 1
  } else {
    return 0 ; # try out. 
  }
}

# @todo how is the clj equiv function called?
# @todo result could be opposite of is_atom, but maybe there will be another option
proc is_list {el} {
  if {[string is list $el]} {    # Only [string is] where -strict has no effect
    if {[is_atom $el]} {
      return 0 
    } else {
      return 1
    }
  } else {
    return 0 ; # try out. 
  }
}

proc det_type2 {el} {
  if {[is_atom $el]} {
    return atom 
  } elseif {[is_dict_atom_keys $el]} {
    return dict 
  } elseif {[is_list $el]} {
    return list 
  } else {
    return unknown 
  }
}

proc det_type {value} {
  if {[regexp {^value is a (.*?) with a refcount} \
        [::tcl::unsupported::representation $value] -> type]} {
    return $type
  } else {
    return "type2: [det_type2 $value]" 
  }
}    
