# add file to #include list in globals.h
proc globals_add_file_include {filename} {
  # only include .c and .h files
  set ext [file extension $filename]
  if {($ext != ".c") && ($ext != ".h")} {
    return
  }
  set fn "globals.h"
  set fi [open $fn r]
  set fo [open_temp_w $fn]
  set in_includes 0
  set found 0
  while {[gets $fi line] >= 0} {
    if {$in_includes} {
      if {[regexp {\#include \"(.+)\"} $line z include]} {
        if {$include == $filename} {
          set found 1
        }
      } elseif {[string trim $line] == ""} {
        # ok, continue
      } else {
        # not in includes anymore, so add new one if needed
        if {!$found} {
          puts $fo "#include \"$filename\""
        }
        set in_includes 0
      }
    } else {
      if {[regexp {\#include} $line]} {
        # first line should always be lrun.h, so don't check on this one.
        set in_includes 1
      }
    }
    puts $fo $line
  }
  close $fo
  close $fi
  commit_file $fn
}

# //--------------------------------------------------------------------
# // Global Variables
proc globals_add_var {name datatype} {
  set text [read_file globals.h]
  if {$datatype == "int"} {
    set line "int $name;"  
  } elseif {$datatype == "str"} {
    set line "char *$name;"
  } else {
    error "Unknown datatype: $datatype (name=$name)"
  }
  set lines [split $text "\n"]
  if {[lsearch -exact $lines $line] < 0} {
    # new line
    set ndx [lsearch -exact $lines "// Global Variables"]
    # search first empty line after header, add line here.
    set ndx2 [lsearch -start $ndx -regexp $lines {^\s*$}]
    if {$ndx2 >= 0} {
      set ndx $ndx2
    } else {
      # no empty line, add at the end
      set ndx end
    }

    set lines [linsert $lines $ndx $line]
    set fo [open_temp_w globals.h]
    puts -nonewline $fo [join $lines "\n"]
    close $fo
    commit_file globals.h
  }
}


