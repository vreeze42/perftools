package require ndv
package require tdbc::sqlite3

# This lib is more specific to performance run logs and specific tables to be filled.

# TODO: activate ssl/pubsub again?
# ndv::source_once ssl.tcl pubsub.tcl read-vuserlogs-db-coro.tcl

# [2016-07-09 10:09] for parse_ts and now:
use libdatetime
use libfp

# specific for vugen?
# set VUSER_END_ITERATION 1000

# return list of all started transactions where no end transaction was seen.
# set both start and end fields to start row, so time stamps are always filled.
proc make_trans_not_finished {started_transactions} {
  set res [list]
  set line_fields {linenr ts sec_ts iteration}
  set line_start_fields [map [fn x {return "${x}_start"}] $line_fields]
  set line_end_fields [map [fn x {return "${x}_end"}] $line_fields]
  foreach row [dict values $started_transactions] {
    set dstart [dict_rename $row $line_fields $line_start_fields]
    set dend [dict_rename $row $line_fields $line_end_fields]
    if {[:ts_end $dstart] != ""} {
      # take end timestamp from errorline with timestamp.
      if {[:ts_end $dstart] < [:ts_start $dstart]} {
        # probably because of missing msec: set end = start, resp time = 0
        dict set dend ts_end [:ts_start $dstart]
        dict set dend resptime 0.0
      } else {
        set ts_end [:ts_end $dstart]
        dict set dend ts_end $ts_end
        set sec_ts_end [parse_ts $ts_end]
        dict set dend sec_ts_end $sec_ts_end
        set resptime [format %.3f [expr $sec_ts_end - [:sec_ts_start $dstart]]]
        dict set dend resptime $resptime
        # dict set dend resptime 1234; # TODO: calculate.
      }
      log debug "set ts_end and also resptime to 1234"
    }
    set d [dict merge $dstart $dend]
    lappend res $d
  }
  return $res
}

# make trans(action) record/item based on end-line and started transactions.
# don't want empty keys (and some other keys) in dict.
proc make_trans_finished {row started_transactions} {
  foreach key {"" db ssl split_proc} {
    log debug "mtf - check key: $key"
    assert {[lsearch -exact [dict keys $row] $key] < 0}  
  }
  set line_fields {linenr ts sec_ts iteration}
  set line_start_fields [map [fn x {return "${x}_start"}] $line_fields]
  set line_end_fields [map [fn x {return "${x}_end"}] $line_fields]
  #set no_start 0
  set rowstart [dict_get $started_transactions [:transname $row]]
  if {$rowstart == {}} {
    # probably a synthetic transaction. Some minor error.
    set rowstart $row
    #set no_start 1
  }
  set dstart [dict_rename $rowstart $line_fields $line_start_fields]
  set dend [dict_rename $row $line_fields $line_end_fields]
  set d [dict merge $dstart $dend]
  foreach key {"" db ssl split_proc} {
    log debug "mtfr - check key: $key"
    assert {[lsearch -exact [dict keys $d] $key] < 0}  
  }
  return $d
}

# TODO: merge with make_trans_finished?

# [2017-04-11 16:57:52] old version before also handling started_trans
proc make_trans_error_old {row} {
  set line_fields {linenr ts sec_ts iteration}
  set line_start_fields [map [fn x {return "${x}_start"}] $line_fields]  
  set line_end_fields [map [fn x {return "${x}_end"}] $line_fields]
  set d [dict_rename $row $line_fields $line_end_fields]
  set d2 [dict merge $d [dict_rename $row $line_fields $line_start_fields]]
  # breakpoint
  return $d2
}


proc add_read_status {db status} {
  $db insert read_status [dict create ts [now] status $status]
}

proc is_logfile_read {db logfile} {
  # if query returns 1 record, return 1=true, otherwise 0=false.
  :# [$db query "select 1 from logfile where logfile='$logfile'"]
}
