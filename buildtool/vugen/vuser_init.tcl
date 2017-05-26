# //Filter out some production URLs
# add filter lines just after the comment (// Filter out), or just before return 0;
# replace all settings with info in domains.ini
# this proc also belongs to domains.tcl
proc vuser_init_update_domains {domains_ini} {
  # alle huidige ignore lines helemaal weg en vervangen door domains_ini, op alfabet.
  set replaced 0
  set fi [open vuser_init.c r]
  #set fo [open [tempname vuser_init.c] w]
  #fconfigure $fo -translation crlf
  set fo [open_temp_w vuser_init.c]
  while {[gets $fi line] >= 0} {
    if {[regexp {Filter out some production URLs} $line]} {
      puts $fo $line
      puts_ignore_domain_lines $fo $domains_ini
      set replaced 1
    } elseif {[regexp {return 0;} $line]} {
      if {!$replaced} {
        puts_ignore_domain_lines $fo $domains_ini
        set replaced 1
      }
      puts $fo $line
    } elseif {[regexp {web_add_auto_filter} $line]} {
      # ignore line
    } else {
      puts $fo $line
    }
  }
  close $fi
  close $fo
  commit_file vuser_init.c
}

# this proc also belongs to domains.tcl
proc puts_ignore_domain_lines {fo ini} {
  foreach line [lsort [ini/lines $ini ignore]] {
    if {$line != ""} {
      puts $fo "\tweb_add_auto_filter\(\"Action=Exclude\", \"HOSTSUFFIX=${line}\", LAST);"      
    }
  }
}


proc vuser_init_add_param {name datatype varparam default_val} {
  set text [read_file vuser_init.c]
  set line [vuser_init_param_line $name $datatype $varparam $default_val]
  set lines [split $text "\n"]
  if {[lsearch -regexp $lines "config_cmdline_get.+\\42$name\\42"] < 0} {
    set header_line "\t// Config parameters"
    set ndx [lsearch -exact $lines $header_line]
    set ndx_return_0 [lsearch -exact $lines "\treturn 0;"]
    if {$ndx < 0} {
      set ndx $ndx_return_0
      if {$ndx < 0} {
        error "return 0; not found in vuser_init.c"
      }
      set lines [linsert $lines $ndx $header_line]
      incr ndx ; # insert new param after the header.
    } else {
      # find first empty line after header, only when it already exists
      set ndx2 [lsearch -start $ndx -regexp $lines {^\s*$}]
      if {($ndx2 >= 0) && ($ndx2 < $ndx_return_0)} {
        # only change insert-index iff empty line found before return 0;
        set ndx $ndx2
      } else {
        # insert just before return 0
        set ndx $ndx_return_0
      }
    }
    set lines [linsert $lines $ndx $line]
    #set fo [open [tempname vuser_init.c] w]
    #fconfigure $fo -translation crlf
    set fo [open_temp_w vuser_init.c]
    puts -nonewline $fo [join $lines "\n"]
    close $fo
    commit_file vuser_init.c
  }
}

proc vuser_init_param_line {name datatype varparam default_val} {
  if {$varparam == "var"} {
    if {$datatype == "int"} {
      set line "\t$name = config_cmdline_get_int(config, \"$name\", $default_val);"
    } elseif {$datatype == "str"} {
      set line "\t$name = config_cmdline_get_string(config, \"${name}\", \"${default_val}\");"
    } else {
      error "Unknown datatype: $datatype (name=$name)"
    }
  } elseif {$varparam == "param"} {
    if {$datatype == "int"} {
      error "Combination not (yet) possible: $varparam/$datatype"
    } elseif {$datatype == "str"} {
      set line "\tlr_save_string(config_cmdline_get_string(config, \"${name}\", \"${default_val}\"), \"${name}\");"
    } else {
      error "Unknown datatype: $datatype (name=$name)"
    }
  } else {
    error "Unknown value for varparam: $varparam (name=$name)"
  }
  return $line
}

