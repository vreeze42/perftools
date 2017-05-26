#!/usr/bin/env tclsh

# Build tool, mainly for VuGen scripts and libraries
# [2016-08-10 22:53] Starting to be useful for other kinds of projects (ahk, tcl, clj)

package require ndv

set_log_global info
# set_log_global debug

ndv::source_once task.tcl prjgroup.tcl prjtype.tcl \
    lib/misc.tcl init.tcl

require libinifile ini
use liblist

proc trace_callback {nm idx action} {
  upvar $nm var
  log debug "Trace callback: $nm/$idx/$action: new value: $var"
  # log debug "Trace callback: level: [info level]" ; # level is always 1. So not on the stack where the change occured.
}
    
# debug - add trace for lr_include_dir
# trace add variable lr_include_dir write trace_callback
    
proc main {argv} {
  global log
  try_eval {
    if {[lsearch -exact $argv "-debug"] >= 0} {
      $log set_log_level debug
      lremove argv -debug
    }
    set dir [file normalize .]
    set tname [task_name [lindex $argv 0]]
    if {$tname == ""} {set tname help}
    set trest [lrange $argv 1 end]
    handle_init_env $tname $trest
    # here the env config file is available: ~/.config/buildtool/env.tcl 
    if {[in_bld_subdir? $dir]} {
      puts "In buildtool subdir, exiting: $dir"
      return
    }
    if {[is_prjgroup_dir $dir]} {
      handle_prjgroup_dir $dir $tname $trest
    } else {
      handle_script_dir $dir $tname $trest
    }
  } {
    ndv::stacktrace_info $errorResult $errorCode $errorInfo
  }
}

proc handle_init_env {tname trest} {
  if {![file exists [buildtool_env_tcl_name]]} {
    if {$tname == "init_env"} {
      task_init_env 
    } else {
      puts "File does not exist: [buildtool_env_tcl_name]"
      puts "Initialise env with init-env task"
    }
    exit
  }
}

# [2016-08-10 21:11] TODO: later call this one 'handle_project_dir'. Not now, still confusing name.
# @pre - [buildtool_env_tcl_name] exists
proc handle_script_dir {dir tname trest} {
  global as_prjgroup buildtool_env
  assert {[file exists [buildtool_env_tcl_name]]}
  uplevel #0 {source [buildtool_env_tcl_name]}
  # [2016-10-01 21:38] first check if task = init, to fix project errors.
  if {$tname == "init"} {
    task_$tname {*}$trest
  } elseif {[current_version] == [latest_version]} {
    if {![file exists [config_tcl_name]]} {
      # [2016-10-01 21:35] maybe .bld/config.tcl is not under version control.
      log warn "File not found: [config_tcl_name]"
      log warn "Run bld init -update"
      return
    }
    # ok, normal situation.
    assert {[file exists [config_tcl_name]]}
    #puts "before source_dir: generic"
    #puts "buildtool_dir:"
    #puts [buildtool_dir]
    source_dir [file join [buildtool_dir] generic]
    uplevel #0 {source [config_tcl_name]}
    source_prjtype;             # load prjtype dependent tasks
    if {[info procs task_$tname] == {}} {
      puts "Unknown task: $tname"
      return
    }
    set as_prjgroup 0
    set_origdir ; # to use by all subsequent tasks.
    task_$tname {*}$trest
    mark_backup $tname $trest
    check_temp_files
  } else {
    puts "Update config version with init -update"
    exit
  }
}


# source all tcl files in bldprjlib iff defined.
proc source_prjtype {} {
  global bldprjlib
  if {![info exists bldprjlib]} {
    log info "No prjtype specific build lib"
    return
  }
  source_dir $bldprjlib
}

# source all tcl files in dir
proc source_dir {dir} {
  foreach libfile [lsort [glob -nocomplain -directory $dir *.tcl]] {
    # ndv::source_once?
    # uplevel #0 [list source $libfile]
    # puts "dynamic source: $libfile"
    uplevel #0 [list ndv::source_once $libfile]
  }
}

proc buildtool_dir {} {
  global argv0
  # set res [file dirname [file normalize [info script]]]
  # [2016-08-10 22:31] info script does not work now, because this proc is called from
  # .bld/config.tcl, and returns .bld dir.
  set res [file dirname [file normalize [file_follow_links $argv0]]]
  log debug "buildtool_dir: $res"
  return $res
}

proc file_follow_links {path} {
  while {[file type $path] == "link"} {
    set path [file link $path]
  }
  return $path
}

# return true iff dir is .bld dir or subdir of this.
# independent from config/var.
proc in_bld_subdir? {dir} {
  foreach el [file split $dir] {
    if {$el == ".bld"} {
      return 1
    }
  }
  return 0
}

if {[this_is_main]} {
  main $argv  
} else {
  puts "not main"  
}

