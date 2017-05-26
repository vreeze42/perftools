# Tijdelijke versie voor chk_par_calls: als goed dan in main opnemen.
# Nu voornamelijk om ook milliseconden mee te nemen.

# CTimestamp.tcl
# set date once, and time repeatedly. Adjust date when necessary. Provide format functions.

package require Itcl

# source ../lib/perflib.tcl
source [file join $env(CRUISE_DIR) checkout lib perflib.tcl]

# class maar eenmalig definieren
if {[llength [itcl::find classes CTimestamp]] > 0} {
	return
}

addLogger timestamp
setLogLevel timestamp info
# setLogLevel timestamp debug

# usage:
# 	set ctimestamp [CTimestamp::new_timestamp]
#   $ctimestamp set_qmon_datetime $line

itcl::class CTimestamp {

  private common logtype "timestamp"
  # MONTH_LIST not necessary yet, Tcl can parse nmon date directly (16-NOV-2006).
  # private common MONTH_LIST [list jan feb mar apr may jun jul aug sep oct nov dec]
  
  public proc new_timestamp {{other null}} {
 		set result [uplevel {namespace which [CTimestamp #auto]}]
		if {$other != "null"} {
			$result set_from $other
		}
    return $result
  }

	private variable sec_date

	# sec_time contains only the time, not the current date, so correct value returned by clock scan
	# if time is 01:00, sec_time is 3600. With clock format the -gmt true option is needed.
	private variable sec_time
	private variable msec_time

	private variable datetime_formatted

	private variable SECONDS_IN_DAY

	# door private constructor is deze niet meer van buiten aan te roepen...
	private constructor {} {
		set sec_date 0
		set sec_time 0
		set msec_time 0
		set SECONDS_IN_DAY [expr 24 * 60 * 60]
	}

	public method set_from {other} {
		set sec_date [$other get_sec_date]
		set sec_time [$other get_sec_time]
		set msec_time [$other get_msec_time]
	}

	public method get_sec_date {} {
		return $sec_date
	}

	public method get_sec_time {} {
		return $sec_time
	}

	public method get_msec_time {} {
		return $msec_time
	}

	# determine seconds (incl milliseconds as fraction) since epoch
	public method det_sec_abs {} {
		if {$msec_time == ""} {
			fail "msec_time is empty"
		}
		# return [expr ($sec_date + $sec_time + (0.001 * $msec_time))]
		# als string doen.
		return "[expr $sec_date + $sec_time].[format %03d $msec_time]"
	}

	# %d-%m-%Y-%H:%M:%S: plotfile format.
	public method set_datetime {a_datetime} {
		if {[regexp {^([0-9]{2})-([0-9]{2})-([0-9]{4})-(.*)$} $a_datetime z dd mm yyyy time]} {
			set sec_date [clock scan $yyyy$mm$dd]
			set sec_time [scan_time $time]
		} else {
			log "ERROR: Could not parse datetime: $a_datetime" error timestamp
			set_null
		}
	}

  public method is_datetime {a_datetime} {
		if {[regexp {^([0-9]{2})-([0-9]{2})-([0-9]{4})-(.*)$} $a_datetime]} {
		  return 1
		} else {
      return 0
    }  
  }

	# nmon_date: 22/06/06
	# nmon_date: 16-NOV-2006
	public method set_nmon_date {nmon_date} {
		if {[regexp {^([0-9]{2})/([0-9]{2})/([0-9]{2})$} $nmon_date z dd mm yy]} {
			# dd/mm/yy
			set sec_date [clock scan $yy$mm$dd]
		} elseif {[regexp {^([0-9]{2})-([a-zA-Z]{3})-([0-9]{4})$} $nmon_date z dd mmm yyyy]} {
			# dd-MMM-yyyy, Tcl can scan this directly
			set sec_date [clock scan $nmon_date]
		} else {
			log "ERROR: Could not parse nmon_date: $nmon_date" error timestamp
			set_null
		}
	}

	# date : 01-03-2006
	public method set_date {adate} {
		if {[regexp {^([0-9]{2})-([0-9]{2})-([0-9]{4})$} $adate z dd mm yyyy]} {
			set sec_date [clock scan $yyyy$mm$dd]
		} else {
			log "ERROR: Could not parse date: $adate" error timestamp
			set_null
		}
	}

	# @param time: 12:13:14
	public method set_time {time} {
		# set sec_new_time [clock scan $time]
		set sec_new_time [scan_time $time]
		if {$sec_time == 0} {
			# first timestamp, don't adjust date
		} elseif {$sec_new_time < $sec_time} {
			# a new day, adjust sec_date
			set sec_date [clock scan "1 day" -base $sec_date]
		} else {
			# nothing
		}
		set sec_time $sec_new_time
	}

	# line: 2006-07-04-19:59:46
	public method set_qmon_datetime {line} {
		if {[regexp {^([0-9]{4})-([0-9]{2})-([0-9]{2})-(.*)$} $line z yyyy mm dd time]} {
			set sec_date [clock scan $yyyy$mm$dd]
			set sec_time [scan_time $time]
		} else {
			# fail "ERROR: Could not parse qmon_datetime: $line"
			log "ERROR: Could not parse qmon_datetime: $line" error timestamp
			set_null
		}
	}

	# strdtjm: 2006/01/11 19:04:30
	public method set_jmeter_datetime {strdtjm} {
		if {[regexp {^([0-9]{4})/([0-9]{2})/([0-9]{2}) (.*)$} $strdtjm z yyyy mm dd time]} {
			set sec_date [clock scan $yyyy$mm$dd]
			set sec_time [scan_time $time]
		} else {
			# fail "ERROR: Could not parse qmon_datetime: $line"
			log "Could not parse jmeter_datetime: $strdtjm" warn timestamp
			set_null
		}
		log "1. sec_date: $sec_date; sec_time: $sec_time" debug timestamp
	}

  # cctimestamp: 20060803180500
  public method set_cctimestamp {cctimestamp} {
		if {[regexp {^([0-9]{4})([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})$} $cctimestamp z yyyy mm dd hour minute second]} {
			set sec_date [clock scan $yyyy$mm$dd]
			set sec_time [scan_time "$hour:$minute:$second"]
		} else {
			# fail "ERROR: Could not parse qmon_datetime: $line"
			log "Could not parse cctimestamp: $cctimestamp" warn $logtype
			set_null
		}
  }

	# @param str: 2007-09-10 17:19:56,307
	# @note: door greedy 0* komen er geen voorloopnullen in msec.=> dit werkt dus niet.
	public method set_portals_log_timestamp {str} {
		if {[regexp {^([0-9]{4})-([0-9]{2})-([0-9]{2}) (.{8}),([0-9]{3})$} $str z yyyy mm dd time msec]} {
			set sec_date [clock scan $yyyy$mm$dd]
			set sec_time [scan_time $time]
			# voorloopnullen verwijderen nu erg vreselijk, maar eens anders doen
			while {[regsub {^(0)} $msec "" msec]} {}
			if {$msec == ""} {
				set msec 0
			}
			if {[regexp {^0.} $msec]} {
				fail "msec starts with 0: $msec; str=$str"
			}

			set msec_time $msec
		} else {
			# fail "ERROR: Could not parse qmon_datetime: $line"
			log "Could not parse jmeter_datetime: $strdtjm" warn timestamp
			set_null
		}
	}


	public method add_seconds {seconds} {
    set seconds [expr round($seconds)]
		log "2. sec_date: $sec_date; sec_time: $sec_time" debug timestamp
		set sec_time [clock scan "$seconds seconds" -base $sec_time]
		log "3. sec_date: $sec_date; sec_time: $sec_time" debug timestamp
		# post: sec_new_time will be bigger than sec_time, if seconds > 0. So check for a new day needs to be different.
		while {($seconds > 0) && ($sec_time >= $SECONDS_IN_DAY)} {
			set sec_time [expr $sec_time - $SECONDS_IN_DAY]n
			set sec_date [clock scan "1 day" -base $sec_date]
			log "4. sec_date: $sec_date; sec_time: $sec_time" debug timestamp
		}

		while {($seconds < 0) && ($sec_time < 0)} {
			set sec_time [expr $sec_time + $SECONDS_IN_DAY]
			set sec_date [clock scan "-1 day" -base $sec_date]
		}
		log "5. sec_date: $sec_date; sec_time: $sec_time" debug timestamp
	}

	# @param milliseconds: can be negative..
	public method add_milliseconds {milliseconds} {
		set msec_time [expr round($msec_time + $milliseconds)]
		# if msec's >= 1000 or negative, adjust the seconds and milliseconds
		if {($msec_time >= 1000) || ($msec_time < 0)} {
			set extra_seconds [expr floor(0.001 * $msec_time)] ; # 5800 -> 5
			set msec_time [expr round($msec_time - (1000 * $extra_seconds))]
			add_seconds $extra_seconds
		}

	}

	# @return this.time - other.time in seconds, can include msec's as fraction.
	public method det_msec_diff {other} {
		return [expr round(1000 * ([det_sec_abs] - [$other det_sec_abs]))]
	}

	public method is_before {other} {
		if {[det_msec_diff $other] < 0} {
			return 1
		} else {
			return 0
		}
	}


	# clock scan also returns current date, with this method, the date is stripped.
	private method scan_time {time} {
		return [expr [clock scan $time] - [clock scan "0:00:00"]]
	}

  public method is_null {} {
    if {($sec_date == 0) && ($sec_time == 0)} {
      return 1
    } else {
      return 0
    }    
  }

	public method set_null {} {
		set sec_date 0
		set sec_time 0
	}

	public method format_timestamp_plot {} {
		# gnuplot.m: set timefmt "%d-%m-%Y-%H:%M:%S"
    if {[is_null]} {
      # timestamp not set yet, return empty string.
      return ""
    } else {		
		  return "[clock format $sec_date -format "%d-%m-%Y"]-[clock format $sec_time -format "%H:%M:%S" -gmt true]"
		}
	}

	public method format_database {} {
    if {[is_null]} {
      # timestamp not set yet, return null
      return "null"
    } else {		
		  return "[clock format $sec_date -format "%Y-%m-%d"] [clock format $sec_time -format "%H:%M:%S" -gmt true]"
		}
	}

	public method format_milliseconds {} {
    if {[is_null]} {
      # timestamp not set yet, return empty string.
      return ""
    } else {		
		  return "[clock format $sec_date -format "%d-%m-%Y"] [clock format $sec_time -format "%H:%M:%S" -gmt true],[format %03d $msec_time]"
		}
	}

	# was_datetime : 9/28/05 14:05:58:364 CEST
	# month can be one or two digits, day maybe too, and hour also.
	public method is_after_waslogdatetime {was_datetime} {
		set can_this "[clock format $sec_date -format "%Y-%m-%d"]-[clock format $sec_time -format "%H:%M:%S" -gmt true]"

		if {[regexp {^([0-9]+)/([0-9]+)/([0-9]+) ([0-9]+:[0-9]+:[0-9]+)} $was_datetime z mm dd yyyy time]} {
			if {[string length $mm] == 1} {
				set mm "0$mm"
			}
			if {[string length $dd] == 1} {
				set dd "0$dd"
			}
			if {[string length $time] == 7} {
				set time "0$time"
			}
			if {[string length $yyyy] == 2} {
				set yyyy "20$yyyy"
			}
			set can_was "$yyyy-$mm-$dd-$time"
		} else {
			# it's possible a line doesn't start with a timestamp, for instance within a stacktrace.
			# in this case, don't use the log.
			# 'Exception' can be part of the text, so don't check anymore in maakindex.html.
			log "cannot parse waslog datetime: $was_datetime" warn timestamp
			return 1 ; # so is_too_early will be true and log will not be used.
		}

		if {$can_this > $can_was} {
			return 1
		} else {
			return 0
		}
	}




}


