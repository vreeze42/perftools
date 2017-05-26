# perform some tests. For now only show if libs are up-to-date
task test {Perform tests on script
  Calls following tasks: libs, check, check_configs, check_lr_params.
} {{includes "Check includes (default)"}
  {todos "Check todo's"}
  {comments "Check comments"}
  {misc "Check misc things"}
  {all "Do full check, including todo's and comments"}
} {
  task_libs;   # task_libs doesn't take cmdline arguments.

  # [2017-04-28 12:48] use args_orig, so task_check can do it's own parsing.
  #                    going back from opt -> args is difficult, wrt options
  #                    taking 0 or 1 arguments.
  task_check {*}$args_orig

  task_check_configs;   # task_check_configs doesn't take cmdline arguments.
  task_check_lr_params;   # task_check_lr_params doesn't take cmdline arguments.
}

task check {Perform some checks on sources
  location of #includes, todo's, comments.
} {{includes "Check includes (default)"}
  {todos "Check todo's"}
  {comments "Check comments"}
  {misc "Check misc things"}
  {all "Do full check, including todo's and comments"}
} {
  if {$args != {}} {
    foreach filename $args {
      check_file $filename $opt
    }
  } else {
    foreach srcfile [get_source_files]	{
      check_file $srcfile $opt
    }
    check_script
  }
}

proc check_file {srcfile opt} {
  #log debug "check_file: $srcfile"
  #puts "check_file: $srcfile"
  if {[:all $opt]} {
    set opt [dict merge $opt [dict create includes 1 todos 1 comments 1]]
  }
  if {[count_set_options $opt] == 0} {
    set opt [dict merge $opt [dict create includes 1 misc 1]]
  }
  if {[:includes $opt]} {
    check_file_includes $srcfile  
  }
  check_file_todos $srcfile $opt
  if {[:comments $opt]} {
    check_file_comments $srcfile
  }
  if {[:misc $opt]} {
    check_file_misc $srcfile
  }
}

# return the number of set binary options in opt
proc count_set_options {opt} {
  set res 0
  dict for {nm val} $opt {
    if {$val == 1} {
      incr res
    }
  }
  return $res
}

# check if include statement occurs after other statements. Includes should all be at the top.
proc check_file_includes {srcfile} {
  set other_found 0
  set in_comment 0
  set f [open $srcfile r]
  set linenr 0
  while {[gets $f line] >= 0} {
    incr linenr
    set lt [line_type $line]
    if {$lt == "comment_start"} {
      set in_comment 1
    }
    if {$lt == "comment_end"} {
      set in_comment 0
    }
    if {!$in_comment} {
      if {$lt == "include"} {
        if {$other_found} {
          puts_warn $srcfile $linenr "#include found after other statements: $line"
        }
      }
      if {$lt == "other"} {
        set other_found 1
      }
    }
  }
  close $f
}

# [2016-02-05 11:16:37] Deze niet std, levert te veel op, evt wel losse task.
# [2017-04-28 12:54] Wel std FIXME tonen.
proc check_file_todos {srcfile opt} {
  set f [open $srcfile r]
  set linenr 0
  while {[gets $f line] >= 0} {
    incr linenr
    if {[regexp {FIXME} $line]} {
      puts_warn $srcfile $linenr "FIXME found: $line"
    }
    if {[regexp {TODO} $line]} {
      if {[:todos $opt]} {
        puts_warn $srcfile $linenr "TODO found: $line"  
      }
    }
  }
  close $f
}

# [2016-02-05 11:14:23] deze niet std uitvoeren, levert te veel op. Mogelijk wel los, maar dan een task van maken.
proc check_file_comments {srcfile} {
  set f [open $srcfile r]
  set linenr 0
  while {[gets $f line] >= 0} {
    incr linenr
    set lt [line_type $line]
    if {$lt == "comment"} {
      # [2016-02-05 11:10:41] als er een haakje inzit, is het waarschijnlijk uitgecommente code.
      if {[regexp {[\(\)]} $line]} {
        puts_warn $srcfile $linenr "Possible out-commented code found: $line"
      }
    }
  }
  close $f
}

proc check_file_misc {srcfile} {
  set text [read_file $srcfile]
  if {[regexp {dynaTraceMonitor} $text]} {
    puts_warn $srcfile 0 "Found dynaTraceMonitor"
  }
  # check for deprecated functions, first just one.
  if {[file tail $srcfile] != "functions.c"} {
    if {[regexp {rb_web_reg_find\(} $text]} {
      puts_warn $srcfile 0 "Found deprecated function call: rb_web_reg_find"
    }
  }
}

# check script scope things, eg all .c/.h files in dir are included in the script. Also for .config files.
proc check_script {} {
  set src_files [filter_ignore_files \
                     [concat [glob -nocomplain -tails -directory . -type f "*.c"] \
                          [glob -nocomplain -tails -directory . -type f "*.h"] \
                          [glob -nocomplain -tails -directory . -type f "*.config"]]]
  set prj_text [read_file [lindex [glob *.usr] 0]]
  foreach src_file $src_files {
    if {[string first $src_file $prj_text] == -1} {
      puts "Sourcefile not in script.usr file: $src_file"
    } else {
      # puts "Ok: $src_file found in script.usr"
    }
  }
  set ini [ini/read default.cfg]
  set headers [ini/headers $ini]
  if {[lsearch -exact $headers "WEB"] >= 0} {
    # Only check for WEB scripts, so with a [WEB] header
    check_setting $ini WEB FailNonCriticalItem 1
    check_setting $ini WEB ProxyUseProxy 0
    check_setting $ini WEB ProxyUseProxyServer 0
    check_setting $ini General ContinueOnError 0
  }
}

proc check_setting {ini header key value} {
  set val [ini/get_param $ini $header $key "<none>"]
  if {$val == $value} {
    # ok, no worries
  } else {
    puts "WARN: unexpected value for $header/$key: $val (expected: $value)"
  }
}
