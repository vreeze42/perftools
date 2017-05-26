proc read_config {filename} {
  set f [open $filename r]
  set d [dict create]
  while {![eof $f]} {
    gets $f line
    if {[regexp {^#} $line]} {
      continue
    }
    if {[regexp {^([^=]+)=(.*)$} $line z nm val]} {
      dict set d [string trim $nm] [string trim $val]
    }
  }
  close $f
  return $d
}

proc get_field_text {node field} {
  if {$node == {}} {
    return "<empty>"
  }
  if {[llength $node] > 1} {
    log warn "More than one node: $node"
    return "<more-than-one>"
  }
  
  set node2 [$node selectNode $field]
  if {$node2 != {}} {
    $node2 text
  } else {
    return "<empty>"
  }
}

proc is_empty {text} {
  if {$text == ""} {
    return 1
  }
  if {$text == "<empty>"} {
    return 1
  }
  return 0
}



