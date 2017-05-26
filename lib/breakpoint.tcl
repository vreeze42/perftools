# van http://www.linuxjournal.com/article/1159
proc breakpoint {} {
  # set max [expr [info level] - 2]
  set max [expr [info level] - 1]
  set current $max
  # NdV 3-11-2010 soms grote waarden in params, tonen duurt erg lang.
  breakpoint_show $current
  while {1} {
    puts -nonewline stderr "#$current: "
    gets stdin line
    while {![info complete $line]} {
      puts -nonewline stderr "? "
      append line \n[gets stdin]
    }
    switch -- $line {
      + {if {$current < $max} {breakpoint_show [incr current]}}
      - {if {$current > 0} {breakpoint_show [incr current -1]}}
      C {puts stderr "Resuming execution";return}
      ? {breakpoint_show $current 1}
      default {
        catch { uplevel #$current $line } result
        puts stderr $result
      }
    }
  }
}

# van http://www.linuxjournal.com/article/1159
# 16-9-2011 NdV info proc failed if withinn namespace. Now exec info proc with uplevel, so it is in correct namespace.
proc breakpoint_show {current {show_params 1}} {
  if {$current > 0} {
    set info [info level $current]
    set proc [lindex $info 0]
    set proc_args "<?>"
    catch {set proc_args [uplevel #$current "info args $proc"]}
    puts stderr "$current: Namespace [uplevel #$current {namespace current}] Procedure $proc $proc_args"
    set index 0
    if {$show_params} {
      foreach arg $proc_args {
        puts stderr "\t$arg = [string range [lindex $info [incr index]] 0 50]"
      }
    }
  } else {
    puts stderr "Top level"
  }
}

# [2016-12-07 21:06] some idea from Cognicast / Think Relevance podcast nr 7.
# use editproc to edit a proc
# procname can include a namespace: ns::procname
# TODO: maybe keep a list of changed procs.
proc editproc {procname} {
  global tcl_platform
  # generate a tempfile.
  set f [file tempfile tempname]
  # puts "temp: $tempname"
  if {$tcl_platform(platform) == "unix"} {
    set unix 1;                 # don't want to use = operator here, from libfp.
  } else {
    set unix 0
  }
  if {!$unix} {
    # to be sure, for notepad.
    fconfigure $f -translation crlf
  }
  # [2016-12-07 21:43] wanted to add newlines around [info body], but then keeps growing.
  if {[catch {puts $f "proc $procname {[info args $procname]} {[info body $procname]}"}]} {
    # proc not found, create a new definition.
    puts $f "proc $procname {} {\n\t\n}"
  }
  close $f
  # make editor configurable? Maybe use EDITOR env var? Want an editor that starts a nwe
  # instance and blocks this process.
  if {$unix} {
    catch {exec -ignorestderr leafpad $tempname >/dev/null 2>&1} msg
  } else {
    catch {exec -ignorestderr notepad $tempname} msg
  }
  #puts "exec msg: $msg"
  # assume editing is done here, alternative is a separate read proc.
  #puts "new proc:"
  #puts [read_file $tempname]
  uplevel #0 [source $tempname]
  # file delete $tempname
}

