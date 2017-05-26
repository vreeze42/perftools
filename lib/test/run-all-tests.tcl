#! /home/nico/bin/tclsh

# [2016-11-03 21:02] onderstaande werkt blijkbaar niet vanuit gosleep.tcl
#! /usr/bin/env tclsh

# Run all test scripts in repo (may other repo's too?)

# Renamed to run-all-tests.tcl, so it will not call itself.

# To be sure, also the following:
#@test never

package require ndv

set_log_global info

proc main {argv} {
  global log
  set options {
    {roots.arg "auto" ": separated list of roots to check for test_*.tcl files (use auto for this library)"}
    {full "Run full testsuite, including long running tests"}
    {manual "Also run tests defined as manual/interactive"}
    {coe "Continue on error"}
    {nopopup "Don't show Tk popup when a test fails"}
    {debug "Set loglevel to debug"}
  }
  set usage ": [file tail [info script]] \[options]:"
  set opt [getoptions argv $options $usage]
  if {[:debug $opt]} {
    $log set_log_level debug
  }
  test_all $opt 
}

proc test_all {opt} {
  foreach root [split [:roots $opt] ":"] {
    if {$root == "auto"} {
      test_root $opt [file normalize [file join [info script] .. .. ..]]  
    } else {
      test_root $opt [file normalize $root]  
    }
  }
}

proc test_root {opt root} {
  log info "Running all tests in: $root"
  set lst [lsort [libio::glob_rec $root is_test]]
  set nfiles_with_errors 0
  set files_with_errors [list]
  set tclsh [info nameofexecutable]; # want sub-processes to use the same tclsh.
  foreach path $lst {
    log debug "Run tests in: $path"
    if {[should_test $path $opt]} {
      log debug "Running tests in: $path"
      set old_pwd [pwd]
      cd [file dirname $path]
      #set res [exec $tclsh $path]
      #log debug "res: $res"
      set res "<none>"
      set has_error 0
      set errCode "<none>"
      try_eval {
        set res [exec -ignorestderr $tclsh $path]
        # exec $tclsh $path  
      } {
        set has_error 1
        set errCode $errorCode
      }
      log debug "res: $res"
      if {[regexp {FAILED} $res]} {
        set has_error 1
      }
      if {$has_error} {
        log warn "Found error(s) in $path: $errCode"
        if {[:coe $opt]} {
          # continue-on-error
          incr nfiles_with_errors
          lappend files_with_errors $path
        } else {
          exit
        }
      }
      cd $old_pwd
    } else {
      log debug "-> Don't run tests"
    }
    # puts "============================="
  };                            # end-of-foreach file

  # for testing popup:
  # incr nfiles_with_errors
  # lappend files_with_errors a bc.def en nog een paar
  
  if {$nfiles_with_errors > 0} {
    set warn_msg "WARNING: Tcl test suite: $nfiles_with_errors file(s) with errors found!:\n[join $files_with_errors "\n"]"
    log warn $warn_msg
    if {![:nopopup $opt]} {
      popup_warning $warn_msg
    }
  } else {
    log info "Everything ok!"
  }
  exit;                         # to quit from Tk.
}

proc is_test {path} {
  if {[file type $path] == "directory"} {
    return 1;                   # recurse all sub directories
  } else {
    if {[regexp -- {^test-.+\.tcl$} [file tail $path]]} {
      return 1
    } else {
      # possibly other files as well.
      return 0
    }
  }
}

# TODO: if spec in file is set in options, return true.
proc should_test {path opt} {
  set tspec [test_spec $path]
  if {$tspec == "full"} {
    if {![:full $opt]} {
      return 0
    } else {
      return 1
    }
  } elseif {$tspec == "manual"} {
    if {[:manual $opt]} {
      return 1
    } else {
      return 0
    }
  } elseif {$tspec == "never"} {
    return 0
  } else {
    return 1  
  }
}

proc test_spec {path} {
  set text [read_file $path]
  if {[regexp big $path]} {
    # breakpoint
  }
  if {[regexp {\#@test (\S+)} $text z spec]} {
    return $spec
  } else {
    return "always"
  }
}

proc popup_warning_old {text} {
  package require Tk
  wm withdraw .
  set answer [::tk::MessageBox -message "Warning!" \
                  -icon info -type ok \
                  -detail $text]
}

# start a new process which shows warnings, so this one can stop, and gosleep can continue.
proc popup_warning_old {text} {
  # TODO: find script binary (tclsh) of current process and reuse for this one.
  set popup [file normalize [file join [info script] .. .. popupmsg.tcl]]
  log info "popup: $popup"
  # [2016-11-03 21:31] TODO: met deze blijft gosleep nog steeds wachten totdat op ok geklikt is.
  # Opties:
  # * testen worden snel genoeg gedaan zodat je het ziet en op ok kunt klikken.
  # * testen duren te lang, monitor al uitgezet. Dan geen sleep, niet heel erg, moet toch weinig voorkomen.
  # * resultaten wegschrijven naar file. Bij volgende gosleep eerst de file tonen (kan heel snel). Maar nogal houtje/touwtje oplossing.
  # Eerst maar zo laten.
  exec -ignorestderr nohup $popup $text &
}

main $argv
