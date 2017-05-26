# libdatetime.tcl - date and time functions, especially formatting and parsing.

# general naming of functions:
# parse_XXX - parse a string, return seconds since epoch, possibly using given format.
# format_XXX - format seconds since epoch to a string in a certain timezone and possibly given format.

namespace eval ::libdatetime {
  # namespace export parse_cet parse_ts now
  namespace export parse_ts now
  
  # convert string timestamp in CET timezone to seconds since epoch
  # format of string: 2016-06-09 15:52:22.096
  # @return seconds including milliseconds iff format is ok.
  # @return -1 iff format is not ok.
  # this really is a parse_local_timezone, CET not mentioned in body.
  # @deprecated. [2016-07-31 11:47] Seriously, only cet in winter, only cest in summer.
  # see: https://www.timeanddate.com/time/zones/cest
  # and: https://www.timeanddate.com/time/zones/cet
  proc parse_cet_old {ts_cet} {
    if {[regexp {^([^.]+)(\.\d+)?$} $ts_cet z ts msec]} {
      if {[catch {set sec [clock scan $ts -format "%Y-%m-%d %H:%M:%S"]}]} {
        return -1
      } else {
        if {$msec != ""} {
          expr $sec + $msec
        } else {
          return $sec
        }
      }
    } else {
      return -1
    }
  }

  # generic parse timestamp function, which returns seconds as [clock seconds], but can
  # include msec/usec if given.
  # also parse numeric timezone (+0200 etc)if given, otherwise assume local timezone.
  # so ts_full looks like: <date> <time>[.<msec>][ <timezone>]
  # date is in YYYY-mm-dd format
  # time is in HH:MM:SS format
  # msec/usec are recognised as starting with a . right after seconds part.
  # timezone is recognised as starting with a space after time part (possibly including msec)
  # return -1 iff format of time string is incorrect
  # return -2 iff clock scan fails.
  proc parse_ts {ts_full} {
    if {[regexp {^([^.]{19})(\.\d+)?( .+)?$} $ts_full z ts msec tz]} {
      set format "%Y-%m-%d %H:%M:%S"
      if {$tz != ""} {
        append format " %z"
      }
      if {[catch {set sec [clock scan "$ts$tz" -format $format]}]} {
        return -2
      } else {
        if {$msec != ""} {
          expr $sec + $msec
        } else {
          return $sec
        }
      }
    } else {
      return -1
    }
  }

  # default - the timestamp as can be inserted in sqlite
  # maybe use getoptions processing, but want to keep it fast
  # args - -filename to generate time string to be used in filename.
  #        -gmt to use GMT/UTC time. Can be combined with -filename
  # [2016-10-12 10:36:53] also use milliseconds.
  proc now {args} {
    set options {
	  {filename "Return current time usable in filename"}
	  {gmt "Use GMT/UTC time"}
	}
	set opt [getoptions args $options ""]
    if {[:filename $opt]} {
      clock format [clock seconds] -format "%Y-%m-%d--%H-%M-%S" -gmt [:gmt $opt]
    } else {
      set msec [clock milliseconds]
      set sec [expr $msec / 1000]
      set msec1 [expr $msec % 1000]
      clock format $sec -format "%Y-%m-%d %H:%M:%S.[format %03d $msec1] %z" -gmt [:gmt $opt]
    }
  }

  proc now_old {args} {
    lassign $args arg1 arg2
    if {$arg1 == "-filename"} {
      clock format [clock seconds] -format "%Y-%m-%d--%H-%M-%S"
    } else {
      set msec [clock milliseconds]
      set sec [expr $msec / 1000]
      set msec1 [expr $msec % 1000]
      clock format $sec -format "%Y-%m-%d %H:%M:%S.[format %03d $msec1] %z"
    }
  }

  
}
