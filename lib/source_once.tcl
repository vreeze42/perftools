package require Tclx

package provide ndv 0.1.1

namespace eval ::ndv {
  namespace export source_once source_once_file
  variable sources
  variable _stacktrace_files
  variable _stacktrace_procs
  
  array set sources {}

  set _stacktrace_files [dict create]
  set _stacktrace_procs [dict create]

  # puts "set _stacktrace_files: $_stacktrace_files"

  # @param one or more filenames to source.
  proc source_once {args} {
    foreach filename $args {
      source_once_file $filename 2 ; # uplevel 2: 1 for the caller, and 1 for the called sub-function (source_once_file)
      # source_once $filename 2
    }
  }
  
  # @param file: relative or absolute path. If relative, then relative to [info script], not the current directory!
  proc source_once_file {file {uplevel 1}} {
    # Remaining exercise for the next reader.  Adapt argument
    # processing to support the -rsrc and -encoding options
    # that [::source] provides (or will in Tcl 8.5)
    variable sources
    set res ""
    # debugging info
    # puts "source_once: info script: [info script]"
    # [2016-08-19 12:59] ok, put whole path in sources list/array.
    # puts "info script: [info script]"
    # set file_norm [file normalize [file join [file dirname [info script]] $file]]
    set file_norm [find_location $file]
    if {[regexp {backup.tcl} $file_norm]} {
      # breakpoint
    }
    if {![info exists sources($file_norm)]} {
      # don't catch errors, since that may indicate we failed to load it...?
      #     Extra challenge:  Use the techniques outlined in TIP 90
      #     to catch errors, then re-raise them so the [uplevel] does
      #     not appear on the stack trace.
      # We don't know what command is [source] in the caller's context,
      # so fully qualify to get the [::source] we want.
      # uplevel 1 [list ::source $file_norm]
      # puts "source: $file_norm"
      set res [uplevel $uplevel [list ::source $file_norm]]
      # mark it as loaded since it was source'd with no error...
      set sources($file_norm) 1
      
      # and read proc names for stacktrace.
      # [2017-04-02 15:16] alternative may be to override proc, and use [info sourceline???], then special handling for eg task would not be needed.
      stacktrace_read_source $file_norm
    }
    return $res
  }

  proc stacktrace_read_source {filename} {
    # global _stacktrace_procs _stacktrace_files
    variable _stacktrace_procs
    variable _stacktrace_files; # variable decl's should be on separate lines!
    
    set filename [file normalize $filename]; # full path
    if {[dict exists $_stacktrace_files $filename]} {
      puts "Already read: $filename"
      return;                     # already read
    }
    dict set _stacktrace_files $filename 1
    set lines [split [read_file $filename] "\n"]
    set linenr 1
    set namespace ""
    foreach line $lines {
      set line [string trim $line]
      if {[regexp {proc ([^ ]+)} $line z procname]} {
        dict lappend _stacktrace_procs [qualified_procname proc $namespace $procname] [dict create filename $filename linenr $linenr]
      }
      if {[regexp {task ([^ ]+)} $line z procname]} {
        # [2017-04-02 15:21] apparently for task items need to add 1 to linenr.
        dict lappend _stacktrace_procs [qualified_procname task $namespace $procname] [dict create filename $filename linenr [expr $linenr + 1]]
      }
      if {[regexp {namespace eval (::)?([^ ]+)} $line z z ns]} {
        set namespace $ns
      } 
      
      incr linenr
    }
    # breakpoint
  }

  # find location/path of file to source relative to the current script file.
  # this script file can be a symlink, so follow there to the actual file.
  proc find_location {file} {
    set script_path [info script]
    while {[file type $script_path] == "link"} {
      set script_path [file link $script_path]
    }
    set file_norm [file normalize [file join [file dirname $script_path] $file]]
    return $file_norm
  }

  
  proc qualified_procname {type namespace procname} {
    if {$procname == "read_run_logfile"} {
      # breakpoint
    }
    if {$type == "task"} {
      set procname "task_$procname"
    }
    if {$namespace != ""} {
      set procname "::${namespace}::${procname}"
    }
    return $procname
  }
  
  proc stacktrace_info {errorResult errorCode errorInfo} {
    puts stderr "$errorResult (code = $errorCode)"
    puts stderr [stacktrace_add_info $errorInfo]
  }

  proc stacktrace_add_info {errorInfo} {
    variable _stacktrace_procs
    set lines [split $errorInfo "\n"]
    set i 0
    set res [list]
    foreach line $lines {
      #  (procedure "proc2" line 2)
      if {[regexp {procedure \"([^ \"]+)\" line (\d+)} $line z procname linenr]} {
        set lst [dict_get $_stacktrace_procs $procname]
        if {$lst != {}} {
          foreach el $lst {
            # could have the same proc name in different namespaces, or procs overwriting each other.
            lappend res "$line \[[:filename $el]:[expr [:linenr $el] + $linenr - 1]\]"
          }
        } else {
          # info not found
          lappend res "$line (proc info not read)"
          puts stderr "$line (proc info not read)"
          breakpoint
        }

      } else {
        lappend res "$line"  
      }


      incr i
    }
    join $res "\n"
  }


  # ininialise when this source is read:
  
  stacktrace_read_source [info script]
  stacktrace_read_source $argv0
  


}

