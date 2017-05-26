# Vugen version of select files, overwrite some procs.

proc get_repo_libs {} {
  global repo_lib_dir
  glob -nocomplain -tails -directory $repo_lib_dir -type f *
}

# Override generic version to include action option.
proc get_filenames {opt} {
  if {[:action $opt]} {
    set filenames [get_action_files]
  } elseif {[:all $opt]} {
    set filenames [get_pattern_files *]
  } elseif {[:pat $opt] != ""} {
    set filenames [get_pattern_files [:pat $opt]]
  } elseif {[:allrec $opt] != ""} {
    #error "XXNot implemented yet: allrec"
    set filenames [get_pattern_files_rec . *]
  } elseif {[:patrec $opt] != ""} {
    #error "XXNot implemented yet: patrec"
    set filenames [get_pattern_files_rec . [:patrec $opt]]
  } else {
    set filenames [get_source_files]
  }
  return $filenames
}

# return sorted list of all (.c/.h) source files in project directory.
# so no config files etc.
# [2016-07-17 09:12] filter_ignore_files was always called in combination with this one,
# so make it standard.
# This one overrides generic version.
proc get_source_files {} {
  set lst [concat [glob -nocomplain -tails -directory . -type f "*.c"] \
               [glob -nocomplain -tails -directory . -type f "*.h"]]
  lsort [filter_ignore_files $lst]
}

# delete combined_* files from list.
# maybe later use FP filter command
# this one overrides generic version.
proc filter_ignore_files {source_files} {
  set res {}
  foreach src $source_files {
    if {[regexp {^combined_} $src]} {
      # ignore
    } elseif {$src == "pre_cci.c"} {
      # ignore
    } else {
      lappend res $src
    }
  }
  return $res
}

proc det_includes_files {source_files} {
  set res {}
  foreach source_file $source_files {
    lappend res {*}[det_includes_file $source_file]
  }
  lsort -unique $res
}

proc det_includes_file {source_file} {
  set res {}
  set f [open $source_file r]
  while {[gets $f line] >= 0} {
    if {[regexp {^#include "(.+)"} $line z include]} {
      # puts "FOUND include stmt: $include, line=$line"
      lappend res $include
    }
  }
  close $f
  return $res
}

proc in_lr_include {srcfile} {
  global lr_include_dir
  set res [file exists [file join $lr_include_dir $srcfile]]
  log debug "in_lr_include: $srcfile: $res (lr_include_dir: $lr_include_dir)"
  return $res
}

# get filename for script
# spec can be: prm, usr
proc script_filename {spec} {
  set script_ext {prm usr}
  if {[lsearch -exact $script_ext $spec] >= 0} {
    return "[file tail [file normalize .]].$spec"
  }
  error "Unknown spec: $spec"
}

# return list of all action files in script dir.
proc get_action_files {} {
  # set usr_file "[file tail [file normalize .]].usr"
  set usr_file [script_filename usr]
  set ini [ini/read $usr_file]
  set lines [ini/lines $ini Actions]
  set res {}
  foreach line $lines {
    set filename [:1 [split $line "="]]
    if {![regexp {^vuser_} $filename]} {
      assert {![regexp __TEMP__ $filename]}
      lappend res $filename
    }
  }
  # log debug "action files: $res"
  # breakpoint
  return $res
}

# return list of all project files, ie. all files which will be uploaded to ALM/PC
# use ScriptUploadMetadata.xml and check filters, 2 or 4.
#    <FileEntry Name="default.usp" Filter="4" />
#    <FileEntry Name="globals.h" Filter="2" />
proc get_project_files {} {
  set lines [split [read_file ScriptUploadMetadata.xml] "\n"]
  set res [list]
  foreach line $lines {
    if {[regexp {<FileEntry Name="(.+)" Filter="(2|4)"} $line z name]} {
      lappend res $name
    }
  }
  return $res
}

