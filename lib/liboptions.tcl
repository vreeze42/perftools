package require Tclx

# getoptions wrapper: exit when options are not ok, don't print stacktrace.
# if retval==opt, normal beheviour: return dict with options, or fail with printing to
# stderr.
# if retval==help, just create help text based on options and usage, argv_name is ignored then.
proc getoptions {argv_name options usage {retval opt}} {
  if {$retval == "help"} {
    ::cmdline::usage $options $usage
  } else {
    # assume opt/default for now
    upvar $argv_name argv
    try_eval {
      ::cmdline::getoptions argv $options $usage
    } {
      # if getoptions gives error, don't print stacktrace, just exit.
      puts stderr $errorResult
      exit 
    }
  }
}



