# Generic version of select files.

proc get_filenames {opt} {
  if {[:all $opt]} {
    set filenames [get_pattern_files *]
  } elseif {[:pat $opt] != ""} {
    set filenames [get_pattern_files [:pat $opt]]
  } elseif {[:allrec $opt]} {
    # error "Not implemented yet: allrec"
    set filenames [get_pattern_files_rec . *]
  } elseif {[:patrec $opt] != ""} {
    # error "Not implemented yet: patrec"
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
proc get_source_files {} {
  return [list]
}

proc filter_ignore_files {source_files} {
  return $source_files
}

proc get_action_files {} {
  return [list]
}

# return list of all project files, ie. all files which will be uploaded to ALM/PC
# use ScriptUploadMetadata.xml and check filters, 2 or 4.
#    <FileEntry Name="default.usp" Filter="4" />
#    <FileEntry Name="globals.h" Filter="2" />
proc get_project_files {} {
  return [list]
}

# get all non-hidden files in current directory
proc get_pattern_files {pat} {
  glob -nocomplain -type f $pat
}

# get all non-hidden files in current directory and below matching pattern.
# pat is only for files, all non-hidden subdirs will be searched.
proc get_pattern_files_rec {dir pat} {
  log debug "get_pattern_files_rec: $dir, $pat"
  set res [list]
  foreach subdir [glob -nocomplain -directory $dir -type d *] {
    lappend res {*}[get_pattern_files_rec $subdir $pat]
  }
  lappend res {*}[glob -nocomplain -directory $dir -type f $pat]
  log debug "get_pattern_files_rec: $dir, $pat -> $res"
  return $res
}

