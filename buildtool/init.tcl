# project config versions:
# 1. original, with _orig* and .base directories directly in main directory.
# 2. using .bld subdir, with subdirs .base and _orig*
# 3. using ~/.config/buildtool/env.tcl and prjtype specific settings.

require libdatetime dt

use libmacro

# [2016-08-16 20:09] In general, procs here should not be dependent on configfile/var existence. Always check, and do as much as possible without config settings.

# TODO: add type parameter, and only write stuff to config for certain types, eg lr_include_dir.
task init {Initialise project/script
  Also update config to latest version.  
} {{update "Update project/script from old config version to latest"}
  {version "Show config version"}
  {info "Show project info"}
  {contents "Show config contents alongside info"}
} {
  # opt dict now available.
  if {[:version $opt]} {
    puts "Current config version: [current_version]"
    return
  }
  if {[:info $opt]} {
    show_project_info $opt
    return
  }
  if {[latest_version] == [current_version]} {
    if {[check_build_dir] == 0} {
      puts "Version already set to latest: [current_version]"  
    } else {
      puts "Fixed some issues in latest version: [current_version]"
    }
    # [2016-10-15 19:28] Check if config files exist. If not, create them:
    if {![file exists [config_env_tcl_name]]} {
      make_config_env_tcl    
    }
    return
  }
  if {[current_version] == 0} {
    puts "Ok, initialise from scratch"
    init_from_scratch
    return
  }
  # here current >=1 and != latest
  if {![:update $opt]} {
    puts "Already initialised, use init -update to set to latest version"
    return
  }
  init_update [current_version] [latest_version]
  
  # puts "Error: unknown versions: [current_version] <-> [latest_version]"
}

proc latest_version {} {
  return 3
}

# config/vars independent
proc current_version {} {
  # first try to read it from .bld/.configversion
  set version_filename [version_file]
  if {[file exists $version_filename]} {
    set version [string trim [read_file $version_filename]]
  } else {
    # if not found, it's 1 (per definition) or 0, if no .base and _orig dirs found.
    if {[file exists .base] || ([glob -nocomplain _orig*] != {})} {
      set version 1
    } else {
      set version 0
    }
  }
  return $version
}

# [2016-07-30 12:17] maybe change, if tool name changes, so one place to change then.
# [2016-08-16 20:17] independent of configs/vars.
proc config_dir {} {
  return ".bld"
}

# [2016-08-16 20:17] config/var independent
proc config_tcl_name {} {
  file join [config_dir] "config.tcl"
}

# [2016-08-16 20:20] independent of config/vars, but returns empty string when
# buildtool_env not set.
proc config_env_tcl_name {} {
  global buildtool_env
  if {[info exists buildtool_env]} {
    file join [config_dir] "config-${buildtool_env}.tcl"    
  } else {
    puts "WARN: buildtool_env var does not exist, should run bld init"
    return ""
  }
}

# [2016-08-16 20:21] config/vars independent.
proc version_file {} {
  file join [config_dir] .configversion
}

# TODO: also update .gitignore with .base and _orig paths, but should be in hook for git package.
# [2016-08-16 20:13] Independent from config/vars
proc init_from_scratch {} {
  set cfgdir [config_dir]
  file mkdir $cfgdir
  make_config_tcl
  set_config_version [latest_version]
}

# [2016-08-16 20:13] Independent from config/vars
proc init_update {from to} {
  while {$from < $to} {
    set from [init_update_from_$from]
  }
  set_config_version $to
}

# [2016-08-16 20:13] Independent from config/vars
proc init_update_from_1 {} {
  init_from_scratch
  if {[file exists ".base"]} {
    file rename ".base" [file join [config_dir] ".base"]
  }
  foreach orig [glob -nocomplain -type d _orig*] {
    file rename $orig [file join [config_dir] $orig]
  }
  return 2
}

# [2016-08-16 20:14] config/vars independent.
proc init_update_from_2 {} {
  set config_name [config_tcl_name]
  set text [read_file $config_name]
  set config_v3 [get_config_v3]
  set text "$text\n$config_v3"
  write_file $config_name [format_code $text]
  make_config_env_tcl
  return 3
}

# set to v3, source env things
# [2016-08-16 20:15] config/vars independent.
proc make_config_tcl {} {
  set config_name [config_tcl_name]
  if {[file exists $config_name]} {
    puts "Config file already exists: $config_name"
    # TODO: maybe? check if config is complete?
    return
  }
  set now [dt/now]
  set config_v3 [get_config_v3]
  write_file $config_name [format_code [syntax_quote {# config.tcl generated ~@$now
    set repo_dir [file normalize "../repo"]
    set repo_lib_dir [file join $repo_dir libs]
    ~@$config_v3
  }]]
  make_config_env_tcl
}

# [2016-08-16 20:26] should be config/vars independent now.
# [2016-08-16 20:31] did some tests with empty env, works now.
proc make_config_env_tcl {} {
  set filename [config_env_tcl_name]
  if {$filename != ""} {
    if {[file exists $filename]} {
      puts "File already exists: $filename"
      return
    }
    write_file $filename [format_code {set testruns_dir {<FILL IN>}
      set lr_include_dir [det_lr_include_dir]
    }]
  } else {
    puts "Name of config_env_tcl_name (like .bld/config-<pcname>.tcl) is not set"
    puts "Run bld init -update"
    return
  }
}

# [2016-08-16 20:23] config/vars independent.
proc get_config_v3 {} {
  return [format_code {set config_env_tcl_name [config_env_tcl_name]
    if {($config_env_tcl_name != "") && [file exists $config_env_tcl_name]} {
      source $config_env_tcl_name
    }
  }]
}

# [2016-08-16 20:22] config/vars independent.
proc set_config_version {version} {
  write_file [version_file] $version
}

# for now here, should be in package vugen or something.
# return the first of a list of loadrunner include dirs that exists
# if none exists, return empty string.
# [2016-07-24 18:54] this one should be set in a project/repo config task.
# [2016-11-15 13:01:00] Look for HP/LoadRunner/Include dir in all program files dirs on all drives.
proc det_lr_include_dir {} {
  global lr_include_dir
  if {[catch {set lr_include_dir}]} {
    # not already set, continue.
    set dirs {{C:\Program Files (x86)\HP\Virtual User Generator\include}
	  {d:\HPPC\include}
    }
	lappend dirs {*}[find_loadrunner_dirs]  
	# breakpoint
    foreach dir $dirs {
      if {[file exists $dir]} {
        return $dir
      }
    }
	log warn "No LR include dir found, return empty string."
    return ""
  } else {
    # already set, leave unchanged
	if {[file exists $lr_include_dir]} {
		return $lr_include_dir
	} else {
		error "lr_include_dir not found: $lr_include_dir. Check [buildtool_env_tcl_name]"
	}
  }
}

# Look for loadrunner in both 'Program Files (x86)' and 'Program Files' on all drives.
# [2016-11-15 13:25:34] some drives too slow now. For now hardcoded to only check c: and d:
proc find_loadrunner_dirs {} {
  set res [list]
  log debug "Determining volumes"
  # set volumes [file volumes]
  # [2016-12-03 21:03] no network drives for now.
  # TODO: check with eg NET USE which drives are network drives. Could add to system
  # specific config file.
  set volumes {c:/ d:/}
  foreach volume $volumes {
    log debug "Check volume: $volume"
    foreach progdir [glob -nocomplain -directory $volume -type d "Prog*"] {
      set inc_dir [file join $progdir HP LoadRunner include]
      if {[file exists $inc_dir]} {
        lappend res $inc_dir
      }
    }
  }
  log debug "Checked all volumes"
  return $res
}

# this one should be independent of existing config files or vars.
task init_env {initialise environment
  by creating a ~/.config/buildtool/env.tcl file,
  with buildtool_env var default set to hostname
} {
  set filename [buildtool_env_tcl_name]
  if {[file exists $filename]} {
    puts "Already exists: $filename"
    return
  }
  file mkdir [file dirname $filename]
  set hostname [det_hostname];  # in ndv lib, so not dependent on config files/vars.
  write_file $filename [syntax_quote {set buildtool_env ~$hostname}]
  puts "Wrote env config file: $filename"
}

# this one completely independent of settings and vars.
proc buildtool_env_tcl_name {} {
  file normalize [file join ~ .config buildtool env.tcl]
}

# check if all items in build-dir are ok (and return 0), or fix if not and return 1
proc check_build_dir {} {
  set res 0
  if {![file exists [config_tcl_name]]} {
    make_config_tcl
    set res 1
  }
  if {![file exists [version_file]]} {
    log warn "Version file does not exist, do bld init: [version_file]"
    set res 1
  }
  if {![file exists [config_env_tcl_name]]} {
    log warn "Config env file does not exist: [config_env_tcl_name]"
    log warn "Run bld init"
    set res 1
  }
  return $res
}

# show project information: location/contents of config files, prjtype
proc show_project_info {opt} {
  puts "Current config version: [current_version]"
  foreach proc_name {buildtool_env_tcl_name config_tcl_name config_env_tcl_name} {
    show_config_info $proc_name $opt
  }
  source [config_tcl_name]
  puts "Project type: $prjtype"
}

proc show_config_info {proc_name opt} {
  set filename [$proc_name]
  if {[file exists $filename]} {
    puts "$proc_name: $filename \[Ok\]"
    if {[:contents $opt]} {
      show_contents $filename
    }
  } else {
    puts "$proc_name: $filename - DOES NOT EXIST"
  }
}

proc show_contents {filename} {
  set text [read_file $filename]
  puts "=="
  puts $text
  puts "======="
}
