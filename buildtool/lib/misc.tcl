# Miscellaneous procs
proc puts_warn {srcfile linenr text} {
  puts "[file tail  $srcfile] \($linenr\) WARN: $text"
}

# One generic place to determine perftools dir. Is close to dir of buildtool, but
# in different branch.
# maybe later set in .bld/config.tcl or better in ~/.config/buildtool/env.tcl
proc perftools_dir {} {
  # not sure how deep we are exactly, so check several levels
  set dir [file dirname [info script]]
  while {[string length $dir] > 4} {
	set res [file normalize [file join $dir perftools]]
	# log info "Checking pt dir: $res"
	if {[file exists $res]} {
        # log info "Found: $res"
		return $res
	}
	set dir [file dirname $dir]
  }
  if {![file exists $res]} {
    puts "WARNING: perftools_dir not found: $res"
  }
  return $res
}

proc perftools_dir_old {} {
  set res [file normalize [file join [info script] .. .. .. perftools]]
  if {![file exists $res]} {
    puts "WARNING: perftools_dir not found: $res"
  }
  return $res
}


# puts "perftools_dir: [perftools_dir]"

