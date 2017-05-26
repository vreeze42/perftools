# Statistics library functions.

package require Itcl

source [file join $env(CRUISE_DIR) checkout lib perflib.tcl]


# class maar eenmalig definieren
if {[llength [itcl::find classes StatsCalc]] > 0} {
		return
}

# @todo: hele max waarde weg halen, als increase_slot_max goed werkt.

source [file join $env(CRUISE_DIR) checkout script lib CLogger.tcl]

itcl::class StatsCalc {
	private common log
	set log [CLogger::new_logger [file tail [info script]] info]

		private variable nValues
		private variable sumValues
		private variable sumSquares
		private variable minValue
		private variable maxValue
		private variable firstValue
		private variable lastValue

		private variable calcPercentiles
		private variable calcPercentages

		# list of the slots, keep the max-value of each slot.
		# private variable lstSlots
		private variable arCountSlot
		private variable slotMin
		private variable slotMax
		private variable slotSize
		private variable slotFormat

		# bigger slots after max value
		# @todo further program/make/build/implement big slots.
		private variable big_slot_size
		private variable slot_max_big

		private variable lstPercentages
		private variable arCountPercentages
		private variable perc_factor

		private variable description

		public proc new_StatsCalc {{adescription "<none>"}} {
				$log debug "new_statsCalc: start"
				set result [uplevel {namespace which [StatsCalc \#auto]}]
				$result set_description $adescription
				$log debug "new_statsCalc: end"
				return $result
		}

		private constructor {} {
				clearValues
				set perc_factor(98) 2.054
		}

		private method set_description {adescription} {
				set description $adescription
		}

		public method clearValues {} {
				set nValues 0
				set sumValues 0
				set sumSquares 0
				# set minValue "NaN"
				# set maxValue "NaN"
				# minValue and maxValue are floats, also for inserting in DB.
				set minValue 0
				set maxValue 0
				set firstValue "NaN"
				set lastValue "NaN"

				set calcPercentiles 0
				set calcPercentages 0
		}

		# init calculation of using percentiles
		# must me called before any values are added
		public method initPercentiles {aminValue amaxValue aslotSize {a_big_slot_size 0}} {
				$log debug "initPercentiles"

				if {$nValues > 0} {
						fail "call initPercentiles before adding values"
				}
				set calcPercentiles 1
				set slotMin $aminValue
				set slotMax $amaxValue
				set slotSize $aslotSize

				if {$a_big_slot_size == 0} {
						set big_slot_size $aslotSize
				} else {
						set big_slot_size $a_big_slot_size
				}

				if {[expr round($slotSize)] == $slotSize} {
						set slotFormat "%d"
				} else {
						# @todo maybe need more than 3 decimals...
						set slotFormat "%.3f"
				}

				# 2-2-2008 nu geen lijst meer van slots, en niet meer array-elements initialiseren, vanwege performance.
		}

		# init calculation of using percentiles
		# must me called before any values are added
		public method initPercentiles_test {aminValue amaxValue aslotSize {a_big_slot_size 0}} {
				set slotMin $aminValue
				set slotMax $amaxValue
				set slotSize $aslotSize
				
				if {0} {
						
						for {set i $slotMin} {$i <= $slotMax} {set i [expr $i + $slotSize]} {
								# call detSlot with round is true, bug in ceil() function causes ceil(0.07)==0.08 
								# set slotUpperValue [detSlot [expr $i + $slotSize] 1]
								# set slotUpperValue [expr $i + $slotSize]
								set a "abc"
						}
				}
				if {1} {
						# test met integer-iteratie
						set n [expr round(($slotMax - $slotMin) / $slotSize)]
						for {set i 0} {$i < $n} {incr i} {
								set val [expr $slotMin + ($i * $slotSize)]
								set a "abc"
						}
				}
				
		}
		
		# init calculation of percentages below the given values.
		# for example the percentage of values below 3 seconds and 5 seconds.
		# must be called before any values are added
		public method initPercentages {lstValues} {
				$log debug "initPercentages"
				
				if {$nValues > 0} {
						fail "call initPercentages before adding values"
				}
				set calcPercentages 1

				set lstPercentages $lstValues
				foreach el $lstPercentages {
						set arCountPercentages($el) 0
				}
		}

		# get percentages from cproperties
		public method init_percentages_props {cprops} {
				set mt [$cprops get_property "testsuite.maxtimes" "2.0"]
				set maxtimes_def [split $mt ";"]
				initPercentages $maxtimes_def		
		}

		public method add {x} {
				# log "adding value: $x" debug statslib
				
				incr nValues
				if {$nValues == 1} {
						set minValue $x
						set maxValue $x
						set firstValue $x
				} else {
						if {$x < $minValue} {
								set minValue $x
						} elseif {$x > $maxValue} {
								set maxValue $x
						}
				}
				set sumValues [expr $sumValues + $x]
				set sumSquares [expr $sumSquares + ($x * $x)]
				set lastValue $x

				if {$calcPercentiles} {
						addPercentile $x
				}

				if {$calcPercentages} {
						addPercentage $x
				}
		}

		private method addPercentile {x} {
				set slot [detSlot $x]
				#if {$slot == 0} {
				#	puts "x = $x => slot = $slot"
				#}
				# debugArCountSlot

				if {0} {
						if {$slot == "max"} {
								# value is bigger than current maxSlot: increase max slot and try again.
								$log debug "slot van $x is max, increase_slot_max callen..."
								increase_slot_max $x
								# try again
								set slot [detSlot $x]
								$log debug "slot gezet op $slot bij $x"
						}
				}
        if {[array get arCountSlot $slot] != {}} {
          incr arCountSlot($slot)
        } else {
          set arCountSlot($slot) 1
        }
		}

		private method debugArCountSlot_old {} {
				$log debug "Contents of arCountSlot"
				foreach el $lstSlots {
						$log debug "$el => $arCountSlot($el)"
				}
		}

		# geen min en max meer gebruiken.
		private method detSlot {x {round 0} {nomax 0}} {
				if {$round} {
						set result [formatSlot [expr round(1.0 * $x / $slotSize) * $slotSize]]
				} else {
						set result [formatSlot [expr ceil(1.0 * $x / $slotSize) * $slotSize]]
				}
				# log "detSlot of $x => $result" debug statslib
				return $result
		}

		private method detSlot_old {x {round 0} {nomax 0}} {
				# # @todo maybe rounding here is a problem, if the result is something like 1.0000000000001
				if {$x <= $slotMin} {
						set result "min"
				} elseif {($x > $slotMax) && ($nomax == 0)} {
						set result "max"
				} else {
						if {$round} {
								set result [formatSlot [expr round(1.0 * $x / $slotSize) * $slotSize]]
						} else {
								set result [formatSlot [expr ceil(1.0 * $x / $slotSize) * $slotSize]]
						}
				}
				# log "detSlot of $x => $result" debug statslib
				return $result
		}
		
		# increase max value of slots, make more slots.
		private method increase_slot_max_old {x} {
				# set lstSlots [list min]
				# haal laatste item van lstSlots weg (nl. max)
				set lstSlots [lreplace $lstSlots end end]

				set lastSlot ""

				set max [lindex $lstSlots end]
				# 23-8-2006 (NdV) door afrondingsfouten de check aangepast van $max < $x naar $max <= $x.
				while {$max <= $x} {
						set max [expr $max + $slotSize]
						# detSlot: round = 1, nomax = 1, don't want 'max' returned here.
						set slotUpperValue [detSlot $max 1 1]
						$log debug "making slot (increase_slot_max, new value = $x, $description): $slotUpperValue"
						lappend lstSlots $slotUpperValue
						set arCountSlot($slotUpperValue) 0
						if {$slotUpperValue == $lastSlot} {
								$log critical "Slot is the same as previous (increase_slot_max): $slotUpperValue == $lastSlot"
								fail "Slot is the same as previous (increase_slot_max)"
						}
						set lastSlot $slotUpperValue
				}
				set slotMax $max
				if {$lastSlot != "max"} {
						lappend lstSlots max
				}
				set arCountSlot(max) 0
		}


		private	method formatSlot {slot} {
				if {$slotFormat == "%d"} {
						set slot [expr round($slot)]
				}
				return [format $slotFormat $slot]
		}

		private method addPercentage {x} {
				foreach el $lstPercentages {
						if {$x <= $el} {
              if {[array get arCountPercentages $el] != {}} {
								  incr arCountPercentages($el)
              } else {
                set arCountPercentages($el) 1
              }
						}
				}
		}

		public method nValues {} {
				return $nValues
		}

		public method avg {} {
				if {$nValues > 0} {
						return [expr $sumValues / $nValues]
				}	else {
						return "NaN"
				}
		}

		public method std {} {
				if {$nValues == 0} {
						return "NaN"
				} elseif {$nValues == 1} {
						return [avg]
				} else {
						# return Math.sqrt(((nValues * sumSquares) - (sumValues * sumValues))) / (nValues - 1);
						$log debug "calc std: sqrt((($nValues * $sumSquares) - ($sumValues * $sumValues))) / ($nValues - 1)"
						# return [expr sqrt((($nValues * $sumSquares) - ($sumValues * $sumValues))) / ($nValues - 1)]
						set square [expr (($nValues * $sumSquares) - ($sumValues * $sumValues))]
						if {$square >= 0.0} {
								return [expr sqrt($square) / ($nValues - 1)]
						} else {
								return 0.0; # rounding failure.
						}
				} 
		}

		public method min {} {
				return $minValue
		}

		public method max {} {
				return $maxValue
		}

		public method first {} {
				return $firstValue
		}

		public method last {} {
				return $lastValue
		}

		public method total {} {
				return $sumValues
		}

		# calculate the percentile using the slots
		# percentile is given as a percentage, so 98% is given as 98, not 0.98.
		# @return a value, could be min or max value of dataset, not literal string constant 'min' or 'max'
		public method getPercentile {percentile} {
				set neededCount [expr ($percentile / 100.0) * $nValues]
				set count 0
				set i 0

				
				set slot [detSlot $minValue]
				set slot_prev $slot
				while {($count < $neededCount) && ($slot <= $maxValue)} {
						# set slot [lindex $lstSlots $i]
						# set count [expr $count + $arCountSlot($slot)]
						# beetje magic nu: array get levert lege lijst als element niet gevonden; deze vooraan in expressie, dan werkt + goed
						# als werkt, dan een testje met incr 0 vantevoren, kijken wat sneller is.
						set count [expr [lindex [array get arCountSlot $slot] 1] + $count]
																		 
						# incr i
						set slot_prev $slot
						set slot [detSlot [expr $slot + $slotSize]]
						if {$slot == $slot_prev} {
								$log error "Slot equals previous: $slot, $slotSize, [expr $slot + $slotSize], [detSlot [expr $slot + $slotSize]]"
								# dan zorgen dat 'ie toch verder gaat:
								set slot [detSlot [expr $slot + (5 * $slotSize)]]
						}
				}
				return [slot_to_float $slot_prev]		
		}

		public method getPercentile_old {percentile} {
				set neededCount [expr ($percentile / 100.0) * $nValues]
				set count 0
				set i 0
				while {$count < $neededCount} {
						set slot [lindex $lstSlots $i]
						set count [expr $count + $arCountSlot($slot)]
						incr i
				}
				return [slot_to_float $slot]		
		}

		
		private method slot_to_float {slot} {
				if {$slot == "min"} {
						# log "slot is min, return minvalue: $minValue" info statslib
						return $minValue
				} elseif {$slot == "max"} {
						return $maxValue
				} else {
						return $slot
				}
		}

		# calculate the percentile using the slots
		# percentile is given as a percentage, so 98% is given as 98, not 0.98.
		public method get_percentiles {lst_percentiles ar_resptimes_name} {
				upvar $ar_resptimes_name ar_resptimes

				# even simpel, perf misschien niet optimaal
				foreach percentile $lst_percentiles {
						set ar_resptimes($percentile) [getPercentile $percentile]
				}
		}

		public method get_percentiles_old {lst_percentiles ar_resptimes_name} {
				upvar $ar_resptimes_name ar_resptimes
				set n_percentiles [llength $lst_percentiles]
				set i_percentile 0
				set percentile [lindex $lst_percentiles $i_percentile]
				set count_total 0
				set finished 0
				foreach slot $lstSlots {
						set count_total [expr $count_total + $arCountSlot($slot)]
						set percentage [expr 100.0 * $count_total / $nValues]
						while {$percentile < $percentage} {
								set ar_resptimes($percentile) [slot_to_float $slot]
								incr i_percentile
								if {$i_percentile >= $n_percentiles} {
										set finished 1
										break
								}
								set percentile [lindex $lst_percentiles $i_percentile]
						}
						if {$finished} {
								break
						}		
				}
				# vul rest percentiles met maximum waarden
				for {} {$i_percentile < $n_percentiles} {incr i_percentile} {
						set percentile [lindex $lst_percentiles $i_percentile]
						set ar_resptimes($percentile) $maxValue			
				}
		}
		
		# # return a list of the slot and the percentages in the slot.
		# return a list of the slot and the counts of items in the slot.
		public method get_histogram {} {
				set result {}

				set slot [detSlot $minValue]
				set slot_max [detSlot $maxValue]
				while {$slot <= $slot_max} {
						# volgende constructie beetje magic, nodig voor als array elt niet bestaat, leeg + 0 == 0
						lappend result [list $slot [expr [lindex [array get arCountSlot $slot] 1] + 0]]
						set slot [detSlot [expr $slot + $slotSize]]
				}
				return $result
		}

		public method get_histogram_old {} {
				set result {}
				foreach slot $lstSlots {
						# lappend result [list $slot [expr 1.0 * $arCountSlot($slot) / $nValues * 100.0]]
						lappend result [list $slot $arCountSlot($slot)]
				}
				return $result
		}
		
		# estimate the percentile using avg, std, and values of the normal distribution.
		# percentile is given as a percentage, so 98% is given as 98, not 0.98.
		public method estimatePercentile {percentile} {
				return [expr [avg] + $perc_factor($percentile) * [std]]
		}

		public method getPercentage {maxvalue} {
				return [expr 1.0 * $arCountPercentages($maxvalue) / $nValues * 100.0]
		}

		# return a list with the given Values (in initPercentages) and the percentage of the values that
		# fall below or on this value
		public method getPercentages {} {
				set result {}
				foreach el $lstPercentages {
						lappend result [list $el [expr 1.0 * $arCountPercentages($el) / $nValues * 100.0]]
				}
				return $result
		}

}



