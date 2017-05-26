# Generate a (text) file based on a template.
# Used for suite.xml files.

package require Itcl

source [file join $env(CRUISE_DIR) checkout lib perflib.tcl]
source [file join $env(CRUISE_DIR) checkout script lib CLogger.tcl]

# class maar eenmalig definieren
if {[llength [itcl::find classes CTemplateFile]] > 0} {
	return
}

# vooral bedoeld om output XML van Lqn te parsen.
# later evt ook de asymptoten berekening direct op de (input) XML doen.
itcl::class CTemplateFile {

	private common log
	set log [CLogger::new_logger templatefile info]

	private common MAX_ITER_REPLACE_LINE 10

	public proc new_ctemplatefile {} {
		set result [uplevel {namespace which [CTemplateFile #auto ""]}]
		return $result
	}

	private variable template_filename
	private variable ar_properties ; # list of name/value pairs to fill in the lqn model

	

	public constructor {a_template_filename} {
		set_template_filename $a_template_filename
	}

	public method set_template_filename {a_template_filename} {
		set template_filename $a_template_filename
	}

	public method get_template_filename {} {
		return $template_filename
	}
	
	public method read_properties {properties_filename} {
		set f [open $properties_filename r]
		while {![eof $f]} {
			gets $f line
			set line [string trim $line]
			if {[regexp {^#} $line]} {
				continue
			}
			if {[regexp {^([^=]+)=(.*)$} $line z name value]} {
				# lappend lqn_properties [list [string trim $name] [string trim $value]]
				set_property [string trim $name] [string trim $value]
			}
		}
		close $f	
	}
	
	public method set_property {a_name a_value} {
		set ar_properties($a_name) $a_value
	}
	
	# nu hele file in 1 keer inlezen in een string
	public method make_file {a_filename} {
		set text [read_file $template_filename]

		set text [include_files $text]

		set text_prev "<unknown>"
		set iter_replace_text 0
		while {($text != $text_prev) && ($iter_replace_text < $MAX_ITER_REPLACE_LINE)} {
			incr iter_replace_text
			set text_prev $text
			foreach prop_name [array names ar_properties] {
				set text [replace_line $text $prop_name $ar_properties($prop_name)]
			}
		}

		$log debug "text na aanroepen replace_line: $text"
		# ook expressies kunnen genest worden, dus ook meerdere keren.
		set text_prev "<unknown>"
		set iter_replace_text 0
		while {($text != $text_prev) && ($iter_replace_text < $MAX_ITER_REPLACE_LINE)} {
			incr iter_replace_text
			set text_prev $text
			set text [expr_line $text]
		}		

		$log debug "text na aanroepen expr_line: $text"
		file mkdir [file dirname $a_filename]
		set fo [open $a_filename w]
		puts $fo $text
		close $fo	
	}

	private method include_files {text} {
		# template_filename is instance-var, use for path determination.
		# includes staan tussen @[INCLUDE en ]@ paren.
		if {[regexp {^(.*)@\[INCLUDE ([^\]@]+)\]@(.*)$} $text z str_before str_include_file str_after]} {
			set str_before [include_files $str_before]
			set str_after [include_files $str_after]
			set text_included_file [read_file $str_include_file]
			return "$str_before[include_files $text_included_file]$str_after"
		} else {
			return $text
		}		
	}

	# @param line can also be the whole text.
	private method replace_line {line var_name var_value} {
		set $var_name $var_value
		set re "\\$\\{$var_name\\}"
		# regsub -all "\$\{$var_name\}" $line $var_value line
		regsub -all $re $line $var_value line
		# set line [subst $line]
		return $line
	}

	private method expr_line {a_line} {
		# expressies staan tussen @[ en ]@ paren.
		if {[regexp {^(.*)@\[([^@]+)\]@(.*)$} $a_line z str_before str_expr str_after]} {
			set str_before [expr_line $str_before]
			set str_after [expr_line $str_after]
			set str_value [expr $str_expr]
			return "$str_before$str_value$str_after"
		} else {
			return $a_line
		}
	}

	# @filename path relative to template filename, can be template filename itself.
	private method read_file {filename} {
		set path [file join [file dirname $template_filename] $filename]
		set fi [open $path r]
		set text [read $fi]
		close $fi
		return $text
	}

	# 29-1-2008 expand macro's voorlopig helemaal los
		private variable interp
		private variable in_script
		private variable script
		private variable fo

		public method expand_template {gen_filename} {
				set interp [interp create]

				set fi [open $template_filename r]
				set fo [open $gen_filename w]

				set in_script 0

				# <tcl> moet eerste stuk van een regel zijn.
				# </tcl> moet laatste stuk van een regel zijn.
				while {![eof $fi]} {
						gets $fi line
						handle_line $line
				}
				
				close $fi
				close $fo
		}

		private method handle_line {line} {
				set trim_line [string trim $line]
				if {$in_script} {
						if {[regexp {^(.*)</tcl>$} $trim_line z rest_line]} {
								handle_line $rest_line
								handle_script
								set in_script 0
						} else {
								append script "${line}\n"
						}
				} else {
						if {[regexp {^<tcl>(.*)$} $trim_line z rest_line]} {
								set in_script 1
								set script ""
								handle_line $rest_line
						} else {
								puts $fo $line
						}
				}
		}

		private method handle_script {} {
				set result [$interp eval $script]
				puts $fo $result
		}

}

proc main {argc argv} {
  # check_params $argc $argv
  # set template_filename [lindex $argv 0]
  # set result_dirname [lindex $argv 1]

	if {0} {
		set ctmpfile [CTemplateFile \#auto [lindex $argv 0]]
		$ctmpfile read_properties [lindex $argv 1]
		$ctmpfile make_file [lindex $argv 2]
	}
	
	if {1} {
		set in_filename [lindex $argv 0]
		set gen_filename "$in_filename.gen"	
		set tmp_file [CTemplateFile \#auto $in_filename]
		$tmp_file expand_template $gen_filename
	}	
}

proc check_params {argc argv} {
  global env argv0
  if {$argc != 3} {
    fail "syntax: $argv0 <template_filename> <props_filename> <out_filename>; got $argv \[#$argc\]"
  }
}

# aanroepen vanuit Ant, maar ook mogelijk om vanuit Tcl te doen.
if {[file tail $argv0] == [file tail [info script]]} {
  main $argc $argv
}
