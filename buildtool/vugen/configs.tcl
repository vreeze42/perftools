task check_configs {Check .config files
  Check if settings in config files occur more than once.
} {
  # eerst per config kijken of er dubbele settings in voorkomen, regelnummers erbij noemen.
  foreach configfile [get_configs .] {
    read_check_configfile $configfile
  }
}

proc get_configs {dir} {
  lsort [glob -nocomplain -directory $dir -type f "*.config"]
}

proc read_check_configfile {configfile} {
  set linenr 0
  set f [open $configfile r]
  set dct [dict create]
  while {[gets $f line] >= 0} {
    incr linenr
    if {[regexp {^#} $line]} {
      # comment, continue
      continue
    }
    if {[regexp {^([^=]+)=(.*)$} $line z nm val]} {
      set nm [string trim $nm]
      set val [string trim $val]
      if {[array get params $nm] != {}} {
        puts_warn $configfile $linenr "Redef of param: old: $params($nm), new:$linenr-$val"
      } else {
        set params($nm) "$linenr-$val"
        dict set dct $nm $val
      }
    }
  }
  close $f
  return $dct
}

task show_configs {Show .config files in HTML table
  Create configs.html which shows all settings in all config files.
} {
  puts "Show configs"
  set f [open configs.html w]

  set hh [ndv::CHtmlHelper::new]
  $hh set_channel $f
  $hh write_header "Configs" 0
  $hh table_start

  set configs [get_configs .]
  set keys [dict create]

  foreach configfile $configs {
    set dct [read_check_configfile $configfile]
    dict set all $configfile $dct
    set keys [dict merge $keys $dct]
  }

  puts [join $configs "\t"]
  $hh table_row_start
  $hh table_data "Config" 1
  foreach config $configs {
    $hh table_data [file tail $config] 1
  }
  $hh table_row_end
  foreach key [lsort [dict keys $keys]] {
    $hh table_row_start
    puts -nonewline $key
    $hh table_data $key 1
    foreach config $configs {
      set dct [dict get $all $config]
      if {[dict exists $dct $key]} {
        puts -nonewline "\t[dict get $dct $key]"
        $hh table_data [fix_width [dict get $dct $key] 15]
      } else {
        puts -nonewline "\t<none>"
        $hh table_data "-"
      }
    }
    puts ""
    $hh table_row_end
  }
  $hh table_end
  $hh write_footer
  
  close $f
}

# put <br/> in long string for putting in html table.
proc fix_width {str width} {
  if {[string length $str] > $width} {
    return "[string range $str 0 $width-1]<br/>[fix_width [string range $str 15 end] $width]"
  } else {
    return $str
  }
}
