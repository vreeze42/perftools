# procs for reading and writing (similiar to windows) .ini files, as used in Loadrunner.
namespace eval ::libinifile {
  # namespace export read write add set_lines add_no_dups headers lines exists set_param get_param
  namespace export read create write add set_lines add_no_dups headers lines exists set_param get_param

# return a list, where each item is a dict: header and lines. Lines is a list.
proc read {filename {fail_on_file_not_found 1}} {
  set ini [list]
  set header ""
  set lines [list]
  if {[file exists $filename]} {
    set f [open $filename r]
    while {[gets $f line] >= 0} {
      if {[regexp {^\[(.+)\]$} $line z h]} {
        if {$header != ""} {
          lappend ini [dict create header $header lines $lines]
        }
        set header $h
        set lines [list]
      } else {
        lappend lines $line
      }
    }
    if {$header != ""} {
      lappend ini [dict create header $header lines $lines]
    }
    close $f
  } else {
    if {$fail_on_file_not_found} {
      error "File not found: $filename"
    } else {
      # nothing, return empty ini
    }
  }
  return $ini
}

# create an empty ini 'object'
proc create {} {
  return [list]
}

# also make backup
# [2016-11-26 15:45] This probably won't work outside of buildtool, open_temp_w not available; commit_file neither.
# [2016-11-26 16:00] caller should provide tempname and call commit, outside of scope of this library.
proc write {filename ini {translation crlf}} {
  # puts "ini/write called: $filename"
  # set f [open [tempname $filename] w]
  set f [open $filename w]
  fconfigure $f -translation $translation
  # set f [open_temp_w $filename]
  
  foreach d $ini {
    puts $f "\[[:header $d]\]"
    # don't put empty lines
    foreach line [:lines $d] {
      if {$line != ""} {
        puts $f $line
      }
    }
    # puts $f [join [:lines $d] "\n"]
  }
  close $f
  # commit_file $filename
}

# add header/line combination to ini
# add to existing header if it exists, otherwise create new header at the end.
proc add {ini header line} {
  set res {}
  set found 0
  foreach d $ini {
    if {[:header $d] == $header} {
      dict lappend d lines $line
      set found 1
    }
    lappend res $d
  }
  if {!$found} {
    lappend res [dict create header $header lines [list $line]]
  }
  return $res
}

# set all lines under a heading, eg for sorting
# return updated ini
proc set_lines {ini header lines} {
  set res {}
  set found 0
  foreach grp $ini {
    if {[:header $grp] == $header} {
      lappend res [dict create header $header lines $lines]
      set found 1
    } else {
      lappend res $grp 
    }
  }
  if {!$found} {
    lappend res [dict create header $header lines $lines]
  }
  return $res
}

# add line to ini, but only if it does not already exist
proc add_no_dups {ini header line} {
  set lines [lines $ini $header]
  if {[lsearch -exact $lines $line] < 0} {
    set ini [add $ini $header $line]
  }
  return $ini
}

proc headers {ini} {
  # find_proc has trouble with proc names starting with :
  make_dict_accessor get_header header
  map get_header $ini
}

proc lines {ini header} {
  foreach d $ini {
    if {[:header $d] == $header} {
      return [:lines $d]
    }
  }
  return [list]
}

# return 1 iff line exists under header
proc exists {ini header line} {
  if {[lsearch -exact [lines $ini $header] $line] >= 0} {
    return 1
  } else {
    return 0
  }
}

# set value for name under header, create iff new.
# return new ini 'object'
proc set_param {ini header name value} {
  set lines [lines $ini $header]
  set ndx [lsearch -regexp $lines "^$name\\s*="]
  if {$ndx >= 0} {
    set lines [lreplace $lines $ndx $ndx "$name=$value"]
  } else {
    lappend lines "$name=$value"
  }
  set ini [set_lines $ini $header $lines]
  return $ini
}

proc get_param {ini header name {default "<none>"}} {
  set lines [lines $ini $header]
  set ndx [lsearch -regexp $lines "^$name\\s*="]
  if {$ndx >= 0} {
    set line [lindex $lines $ndx]
    regexp {^[^=]+=(.*)$} $line z value
    return [string trim $value]
  } else {
    return $default
  }
}

} ; # end-of-namespace

