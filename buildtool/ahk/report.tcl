# [2016-08-18 15:02:30] Version for AHK

source [file join [perftools_dir] report read-report-dir.tcl]

task report {Create report of output.txt in script dir
  Copy output.txt to testruns dir, call perftools/autohotkey/ahklog/read-ahklogs-db.tcl
  and create html report.
} {{summary "Create summary report, with aggregate times and errors"}
  {full "Create full report, with each iteration/transaction."}
  {all "Both summary and full"}
  {ssl "SSL report (unused)"}
} {
  global testruns_dir
  if {[regexp {<FILL IN>} $testruns_dir]} {
    puts "WARN: testruns_dir not set yet (in .bld/config.tcl): $testruns_dir"
    return
  }
  # opt available
  log debug "Report for AHK"
  
  # first copy output.txt to restruns dirs, iff not already done.
  set logfilename output2/logfile.txt
  if {![file exists $logfilename]} {
    puts "WARN: no output.txt found"
    return
  }
  set subdir [file join $testruns_dir \
                  "ahk-[clock format [file mtime $logfilename] -format \
                  "%Y-%m-%d--%H-%M-%S"]"]
  set to_file [file join $subdir [file tail $logfilename]]
  if {![file exists $to_file]} {
    file mkdir $subdir
    file copy $logfilename $to_file
  }
  # [2016-08-13 18:30] while testing keep the logfile in the target dir, so already exists.
  copy_dir_png output2 $subdir
  read_report_run_dir $subdir $opt
  # then call read_logfile_dir; idempotency should already be arranged by read_logfile_dir
  #set dbname [file join $subdir "ahklog.db"]
  #read_logfile_dir_ahk $subdir $dbname

  # and finally make the report.
  #vuser_report $subdir $dbname $opt
}

proc copy_dir_png {from to} {
  # breakpoint
  foreach fromfile [glob -nocomplain -directory $from -type f *.png] {
    set tofile [file join $to [file tail $fromfile]]
    if {![file exists $tofile]} {
      file copy $fromfile $tofile
    }
  }
}
