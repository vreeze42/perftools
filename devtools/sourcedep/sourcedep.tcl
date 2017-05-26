#!/usr/bin/env tclsh

# TODO:
# Checks of procs worden geraakt vanuit de root. Ook over alle projecten heen.

package require ndv

require libinifile ini

ndv::source_once sourcedepdb.tcl htmloutput.tcl

use libfp

set_log_global info

set reader_namespaces [list]
set sourcedep_dir [file normalize [file dirname [info script]]]

lappend reader_namespaces [source [file join $sourcedep_dir vugenreader.tcl]]

proc main {argv} {
  set options {
    {rootdir.arg "" "Directory that contains db"}
    {dirs.arg "" "Subdirs within root dir to handle, empty for all (: separated)"}
    {targetdir.arg "sourcedep" "Directory where to generate DB, images, html"}
    {db.arg "sourcedep.db" "SQLite DB to create, relative to targetdir"}
    {deletedb "Delete DB first"}
    {loglevel.arg "info" "Set loglevel"}
  }
  set usage ": [file tail [info script]] \[options] :"
  set opt [getoptions argv $options $usage]
  log set_log_level [:loglevel $opt]
  # make_graphs $dargv
  # First only read into DB. Later also graphs and HTML
  sourcedep $opt
}

proc sourcedep {opt} {
  sourcedep_set_namespaces

  set targetdir [file join [:rootdir $opt] [:targetdir $opt]]
  file mkdir $targetdir
  set dbname [file join $targetdir [:db $opt]]
  # [2016-09-24 10:34] voorlopig altijd db delete.
  if 1 {
    delete_database $dbname
    set db [get_sourcedep_db $dbname $opt]
    read_sources $db $opt
    det_calls $db $opt
    det_include_refs $db
  } else {
    set db [get_sourcedep_db $dbname $opt]
  }
  graph_include_refs $db $opt
  html_output $db $opt
}

proc read_sources {db opt} {
  set rootdir [file normalize [:rootdir $opt]]
  if {[:dirs $opt] != ""} {
    foreach sub [split [:dirs $opt] ":"] {
      read_source_dir $db [file join $rootdir $sub]
    }
  } else {
    read_source_dir $db $rootdir
  }
  #log info "read_sources done, check sourcefiles:"
  #breakpoint
  
  read_vugen_usr $db $rootdir
}

# TODO: find correct place and where to call for this one.
# TODO: includes determined correctly, but calls are not always the same: check which actions are active, and called from project. Normally only Action.c (and vuser_init/end)
proc read_vugen_usr {db rootdir} {
  $db in_trans {
    set usrfile [file join $rootdir "[file tail $rootdir].usr"]
    if {![file exists $usrfile]} {return}
    set usr [ini/read $usrfile]
    set usrfile_id [$db insert sourcefile [dict create path $usrfile name [file tail $usrfile] language vugen]]
    foreach line [ini/lines $usr Actions] {
      if {[regexp {=(.+)$} $line z filename]} {
        insert_vugen_refs $db $usrfile_id $filename
      }
    }
    foreach line [ini/lines $usr ExtraFiles] {
      if {[regexp {^(.+)=$} $line z filename]} {
        insert_vugen_refs $db $usrfile_id $filename
      }
    }
  }
}

proc insert_vugen_refs {db usrfile_id filename} {
  foreach stmt_type {include call} {
    $db insert statement [dict create sourcefile_id $usrfile_id stmt_type $stmt_type callees $filename text "Ref from vugen.usr"]
  }
  # create a ref for the call, includes are handled elsewhere.
  set query "select id from sourcefile where name = '$filename'"
  set to_file_id [:id [first [$db query $query]]]
  assert {$to_file_id > 0}
  $db insert ref [dict create from_file_id $usrfile_id to_file_id $to_file_id \
                      reftype "call"]
}

proc read_source_dir {db dir} {
  # [2016-09-26 10:41:08] ignore hidden dirs, starting with . Was under the assumption that glob did not return these.
  if {[regexp {^\.} [file tail $dir]]} {
    log debug "Ignoring dir: $dir"
    return
  }
  # TODO: add project/sourcetype specific function to determine to-be-ignored files
  
  foreach filename [glob -nocomplain -directory $dir -type f *] {
    set ignore 0
    foreach re {{^pre_cci} {^combined_}} {
      if {[regexp $re [file tail $filename]]} {
        log debug "Ignoring file: $filename"
        set ignore 1
      }
    }
    if {!$ignore} {
      read_source_file $db $filename  
    }
  }
  foreach subdir [glob -nocomplain -directory $dir -type d *] {
    read_source_dir $db $subdir
  }
}

proc read_source_file {db filename} {
  log info "Read sourcefile: $filename"

  global reader_namespaces
  set nread 0
  foreach ns $reader_namespaces {
    if {[${ns}::can_read? $filename]} {
      log debug "Reading $filename with ns: $ns"
      ${ns}::read_sourcefile $filename $db
      set nread 1
      break
    }
  }
  if {$nread == 0} {
    log debug "Could not read (no ns): $filename"
  } else {
    log info "Read sourcefile finished: $filename"
  }
  return $nread
}

# insert ref-records based on include statements, from file to file.
# also a phase 2 action.
proc det_include_refs {db} {
  set query "insert into ref (from_file_id, to_file_id, reftype, from_statement_id)
select st.sourcefile_id, tf.id, 'include' reftype, st.id
from statement st 
join sourcefile tf on st.callees = tf.name"
  $db exec $query
}

# phase 2 - determine calls from one proc to the other:
# - get all proc names from db
# - read each source file again, per line:
# - break up into words and finds refs to procs.
# - if found, insert records statement and ref in db.
proc det_calls {db opt} {
  set proc_info [det_proc_info $db]
  # [2016-09-28 21:03] Handling should be faster if everything is within a transaction.
  $db in_trans {
    foreach sourcefile [get_files_recursive [:rootdir $opt]] {
      det_calls_sourcefile $db $proc_info [file normalize $sourcefile]
    }
  }
}

# return dict: key = procname, value = dict: sourcefile_id, name, linenr_start, linenr_end.
# TODO: handle namespaces and classes (in Tcl)
proc det_proc_info {db} {
  set d [dict create]
  foreach row [$db query "select * from proc"] {
    dict set d [:name $row] $row
  }
  return $d
}

# determine inside which proc def the line/linenr resides.
# TODO: ? don't use DB?
# return dict: proc_id, sourcefile_id, in_body
# in_body: 1 iff in body of proc, not in header/def.
proc det_inside_proc {db sourcefile_id linenr} {
  assert {$sourcefile_id > 0}
  assert {[count $sourcefile_id] == 1}
  set query "select id proc_id, linenr_start
             from proc
             where sourcefile_id = $sourcefile_id
             and $linenr between linenr_start and linenr_end"
  set rows [$db query $query]
  if {[count $rows] == 1} {
    set res [first $rows]
    if {[:linenr_start $res] == $linenr} {
      dict set res in_body 0
    } else {
      dict set res in_body 1
    }
  } else {
    set res [get_sourcefile_rootproc $db $sourcefile_id]
  }
  return $res
}

# get dummy proc which is inside a sourcefile, but outside any proc definitions.
# could already exist, otherwise create.
# return dict same as det_inside_proc
proc get_sourcefile_rootproc {db sourcefile_id} {
  set name "__FILE__"
  set query "select id proc_id, sourcefile_id, 1 in_body
             from proc
             where sourcefile_id = $sourcefile_id
             and name = '$name'"
  set rows [$db query $query]
  if {[count $rows] == 1} {
    return [first $rows]
  } else {
    set proc_id [$db insert proc [vars_to_dict sourcefile_id name]]
    set in_body 1
    return [vars_to_dict proc_id sourcefile_id in_body]
  }
}

# return a list of all files within dir.
# TODO: library function.
proc get_files_recursive {dir} {
  set todo [list $dir]
  set res [list]
  while {[count $todo] > 0} {
    set dir [first $todo]
    set todo [rest $todo]
    lappend todo {*}[glob -nocomplain -directory $dir -type d *]
    lappend res {*}[glob -nocomplain -directory $dir -type f *]
  }
  return $res
}

# determine which calls are being done from within sourcefile to which other (library) procs and insert in DB.
proc det_calls_sourcefile {db proc_info sourcefile} {
  log info "phase 2 - handle $sourcefile"
  set sourcefile_id [:id [first [$db query "select id from sourcefile where path='$sourcefile'"]]]
  if {$sourcefile_id == ""} {
    return; # source file not read in phase 1, also ignore in phase 2.
  }
  assert {$sourcefile_id > 0}
  with_file f [open $sourcefile r] {
    set lines [split [read $f] "\n"]
  }
  set linenr 0
  set lines [remove_comments $lines]
  foreach line $lines {
    incr linenr
    # if {[is_comment $sourcefile $line]} {continue}
    set inside_proc [det_inside_proc $db $sourcefile_id $linenr]
    if {![:in_body $inside_proc]} {continue}; # in header, procname match is of no use.
    set words [get_words $line]
    set stmt_id 0
    foreach word $words {
      set pi [dict_get $proc_info $word]
      if {$pi != ""} {
        assert {[:id $pi] > 0}
        if {$stmt_id == 0} {
          set proc_id [:proc_id $inside_proc]
          set linenr_start $linenr
          set linenr_end $linenr
          set text [string trim $line]
          set stmt_type "call"
          set stmt_id [$db insert statement \
                           [vars_to_dict sourcefile_id proc_id \
                                linenr_start linenr_end text stmt_type]]
        }
        set notes "[file tail $sourcefile]/$linenr -> $pi"
        $db insert ref [dict create from_file_id $sourcefile_id \
                            to_file_id [:sourcefile_id $pi] \
                            from_proc_id $proc_id \
                            to_proc_id [:id $pi] \
                            from_statement_id $stmt_id \
                            reftype [det_reftype $line] notes $notes]
      }
    }
  }
}

# remove both // and /* */ style comments from lines.
# keep resulting blank lines, so calculated line numbers stay the same.
# for this reason, handle by lines, not as complete block.
# nested comments are not allowed, this is C code.
# TODO: assume for now no multiple comments in a line, only one of //, /* or */ occurs in a line.
proc remove_comments {lines} {
  set in_comment 0;             # if we are in commented block at end-of-line
  set res [list]
  foreach line $lines {
    if {$in_comment} {
      if {[regexp {^(.*?)\*/(.*)$} $line z pre post]} {
        # pre is within comment, post after the comment.
        lappend res $post
        set in_comment 0
      } else {
        lappend res "";         # in_comment stays 1
      }
    } else {            # not in comment
      # // and /* can also occur after regular code.
      if {[regexp {^(.*?)//(.*)$} $line z pre post]} {
        lappend res $pre;       # in_comment stays 0
      } elseif {[regexp {^(.*?)/\*(.*)$} $line z pre post]} {
        lappend res $pre
        set in_comment 1
      } else {
        lappend res $line;      # in comment stays 0
      }
    }
  }
  return $res
}

proc det_reftype {line} {
  if {[regexp {\#define} $line]} {
    return "#define"
  }
  return "call"
}

# split line into words, which might be proc names
# return list
# TODO: dependent on programming language.
proc get_words {line} {
  set l [split $line " \t{}\[\]()*^\$\\;:?\""]
  # set res [filter {x {not [empty? $x]}} $l]
  set res [filter [comp not empty?] $l]
  return $res
}

# TODO: dependent on programming language
# TODO: multi-line comments.
proc is_comment {sourcefile line} {
  if {[regexp {^\s*//} $line]} {
    return 1
  }
  return 0
}

# TODO: naar losse file/module, output/graph.
proc graph_include_refs {db opt} {
  set targetdir [file join [:rootdir $opt] [:targetdir $opt]]
  set dotfile [file join $targetdir "includes.dot"]
  set f [open $dotfile w]
  write_dot_header $f LR
  foreach row [$db query "select * from sourcefile"] {
    dict set nodes [:id $row] [puts_node_stmt $f [:name $row]]
  }
  if 0 {
    foreach row [$db query "select * from ref where reftype = 'include'"] {
      puts $f [edge_stmt [dict get $nodes [:from_file_id $row]] \
                   [dict get $nodes [:to_file_id $row]]]
    }
  }
  # also include calls from one source file proc/statement to another.
  set query "select distinct from_file_id, to_file_id, reftype
             from ref
             where from_file_id <> to_file_id
             and reftype not in ('#define')"
  foreach row [$db query $query] {
    puts $f [edge_stmt [dict get $nodes [:from_file_id $row]] \
                 [dict get $nodes [:to_file_id $row]] color [det_color $row]]
    
  }
  write_dot_footer $f
  close $f
  log debug "Before do_dot"
  do_dot $dotfile [file join $targetdir "includes.png"]
}

proc det_color {row} {
  if {[:reftype $row] == "include"} {
    return "black";             # include is the default
  } else {
    return "red";               # call without include is an error, should add include.
  }
}

proc sourcedep_set_namespaces {} {
	global reader_namespaces sourcedep_dir
	
	set reader_namespaces [list]
	
	lappend reader_namespaces [source [file join $sourcedep_dir vugenreader.tcl]]
}


if {[this_is_main]} {
  main $argv  
}

