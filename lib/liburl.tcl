package provide ndv 0.1.1
package require json

namespace eval ::liburl {
  namespace export url-encode url-decode url->parts url->params url->domain url->path det_valuetype

# source: http://wiki.tcl.tk/14144
proc init-url-encode {} {
    variable map
    variable alphanumeric a-zA-Z0-9
    for {set i 0} {$i <= 256} {incr i} { 
        set c [format %c $i]
        if {![string match \[$alphanumeric\] $c]} {
            set map($c) %[format %.2x $i]
        }
    }
    # These are handled specially
    array set map { " " + \n %0d%0a }
}
init-url-encode

# source: http://wiki.tcl.tk/14144
proc url-encode {string} {
    variable map
    variable alphanumeric

    # The spec says: "non-alphanumeric characters are replaced by '%HH'"
    # 1 leave alphanumerics characters alone
    # 2 Convert every other character to an array lookup
    # 3 Escape constructs that are "special" to the tcl parser
    # 4 "subst" the result, doing all the array substitutions

    regsub -all \[^$alphanumeric\] $string {$map(&)} string
    # This quotes cases like $map([) or $map($) => $map(\[) ...
    regsub -all {[][{})\\]\)} $string {\\&} string
    return [subst -nocommand $string]
}

# source: http://wiki.tcl.tk/14144
proc url-decode str {
    # rewrite "+" back to space
    # protect \ from quoting another '\'
    set str [string map [list + { } "\\" "\\\\"] $str]

    # prepare to process all %-escapes
    regsub -all -- {%([A-Fa-f0-9][A-Fa-f0-9])} $str {\\u00\1} str

    # process \u unicode mapped chars
    return [subst -novar -nocommand $str]
}

# return dict with keys protocol, domain, port, path, params.
# params as in url->params
# return empty dict iff url cannot be parsed.
# {webpackPublicPath}styles/fonts/ri-icon.eot?
proc url->parts {url} {
  if {[regexp {^(.+?)://([^/:]+?)(:(\d+))?/([^?]*)(.*)$} $url z protocol domain z port path rest]} {
    if {$rest != ""} {
      set params [url->params $rest]; # could use $url as well.
    } else {
      set params [list]
    }
    vars_to_dict protocol domain port path params
  } else {
    # error "Could not parse URL: ${url}."
    #log warn "Could not parse URL: ${url}."
    #breakpoint
    dict create;                # empty dict
  }
}

# some syntactic sugar on url->parts:
proc url->domain {url} {
  :domain [url->parts $url]
}

proc url->path {url} {
  :path [url->parts $url]
}

# return list of url params
# each element is a dict: type,name,value,valuetype
# package uri can only provide full query string, so not really helpful here.
proc url->params {url} {
  if {[regexp {^[^?]*\?(.*)$} $url z params]} {
    set res [list]
    foreach pair [split $params "&"] {
      # lappend res [split $pair "="]
      lassign [split $pair "="] nm val
      lappend res [dict create type namevalue name $nm value $val \
                      valuetype [det_valuetype $val]]
    }
    return $res
  } else {
    return [list]
  }
}

# TODO: several date/time formats.
proc det_valuetype {val} {
  set base64_min_length 32;     # should test, maybe configurable.
  if {$val == ""} {
    return empty
  }
  if {[regexp {^\d+$} $val]} {
    # integer, check if it could be an epoch time.
    if {($val > "1400000000") && ($val < "3000000000")} {
      return "epochsec: [clock format $val]"
    }
    if {($val > "1400000000000") && ($val < "3000000000000")} {
      return "epochmsec: [clock format [string range $val 0 end-3]]"
    }
    return integer
  }
  foreach stringtype {boolean xdigit double} {
    if {[string is $stringtype $val]} {
      return $stringtype
    }
  }
  # still here, so look deeper.
  # json
  if {![catch {json::json2dict $val}]} {
    # [2016-12-06 21:47] previous things like t8.inf and {abc} are now not seen as
    # json, get parse error.
    # [2016-12-07 14:17:53] On Windows they are seen as json, maybe json lib version? So do same checks here.
    if {[regexp {^\{[A-Za-z0-9_]+\}$} $val]} {
      return lrparam
    }
    # [2016-12-07 14:19:09] Windows - t8.inf is also seen as json. So check surrounded by {}
    if {[regexp {^\{.+\}$} $val]} {
      return json  
    } else {
      # fall through to other checks.
    }
  }
  
  if {[regexp {^\{[A-Za-z0-9_]+\}$} $val]} {
    return lrparam
  }
  
  # base64 - val should have minimal length
  if {[string length $val] >= $base64_min_length} {
    if {[regexp {^[A-Za-z0-9+/]+$} $val]} {
      return base64
    }
  }

  # url and/or html encoded?

  return string;              # default, if nothing else.
}


}


