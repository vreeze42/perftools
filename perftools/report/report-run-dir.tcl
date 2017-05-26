#!/usr/bin/env tclsh

package require ndv

set_log_global debug

set perftools_dir [file normalize [file join [file dirname [info script]] ..]]

source [file join $perftools_dir logdb liblogdb.tcl]

# create html report based on vuser results read into sqlite DB.

# use libns
require libio io
use libfp

proc main {argv} {
  set options {
    {dir.arg "" "Directory with vuserlog files"}
    {all "Create all reports (full and summary)"}
    {full "Create full report"}
    {summary "Create summary report"}
    {ssl "Use SSL lines in log (not used)"}
    {testruns "Create report for all runs in testruns dir for project"}
  }
  set usage ": [file tail [info script]] \[options] :"
  set opt [getoptions argv $options $usage]

  set subdir [:dir $opt]

  report_dir $subdir $opt
}

proc report_run_dir {dir dbname opt} {
  if {[:all $opt]} {
    set opt [dict merge $opt [dict create full 1 summary 1]]
  }
  set report_made 0
  set db [get_run_db $dbname $opt]
  logdb_make_indexes $db
  # $db load_percentile ; # do in get_run_db
  if {[:full $opt]} {
    report_full $db $dir $opt
    set report_made 1
  }
  if {[:summary $opt]} {
    report_summary $db $dir $opt
    set report_made 1
  }
  if {!$report_made} {
    puts "No report made, specify an option (or help)"
  }
}

# create full report where every transaction and error is visible in the report.
# maybe one html per vuser, possible TODO:
# maybe use user/script definitions for report, eg which fields to use as result of
# split_trans. Could also check which fields have more than 1 different value, or are
# not empty. Also (with eg newuser/revisit) could check if value varies during this
# block/iteration: if so, make a column. If not, add above table.
proc report_full {db dir opt} {
  set html_name [file join $dir "report-full.html"]
  if {[file exists $html_name]} {
    # return ; # or maybe a clean option to start anew
  }

  # [2017-03-29 12:51:46] idempotent, so can be done here. Should be done while reading.
  $db exec "update trans set iteration_sub = 1 where iteration_sub is null"
  
  io/with_file f [open $html_name w] {
    set hh [ndv::CHtmlHelper::new]
    $hh set_channel $f
    $hh write_header "Vuser log report" 0
    # [2016-08-17 12:28:11] check both logfile and vuserid
    # [2017-03-28 15:49:11] use iteration_sub if available.
    set query "select logfile, vuserid, iteration_start, iteration_sub, usecase, user,
               min(ts_start) ts_min, max(ts_end) ts_max
               from trans
               group by 1,2,3,4,5,6
               order by 1,2,3,4,6"
    foreach row [$db query $query] {
      report_iter_user $db $row $hh
    }
    if {[:step $opt]} {
      report_steps $db $hh $opt $dir
    }
    $hh write_footer
  }
}

proc report_iter_user {db row hh} {
  $hh heading 1 "Logfile: [file tail [:logfile $row]] / Iteration: [:iteration_start $row].[:iteration_sub $row] / usecase: [:usecase $row] / user: [:user $row][vuser_str $row]"
  $hh line "[:ts_min $row] => [:ts_max $row]"
  # $hh table body ook leuk? Ook vgl clojure/hiccup.
  $hh table_start
  $hh table_header Transaction Result Resp.time Start End Resources
  # [2016-08-02 13:40:10] + 0 if var is empty
  set query "select transname, transshort, trans_status, resptime, ts_start, ts_end
             from trans
             where vuserid = [:vuserid $row] + 0
             and iteration_start = [:iteration_start $row] + 0
             and iteration_sub = [:iteration_sub $row] + 0
             and user = '[:user $row]'
             and logfile = '[:logfile $row]'
             order by ts_start"
  log debug "Query: $query"
  foreach trow [$db query $query] {
    $hh table_row_class [vuser_row_class $trow] [:transshort $trow] \
        [status_text $trow] \
        [format "%.3f" [:resptime $trow]] \
        [time_part [:ts_start $trow]] [time_part [:ts_end $trow]] \
        [href_resources $db $hh [:vuserid $row] [:iteration_start $row] [:user $row] \
             [:transname $trow]]
  }
  $hh table_end

  # Check if there were errors in this iteration
  # [2016-08-02 13:41:59] + 0 for when fields are empty.
  # [2017-03-28 15:52:57] error table does not have iteration_sub (yet)
  #              and iteration_sub = [:iteration_sub $row] + 0
  set query "select ts, linenr, line
             from error
             where vuserid = [:vuserid $row] + 0
             and iteration = [:iteration_start $row] + 0
             and user = '[:user $row]'
             and logfile = '[:logfile $row]'
             order by ts, srclinenr, linenr"
  set res [$db query $query]
  if {[:# $res] > 0} {
    $hh table_start
    $hh table_header Time Linenr Message
    foreach erow $res {
      # $hh set_colour red - dan wel ook bij andere dingen dan table te doen.
      # of algemeen een set-option.
      $hh table_row_class Failure [time_part [:ts $erow]] [:linenr $erow] [:line $erow]
      # $hh reset_colour
    }
    $hh table_end
  }
}

# return html representation of references to resources for transaction
proc href_resources {db hh vuserid iteration user transname} {
  set query "select resource from resource
             where vuserid + 0 = $vuserid + 0
             and iteration + 0 = $iteration + 0
             and user = '$user'
             and transname = '$transname'
             order by ts"
  set res [$db query $query]
  set hrefs [list]
  # TODO: use map? or list comprehension?
  foreach row $res {
    set resource [:resource $row]
    lappend hrefs [$hh get_anchor [file tail $resource] $resource]
  }
  if {$hrefs == {}} {
    # return "No resources for $vuserid/$iteration/$user/$transname: $query"
    return ""
  } else {
    join $hrefs "<br/>"  
  }
}

proc report_steps {db hh opt dir} {
  $hh heading 1 "All steps within transactions"
  $hh table_start
  $hh table_header linenr transname step_name step_type
  set query "select linenr, transname, step_name, step_type from step order by linenr"
  foreach row [$db query $query] {
    $hh table_row [:linenr $row] [:transname $row] [step_href $hh $dir [:step_name $row]] [:step_type $row]
  }
  $hh table_end
}

proc step_href {hh dir step_name} {
  set ref_file [step_html_ref $dir $step_name]
  $hh get_anchor $step_name [file join "result1/iteration1" $ref_file]
}

# find and return .inf file which contains step.
# dir - main dir, so need to go to result1/iteration1
proc step_html_ref {dir step_name} {
  set ref_file ""
  foreach filename [glob -nocomplain -directory [file join $dir "result1/iteration1"] *.inf] {
    set text [read_file $filename]
    # StepName=Url: System Features
    if {[regexp -nocase -line "^StepName=\[^:\]+: ${step_name}$" $text line]} {
      set ref_file [step_get_ref_file $filename]
      # puts "[file tail $filename]: $line -> $ref_file"
    }
  }
  return $ref_file
}

# find FileName1 in .inf file.
# FileName1=t8.html
# [2016-12-18 17:13] this one copied from steps.tcl in buildtool, should have SPOD.
proc step_get_ref_file {filename} {
  set text [read_file $filename]
  if {[regexp -line {^FileName1=(.+)$} $text z ref]} {
    return $ref
  } else {
    return "FileName1 not found"
  }
}



# starting point, also called from buildtool/ahk and /vugen.
proc report_summary {db dir opt} {
  # call orig for now
  insert_report_summary $db $dir
  insert_report_percentiles $db $dir
  report_summary_html $db $dir
}

# create summary in DB, in table summary
proc insert_report_summary {db dir} {
  $db exec "delete from summary"
  set query "select usecase, min(ts_start) min_ts from trans group by 1 order by 2"
  foreach row [$db query $query] {
    insert_report_summary_usecase $db $row
  }
}

proc insert_report_percentiles {db dir} {
  $db exec "delete from percentiles"
  set query "select distinct usecase, transshort from trans where trans_status = 0"
  set usecase ""
  $db in_trans {
    foreach row [$db query $query] {
      log debug "insert percentile for row: $row"
      insert_report_percentiles_usecase_trans $db [:usecase $row] [:transshort $row]
      if {[:usecase $row] != $usecase} {
        insert_report_percentiles_usecase_trans $db [:usecase $row] "Total"
        set usecase [:usecase $row]
      }
    }
    insert_report_percentiles_usecase_trans $db "Total" "Total"
  }
}

# options:
# * both usecase, trans filled in: calc percentiles for specific trans within usecase
# * usecase filled in, trans is 'Total': calc percentiles for usecase, over all transactions.
# * both usecase and trans are 'Total': calc percentiles over all usecases and transactions.
# use percentile function (embedded C function). Could be more efficient with own query.
proc insert_report_percentiles_usecase_trans {db usecase transshort} {
  set perc 5
  while {$perc <= 100} {
    set query "select percentile(resptime, $perc) resptime
               from trans
               where usecase like '[to_like $usecase]' and transshort like '[to_like $transshort]'
               and trans_status = 0"
    set res [$db query $query]
    set resptime [:resptime [:0 $res]]
    $db insert percentiles [vars_to_dict usecase transshort perc resptime]
    incr perc 5
  }
}

proc to_like {str} {
  if {$str == "Total"} {
    return "%"
  } else {
    return $str
  }
}

# create summary report table with statistics.
# maybe use user/script definitions for report, eg which fields to use as result of
# split_trans. Could also check which fields have more than 1 different value, or are
# not empty. Also (with eg newuser/revisit) could check if value varies during this
# block/iteration: if so, make a column. If not, add in header in html above table (as iteration, user, usecase)
proc insert_report_summary_usecase {db row} {
  set usecase [:usecase $row]
  # TODO: make 95% column red iff value > requirement (3 sec now). Something with SLA status/req in config.
  set query "select transname, '1-Standard' resulttype, transshort, min(ts_start) min_ts, min(resptime) resptime_min, avg(resptime) resptime_avg,
             max(resptime) resptime_max, count(*) npass, percentile(resptime, 95) resptime_p95
             from trans
             where usecase = '$usecase'
             and trans_status = 0
             group by 1,2
             order by 3,1"
  log debug "Query**: $query"
  foreach trow [$db query $query] {
    log debug "summary trow: $trow"
    $db insert summary [dict merge $row $trow [dict create nfail [count_trans_error $db $usecase [:transname $trow]]]]
  }
  # Transactions with only errors, mostly synthetic transactions.
  # so not 0 (ok) or 4 (warning, eg no items found)
  set query "select transname, '2-Fail' resulttype, transshort, min(ts_start) min_ts, count(*) nfail
             from trans t1
             where usecase = '$usecase'
             and trans_status not in (0,4)
             and not transname in (
               select transname
               from trans
               where usecase = '$usecase'
               and trans_status = 0
             )
             group by 1,2
             order by 3,1"

  foreach trow [$db query $query] {
    $db insert summary [dict merge $row $trow [dict_setvals 0 resptime_min resptime_avg resptime_p95 resptime_max npass]]
  }
  
  # Also total for this usecase:
  set query "select 'Total' transshort, '3-Total' resulttype, min(ts_start) min_ts, min(resptime) resptime_min, avg(resptime) resptime_avg,
             max(resptime) resptime_max, count(*) npass, percentile(resptime, 95) resptime_p95
             from trans
             where usecase = '[:usecase $row]'
             and trans_status = 0"
  set trow [:0 [$db query $query]]
  log debug "Total trow: $trow"
  set dct_error [dict create nfail [count_trans_error $db $usecase "All"]]
  if {($trow == {}) || ([:npass $trow] == 0)} {
    #log debug "Empty trow"
    #breakpoint
    $db insert summary [dict merge $row $trow $dct_error \
                            [dict_setvals 0 resptime_min resptime_avg resptime_p95 resptime_max]]
  } else {
    #log debug "Non-empty trow"
    #breakpoint
    $db insert summary [dict merge $row $trow $dct_error]
  }
}

# create a dict with all values set to val for keys in args
proc dict_setvals {val args} {
  set res [dict create]
  foreach k $args {
    dict set res $k $val
  }
  return $res
}

# create summary report with statistics.
# maybe use user/script definitions for report, eg which fields to use as result of
# split_trans. Could also check which fields have more than 1 different value, or are
# not empty. Also (with eg newuser/revisit) could check if value varies during this
# block/iteration: if so, make a column. If not, add above table.
proc report_summary_html {db dir} {
  set html_name [file join $dir "report-summary.html"]
  if {[file exists $html_name]} {
    # return ; # or maybe a clean option to start anew
  }
  io/with_file f [open $html_name w] {
    set hh [ndv::CHtmlHelper::new]
    $hh set_channel $f
    $hh write_header "Vuser log report" 0
    report_summary_testrun $db $hh
    set query "select usecase, min(min_ts) min_ts from summary group by 1 order by 2"
    foreach row [$db query $query] {
      report_summary_html_usecase $db $hh $row
    }
    report_summary_testrun_errors $db $hh
    $hh write_footer
  }
}

# show runtime of test
proc report_summary_testrun {db hh} {
  set query "select min(ts_start) min_ts, max(ts_end) max_ts,
       round((max(sec_ts_end) - min(sec_ts_start)) / 60) runtime_minutes from trans"
  set rows [$db query $query]
  if {[count $rows] > 0} {
    set row [first $rows]
    if {[:runtime_minutes $row] != ""} {
      $hh heading 1 "[:min_ts $row] - [:max_ts $row] ([format %.0f [:runtime_minutes $row]] minutes)"
    } else {
      $hh heading 1 "Row 0 has empty runtime_minutes"
    }
  } else {
    $hh heading 1 "No rows found in DB!"
  }
}

proc report_summary_html_usecase {db hh row} {
  set usecase [:usecase $row]
  $hh heading 1 "Usecase: $usecase"
  $hh table_start
  $hh table_header Transaction Minimum Average 95% Maximum Pass Fail
  set query "select transshort, resptime_min, resptime_avg, resptime_p95, resptime_max, npass, nfail
             from summary
             where usecase = '[:usecase $row]'
             order by resulttype, min_ts"
  log debug "Query**: $query"
  foreach trow [$db query $query] {
    log debug "summary trow: $trow"
    $hh table_row [:transshort $trow] \
        [:resptime_min $trow] \
        [format %.3f [:resptime_avg $trow]] \
        [format %.3f [:resptime_p95 $trow]] [:resptime_max $trow] \
        [:npass $trow] [:nfail $trow]
  }
  $hh table_end
}

proc report_summary_testrun_errors {db hh} {
  $hh heading 1 "Errors summary"
  $hh table_start
  $hh table_header Srcfile SrcLinenr ErrorNr ErrorType Details Count
  set query "select srcfile, srclinenr, errornr, errortype, details, count(*) cnt
             from error
             group by 1,2,3,4,5
             order by 1,2,3,4,5"
  log debug "Query**: $query"
  foreach erow [$db query $query] {
    $hh table_row [:srcfile $erow] [:srclinenr $erow] [:errornr $erow] [:errortype $erow] [:details $erow] [:cnt $erow]
  }
  $hh table_end

  $hh heading 1 "Errors details"
  $hh table_start
  $hh table_header Srcfile SrcLinenr ErrorNr ErrorType Details Line
  set query "select ts, srcfile, srclinenr, errornr, errortype, details, line
             from error
             order by 1,2,3,4,5,6"
  log debug "Query**: $query"
  foreach erow [$db query $query] {
    $hh table_row [:srcfile $erow] [:srclinenr $erow] [:errornr $erow] [:errortype $erow] [:details $erow] [:line $erow]
  }
  $hh table_end
  
}

proc count_trans_error {db usecase transname} {
  if {$transname == "All"} {
    set query "select count(*) cnt from trans where usecase='$usecase' and trans_status not in (0,4)"
  } else {
    set query "select count(*) cnt from trans where usecase='$usecase' and transname = '$transname' and trans_status not in (0,4)"   
  }
 
  set res [$db query $query]
  :cnt [:0 $res]
}

proc vuser_row_class {trow} {
  if {[:trans_status $trow] == 0} {
    return ""
  } elseif {[:trans_status $trow] == 4} {
    return "Warning"
  } else {
    return "Failure"
  }
}

proc vuser_str {row} {
  if {[:vuserid $row] != -1} {
    return " / vuser: [:vuserid $row]"  
  }
  return ""
}

proc status_text {trow} {
  set st [:trans_status $trow]
  switch $st {
    -1 {
      set res "Error"
    }
    0 {
      set res "Ok"
    }
    1 {
      set res "Fail"
    }
    4 {
      set res "Warning"
    }
    default {
      set res "Unknown"
    }
  }
  return "$res ($st)"
}

proc time_part {ts} {
  lindex [split $ts " "] 1
}

if {[this_is_main]} {
  main $argv
}
