#############################################
# General                                   #
#############################################

# if DEBUGGING_MODE is true, an error will always be thrown when something's not ok.
# set DEBUGGING_MODE 1
set DEBUGGING_MODE 0

proc komma2punt {line} {
  regsub -all "," $line "." line
  return $line
}

proc punt2komma {str} {
  regsub -all {\.} $str "," str
  return $str
}

set LOGLEVEL 0

set intLevel(trace) 14
set intLevel(debug) 12
set intLevel(perf) 10
set intLevel(info) 8
set intLevel(notice) 6
set intLevel(warn) 4
set intLevel(error) 2
set intLevel(critical) 0

set loggers(DEFAULT) 0

proc add_logger {service} {
	global loggers intLevel
  set loggers($service) $intLevel(debug)
}

proc set_log_level {service level} {
	global stderr loggers intLevel
	set loggers($service) $intLevel($level)
}

# @deprecated
proc addLogger {service} {
	return [add_logger $service]
}

# @deprecated
proc setLogLevel {service level} {
	return [set_log_level $service $level]
}

proc fail {msg {level critical} {service "DEFAULT"} {exit_code 1}} {
	log $msg $level $service
  exit $exit_code
}

add_logger perflib
setLogLevel perflib info
# set_log_level perflib debug

proc log_start_finished {service script {loglevel -1}} {
	log "start" perf $service $loglevel
	uplevel $script
	log "finished" perf $service $loglevel
}

# to be called from within catch-block of try-eval (I always forget the names of the error-vars)
proc log_error {logtext} {
  uplevel 1 {log warn "$errorResult $errorCode $errorInfo, continuing"}
  log warn $logtext
}

proc line2list {line} {
	set l [split $line]
	set result {}
	foreach el $l {
		if {$el != ""} {
			lappend result $el
		}
	}
	return $result
}

# assert best lastig te maken, zie voorbeeld in ::Control::assert (control/assert.tcl)
proc _assert_old1 {expr {message ""}} {
  set res 1
  set code [catch {uplevel 1 [list expr $expr]} res]
  if {$code} {
    log "Assert: evaluation failed: $expr; msg = $res; message = $message" warn perflib
    error "Assert: evaluation failed: $expr"
  } else {
    if {!$res} {
      if {$message != ""} {
        set error_message $message
      } else {
        set error_message "Assert: evaluation of expr resulted in false: $expr"
      }
      log $error_message warn perflib
      error $error_message
    } else {
      # everything ok, do nothing.
    }
  }
}

#############################################
# XML related, maybe put in separate file   #
#############################################

proc xmlElementStart {f name {attributes {}} {newline 1}} {
	puts -nonewline $f "<$name"
	foreach attribute $attributes {
		xmlAttribute $f $attribute
	}
	if {$newline} {
		puts $f ">"
	} else {
		puts -nonewline $f ">"
	}
}

proc xmlElementEnd {f name {newline 1}} {
	if {$newline} {
		puts $f "</$name>"
	} else {
		puts -nonewline $f "</$name>"
	}
}

# attributes contains a list of name/value-pairs
proc xmlElement {f name attributes} {
  puts -nonewline $f "<$name"
	foreach attribute $attributes {
		xmlAttribute $f $attribute
	}
	puts $f "/>"
}

# attribute is a list (pair) with name and value
proc xmlAttribute {f attribute {addspace 1}} {
	set name [lindex $attribute 0]
	set value [lindex $attribute 1]
  if {$addspace} {
	  puts -nonewline $f " "
  }
  puts -nonewline $f "$name=\"$value\""
}

proc xmlComment {f comment} {
  puts $f "<!-- $comment -->"
}

###################################
# List helpers
###################################

# helper: check if list contains element, if not, add it and return 1, otherwise 0
# @deprecated, this can be done with the struct::set functions.
proc list_add {list_name element} {
	upvar $list_name lst
	if {[lsearch -exact $lst $element] == -1} {
		lappend lst $element
		set result 1
	} else {
		set result 0
	}
	return $result
}

###################################
# GNUPLOT
###################################

proc gnuplot_file {m_filename png_filename plot_filename} {
	global env
	
	log "gnuplot_file start" debug perflib
	set res_both ""

	set error 0
	if {![file exists $plot_filename]} {
		log "Plotfile doesn't exist: $plot_filename" warn perflib
		set error 1
	} else {
		set f [open $plot_filename r]
		set plotline_found 0
		while {(![eof $f]) && (!$plotline_found)} {
			gets $f line
			if {($line != "") && (![regexp {^#} $line])} {
				set plotline_found 1
			}
		}
		close $f
		if {!$plotline_found} {
			log "Plotfile doesn't contain plottable lines: $plot_filename" warn perflib
			set error 1
		}
	}

	if {!$error} {
		set res ""
		set res_stderr ""

		set reslogs_dir [file dirname $png_filename]
		set old_dir [pwd]
		cd $reslogs_dir

		# 5-9-2006 (NdV) padnaam kan te lang worden voor gnuplot, dus copy naar temp-dir
		set m_filename_temp [file join $env(windir) temp gnuplot.m]
		file copy -force $m_filename $m_filename_temp
		log "exec: $env(GNUPLOT_EXE) $m_filename" debug perflib
		# catch {set res [exec $env(GNUPLOT_EXE) $m_filename]} res_stderr
		catch {set res [exec $env(GNUPLOT_EXE) $m_filename_temp]} res_stderr
		file delete $m_filename_temp

		cd $old_dir

		# 5-7-06: paar aanpassing in plotten gedaan: set output toegevoegd, maxtries = 1, delay verwijderd, plotfile als param ipv stdin meegeven.
		# Resultaat is melding "Can't find the gnuplot window", maar de .png is wel gemaakt. Hierop checken en log aanpassen, anders melding
		# technische fout in index.html
		if {[regexp {Can't find the gnuplot window} $res_stderr]} {
			set res_stderr "Can't find the gnuplot window => niet spannend, .png zou wel gemaakt moeten zijn"
		}

		if {$res == ""} {
			if {$res_stderr == ""} {
				set res_both ""
			} else {
				set res_both "stderr: $res_stderr"
			}
		} else {
			if {$res_stderr == ""} {
				set res_both "stdout: $res"
			} else {
				set res_both "stdout: $res\nstderr: $res_stderr"
			}
		}
	}

	# check if .png exists
	if {[file exists $png_filename]} {
		if {[file size $png_filename] > 0} {
			# nothing, ok.
		} else {
			log "png file has 0 bytes: $png_filename" warn perflib
		}
	} else {
		log "png file doesn't exist: $png_filename" warn perflib
	}
  
  if {$res_both != "" } {
	 log "$res_both" info perflib
	}
	log "gnuplot_file finished" debug perflib
	
}

# subst uitvoeren zonder variabelen te vervangen, ofwel $ negeren
# subst met -novariables werkt niet (goed)
# vervang eerst $ door een \004
proc subst_no_variables {text} {
  # 4-11-2010 NdV: testje, lijkt wel goed te gaan. 
  return [subst -novariables $text]
  
  global log
  set special_char [det_special_char $text]
  regsub -all {\$} $text $special_char text2
  try_eval {
    set text3 [subst $text2]
  } {
    breakpoint 
  }
  regsub -all $special_char $text3 "\$" text4
  return $text4
}

# @todo format eigenlijk vervangen door id-functie.
proc get_array_values {ar_name args} {
  upvar $ar_name ar
  struct::list mapfor el $args {format %s $ar($el)}
}

# split tekst in $fd based on regexp $re. When a line matches $re, the previous lines will be sent to $callbackproc
# with additional $args
# and after this the previous lines block will be re-initialised with current line (which matched $re)
proc file_block_splitter {fd re callbackproc args} {
  set lst_lines {}
  set in_block 0
  while {![eof $fd]} {
    gets $fd line
    if {[regexp $re $line]} {
      if {$in_block} {
        $callbackproc [join $lst_lines "\n"] {*}$args
      }
      set in_block 1
      set lst_lines [list $line]
    } else {
      if {$in_block} {
        lappend lst_lines $line
      }
    }
  }
  if {$in_block} {
    $callbackproc [join $lst_lines "\n"] {*}$args
  }
}

proc xls2csv {xls_filename} {
  set csv_filename "[file rootname $xls_filename].csv" 
  file delete $csv_filename
  exec cmd /c xls2csv.vbs [file nativename [file normalize $xls_filename]] [file nativename [file normalize $csv_filename]]
  return $csv_filename
}

#######################################################
# General helper procs #
#######################################################

proc shuffle_group {lst} {
  # test first, return same list
  global ar_random
  array unset ar_random
  foreach el $lst {
    set ar_random($el) [random1] 
  }
  return [lsort -command compare_random $lst]
}

# determine if a list has only unique elements
proc lunique {lst} {
  return [expr [llength $lst] == [llength [lsort -unique $lst]]]
}

proc compare_random {a b} {
  global ar_random
  if {$ar_random($a) < $ar_random($b)} {
    return -1 
  } elseif {$ar_random($a) > $ar_random($b)} {
    return 1 
  } else {
    return 0 
  }
}

# choose ntochoose different random numbers between 0 and max-1 inclusive.
proc choose_random {max ntochoose} {
  if {$ntochoose == 2} {
    set rnd1 [random_int $max]
    set rnd2 [random_int [expr $max - 1]]
    if {$rnd2 == $rnd1} {
      set rnd2 [expr $max - 1] 
    }
    return [list $rnd1 $rnd2]
  } else {
    error "Not implemented, ntochoose != 2" 
  }
}

proc gcd {a b} {
# The next line does all of Euclid's algorithm! We can make do
# without a temporary variable, since $a is substituted before the
# [lb]set a $b[rb] and thus continues to hold a reference to the
#   "old" value of [var a].
  while {$b > 0} { set b [expr { $a % [set a $b] }] }
  return $a
}

proc array_values {ar_name} {
  upvar $ar_name ar
  ::struct::list mapfor nm [array names ar] {
    expr $ar($nm)    
  }
}

proc lees_tsv {filename callback_proc} {
  set f [open $filename r]
  gets $f line
  set lst_names [split $line "\t"]
  while {![eof $f]} {
    gets $f line
    set lst_values [split $line "\t"]
    array unset ar_values
    foreach name $lst_names value $lst_values {
      set ar_values($name) [string trim $value]
    }
    {*}$callback_proc $line $lst_names ar_values
  }  
  close $f
}

proc catch_call {catch_result args} {
  try_eval {
    set result [eval {*}$args]
  } {
    set result $catch_result
  }
  return $result
}

#############################################
# Directory walking                         #
#############################################

# @param actionproc can be a list with procname and parameters, will be curried with actual filename and rootdir
proc handle_dir_rec {dir globpattern actionproc {rootdir ""}} {
  if {$rootdir == ""} {
    set rootdir $dir 
  }
  foreach filename [lsort [glob -nocomplain -directory $dir -type f $globpattern]] {
    # $actionproc $filename $rootdir
    {*}$actionproc $filename $rootdir
  }
  foreach dirname [lsort [glob -nocomplain -directory $dir -type d *]] {
    handle_dir_rec $dirname $globpattern $actionproc $rootdir
  }
}

proc det_relative_path {sourcefile rootdir} {
  string range $sourcefile [string length $rootdir]+1 end
}

# determine corresponding path in root2 for path1 within root1
proc corresponding_path {root1 root2 path1} {
  file join $root2 [det_relative_path $path1 $root1]
}


### determine HOSTNAME on both Linux and windows ###
proc det_hostname {} {
  global env
  if {[array names env HOSTNAME] != ""} {
    return $env(HOSTNAME)
  }
  if {[array names env COMPUTERNAME] != ""} {
    return $env(COMPUTERNAME)
  }
  try_eval {
    set hostname [exec hostname]
    return $hostname
  } {
    # nothing, continue with next one (if any)
  }
  error "Cannot determine HOSTNAME from environment (env)"
}

if 0 {
  [2016-07-22 16:39] old functional programming procs, like map. Now in libfp.tcl

  These ones could be used to describe "Evolution of the map proc/function in Tcl"

########################################
# Wat procs voor functioneel programmeren.
# in tcllib 1.4 zit dit er standaard in, maar nu (1-2-08) nog tcllib 1.3, onder tcl 8.4.2.0.
########################################
proc lambda {argl body} {
		# set name {}
		set name $argl/$body
		proc $name $argl $body
		return $name
}

proc map {fun list} {
		set res {}
		foreach i $list {lappend res [$fun $i]}
		return $res
}

# voorbeeld:
# map [lambda x {expr $x * 3}] [list 4 7 3]
# => 12 21 9

# in tcl 8.5:
proc map85 {lambda list} {
   set result {}
   foreach item $list {
      lappend result [apply $lambda $item]
   }
   return $result
}

proc filter85 {lambda list} {
	set result {}
	foreach item $list {
		if {[apply $lambda $item]} {
			lappend result $item
		}
	}
	return $result
}

# hier nog niet helemaal uitgekomen. Idee is met uplevel 2 uit te voeren, zodat geen upvars nodig zijn, behalve voor de loop-var.
proc map85_l2 {lambda list} {
  # upvar 2 [lindex $lambda 0] var ; misschien niet nodig vanwege apply en lambda 
	upvar 1 _lambda0 lambda1 ; # kan niet direct koppelen aan lambda
	upvar 1 _item0 item
	set lambda1 $lambda ; # hiermee wordt level hoger lambda 0 ook gezet.
	
	set result {}
   foreach item $list {
      # lappend result [apply $lambda $item]
			# zelfs met uplevel #0 wordt bij info level in de lambda nog 1 teruggegeven.
			lappend result [uplevel #0 {apply $_lambda0 $_item0}]
   }
   return $result
}

proc maptest {lambda} {
	upvar 1 lambda0 lambda1
	set lambda1 $lambda
	# set res [uplevel 1 {apply $lambda 23}]
	set res [uplevel 1 {apply $lambda0 23}]
	puts "res: $res"
	return $res
}
#maptest {x {expr $x + 2}}

proc maptest2 {lambda} {
	upvar 1 lambda0 lambda
	# set lambda1 $lambda
	# set res [uplevel 1 {apply $lambda 23}]
	set res [uplevel 1 {apply $lambda0 23}]
	puts "res: $res"
	return $res
}
#maptest2 {x {expr $x + 2}}


#map {x {return [string length $x]:$x}} {a bb ccc dddd}
#      -> 1:a 2:bb 3:ccc 4:dddd

# van: http://invece.org/tclwise/extending_tcl_in_tcl.html
# ander idee is de item variable met upvar te doen:
# upvar 1 $item item2
# note: gebruik geen return in de body, anders is het na het eerste item afgelopen.
proc map2 {varname mylist body} {
    upvar 1 $varname var
    set res {}
    foreach var $mylist {
      # puts "var: $var"  
			lappend res [uplevel 1 $body]
    }
		# puts "res: $res"
    return $res
}

# hiermee werkt:
# set a 23
#% map2 x [list 1 2 3] {expr $x + $a}
#24 25 26

  

  
}
