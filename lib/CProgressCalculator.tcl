package require Itcl

# source [file join $env(CRUISE_DIR) checkout lib perflib.tcl]

source [file join [file dirname [info script]] CLogger.tcl]

# class maar eenmalig definieren
if {[llength [itcl::find classes CProgressCalculator]] > 0} {
	return
}

itcl::class CProgressCalculator {

	#private common log
	#set log [CLogger::new_logger progress perf]

	public proc new_instance {} {
 		set instance [uplevel {namespace which [CProgressCalculator #auto]}]
    return $instance		
	}
	
	private variable time_start
	private variable items_total
	
	# remember info from last call, to determine remaining time based on last time-slot also.
	# could also use a sliding average, but keep it simple for now.
	private variable time_last
	private variable item_last
		
	public constructor {} {
		set time_start -1
		set time_last -1
		set items_total -1
		set item_last -1
	}
	
	# need an estimate of total items to calculate total time
	public method set_items_total {a_items_total} {
		set items_total $a_items_total
	}
	
	public method start {} {
		set time_start [clock seconds]
		set time_last $time_start
		set item_last 0
		log perf "Started calculating remaining time..."
	}

	public method at_item {item_current} {
    log perf "At item: $item_current/$items_total"
		if {$item_current > $items_total} {
			log warn "Current item > total items: $item_current > $items_total"
			return
		}
		if {$item_current < 1} {
			log warn "Current item < 1: $item_current"
			return
		}
			
		set time_now [clock seconds]
		if {$item_last != -1} {
			# calc based on last slot: remaining items * (diff_time / diff_items)
			set sec_remaining [expr int(($items_total - $item_current) * (1.0 * ($time_now - $time_last) / ($item_current - $item_last)))]
			log_eta "ETA (last)" $time_now $sec_remaining
			log perf "Remaining sec (last): [format %.0f $sec_remaining]"
		}
		if {$time_start != -1} {
			# calc based on total time remaining items * (total_time / item_current)
			set sec_remaining [expr int(($items_total - $item_current) * (1.0 * ($time_now - $time_start) / $item_current))]
			log_eta "ETA (all) " $time_now $sec_remaining
			log perf "Remaining sec (all) : [format %.0f $sec_remaining]"
		}
		set time_last $time_now
		set item_last $item_current
	}
	
	private method log_eta {msg sec_now sec_remaining} {
		set sec_eta [expr $sec_now + $sec_remaining]
		log perf "$msg: [clock format $sec_eta]"
	}
	
}
