# Both real LR params (like set with Ctrl-L) as vars/params set in code are handled here.
# There is an overlap with add_param type=param.

task check_lr_params {Check LR parameter settings
  For each parameter, check:
  * not set to sequential - should only be used for script testing.
  * first row != 1        - should only be used for script testing.
  * not set to continue-with-last.
} {
  foreach filename [glob -nocomplain *.prm] {
    check_lr_params_file $filename
  }
  check_lr_params_generic;      # check if .prm file exists and if so, done correctly
}

proc check_lr_params_file {filename} {
  set f [open $filename r]
  set param "<none>"
  while {[gets $f line] >= 0} {
    if {[regexp {^\[parameter:(.+)\]$} $line z pm]} {
      set param $pm
    } elseif {[regexp {SelectNextRow="([^""]+)"} $line z sel]} {
      if {$sel == "Sequential"} {
        puts "WARNING: $param: $line"
      }
    } elseif {[regexp {StartRow="(\d+)"} $line z st]} {
      if {$st != 1} {
        puts "WARNING: $param: $line"
      }
    } elseif {[regexp {OutOfRangePolicy="(.+)"} $line z st]} {
      # OutOfRangePolicy="ContinueWithLast"
      # [2016-12-20 20:48] only if unique is set (not sequential or random) this value is used. For now, no warning.
      if {$st == "ContinueWithLast"} {
        # puts "WARNING: $param: $line"
      }
    } elseif {[regexp {Table="(.+)"} $line z dat_filename]} {
      check_param_dat_file $dat_filename
    }
  }
  close $f
}

# [2016-12-18 15:46] Check if param.dat file ends with a newline. If it doesn't, ALM/Controller refuses to execute script, without stating cause of error, causing wasted effort in chasing the 'bug'.
proc check_param_dat_file {dat_filename} {
  set text [read_file $dat_filename]
  if {![regexp {\n$} $text]} {
    puts "FATAL: $dat_filename does NOT end in newline! (ALM will fail to run!)"
  }
}

proc check_lr_params_generic {} {
  foreach prm_file [glob -nocomplain *.prm] {
    if {[script_filename prm] != $prm_file} {
      # if {[file rootname $prm_file] != [file tail [pwd]]} {}
      puts "WARNING: parameter file has wrong name: $prm_file"
    } else {
      # puts "Ok: $prm_file"
      # check value in .usr file
      set usr_file [script_filename usr]
      set ini [ini/read $usr_file]
      if {[ini/get_param $ini General ParameterFile] != $prm_file} {
        puts "WARNING: $prm_file not set correctly in .usr file"
      } else {
        # puts "Ok: $usr_file"
      }
      # check occurs in metadata file
      if {![metadata_includes? $prm_file]} {
        puts "WARNING: $prm_file not included in ScriptUploadMetadata.xml"
      } else {
        # puts "Ok: metadata"
      }
    }
  }
}

task add_param {Add var/param to script
  Syntax: add_param <name> int|str var|param [<default>]
  Adds a config-parameter (not a LR-param) to the project, in the following locations:
  globals.h - iff it should be a var
  vuser_init.c - to set var or param
  *.config - to add var/param
} {
  lassign $args name datatype varparam default_val
  if {$default_val == ""} {
    if {$datatype == "int"} {
      set default_val 0
    } elseif {$datatype == "str"} {
      set default_val ""
    } else {
      puts "Unknown datatype: $datatype (args=$args)"
      task_help add_param
      return
    }
  }
  if {$varparam == "var"} {
    globals_add_var $name $datatype
  }
  add_param_configs $name $default_val
  vuser_init_add_param $name $datatype $varparam $default_val
}

proc add_param_configs {name default_val} {
  #set line "$name=$default_val"
  set line "$name = $default_val"
  foreach configname [glob -nocomplain *.config] {
    set text [read_file $configname]
    if {[lsearch -regexp [split $text "\n"] "^\\s*$name\\s*="] < 0} {
      set fo [open [tempname $configname] w]
      puts $fo $text
      puts $fo $line
      close $fo
      commit_file $configname
    }
  }
}

task param_domain {set domain param and replace within requests in action files
  Syntax: param_domain <domain>
} {
  lassign $args domain
  task_regsub -action -do $domain "{domain}"
  task_add_param domain str param $domain
}

# add iteration parameter to the script, iff it does not exist yet (idempotent)
# [2016-12-01 12:50:01] also set ref to .prm file in .usr file and add to ScriptUploadMetadata.xml (was already implemented)
# [2016-12-02 11:38] Bugfix - result of ini_set_param not used.
proc add_param_iteration {} {
  # .usr: set ParameterFile=<script>.prm
  set prm_file [script_filename prm]
  set usr_file [script_filename usr]
  set ini [ini/read $usr_file]
  set ini [ini/set_param $ini General ParameterFile $prm_file]
  ini/write [tempname $usr_file] $ini
  commit_file $usr_file
  
  # add param in .prm file
  set ini [ini/read $prm_file 0]
  set header "parameter:iteration"
  if {[count [ini/lines $ini $header]] == 0} {
    set lines "Format=\"%d\"
OriginalValue=\"\"
Type=\"CurrentIteration\"
ParamName=\"iteration\""
    set ini [ini/set_lines $ini $header $lines] 
  }
  ini/write [tempname $prm_file] $ini
  commit_file $prm_file
  
  add_file_metadata $prm_file
}

