#!/usr/bin/env tclsh

# test-libdb.tcl - test functionality of libdb.tcl, especially user defined functions in sqlite.

package require tcltest
namespace import -force ::tcltest::*

# TODO: zo te zien hebben libs nogal wat onderlinge afhankelijkheden. Oplosbaar?
# mogelijk bij een lib te checken of de log functie beschikbaar is. Zo niet, dan zelf een kleine versie maken, evt een no-op.
source [file join [file dirname [info script]] .. libfp.tcl]
source [file join [file dirname [info script]] .. libdict.tcl]
source [file join [file dirname [info script]] .. CLogger.tcl]
source [file join [file dirname [info script]] .. generallib.tcl]

source [file join [file dirname [info script]] .. libdb.tcl]
source [file join [file dirname [info script]] .. breakpoint.tcl]

source [file join [file dirname [info script]] .. CLogger.tcl]; # again, so log is ok.

set_log_global info
log debug "Starting the tests"

proc testndv {args} {
  global testndv_index
  incr testndv_index
  test test-$testndv_index test-$testndv_index {*}$args
}

proc pi {args} {
  return 3.14159
}

proc iden {args} {
  return $args
}

testndv {pi} 3.14159
testndv {iden 1 2 3} {1 2 3}

# one time setup
set dbname "/tmp/test-libdb.db"
file delete $dbname
set db [dbwrapper new $dbname]
set conn [$db get_conn]
set handle [$conn getDBhandle]
$handle function pi pi
$handle function iden iden

$db exec "create table testtbl (val integer)"
foreach val {11 12 13 14 15} {
  $db exec "insert into testtbl values ($val)"
}

testndv {
  global db handle
  set res [$db query "select val, pi(val) pi from testtbl where val=11"]
  set qpi [:pi [:0 $res]]
  # = $qpi [pi]
  return $qpi
} [pi]

# Tcl functions in DB don't work as aggregate functions.
# [2016-05-27 20:59] this does not work, iden(val) gives 15, val of the last record.
if 0 {
  testndv {
    global db handle
    set query "select count(*) cnt, pi(*) pi, iden(val) iden from testtbl"
    set res [$db query $query]
    log info "res: $res"
    return 1
  } 1
}

# [2016-05-27 20:59] Compiled C library does work, percentile function already available. Compilation on Linux is straighforward, see compile.sh. On Windows
# also fairly easy with Visual Studio 2013, but use a special dev command prompt.
testndv {
  global db
  set res [$db query "select 1 value from testtbl where val=11"]
  log debug "res of select 1: $res"
  return 1
} 1

# [2016-05-28 12:17:00] Using relative path and no extension (.so/.dll) this works on both Linux and Windows.
testndv {
  global db handle
  $handle enable_load_extension 1
  set res [$db query "select load_extension('../sqlite-functions/percentile')"]
  log debug "res of select 1: $res"
  return 1
} 1

# percentile() works with interpolation between closest values.
testndv {
  global db
  set query "select count(*) cnt, percentile(val, 95) perc from testtbl"
  set res [$db query $query]
  log debug "res of percentile: $res"
  dict get [lindex $res 0] perc
} 14.8

$db close
file delete $dbname

# [2017-05-07 18:42] create DB on the fly and tables also on the fly
testndv {
  set dbname "/tmp/test-libdb-fly.db"
  file delete $dbname
  set db [dbwrapper new $dbname]
  $db insert table1 [dict create field1 abc field2 123]
  $db insert table1 [dict create field1 def field2 456]
  set query "select count(*) cnt from table1"
  set res [$db query $query]
  set cnt [dict get [lindex $res 0] cnt]
  $db close
  file delete $dbname
  iden $cnt
} 2

set ddl_tcl "proc get_db {db_name opt} {
  set existing_db \[file exists \$db_name\]
  set db \[dbwrapper new \$db_name\]
  # define tables
  # table table1: 
  \$db def_datatype {field1} integer 
  \$db def_datatype {field2} integer 
  \$db add_tabledef table1 {id} {field1 field2} 
  # table table2: 
  \$db def_datatype {field3} integer 
  \$db def_datatype {field4} integer 
  \$db add_tabledef table2 {id} {field3 field4}

  \$db create_tables 0 ; # 0: don't drop tables first. Always do create, eg for new table defs. 1: drop tables first.
  if {!\$existing_db} {
    log debug \"New db: \$db_name, create tables\"
    # create_indexes \$db
  } else {
    log debug \"Existing db: \$db_name, don't create tables\"
  }
  \$db prepare_insert_statements
  \$db load_percentile
  
  return \$db
}"


testndv {
  set dbname "/tmp/test-libdb-fly.db"
  file delete $dbname
  set db [dbwrapper new $dbname]
  $db insert table1 [dict create field1 abc field2 123]
  $db insert table2 [dict create field3 abc field4 123]
  $db close
  file delete $dbname
  $db get_ddl_tcl
} $ddl_tcl


cleanupTests
