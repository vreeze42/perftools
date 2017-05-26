# TODO: [2016-09-29 08:58:32] check if the lib to get #include's files not already in repo: then warning or also get those libs.
# [2016-10-05 20:21] different way of determining different or updated files, because git always sets the current timestamp when updating a local file, not the time of the repo. This means local and base can change, while repo version stays the same. Possibly local and base version a bit different timestamp, both changed is the message. So could diff by content iff timestamps differ.
# TODO: [2016-10-05 20:21] maybe should not put .base in git after all. Then it will not change because of git, only when an explicit sync action is done. Local and repo should still be in git, does not matter if repo's are different or the same, moments of commit/push can differ. [2016-10-15 19:51] First get some experience on the content check, just made.

task libs {Overview of lib files, including status
  Show status of all library files, with respect to repository.
} {
  global as_prjgroup
  file mkdir [base_dir]
  set repo_libs [get_repo_libs]
  # puts "repo_libs: $repo_libs"
  set source_files [get_source_files]
  log debug "source_files: $source_files"
  set included_files [det_includes_files $source_files]
  log debug "included_files: $included_files"
  # TODO: determine files in selectfiles.tcl
  set all_files [lsort -unique [concat $source_files $included_files]]
  set diff_found 0
  # also check if all included files exist.
  log debug "all_files; $all_files"
  foreach srcfile $all_files {
    set st "ok"
    if {$srcfile == "globals.h"} {
      # ignore
    } elseif {[in_lr_include $srcfile]} {
      # default loadrunner include file, ignore.
    } elseif {[file extension $srcfile] == ".h"} {
      set st [show_status $srcfile]
    } elseif {[lsearch -exact $included_files $srcfile] >= 0} {
      # puts "in included: $srcfile"
      set st [show_status $srcfile]
    } elseif {[lsearch -exact $repo_libs $srcfile] >= 0} {
      # puts "in repo: $srcfile"
      set st [show_status $srcfile]
    } else {
      # puts "ignore: $srcfile"
    }
    if {$st != "ok"} {
      set diff_found 1
    }
  }
  if {$diff_found} {
    puts "\n*** FOUND DIFFERENCES ***"
  } else {
    if {!$as_prjgroup} {
      puts "\nEverything up to date"  
    }
  }
}

# @param libfile: relative, just file name.
proc show_status {libfile} {
  global repo_lib_dir as_prjgroup
  #set repofile [file join $repo_lib_dir $libfile]
  set repofile [repofile $libfile]
  set basefile [basefile $libfile]

  set lib_ex [file exists $libfile]
  set repo_ex [file exists $repofile]
  set base_ex [file exists $basefile]

  set status_ex "$lib_ex-$repo_ex-$base_ex"
  switch  $status_ex {
    1-1-1 {
      # [2016-10-15 19:41] Git sets time to current time for changed files, so check contents first. (Idea behind this git action is that files should be compiled, make will be confused otherwise)
      if {[contents_all_same? $libfile]} {
        set status "ok"
      } elseif {[contents_same? $libfile $repofile]} {
        set status "ok"
        log info "$libfile: lib == repo, copy to base"
        # [2016-11-26 14:19] file already exists, use -force
        file copy -force $libfile $basefile
      } elseif {[contents_same? $libfile $basefile]} {
        set status "repo-new"
      } elseif {[contents_same? $repofile $basefile]} {
        set status "local-new"
      } else {
        # all exist, but different, check mtimes
        set status [mtime_status $libfile]  
      }
    }
    1-1-0 {
      # no base, check mtimes as before
      if {[file mtime $libfile] < [file mtime $repofile]} {
        set status "repo-new - NO BASE!"
      } elseif {[file mtime $libfile] > [file mtime $repofile]} {
        set status "local-new - NO BASE!"
      } else {
        set status "ok"
        log info "$libfile: lib == repo, copy to base"
        file copy $libfile $basefile
      }
    }
    1-0-0 {
      # just local
      set status "only local"
    }

    default {
      log warn "$libfile - Unexpected situation: status_ex"
      set status "Unexpected: $status_ex (lib-repo-base)"
    }
  }
  # in project scope zo weinig mogelijk uitvoer naar stdout.
  if {$status != "ok" || !$as_prjgroup} {
    puts "\[$status\] $libfile"  
  }

  return $status
}

# @pre: alle 3 versions exist.
# @post: return 1 iff all 3 versions are the same by content (mtimes may differ)
# @note: could set all mtimes to the oldest iff all files are the same, but this would
#        be working against the git timestamps. Or maybe the newest, also strange.
proc contents_all_same? {libfile} {
  global repo_lib_dir
  set repofile [file join $repo_lib_dir $libfile]
  set basefile [file join [base_dir] $libfile]
  set contents [read_file $libfile]
  if {[read_file $basefile] == $contents} {
    if {[read_file $repofile] == $contents} {
      return 1
    }
  }
  return 0
}

# pre: both files exist
proc contents_same? {file1 file2} {
  = [read_file $file1] [read_file $file2]
}

# @pre all 3 versions of libfile exists: local, repo and base
# TODO: maybe allow for tiny difference between mtimes? Could be that a file system is
# less detailed?
proc mtime_status {libfile} {
  global repo_lib_dir
  set repofile [file join $repo_lib_dir $libfile]
  set basefile [file join [base_dir] $libfile]

  set lib_mtime [file mtime $libfile]
  set repo_mtime [file mtime $repofile]
  set base_mtime [file mtime $basefile]

  if {$lib_mtime == $repo_mtime} {
    set status "ok"
    if {$lib_mtime != $base_mtime} {
      log warn "base mtime != lib time, copy lib->base"
      file copy -force $libfile $basefile
    }
  } elseif {$lib_mtime < $repo_mtime} {
    # repo is newer
    if {$lib_mtime == $base_mtime} {
      set status "repo-new"
    } else {
      set status "both-new"
    }
  } else {
    # local is newer
    if {$repo_mtime == $base_mtime} {
      set status "local-new"
    } else {
      set status "both-new"
    }
  }
  return $status
}

task diff {Show differences between local version and repo version
  Syntax: diff <filename>
  Show date/time, size, and differences between local and repo version.
} {{min "Show minimal diff only"}
    v   "Use visual diff tool (eskil)"} {
  lassign $args libfile
  set st [show_status $libfile]
  puts "1:local: [file_info $libfile]"
  puts "2:base : [file_info [basefile $libfile]]"
  puts "3:repo : [file_info [repofile $libfile]]"
  if {[regexp {new} $st]} {
    if {[:min $opt]} {
      # log info "min: only show minimal diff"
    } else {
      if {[:v $opt]} {
        vdiff_files $libfile [repofile $libfile]
      } else {
        diff_files $libfile [repofile $libfile] [basefile $libfile]  
      }
    }
  } else {
    # no use to do diff
  }
}

# diff_files also called from regsub_file, with no base file.
proc diff_files {libfile repofile {basefile ""}} {
  set res "<none>"
  try_eval {
    set temp_out "__TEMP__OUT__"
    if {[file exists $basefile]} {
      # 3 way diff
      log debug "Exec diff3:"
      set res [exec -ignorestderr diff3 $libfile $basefile $repofile >$temp_out]
    } else {
      # just two way diff
      set res [exec -ignorestderr diff $libfile $repofile >$temp_out]  
    }
  } {
    # diff always seems to fail, possibly exit-code.
    log debug "diff(3) failed: $errorResult"
  }
  if {($res == "<none>") || ($res == "")} {
    set res [read_file $temp_out]
  } else {
    log info "Res != none: $res"
  }
  file delete $temp_out
  puts $res
}

proc vdiff_files {libfile repofile} {
  global VDIFF_EXE
  if {[catch {set VDIFF_EXE}]} {
    log warn "set VDIFF_EXE in system configfile: [buildtool_env_tcl_name]"
  } else {
    exec {*}$VDIFF_EXE $libfile $repofile &
  }
}

proc file_info {libfile} {
  if {[file exists $libfile]} {
    return "[clock format [file mtime $libfile] -format "%Y-%m-%d %H:%M:%S"], [file size $libfile] bytes"
  } else {
    return "-"
  }
}

proc repofile {libfile} {
  global repo_lib_dir
  file join $repo_lib_dir $libfile
}

proc basefile {libfile} {
  file join [base_dir] $libfile
}

# put lib file from working/script directory into repository
task put {Put a local lib file in the repo
  Syntax: put [-force] <lib>
  Only put file in repo if it is newer than repo version, unless -force is used.
} {
  global repo_lib_dir
  file mkdir [base_dir]
  # puts "args: $args"
  file mkdir $repo_lib_dir
  lassign [det_force $args] args force
  foreach libfile $args {
    if {[file exists $libfile]} {
      set repofile [file join $repo_lib_dir $libfile]
      if {[file exists $repofile]} {
        if {[file mtime $libfile] > [file mtime $repofile]} {
          # ok, newer file
          puts "Putting newer lib file to repo: $libfile"
          #file copy -force $libfile $repofile
          file_copy_base $libfile $repofile [basefile $libfile]
        } else {
          if {$force} {
            puts "\[FORCE\] Putting older lib file to repo: $libfile"
            # file copy -force $libfile $repofile
            file_copy_base $libfile $repofile [basefile $libfile]            
          } else {
            puts "Local file $libfile is not newer than repo file: do nothing"  
          }
        }
      } else {
        # ok, new lib file
        puts "Putting new lib file to repo: $libfile"
        file_copy_base $libfile $repofile [basefile $libfile]
        # file copy $libfile $repofile
      }
    } else {
      puts "Local lib file not found: $libfile"
    }
  }
}

# get lib file from repository into working/script directory
task get {Get a repo lib file to local dir
  Syntax: get [-force] <lib>
  Only get repo version if it is newer than the local version, unless -force is used.
} {
  global repo_lib_dir
  file mkdir [base_dir]
  # puts "args: $args"
  file mkdir $repo_lib_dir
  lassign [det_force $args] args force
  foreach libfile $args {
    set repofile [file join $repo_lib_dir $libfile]
    if {[file exists $repofile]} {
      if {[file exists $libfile]} {
        if {[file mtime $libfile] < [file mtime $repofile]} {
          # ok, newer file in repo
          puts "Getting newer repo file: $repofile"
          # file copy -force $repofile $libfile
          file_copy_base $repofile $libfile [basefile $libfile] 1
        } else {
          if {$force} {
            puts "\[FORCE\] Getting older repo file: $repofile"
            # file copy -force $repofile $libfile
            file_copy_base $repofile $libfile [basefile $libfile] 1
          } else {
            puts "Repo file $libfile is not newer than local file: do nothing"  
          }
        }
      } else {
        # ok, new repo file, not yet in local prj dir.
        puts "Getting new repo file: $repofile"
        # file copy $repofile $libfile
        file_copy_base $repofile $libfile [basefile $libfile] 1
        # also add to project
        add_file $libfile
      }
    } else {
      puts "Repo lib file not found: $repofile"
    } ; # if file exists repofile
  } ; # foreach libfile
}

# if backup==1, create a backup of the lib (in .orig) before getting new repo version.
proc file_copy_base {src target base {backup 0}} {
  if {$backup} {
    # breakpoint
    file copy -force $src [tempname $target]
    commit_file $target {mtime 1}
  } else {
    file copy -force $src $target    
  }
  file copy -force $src $base
}

proc det_force {lst} {
  set force 0
  set res {}
  foreach el $lst {
    if {$el == "-force"} {
      set force 1
    } else {
      lappend res $el
    }
  }
  list $res $force
}

proc base_dir {} {
  file join [config_dir] ".base"
}
