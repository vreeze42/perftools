#!/home/nico/bin/tclsh86

package require ndv
package require tdbc::sqlite3
package require Tclx

proc main {argv} {
  global conn stmts
  log debug "argv: $argv"
  set options {
      {dir.arg "" "Source directory (where callgraph.db is in)"}
      {db.arg "callgraph.db" "SQLite DB to read callgraph info from (relative to <dir>"}
      {outdir.arg "../doc" "Directory to put the callgraph into (relative to <dir>"}
  }
  set usage ": [file tail [info script]] \[options] :"
  array set ar_argv [::cmdline::getoptions argv $options $usage]
  set src_dir $ar_argv(dir)
  set db_name [file join $src_dir $ar_argv(db)]
  set conn [open_db $db_name]
  set out_dir [file join $src_dir $ar_argv(outdir)]
  make_callgraph $conn $out_dir
  $conn close
}

proc open_db {db_name} {
  set conn [tdbc::sqlite3::connection create db $db_name]
  return $conn
}

# @todo? use start-node/function?
proc make_callgraph {conn path} {
  global ar_nodes
  set dotname [file join $path "callgraph.dot"]
  set pngname [file join $path "callgraph.png"]
  set f [open $dotname w]
  write_dot_header $f LR
  write_dot_title $f "Call graph"
  foreach dct [db_query $conn "select * from function where not name in (select callee from call where calltype='fsm') order by path, linenr"] {
    set name [dict get $dct name]
    set ar_nodes($name) [puts_node_stmt $f [make_label $dct]] 
  }
  foreach dct [db_query $conn "select distinct caller, callee from call where calltype='direct'"] {
    log debug $dct
    dict_to_vars $dct
    # @todo: edge label of edge type dependent on calltype?
    set caller_id [get_node_id $caller]
    set callee_id [get_node_id $callee]
    if {($caller_id != "") && ($callee_id != "")} {
      puts $f [edge_stmt $caller_id $callee_id]
    }
  }
  write_dot_footer $f
  close $f
  do_dot $dotname $pngname
}

proc get_node_id {name} {
  global ar_nodes
  # breakpoint
  if {[array get ar_nodes $name] == {}} {
    return "" 
  } else {
    return $ar_nodes($name) 
  }
}

proc make_label {dct} {
  log debug "make_label: dct: $dct"
  dict_to_vars $dct 
  return "$name\\n[file tail $path] (#$linenr)"
  # return "$name"
}

main $argv
