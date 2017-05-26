# functions for creating dot files (and calling dot)

proc write_dot_header {f {rankdir TB}} {
		puts $f "digraph G \{
		rankdir = $rankdir
/*
		size=\"40,40\";
		ratio=fill;
		node \[fontname=Arial,fontsize=20\];
		edge \[fontname=Arial,fontsize=16\];
*/
    "
  init_dot_lines_once
}

proc write_dot_footer {f} {
	puts $f "\}"
}

proc write_dot_title {f title} {
  puts $f "  title \[shape=rectangle, label=\"$title\", fontsize=18\];"
}

proc set_dot_exe {exe} {
  global DOT_EXE
  set DOT_EXE $exe
}

# TODO: find DOT_EXE iff not set. For now, set in buildtool system specific file.
proc do_dot {dot_file png_file} {
  global tcl_platform DOT_EXE
  #global log ar_argv
  #$log info "Making png $png_file from dot $dot_file"
  #exec [file join $ar_argv(dot_dir) dot.exe] -Tpng $dot_file -o $png_file
  if {$tcl_platform(platform) == "unix"} {
    try_eval {
      exec dot -Tpng $dot_file -o $png_file
    } {
      log warn "dot: $errorResult" 
    }
  } elseif {$tcl_platform(platform) == "windows"} {
    # set DOT_EXE "c:/util/Graphviz2.28/bin/dot.exe"
    try_eval {
      exec $DOT_EXE -Tpng $dot_file -o $png_file
    } {
      log warn "dot: $errorResult" 
    }

  } else {
    puts "tbd" 
  }
}

# algoritme van http://en.wikipedia.org/wiki/Word_wrap 
proc wordwrap {str {wordwrap 60}} {
  # global wordwrap
  if {$wordwrap == ""} {
    return $str
  }
  set spaceleft $wordwrap
  set result ""
  foreach word [split $str " "] {
    if {[string length $word] > $spaceleft} {
      append result "\\n$word "
      set spaceleft [expr $wordwrap - [string length $word]]
    } else {
      append result "$word "
      set spaceleft [expr $spaceleft - ([string length $word] + 1)]
    }
  }
  return $result
}

proc puts_node_stmt {f label args} {
  lassign [node_stmt $label {*}$args] name statement
  puts $f $statement
  return $name  
}

# return list: node name, node statement
# example: node_stmt mynode shape ellipse color black
# @doc pure function
proc node_stmt {label args} {
  set name [sanitise $label]
  list $name "  $name [det_dot_args [concat [list label $label] $args]];"
}

# create one arrow/line from->to, even if called with these params more than once.
# return empty string if called before
proc init_dot_lines_once {} {
  global dot_lines_once
  set dot_lines_once [dict create]                          
}

proc edge_stmt_once {from to args} {
  global dot_lines_once
  if {[dict exists $dot_lines_once "$from/$to"]} {
    if {[regexp trans $from] && [regexp trans $to]} {
      log info "$from->$to already there, not again."
    }
    return ""
  } else {
    dict set dot_lines_once "$from/$to" 1
    return [edge_stmt $from $to {*}$args]
  }
}

# @example: edge_stmt from to color red label abc
proc edge_stmt {from to args} {
  # possible args: label, color, fontcolor
  # return "  $from -> $to \[[join $lst_edge_args ","]\];"
  return "  $from -> $to [det_dot_args $args];"
}

proc det_dot_args {lst_args} {
  set lst_dot_args {}
  foreach {nm val} $lst_args {
    lappend lst_dot_args "$nm=\"$val\"" 
  }
  return "\[[join $lst_dot_args ","]\]"
}

proc sanitise_old {str} {
  regsub -all "/" $str "" str
  regsub -all -- "-" $str "_" str
  regsub -all {\.} $str "_" str
  regsub -all { } $str "_" str
  return "_$str"
}

proc sanitise {str} {
  regsub -all {[^A-Za-z0-9_]} $str "_" str
  return "_$str"
}

# @example: do_list {123 456} {"puts stdout" "set b"}
# 26-12-2011 function below doesn't work correctly, idea needs to be thought about more, some functional stuff.
proc do_list {lst_items lst_procs} {
  #ar_name
  #upvar $ar_name ar
  #set ar(1) 2
  
  upvar up_item item
  foreach item $lst_items procname $lst_procs {
    # need upvar with up_item and braces, otherwise to much eval is done (quoting hell?)
    uplevel 1 {*}$procname {$up_item} 
  }
}

# functional equivalent of if statement.
# not sure if uplevel/expr always works as expected.
proc ifelse {expr iftrue {iffalse ""}} {
  if {[uplevel 1 expr $expr]} {
    return $iftrue 
  } else {
    return $iffalse 
  }
}


