package require ndv
package require tdbc::sqlite3

# [2016-07-09 10:09] for parse_ts and now:
use libdatetime
use libfp

# TODO:
# * mtime in files, to check if anything has changed and reread is needed.

# deze mogelijk in libdb:
proc get_sourcedep_db {db_name opt} {
  set existing_db [file exists $db_name]
  set db [dbwrapper new $db_name]
  define_tables_sourcedep $db $opt
  $db create_tables 0 ; # 0: don't drop tables first. Always do create, eg for new table defs. 1: drop tables first.
  if {!$existing_db} {
    log info "New db: $db_name, create tables"
    # create_indexes $db
  } else {
    log info "Existing db: $db_name, don't create tables"
  }
  # TODO: maybe call prepare just before (or within) first insert call.
  $db prepare_insert_statements
  #breakpoint
  return $db
}

# [2016-09-27 17:27:44] zelfde naam als die voor logdb, gaat fout, daarom deze nu anders.
# TODO: met namespaces oplossen.
proc define_tables_sourcedep {db opt} {

  $db def_datatype {.*id .*linenr.*} integer
  
  $db add_tabledef sourcefile {id} {path name mtime size language notes}
  $db add_tabledef proc {id} {sourcefile_id namespace class proctype name linenr_start linenr_end text}
  # project table eerst niet.
  $db add_tabledef statement {id} {proc_id sourcefile_id linenr_start linenr_end text stmt_type callees}
  # fill ref in phase 2.
  $db add_tabledef ref {id} {from_file_id to_file_id from_proc_id to_proc_id from_statement_id reftype notes}
}

proc delete_database {dbname} {
  log info "delete database: $dbname"
  # error nietgoed
  set ok 0
  catch {
    file delete $dbname
    set ok 1
  }
  if {!$ok} {
    set db [dbwrapper new $dbname]
    foreach table [$db tables] {
      $db exec "drop table $table"
    }
    $db close
  }
}

