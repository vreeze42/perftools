use libio

task totabs {Convert spaces to tabs
  Syntax: totabs [ntabs] - convert n tabs to a single tab. Default is 4.
  Handle all source files.
} {
  # default 4 tabs, kijk of in args wat anders staat.
  if {[:# $args] == 1} {
    lassign $args tabwidth
  } else {
    set tabwidth 4
  }
  foreach srcfile [get_source_files]	{
    totabs_file $srcfile $tabwidth
  }
}

proc totabs_file {srcfile tabwidth} {
  set fi [open $srcfile r]
  #set fo [open [tempname $srcfile] w]
  #fconfigure $fo -translation crlf
  set fo [open_temp_w $srcfile]
  while {[gets $fi line] >= 0} {
    puts $fo [totabs_line $line $tabwidth]
  }
  close $fi
  close $fo
  commit_file $srcfile
}

proc totabs_line {line tabwidth} {
  regexp {^([ \t]*)(.*)$} $line z spaces rest
  set width 0
  foreach ch [split $spaces ""] {
    if {$ch == " "} {
      incr width
    } else {
      # tab
      set width [expr (($width / $tabwidth) + 1) * $tabwidth]
    }
  }
  set ntabs [expr $width / 4]
  set nspaces [expr $width - ($ntabs * 4)]
  return "[string repeat "\t" $ntabs][string repeat " " $nspaces]$rest"
}

# TODO: use code in separate tool fix-endings to check more extensions.
# buildtool should also work for other things besides vugen scripts.
task fixcrlf {Fix line endings
  Syntax: fixcrlf [<filename> ..]
  Fix line endings for filenames. Handle all source files if none given.
  Use Windows line endings (CRLF), as both VuGen and PC/ALM run on Windows.
} {
  if {$args == {}} {
    set lst [get_source_files]
  } else {
    set lst $args
  }
  foreach filename $lst {
    fixcrlf_file $filename
  }
}

proc fixcrlf_file {filename} {
  set text [read_file $filename]
  #set fo [open [tempname $filename] w]
  #fconfigure $fo -translation crlf
  set fo [open_temp_w $filename [line_ending $filename]]
  puts -nonewline $fo $text
  close $fo
  commit_file $filename
}

# TODO: use code in separate tool fixendings to check more extensions.
# [2016-07-31 12:28] but not yet, current implementation in fixendings clashes with needs here, eg. .c files.
proc line_ending {filename} {
  set ext [file extension $filename]
  if {[lsearch -exact {.tcl .sh .R .clj .cljs} $ext] >= 0} {
    return lf
  } else {
    return crlf
  }
}

task remove_empty_lines {Remove double empty lines from source files
  Syntax: remove_empty_lines [<filename> ..]
  Clean for filenames. Handle all source files if none given.
} {
  if {$args == {}} {
    set lst [get_source_files]
  } else {
    set lst $args
  }
  foreach filename $lst {
    remove_double_empty_lines $filename
  }
}

proc remove_double_empty_lines {filename} {
  set text [read_file $filename]
  # first replace lines with only spaces and tabs with real empty lines
  set text2 [regsub -lineanchor -all {^[ \t]+$} $text ""]

  # then combinations of 2 empty lines or more with just 1.
  set text3 [regsub -all {\n{3,}} $text2 "\n\n"]
  if {$text != $text3} {
    # write_file [temp_name $filename] $text3 ; # should also work.
    # [2016-07-30 17:10] but leave one below for now, to also use it elsewhere.
    with_file f [open_temp_w $filename] {
      puts -nonewline $f $text3
    }
    commit_file $filename
  }
}

