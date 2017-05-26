# libcsv.tcl - read csv at ones, return as list of dicts
# header line must be present.
# separator default is a command, can be changed.
package require csv

proc csv2dictlist {filename {sep_char ","}} {
  set f [open $filename r]
  set header [csv::split [gets $f] $sep_char]
  set res {}
  while {![eof $f]} {
    set line [gets $f]
    if {[string trim $line] != ""} {
      lappend res [__make__dict $header $line $sep_char] 
    }
  }
  close $f
  return $res
}

# this should be a namespace_private proc
proc __make__dict {header line sep_char} {
  set vals [csv::split $line $sep_char]
  # should use map or zip here, FP.
  foreach h $header v $vals {
    dict set res $h $v 
  }
  return $res
}

