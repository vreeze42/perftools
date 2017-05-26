#!/usr/bin/env tclsh

package require ndv
package require tdbc::sqlite3

# [2016-08-18 15:06:00] AHK version, as stated in name.

set perftools_dir [file normalize [file join [file dirname [info script]] .. ..]]

# TODO: use source_once with absolute path?
source [file join $perftools_dir logdb liblogreader.tcl]
source [file join $perftools_dir logdb librunlogreader.tcl]

ndv::source_once ahk_parsers_handlers.tcl

# [2016-07-09 10:09] for parse_ts and now:
use libdatetime

# set_log_global debug
set_log_global info

namespace eval ::ahklog {
  
  namespace export can_read? read_run_logfile
  # TODO: also export main?
  
  proc main {argv} {
    set options {
      {dir.arg "" "Directory with vuserlog files"}
      {db.arg "auto" "SQLite DB location (auto=create in dir)"}
      {deletedb "Delete DB before reading"}
    }
    set usage ": [file tail [info script]] \[options] :"
    set opt [getoptions argv $options $usage]

    set logdir [:dir $opt]
    # lassign $argv logdir
    puts "logdir: $logdir"
    if {[:db $opt] == "auto"} {
      set dbname [file join $logdir "ahklog.db"]
    } else {
      set dbname [:db $opt]
    }
    if {[:deletedb $opt]} {
      delete_database $dbname
    }

    read_logfile_dir_ahk $logdir $dbname
  }

  log debug "Define read_logfile_dir, AHK version"

  proc can_read? {filename} {
    log debug "Calling ahk::can_read? for: $filename"
    # regexp {ahk} [file tail $filename]
    # logfile.txt could be in any dir, eg. combination of ahk/vugen
    foreach re {{logfile.txt} {ahk}} {
      if {[regexp $re $filename]} {
        log debug "can_read? (ahk) - YES, can read!"
        return 1
      }
    }
    return 0
  }
  
  proc read_run_logfile {logfile db} {
    # some prep with inserting record in db for logfile, also do with handler?
    if {[is_logfile_read $db $logfile]} {
      return
    }

    # define parsers/handlers again for each logfile for now.
    # reset_parsers_handlers
    define_logreader_handlers_ahk
    
    set vuserid 0
    set ts [clock format [file mtime $logfile] -format "%Y-%m-%d %H:%M:%S"]
    
    set dirname [file dirname $logfile]
    set filesize [file size $logfile]
    lassign [det_project_runid_script $logfile] project runid script

    $db in_trans {
      set logfile_id [$db insert logfile [vars_to_dict logfile dirname ts \
                                              filesize runid project script]]
      # call proc in liblogreader.tcl
      readlogfile_coro $logfile [vars_to_dict db logfile_id vuserid]  
    }
  }

  # [2016-08-12 21:18] still used?
  proc det_project_runid_script {logfile} {
    # [-> $logfile {file dirname} {file dirname} {file tail}]
    set project [file tail [file dirname [file dirname $logfile]]]
    set runid 0
    set script $project
    list $project $runid $script
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

return ::ahklog
