# templates - tasks/functions to make script adhere to certain templates and best
# practices: .config files, set of includes/libs, rb_transaction, text checks.

task templates {Make script adhere to templates and best practices
  .config files,
  set of includes/libs,
  rb_transaction,
  text checks.
  add TT var - ThinkTime.
} {{debug "Add debug/structure lines to output files"}
} {
  get_template_files

  foreach filename [get_action_files] {
    set_rb_transactions $filename
    set_web_reg_find $filename $opt
  }
  
  get_std_libs
  # add TT (thinktime) parameter.
  task_add_param TT int var 5
  task_add_param usertestmode int var 0
  task_add_param dynatrace int var 1
  task_add_param scripttest int var 0

  add_param_iteration
  # proxy_config_loc only used within set_proxy, so no var or param
  # proxy_config_loc = g:\config\proxy.config
  set_web_settings
}

# get .config files from repo/templates iff they do not exist in project yet.
proc get_template_files {} {
  global repo_dir
  set repo_tmp [file join $repo_dir template]
  foreach filename [glob -nocomplain -directory $repo_tmp *.config] {
    set target_name [file tail $filename]
    if {![file exists $target_name]} {
      file copy $filename [tempname $target_name]
      commit_file $target_name
    }
    add_file $target_name
  }
  # get vuser_init.c from template iff it has not been changed yet.
  # ie. it has 5 lines or less.
  set text [read_file vuser_init.c]
  if {[:# [split $text "\n"]] <= 5} {
    file copy [file join $repo_tmp vuser_init.c] [tempname vuser_init.c]
    commit_file vuser_init.c
  } else {
    # log debug "vuser_init.c already too big."
  }
}

proc set_rb_transactions {filename} {
  regsub_file $filename {lr_start_transaction\(([^())]+)\);} \
    {rb_start_transaction(\1);} {do 1}
  regsub_file $filename {lr_end_transaction\(([^()]+), ?LR_AUTO\);} \
    {rb_end_transaction(\1, TT);} {do 1}
  regsub_file $filename {lr_think_time\(([^()]+)\);} {// lr_think_time(\1);} {do 1}
}

# add web_reg_find statements before requests, if they do not already occur.
# cannot simply use regsub to add the web_reg_finds, because it would not be idempotent.
proc set_web_reg_find {filename opt} {
  set statements [read_source_statements $filename]
  set stmt_groups [group_statements $statements]
  # stmt_groups is sort-of like a parse tree. Work on this one, at the end write
  # back to file.
  set stmt_groups2 [add_web_reg_find $stmt_groups]
  # write_source_statements [tempname $filename] $stmt_groups2
  # breakpoint
  write_source_statements $filename $stmt_groups2 $opt
  commit_file $filename
}

proc add_web_reg_find {stmt_groups} {
  #linsert, lreplace : in place of functioneel?
  #lset is inplace: lset lst ndx newvalue
  #linsert is functioneel: $lst ndx element
  map add_web_reg_find_group $stmt_groups
}

# return new statement group based on current one, possibly adding a statement for
# web_reg_find, if it does not exist yet. Add it just before the request
proc add_web_reg_find_group {stmt_grp} {
  if {[stmt_grp_has_type? $stmt_grp main-req]} {
    if {![stmt_grp_has_type? $stmt_grp sub-find]} {
      if {[url_needs_find [:url $stmt_grp]]} {
        dict set stmt_grp statements \
            [linsert [:statements $stmt_grp] end-1 \
                 [stmt_new "\tweb_reg_find(\"Text=<TODO>\", \"SaveCount=savecount\", LAST);\n" sub-find]]
      }
    }
  }
  return $stmt_grp
}

proc url_needs_find {url} {
  foreach re {{\.svg} {\.png} {\.jpg} {\.gif} {\.ico} {dynaTraceMonitor}} {
    if {[regexp $re $url]} {
      return 0
    }
  }
  return 1
}

proc get_std_libs {} {
  foreach libname {vugen.h y_core.c functions.c configfile.c dynatrace.c logger.c} {
    if {![file exists $libname]} {
      task_get $libname  
    }
  }
}

# set web settings which are checked in task checks
proc set_web_settings {} {
  #puts "set_web_settings: default.cfg"
  set ini [ini/read default.cfg]
  set headers [ini/headers $ini]
  if {[lsearch -exact $headers "WEB"] >= 0} {
    # Only check for WEB scripts, so with a [WEB] header
    set ini [ini/set_param $ini WEB FailNonCriticalItem 1]
    set ini [ini/set_param $ini WEB ProxyUseProxy 0]
    set ini [ini/set_param $ini WEB ProxyUseProxyServer 0]
    set ini [ini/set_param $ini General ContinueOnError 0]

    # [2016-12-01 09:16:16] some settings for logging. Log more when creating script, don't check later.
    set ini [ini/set_param $ini Log AutoLog 0]
    set ini [ini/set_param $ini Log AutoLogBufferSize 1]
    set ini [ini/set_param $ini Log IncludeEnvInfo 1]
    set ini [ini/set_param $ini Log LogDetail 1]
    set ini [ini/set_param $ini Log LogOptions LogExtended]
    set ini [ini/set_param $ini Log MsgClassData 1]
    set ini [ini/set_param $ini Log MsgClassParameters 1]
    set ini [ini/set_param $ini Log PrintTimeStamp 1]

    # [2016-12-01 14:00:01] and some more
    set ini [ini/set_param $ini General AutomaticTransactions 0]
    set ini [ini/set_param $ini General AutomaticTransactionsPerFunc 0]
    set ini [ini/set_param $ini General FailTransOnErrorMsg 0]
    set ini [ini/set_param $ini WEB SnapshotOnErrorActive 0]
  }
  ini/write [tempname default.cfg] $ini
  #puts "ini/write default.cfg done"
  #breakpoint;                   # expect temp file to be written, and source still the same.
  commit_file default.cfg
}


