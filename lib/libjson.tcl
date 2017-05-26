package provide ndv 0.1.1

# [2017-05-08 09:05] This one not available now on work laptop
catch {package require json::write}

namespace eval ::libjson {
  namespace export dict2json array2json

  proc dict2json {dct} {
    return $dct
  }

  # cannot determine if param is array or dict, so separate functions.
  # also do not know if items within the array are arrays or dicts, and if the
  # value of the dict elements are atoms, arrays or dicts.
  # assume here:
  # level 1 is array
  # level 2 is dict
  # level 3 is an atom.
  # this is similar to TiddlyWiki import/export.
  proc array2json {ar} {
    set ar2 [list]
    foreach el $ar {
      set d [dict create]
      dict for {k v} $el {
        dict set d $k [json::write str $v]
      }
      lappend ar2 [json::write object {*}$d]
    }
    json::write array {*}$ar2
  }
  
}


