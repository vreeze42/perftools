# procs for adding files and actions, and also for splitting an Action.c file according
# to transactions.

# these tasks should be idempotent: if they are called twice, the second time nothing should happen.

# args: 1 or more files to add.
task add_file {Add an extra file to prj
  Syntax: add_file <file> [<file> ..]
  Adds files (create if needed) to the extra files part of the project.
  Can you glob wildcards (if shell does not expand those)
} {
  foreach filename_pat $args {
    # -tails not needed if not using directory
    foreach filename [glob $filename_pat] {
      add_file $filename  
    }
  }  
}

# could be called by bld get, to automatically add files to project.
proc add_file {filename} {
  add_file_usr $filename
  add_file_metadata $filename
  globals_add_file_include $filename
}

proc add_file_usr {filename} {
  if {![file exists $filename]} {
    set f [open $filename w]
    close $f
  }
  # maybe use project dir instead of current dir?
  set usr_file "[file tail [file normalize .]].usr"
  set ini [ini/read $usr_file]
  set ini [ini/add_no_dups $ini ManuallyExtraFiles "$filename="]
  ini/write [tempname $usr_file] $ini
  commit_file $usr_file
}

# add file to ScriptUploadMetadata.xml, also crlf endings
# [2016-07-31 13:11] could be that this proc adds a newline once at the end of the file.
# calling a second time will not add another newline, so still idempotent.
# [2016-12-02 11:42] add optional second parameter for non-default metadata file, e.g. in saveas task.
proc add_file_metadata {filename {metadatafile ScriptUploadMetadata.xml}} {
  # puts "add_file_meta: $filename"
  # set meta ScriptUploadMetadata.xml
  set meta $metadatafile
  set fi [open $meta r]
  #set fo [open [tempname $meta] w]
  #fconfigure $fo -translation crlf
  set fo [open_temp_w $meta]
  set found 0
  while {[gets $fi line] >= 0} {
    if {[regexp {</GeneralFiles>} $line]} {
      if {!$found} {
        puts $fo "    <FileEntry Name=\"$filename\" Filter=\"2\" />"
      }
    } elseif {[regexp {<FileEntry Name=\"(.+)\" Filter} $line z fn]} {
      if {$filename == $fn} {
        set found 1
      }
    } else {
      # nothing
    }
    puts $fo $line
  }
  close $fo
  close $fi
  commit_file $meta
}

# check if filename occurs in ScriptUploadMetadata.xml
proc metadata_includes? {filename} {
  if {[string first $filename [read_file ScriptUploadMetadata.xml]] >= 0} {
    return 1
  } else {
    return 0
  }
}

# add actions. Similar to add_file, but add to action part of hierarchy.
task add_action {Add action to project
  Syntax: add_acion <action> [<action> ..]
  Add actions to project.
} {
  #breakpoint
  foreach action_pat $args {
    # -tails not needed if not using -directory
    set files [glob -nocomplain $action_pat]
    if {[count $files] > 0} {
      foreach filename $files {
        #breakpoint
        add_action $filename
      }
    } else {
      #breakpoint
      add_action $action_pat;   # not really a pattern, so just add.
    }
  }
}

# create $action.c and add to project: default.usp, <prj>.usr, ScriptUploadMetadata.xml
proc add_action {action} {
  if {[regexp {^(.+)\.c$} $action z act]} {
    if {![file exists $action]} {
      error ".c file given, but does not exist: $action"
    }
    set action $act
  }
  create_action_file $action
  update_default_usp $action
  add_action_usr $action
  add_file_metadata ${action}.c
}

proc create_action_file {action} {
  set filename "${action}.c"
  if {![file exists $filename]} {
    #set f [open $filename w]
    #fconfigure $f -translation crlf
    set f [open_temp_w $filename]
    puts $f "$action\(\) \{

\treturn 0;
\}
"
    close $f
    commit_file $filename
  }
}

proc update_default_usp {args} {
  set new_actions $args ; # could be more than 1
  set fn "default.usp"
  set fi [open $fn r]
  #set fo [open [tempname $fn] w]
  #fconfigure $fo -translation crlf
  set fo [open_temp_w $fn]
  while {[gets $fi line] >= 0} {
    if {[regexp {^Profile Actions name=vuser_init,(.+),vuser_end$} $line z orig_actions]} {
      # breakpoint
      set total_actions [merge_actions [split $orig_actions ","] $new_actions]
      puts $fo "Profile Actions name=vuser_init,[join $total_actions ","],vuser_end"
    } else {
      puts $fo $line
    }
  }
  close $fo
  close $fi
  commit_file $fn
}

# add each action in new list to orig add the end. Return result.
proc merge_actions {orig new} {
  set res $orig
  foreach action $new {
    # breakpoint
    if {[lsearch -exact $orig $action] < 0} {
      lappend res $action
    }
  }
  return $res
}

proc add_action_usr {action} {
  # maybe use project dir instead of current dir?
  set usr_file "[file tail [file normalize .]].usr"
  set ini [ini/read $usr_file]

  set ini [ini/add_no_dups $ini "Actions" "$action=${action}.c"]
  set ini [ini/add_no_dups $ini "Modified Actions" "$action=0"]
  set ini [ini/add_no_dups $ini "Recorded Actions" "$action=0"]
  set ini [ini/add_no_dups $ini "Interpreters" "$action=cci"]

  ini/write [tempname $usr_file] $ini
  commit_file $usr_file
}

# split files named in args by transaction names
# default is Action.c
task split_action {Split file in multiple files per transaction
  syntax: split_action <action> [<action> ..]
  For each start_transaction, create a new file and put statements in here.
} {
  if {$args == {}} {
    set args [list Action]
  }
  foreach action $args {
    split_action $action
  }
}

proc split_action {action} {
  set new_actions {}
  set fn "${action}.c"
  set fi [open $fn r]
  #set fo [open [tempname $fn] w]
  #fconfigure $fo -translation crlf
  set fo [open_temp_w $fn]
  set foc $fo
  set linenr 0
  while {[gets $fi line] >= 0} {
    incr linenr
    if {[regexp {_start_transaction\(\"(.+)\"\);} $line z transname]} {
      # [2016-11-30 12:35:02] this regsub not tested yet.
      regsub -all -- {-} $transname "_" transname; # replace - by _, need for C function names.
      if {[file exists "${transname}.c"]} {
        log warn "transaction file already exists: ${transname}.c"
        # error "transaction file already exists: ${transname}.c"
        # rename file, not the transaction
        set transname [new_transname $transname]
        log info "set new transname: $transname"
      }
      lappend new_actions $transname
      #set foa [open "${transname}.c" w]
      #fconfigure $foa -translation crlf
      puts $fo "\t$transname\(\);"
      set foa [open_temp_w "${transname}.c"]
      set foc $foa
      puts $foc "$transname\(\) \{"
      puts $foc $line
    } elseif {[regexp {_end_transaction} $line]} {
      puts $foc $line
      puts $foc "\treturn 0;\n\}\n"
      # [2016-08-11 14:39:52] close $foa gives exception: can't read foa.
      if {[info vars foa] == {}} {
        error "Error: cannot close foa, not defined. Line=$linenr, action=$action"
      }
      close $foa
      set foc $fo
      commit_file "${transname}.c"
    } elseif {[regexp rb_start_transaction $line]} {
      error "Should do split_action before rb_trans!"
    } else {
      puts $foc $line
    }
  }
  close $fo
  close $fi
  commit_file $fn

  # aan het einde aan project toevoegen
  task_add_action {*}$new_actions
}

# generate a new transname, because ${transname}.c already exists.
# will be like transname1.c, but check in filesystem if it does not exist already.
proc new_transname {transname_orig} {
  set exists 1
  set ndx 0
  while {$exists} {
    incr ndx
    set transname "${transname_orig}$ndx"
    set filename "${transname}.c"
    set exists [file exists $filename]
  }
  return $transname
}

