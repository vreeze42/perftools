#!/usr/bin/env tclsh861

package require ndv

set_log_global perf {showfilename 0}

# [2017-02-07 11:23:59] Deze vooralsnog los, later integreren in buildtool logreader en logdb.
# deze leest log en maakt csv. Via excel2db om te zetten naar een SQLite voor verdere analyse.
proc main {argv} {
  global argv0
  log info "$argv0 called with options: $argv"
  set options {
    {dir.arg "" "Directory with vuserlog files"}
    {csv.arg "requests.csv" "Filename within <dir> to write requests to"}
    {loglevel.arg "info" "Log level"}
  }
  set usage ": [file tail [info script]] \[options] :"
  set opt [getoptions argv $options $usage]
  log set_log_level [:loglevel $opt]
  
  # set logdir [:dir $dargv]
  # lassign $argv logdir
  # log debug "logdir: $logdir"
  read_requests [:dir $opt] [:csv $opt]
}

proc read_requests {dir csv} {
  set csv_filename [file join $dir $csv]
  set fo [open $csv_filename w]
  puts $fo [headerline]
  foreach logfile [glob -directory $dir -type f output.txt] {
    read_requests_log $logfile $fo
  }
  close $fo
}

proc headerline {} {
  # transaction is reserved in SQLite, so use transname
  join [list iteration transname loglinenr sourcefile sourcelinenr reqresp reltime_msec url int_id respsize] ","
}

# TODO: issued at er ook bij.
proc read_requests_log {logfile fo} {
  log debug "Reading $logfile"
  set fi [open $logfile r]
  set loglinenr 0
  set iteration ""
  set transaction ""
  while {[gets $fi line] >= 0} {
    incr loglinenr
    if {($loglinenr % 100000) == 0} {
      log debug "Read #lines: $loglinenr"
    }
    if {[regexp { trans=([^ ,]+),.+, iteration=(\d+)} $line z tr it]} {
      set iteration $it
      set transaction $tr
      log debug "Set transaction=$transaction (iter=$iteration)"
    }
    if {[regexp {^([^\(\)]+)\((\d+)\): t=(\d+)ms: \d+-byte request headers for "([^\"]+)" \(RelFrameId=\d+, Internal ID=(\d+)\)} $line z sourcefile sourcelinenr reltime_msec url int_id]} {
      puts $fo [join [list $iteration $transaction $loglinenr $sourcefile $sourcelinenr req $reltime_msec $url $int_id 0] ","]
    } elseif {[regexp {^([^\(\)]+)\((\d+)\): t=(\d+)ms: (\d+)-byte (((DE|EN)CODED )?response (body|headers)) (received )?for "([^\"]+)" \(RelFrameId=\d+, Internal ID=(\d+)\)} $line z sourcefile sourcelinenr reltime_msec respsize resptype _ _ _ _ url int_id]} {
      puts $fo [join [list $iteration $transaction $loglinenr $sourcefile $sourcelinenr $resptype $reltime_msec $url $int_id $respsize] ","]
    } elseif {[regexp {^([^\(\)]+)\((\d+)\): t=(\d+)ms: (\d+)-byte (DE|EN)CODED response body (received )?for "([^\"]+)" \(RelFrameId=\d+, Internal ID=(\d+)\)} $line z sourcefile sourcelinenr reltime_msec respsize de_en _ url int_id]} {
      log debug "should be handled by previous regexp"
      breakpoint
      # puts $fo [join [list $iteration $transaction $loglinenr $sourcefile $sourcelinenr resp${de_en}coded $reltime_msec $url $int_id $respsize] ","]
    } elseif {[regexp {^([^\(\)]+)\((\d+)\): t=(\d+)ms: (\d+)-byte response body for "([^\"]+)" \(RelFrameId=\d+, Internal ID=(\d+)\)} $line z sourcefile sourcelinenr reltime_msec respsize url int_id]} {
      log debug "should be handled by previous regexp"
      breakpoint

      # puts $fo [join [list $iteration $transaction $loglinenr $sourcefile $sourcelinenr resp $reltime_msec $url $int_id $respsize] ","]
    } elseif {[regexp {2.0.3/img/structure/excel.jpg} $line]} {
      # [2017-02-07 13:51:18] nu zowel std als decoded response bodies in de csv.
      #breakpoint
    }
  }
  close $fi
}

if {[this_is_main]} {
  main $argv
}
