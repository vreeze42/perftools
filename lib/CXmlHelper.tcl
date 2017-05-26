# Unused; probably safe to delete.
# Helper class for generating XML.

package require Itcl

#	source [file join $env(CRUISE_DIR) checkout lib perflib.tcl]
#	source [file join $env(CRUISE_DIR) checkout script lib CLogger.tcl]

package provide ndv 0.1

namespace eval ::ndv {
	# class maar eenmalig definieren
	if {[llength [itcl::find classes CXmlHelper]] > 0} {
		return
	}
	
	namespace export CXmlHelper
	
	itcl::class CXmlHelper {
		# @todo lukt nog niet CLogger hierbinnen te gebruiken terwijl ze in dezelfde namespace en package zitten.
		#private common log
		#set log [CLogger::new_logger [file tail [info script]] info]
		public proc new {} {
				set result [uplevel {namespace which [::ndv::CXmlHelper \#auto]}]
				return $result	
		}
	
		private variable channel
		private variable level
	
		public constructor {} {
			set channel "<none>"
			set level 0
		}
	
		public method set_channel {a_channel} {
			set channel $a_channel
		}
	
		public method set_level {a_level} {
			set level $a_level
		}
	
		public method tag_start {tagname {attr ""}} {
			if {$attr != ""} {
				puts $channel "[to_spaces $level]<$tagname $attr>"
			} else {
				puts $channel "[to_spaces $level]<$tagname>"
			}
			incr level
		}
	
		public method tag_end {tagname} {
			incr level -1
			puts $channel "[to_spaces $level]</$tagname>"
		}
	
		public method tag_tekst {tagname tekst} {
			puts $channel "[to_spaces $level]<$tagname>[expand_codes $tekst]</$tagname>"
		}
	
		public method tekst {tekst} {
			puts $channel [expand_codes $tekst]
		}
	
		private method to_spaces {level} {
			return [string repeat "  " $level]
		}
	
		private method expand_codes {tekst} {
			regsub -all "&" $tekst {\&amp;} tekst
			regsub -all "<" $tekst {\&lt;} tekst
			regsub -all ">" $tekst {\&gt;} tekst
			return $tekst
		}
	
	}
}


