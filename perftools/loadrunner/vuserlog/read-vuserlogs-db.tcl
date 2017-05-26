#!/usr/bin/env tclsh

# [2016-08-17 09:47:56] Version for vugen logs.

package require ndv
package require tdbc::sqlite3

set perftools_dir [file normalize [file join [file dirname [info script]] .. ..]]

# TODO: use source_once with absolute path?
source [file join $perftools_dir logdb liblogreader.tcl]
source [file join $perftools_dir logdb librunlogreader.tcl]

ndv::source_once ssl.tcl pubsub.tcl read-vuserlogs-db-coro.tcl

# [2016-07-09 10:09] for parse_ts and now:
use libdatetime
use libfp

# Note:
# [2016-02-08 11:13:55] Bug - when logfile contains 0-bytes (eg in Vugen output.txt with log webregfind for PDF/XLS), the script sees this as EOF and misses transactions and errors. [2016-07-09 10:12] this should be solved by reading as binary.

namespace eval ::vuserlog {
  
  namespace export can_read? read_run_logfile

  set VUSER_END_ITERATION 1000

  proc main {argv} {
    set options {
      {dir.arg "" "Directory with vuserlog files"}
      {db.arg "auto" "SQLite DB location (auto=create in dir)"}
      {ssl "Read SSL data provided log is 'always'"}
      {deletedb "Delete DB before reading"}
    }
    set usage ": [file tail [info script]] \[options] :"
    set dargv [getoptions argv $options $usage]

    set logdir [:dir $dargv]
    # lassign $argv logdir
    puts "logdir: $logdir"
    set ssl [:ssl $dargv]
    if {[:db $dargv] == "auto"} {
      set dbname [file join $logdir "vuserlog.db"]
    } else {
      set dbname [:db $dargv]
    }
    if {[:deletedb $dargv]} {
      delete_database $dbname
    }

    read_logfile_dir $logdir $dbname $ssl
  }

  log debug "Defining read_logfile_dir, vugen version."

  proc can_read? {filename} {
    log debug "Calling vuserlog::can_read? for: $filename"
    # regexp {ahk} [file tail $filename]
    # logfile.txt could be in any dir, eg. combination of ahk/vugen
    if {[regexp {output.txt} [file tail $filename]]} {
      log debug "can_read? (vugen,output) - YES, can read!"
      return 1
    }
    # TODO: possibly check contenst of file, if it's really a vugen log file.
    if {[regexp {\.log$} [file tail $filename]]} {
      log debug "can_read? (vugen,.log) - YES, can read!"
      return 1
    }
    
    return 0
  }

  proc read_run_logfile {logfile db} {
    define_logreader_handlers
    readlogfile_new_coro $logfile $db 0 split_transname
  }

  # split transaction name in parts to store in DB. Proc should return a dict with a subset of the following fields:
  # usecase, revisit, transid, transshort, searchcrit
  # TODO: this one now in two places, also .bld/config.tcl
  proc split_transname {transname} {
    if {[regexp {^([^_]+)_(.+)$} $transname z usecase transshort]} {
      if {[regexp {^\d+$} $usecase]} {
        # [2016-08-17 10:35:22] TODO: hack now: if usecase contains only digits, it probably isn't a usecase, just return as transname
        dict create usecase "all" transshort $transname
      } else {
        dict create usecase $usecase transshort $transshort    
      }
    } else {
      # [2016-08-17 09:53:29] if regexp fails, set transshort to transname.
      dict create usecase "all" transshort $transname
    }
  }
  
};                              # end-of-namespace

if {[this_is_main]} {
  set_log_global perf {showfilename 0}
  log debug "This is main, so call main proc"
  set_log_global debug {showfilename 0}  
  main $argv  
} else {
  log debug "This is not main, don't call main proc"
}

return ::vuserlog
