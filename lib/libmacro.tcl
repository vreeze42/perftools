# libmacro.tcl - macro like facilities for Tcl. Compare lisp/clojure.

# package require ndv ; # for now, breakpoint

namespace eval ::libmacro {
  namespace export syntax_quote format_code

  # replace ~$var elements with actual value of var in surrounding scope (uplevel)
  # TODO: (maybe) replace ~[cmd x] constructs?
  # TODO: (maybe) replace ~@$lst, splice operator.
  # TODO: implementation very similar to libfp/eval_closure, so combine something, but first make it work.
  proc syntax_quote {form} {
    set indices [regexp -all -indices -inline {(~@?\$)([A-Za-z0-9_]+)} $form]
    # begin at the end, so when changing parts at the end, the indices at the start stay the same.
    # instead of checking if var usage in body occurs in param list, could also try to eval the var and if it succeeds, take the value. However, the current method seems more right.
    foreach {range_name range_prefix range_total} [lreverse $indices] {
      set varname [string range $form {*}$range_name]
      set prefix [string range $form {*}$range_prefix]
      upvar 1 $varname value
      # set body [string replace $body {*}$range_total $value]
      # TODO: or check value and decide what needs to be done, surround with quotes, braces, etc.
      if {$prefix == {~$}} {
        # standard unquote (~)
        set form [string replace $form {*}$range_total [list $value]]
      } elseif {$prefix == {~@$}} {
        # unquote splice (~@)
        set form [string replace $form {*}$range_total $value]
      } else {
        error "Unknown range_prefix: $range_prefix (form: $form)"
      }
    }
    return $form
  }

  # format/indent code, for now based on tcl and vugen/c code.
  # TODO: handle lines ending with backslash?
  # TODO: does this work on a line basis, or do we need full parse of text?
  proc format_code {text {start_indent 0} {step 2}} {
    set res [list]
    set indent $start_indent
    foreach line [split $text "\n"] {
      lassign [det_indents $indent $line] indent new_indent
      set new_line [indent $indent $step $line]
      # puts "\[$indent,$new_indent\] $new_line"
      lappend res $new_line
      set indent $new_indent
    }
    join $res "\n"
  }

  # determine indent for current and next lines based on current indent and line
  # TODO: don't count braces that start with a backslash
  proc det_indents {indent line} {
    regsub -all {\\[\{\}]} $line "" line
    set nstart [regexp -all {\{} $line]
    set nend [regexp -all {\}} $line]
    set ndiff [expr $nstart - $nend]
    # TODO: maybe check the number of close braces before the first open brace.
    set first_start [lindex [lindex [regexp -inline -indices {\{} $line] 0] 0]
    set first_end [lindex [lindex [regexp -inline -indices {\}} $line] 0] 0]
    set new_indent [expr $indent + $ndiff]
    if {$ndiff <= 0} {
      if {$nstart > 0} {
        # nend also > 0, check first occurence
        if {$first_end < $first_start} {
          # special case, like else or elseif
          set res [list [expr $new_indent - 1] $new_indent]
        } else {
          set res [list $new_indent $new_indent]
        }
      } else {
        # start new indent directly
        set res [list $new_indent $new_indent]
      }
    } else {
      set res [list $indent $new_indent]
    }
    # puts "$nstart/$nend ($first_start,$first_end) => $ndiff => $res"
    return $res
  }

  proc indent {indent step line} {
    if {[string trim $line] == ""} {
      return ""
    }
    if {$step == "\t"} {
      return "[string repeat $step $indent][string trim $line]"
    } else {
      return "[string repeat " " [expr $step * $indent]][string trim $line]"
    }
  }

}

