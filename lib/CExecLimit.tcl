# Execute a system command, limit the time it may take.

# @todo add this one to ndv package.

# @note for now only command line commands may be used, because stdout is read to 
# determine when the command has finished.

package require Itcl
package require Tclx
package require fileutil

# math was used for random function, but can use expr rand() as well, don't have math package available now.
# package require math

# class maar eenmalig definieren
if {[llength [itcl::find classes CExecLimit]] > 0} {
	return
}

# 2-1-2014 are those still needed?
# source [file join $env(CRUISE_DIR) checkout lib perflib.tcl]
# source [file join $env(CRUISE_DIR) checkout script lib CLogger.tcl]

itcl::class CExecLimit {
	# private common log
	# set log [CLogger::new_logger [file tail [info script]] info]


	# private common TEMPDIR "c:/temp"
	private variable TEMPDIR

	public common CREATED 1
	public common STARTED 2
	public common FINISHED_OK 3
	public common CANCELLED 4
	public common STR_RUN_STATUS
	
	foreach code [list CREATED STARTED FINISHED_OK CANCELLED] {
			set STR_RUN_STATUS([set $code]) $code
	}
	
	private variable run_status
	private variable after_id
	private variable result_output
	private variable obj_callback
	private variable saveproc_filename

	public constructor {} {
		set obj_callback ""
		set TEMPDIR [det_tempdir]
		init
	}
	
	private method det_tempdir {} {
		global env tcl_platform
		if {$tcl_platform(platform) == "windows"} {
		  set result "c:/temp"
		} elseif {$tcl_platform(platform) == "unix"} {
		  set result "/tmp" 
		} else {
		  set result "/tmp" 
		}
		catch {set result $env(TEMP)}
		catch {set result $env(TMP)}
		return $result
	}
	
	private method init {} {
		set run_status $CREATED
		set after_id -1
		set result_output {}
		set saveproc_filename ""
	}

	public method set_saveproc_filename {a_saveproc_filename} {
		set saveproc_filename $a_saveproc_filename
	}	
	
	public method set_callback {an_obj_callback} {
		set obj_callback $an_obj_callback
	} 

	public method save_proc_id {pid cmd} {
		if {$saveproc_filename != ""} {
      set f [open $saveproc_filename a]
      puts $f "$pid\t$cmd"
      close $f
      # $log info "Saved $pid to $saveproc_filename"
      log info "Saved $pid to $saveproc_filename"
    }
	}
	
	# this method is not re-entrant, but it won't return until the cmd is finished or cancelled.
	# as long as this object is not used in multiple threads, this shouldn't be a problem.
	public method exec_limit {cmd limit_seconds result_name exec_stderr_name} {
		upvar $result_name result
		upvar $exec_stderr_name exec_stderr
		# $log info "running $cmd for a maximum of $limit_seconds seconds"
    log info "running $cmd for a maximum of $limit_seconds seconds"
		set result_output {}
		# it seems that the same channel identifier is used in succeeding calls.
		# set ch [open "|$cmd" r+]
		set stderr_filename [file join $TEMPDIR "exec_stderr[to_filename $this]-[det_rnd].txt"] 
		log debug "stderr_filename: $stderr_filename"
		set f_stderr [open $stderr_filename w]
		set ch [open "| $cmd 2>@ $f_stderr" r+]
		log debug "Channel id of started process: $ch"
		log debug "PID (via Channel) of started process: [pid $ch]"
		save_proc_id [pid $ch] $cmd
		
		# set ch [open [list "|$cmd"] r+]
		# fileevent $ch readable [list read_output $ch]
		fileevent $ch readable [itcl::code $this read_output $ch]
		
		set run_status $STARTED
		# after [expr $limit_seconds * 1000] [list cancel_cmd $ch $cmd]
		set after_id [after [expr $limit_seconds * 1000] [itcl::code $this cancel_cmd $ch $cmd]]
		vwait [itcl::scope run_status]
		catch {close $ch} ; # catch kan fout gaan als child process gekilled is.
		catch {close $f_stderr} ; # catch kan fout gaan als child process gekilled is.
	
		# stderr toevoegen aan stdout
		set result_stderr {}
		::fileutil::foreachLine line $stderr_filename {
			lappend result_stderr "stderr: $line"			
		}
		# 24-9-2008 NdV: file delete kan fout gaan als sub-process het bestand nog vasthoudt. Filenaam is uniek, dus niet zo erg.		
		catch {file delete $stderr_filename}
	
		log info "exec_limit is done, value of run_status: $STR_RUN_STATUS($run_status)"
		log debug "end: llength(result_output): [llength $result_output]"
		set result [join $result_output "\n"]
		set exec_stderr [join $result_stderr "\n"]
		log debug "#result: [string length $result]"
		# new ret_run_status var, so state of this object will be as before the call started. 
		
		set ret_run_status $run_status
		# vast een goede reden dat init hier weer wordt aangeroepen...
		init
		return $ret_run_status
	}
	
	private method read_output {ch} {
		if {[eof $ch]} {
			log debug "EOF of channel reached, ending"
			after cancel $after_id
			set run_status $FINISHED_OK
		} else {
			gets $ch line
			# puts "line of output: $line"
			log trace $line
			lappend result_output $line
			log debug "#result_output: [llength $result_output]"
			if {$obj_callback != ""} {
				$obj_callback output_line $line
			}
		}
	}
	
	private method cancel_cmd {ch cmd} {
		log warn "time limit has exceeded, killing $cmd"
		# see if it works with a close
		set pids [pid $ch]
		log info "pids for channel: $pids, about to be killed"
    # @todo find child-pids, they should also be killed.
    # std tcl, tclx, twapi?
    # 13-3-2014 wel wat dingen mogelijk, maar alleen: getAllProcesses en parent-pid per proces. Dus niet child-processes per process.
    # dan iets als: get_all_child_processes $pid -> ook grand-children etc.
		foreach pid $pids {
			log debug "killing $pid"
			# kill $pid ; # kill is a tclx command.
      kill_tree $pid
		}
		
		# close $ch ; # blijft hangen zolang app niet beeindigd is.
		# puts "channel closed, is this enough?"
		log debug "Processes killed"
		set run_status $CANCELLED
	}

  private method kill_tree {pid} {
    global tcl_platform
    if {$tcl_platform(platform) == "windows"} {
      log debug "killing $pid whole tree with taskkill"
      exec C:\\Windows\\system32\\taskkill.exe /PID $pid /T /F
    } else {
      kill $pid ; # kill is a tclx command.
    }
  }
  
	# convert a fully qualified varname to a filename
	# used for generating a unique filename, based on this instance.
	private method to_filename {ns_varname} {
		set result $ns_varname
		regsub -all "::" $ns_varname "_" result
		return $result
	}

	private method det_rnd {} {
		# return [::math::random]
    expr rand()
	}

}

proc main {argc argv} {
	set exec_limit [CExecLimit #auto]
	
	if {1} {	
		# set exec_limit [CExecLimit #auto]
		puts "Executing dir root (excl subdirectories) with a limit of 5 seconds"
		set exit_code [$exec_limit exec_limit {cmd /c dir c:\\} 5 result2]
		puts "#result of exec: [string length $result2]"
		puts "exitcode: $exit_code"
	}

	if {1} {
		puts "Executing dir root (incl subdirectories) with a limit of 5 seconds"
		set exit_code [$exec_limit exec_limit {cmd /c dir c:\\ /s} 5 result] 	
		puts "#result of exec: [string length $result]"
		puts "exitcode: $exit_code"
	}

	if {1} {	
		# set exec_limit [CExecLimit #auto]
		puts "Executing dir root (excl subdirectories) with a limit of 5 seconds"
		set exit_code [$exec_limit exec_limit {cmd /c dir c:\\} 5 result2]
		puts "#result of exec: [string length $result2]"
		puts "exitcode: $exit_code"
	}

	if {1} {
		puts "Executing dir root (incl subdirectories) with a limit of 5 seconds"
		set exit_code [$exec_limit exec_limit {cmd /c dir c:\\ /s} 5 result] 	
		puts "#result of exec: [string length $result]"
		puts "exitcode: $exit_code"
	}
	
}

# aanroepen vanuit Ant, maar ook mogelijk om vanuit Tcl te doen.
# 2-1-2014 if 'info level' != 0, this script is called from another tcl script, so not at the main level, and main should not be called.
# this is a generic solution, calling main here hardly ever seems necessary/useful.
if {[info level] == 0} {
  if {[file tail $argv0] == [file tail [info script]]} {
    main $argc $argv
  }
}



