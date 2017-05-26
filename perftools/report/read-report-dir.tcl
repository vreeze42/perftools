#!/usr/bin/env tclsh

# Main entry point to read/report a whole dir of performance results, for different
# types of tools (eg AHK and Vugen/Loadrunner)

package require ndv

set_log_global perf {showfilename 0}
# set_log_global debug {showfilename 0}

# source read-vuserlogs-db.tcl
# ndv::source_once vuser-report.tcl

# [2016-11-16 13:23:31] reader_namespaces overschreven door versie in 
# this scripts knows the readers:
# first in global namespace:
set reader_namespaces [list]
set perftools_dir [file normalize [file join [file dirname [info script]] ..]]
# puts "perftools_dir: $perftools_dir"
ndv::source_once report-run-dir.tcl

lappend reader_namespaces [ndv::source_once [file join $perftools_dir autohotkey \
                                       ahklog read-ahklogs-db.tcl]]
lappend reader_namespaces [ndv::source_once [file join $perftools_dir loadrunner \
                                       vuserlog read-vuserlogs-db.tcl]]


# TODO:
# * now expect DB in subdir, also put html reports there.
proc main {argv} {
  global argv0 log
  log debug "$argv0 called with options: $argv"
  set options {
    {dir.arg "" "Directory with subdirs with vuserlog files and sqlite db's"}
    {all "Create all reports (full and summary)"}
    {full "Create full report"}
    {summary "Create summary report"}
    {ssl "Use SSL lines in log (not used)"}
    {debug "set loglevel debug"}
  }
  set usage ": [file tail [info script]] \[options] :"
  set opt [getoptions argv $options $usage]

  if {[:debug $opt]} {
    $log set_log_level debug  
  }
  
  set logdir [:dir $opt]
  # lassign $argv logdir
  log debug "logdir: $logdir"
  foreach subdir [glob -nocomplain -directory $logdir -type d *] {
    if {[ignore_dir $subdir]} {
      log debug "Ignore dir: $subdir"
      continue
    }
    # set dbname "$subdir.db"
    # TODO: check (again) if logs are fully read into db.
    # TODO: use correct logreader (ahk and vugen for now), first only vugen
    read_report_run_dir $subdir $opt
  }
  # also handle root dir, could be just 1 dir
  read_report_run_dir $logdir $opt
}

proc ignore_dir {dir} {
  set dir [file normalize $dir]
  log debug "ignore_dir called: $dir"
  if {[regexp {jmeter} $dir]} {
    return 1
  }
  # [2016-08-17 09:38:41] for now only vugen dirs.
  # [2016-08-19 11:57] both vugen and ahk should work now.
  if {[regexp {ahk} $dir]} {
    return 0
  }
  # [2016-08-19 14:14] for now only ahk.
  if {[regexp {vugen} $dir]} {
    return 0
  }
  if {[regexp {run} $dir]} {
    return 0
  }
  
  return 0
}

# read logs from a single run (ahk/vugen/both) into one DB.
proc read_report_run_dir {rundir opt} {
  # [2016-11-16 13:28:34] zet de namespaces hier opnieuw, kunnen overschreven zijn door bv sourcedep.tcl
  read_report_set_namespaces $rundir $opt
  if {![file exists $rundir]} {
    if {[:nodownload $opt]} {
		log warn "Dir does not exist, and -nodownload set, so returning: $rundir"
		return
	} else {
		log warn "Dir does not exist, and -nodownload not set (TBD, set -download), so returning: $rundir"
		return
	}
  }
  set dbname [file join $rundir testrunlog.db]
  if {[:clean $opt]} {
    log debug "Deleting DB: $dbname"
    file delete $dbname
  }
  if {![file exists $dbname]} {
    log debug "New dir: read logfiles: $rundir"
    # file delete $dbname
    # read_logfile_dir $dir $dbname 0 split_transname
    read_run_dir $rundir $dbname $opt
  } else {
    log debug "Already read: $rundir -> $dbname"
  }
  report_run_dir $rundir $dbname $opt; # in ./report-run-dir.tcl
}

proc read_run_dir {rundir dbname opt} {
  # TODO: check if dir already read.
  set db [get_run_db $dbname $opt]
  add_read_status $db "starting"
  set nread 0;      # number of actually read files.
  set nhandled 0;   # All files, for handling with progress calculator
  set logfiles [glob -nocomplain -directory $rundir -type f *]
  set pg [CProgressCalculator::new_instance]
  $pg set_items_total [:# $logfiles]
  $pg start
  foreach filename $logfiles {
    incr nread [read_run_logfile_generic $filename $db $opt]
    incr nhandled
    $pg at_item $nhandled
  }
  add_read_status $db "complete"
  log debug "set read_status, closing DB"
  $db close
  log debug "closed DB"
  log info "Read $nread logfile(s) in $rundir"
}

proc read_run_logfile_generic {filename db opt} {
  global reader_namespaces
  set nread 0
  foreach ns $reader_namespaces {
    if {[${ns}::can_read? $filename]} {
      log debug "Reading $filename with ns: $ns"
      ${ns}::read_run_logfile $filename $db
      set nread 1
      break
    }
  }
  if {$nread == 0} {
    log debug "Could not read (no ns): $filename"
	if {[regexp {output.txt} $filename]} {
	  breakpoint
	}
  }
  return $nread
}

proc add_read_status {db status} {
  $db insert read_status [dict create ts [now] status $status]
}


# TODO: use this proc again.
proc is_dir_fully_read {dbname ssl} {
  set db [get_results_db $dbname $ssl]
  set res [:# [$db query "select 1 from read_status where status='complete'"]]
  $db close
  return $res
}

# iff opt contains logdotpng, create a dot/png of the readlog process.
# one dot/png per source type.
proc read_report_set_namespaces {rundir opt} {
	global reader_namespaces perftools_dir
	
	set reader_namespaces [list]
	# set perftools_dir [file normalize [file join [file dirname [info script]] ..]]
	# puts "perftools_dir: $perftools_dir"
	
	# [2016-11-16 13:27:51] deze hier waarsch niet nodig.
	# ndv::source_once report-run-dir.tcl

	lappend reader_namespaces [source [file join $perftools_dir autohotkey \
										   ahklog read-ahklogs-db.tcl]]
	lappend reader_namespaces [source [file join $perftools_dir loadrunner \
										   vuserlog read-vuserlogs-db.tcl]]

  if {[:logdotpng $opt]} {
    foreach ns $reader_namespaces {
      create_dot_png $ns $rundir
    }
    # [2016-11-18 11:22] for now, only vugenlog
    #create_dot_png ::vuserlog $rundir
  }
  
}

proc create_dot_png {ns rundir} {
  global parsers handlers
  log debug "Create dot/png for: $ns in dir: $rundir"
  # ${ns}::define_logreader_handlers
  if {$ns == "::vuserlog"} {
    define_logreader_handlers
    set prefix vugen
  } elseif {$ns == "::ahklog"} {
    define_logreader_handlers_ahk
    set prefix ahk
  } else {
    error "Don't know define_logreader_handlers for $ns"
  }

  set dotfilename [file join $rundir $prefix-readlog.dot]
  set pngfilename [file join $rundir $prefix-readlog.png]
  set f [open $dotfilename w]
  write_dot_header $f LR
  # [2016-11-18 12:12] can add nodes multiple times, will just be one node, so ok for topics.
  set filled_blue {style filled fillcolor lightblue shape note}
  set filled_red {style filled fillcolor coral3}
  foreach p $parsers {
    log debug "Parser: [:proc_name $p] -> [:topic $p]/[:label $p]"
    # set nd_proc [puts_node_stmt $f [:proc_name $p]]
    set nd_proc [puts_node_stmt $f [:label $p] {*}$filled_red]
    set nd_topic [puts_node_stmt $f [:topic $p] {*}$filled_blue]
    puts $f [edge_stmt $nd_proc $nd_topic]
  }
  dict for {in_topic lst} $handlers {
    set nd_topic_in [puts_node_stmt $f $in_topic {*}$filled_blue]; # mss niet eens nodig, in_topic moet je al hebben. Maar bof/eof waarsch niet.
    foreach el $lst {
      log debug "Handler: $in_topic -> [:coro_name $el]/[:label $el] -> [:topic $el]"
      # set nd_coro [puts_node_stmt $f [:coro_name $el]]
      set nd_coro [puts_node_stmt $f [:label $el] {*}$filled_red]
      set nd_topic_out [puts_node_stmt $f [:topic $el] {*}$filled_blue]
      puts $f [edge_stmt $nd_topic_in $nd_coro]
      puts $f [edge_stmt_once $nd_coro $nd_topic_out]
      # puts $f [edge_stmt $nd_coro $nd_topic_out]
    }
  }
  write_dot_footer $f
  close $f
  do_dot $dotfilename $pngfilename
  # breakpoint
}

if {[this_is_main]} {
  main $argv
}
