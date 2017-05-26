# libdb.tcl

# @note/@todo wil TclOO gebruiken, maar conflict met unknown method ivm dict-accessor.
# @note TclOO clash met ndv lib lijkt nu verdwenen... (mss was het het laatste statement in vb (na destroy) die sowieso een fout geeft)

# @todo verder invullen, ook met MySQL.
# doel is libsqlite.tcl overbodig te maken, en alles via dit db wrapper object uit te voeren, dan geen namespace/name clash problemen.

package require TclOO 

# SQlite apparently requires Tcl8.6, so check before.
# Probably because of tdbc.
# So also tdbc::mysql
if {$tcl_version >= 8.6} {
  package require tdbc::sqlite3
  catch {package require tdbc}
  catch {package require tdbc::mysql} ; # mysql not available on (all) laptops.  
  catch {package require tdbc::postgres}
  source [file normalize [file join [file dirname [info script]] libsqlite.tcl]]
} else {
  puts "Don't load sqlite, tcl version too low: $tcl_version"
}

set libdb_scriptdir [file normalize [file dirname [info script]]]

oo::class create dbwrapper {

  # class var, set when loading class
  # TODO: [2016-08-17 10:19:21] check how to use class vars, not trivial apparently
  
  # @doc usage: set conn [dbwrapper new <sqlitefile.db]
  # @doc usage: set conn [dbwrapper new -db <mysqldbname> -user <user> -password <pw>]
  constructor {args} {
    my variable conn dbtype dbname db_insert_statements db_tabledefs
    if {[llength $args] == 1} {
      # assume sqlite
      set dbtype "sqlite3"
      log debug "connect to: [lindex $args 0]"
      if {[catch {
        set conn [tdbc::sqlite3::connection new [lindex $args 0]]        
      }]} {
        set path [lindex $args 0]
        log warn "path: $path, exists: [file exists $path]"
        set parent [file dirname $path]
        log warn "parent: $parent, exists: [file exists $parent]"
        error "Failed to connect to sqlite DB: $args"
      }
      log debug "connected"
      set dbname [lindex $args 0]
    } else {
      # assume mysql
      # 20-6-2015 NdV assume postgres now, don't have MySQL anymore.
      #set dbtype "mysql"
      set dbtype "postgres"
      #set conn [tdbc::mysql::connection new {*}$args]
      set conn [tdbc::postgres::connection new {*}$args]
      set dbname [dict get $args -database]
    }
    set db_insert_statements [dict create]
    set db_tabledefs [dict create]
  }
  
  # @todo destructor gets called in beginning?
  #destructor {
  #  log info "destructor: TODO"
    # close prepared statements and db connection. Or just db connection.
  #}
  
  # @param conn: a tdbc connection.
# constructor {a_conn} {
#   my variable conn
#   set conn $a_conn
# }
  
  method close {} {
    my variable conn
    $conn close
  }

  method get_conn {} {
    my variable conn
    return $conn
  }
  
  method get_db_handle {} {
    my variable conn dbtype
    if {$dbtype == "sqlite3"} {
      $conn getDBhandle
    } elseif {$dbtype == "mysql"} {
      error "Not implemented (yet)"
    } else {
      error "Unknown dbtype: $dbtype" 
    }
  }
  
  method get_dbname {} {
    my variable dbname
    return $dbname
  }
  
  # @todo what if something fails, rollback, exec except/finally clause?
  method in_trans {block} {
    my variable conn
    my exec "begin transaction"
    try_eval {
      uplevel $block
    } {
      log_error "Rolling back transaction and raising error"
      my exec "rollback"
      error "Rolled back transaction"
    }
    my exec "commit"
  }
  
  # @todo getDBhandle does (probably) not work with MySQL.
  # @todo also not sure with Postgres
  method exec {query {return_id 0}} {
    my variable conn
    set stmt [$conn prepare $query]
    set res [$stmt execute]
    $res close
    $stmt close
    if {$return_id} {
      return [[$conn getDBhandle] last_insert_rowid]   
    }
  } 

  # @note 27-9-2013 new method signature (rename to exec in due time)
  # @note replaces exec and exec_try
  # @param args possible list of args: -log -try -returnid
  method exec2 {query args} {
    my variable conn
    set options {
      {log "Log the query before exec"}
      {try "Don't throw error if query fails"}
      {returnid "Return last_insert_rowid (SQLite only?)"}
    }
    set dargv [getoptions args $options ""]
    if {[:log $dargv]} {
      log debug $query 
    }
    try_eval {
      set stmt [$conn prepare $query]
      set res [$stmt execute]
      $res close
      $stmt close
      if {[:returnid $dargv]} {
        return [[$conn getDBhandle] last_insert_rowid]   
      }
    } {
      log warn "db exec failed: $query"
      log warn "errorResult: $errorResult"
      if {[:try $dargv]} {
        # nothing, just log error and continue.
      } else {
        error "db exec failed: $query"
      }
    }
  } 
  
  method exec_try {query {return_id 0}} {
    try_eval {
      my exec $query $return_id
    } {
      log warn "db exec failed: $query"
      log warn "errorResult: $errorResult"
    }
  }

  method prepare_stmt {stmt_name query} {
    my variable db_statements conn
    dict set db_statements $stmt_name [$conn prepare $query]
  }
  
  # @note exec a previously prepared statement
  method exec_stmt {stmt_name dct {return_id 0}} {
    my variable db_statements conn
    set stmt [dict get $db_statements $stmt_name]
    set rs [$stmt execute $dct]
    if {$return_id} {
      $rs close
      return [[$conn getDBhandle] last_insert_rowid]   
    } else {
      set res [$rs allrows -as dicts]
      $rs close
      return $res 
    }
  } 
  
  # @return resultset as list of dicts
  method query {query} {
    my variable conn
    set stmt [$conn prepare $query]
    set rs [$stmt execute]
    set res [$rs allrows -as dicts]
    $rs close
    $stmt close
    return $res
  }

  method def_datatype {regexps datatype} {
    # proc in libsqlite
    def_datatype $regexps $datatype
  }
  
  # @todo idea determine tabledef's from actual table definitions in the (sqlite) db.
  method add_tabledef {table args} {
    my variable db_tabledefs
    set ks [make_table_def_keys $table {*}$args]
    dict set db_tabledefs $table $ks
    if {[:flex [:options $ks]] == 1} {
      my add_tabledef_flexfields
    }
  }

  # return all tabledefs for inspection by client code.
  method get_tabledefs {} {
    my variable db_tabledefs
    return $db_tabledefs
  }
  
  method add_tabledef_flexfields {} {
    my variable db_tabledefs
    log debug "Add tabledef for flexfields"
    if {[:flexfields $db_tabledefs] == ""} {
      my add_tabledef flexfields {id} {flextable flexfield flexdatatype notes}
    }
  }
  
  method create_tables {args} {
    my variable db_tabledefs conn
    set drop_first [lindex $args 0]
    if {$drop_first == ""} {
      set drop_first 0 
    }
    dict for {table td} $db_tabledefs {
      if {(![my table_exists $table]) || $drop_first} {
        create_table $conn $td {*}$args
      }
    }
  }
  
  # TODO: don't use libsqlite anymore, wrt namespace clashes.
  method prepare_insert_statements {} {
    my variable db_tabledefs db_insert_statements conn
    dict for {table stmt} $db_insert_statements {
      # stmt is a proc-name, so cannot be closed like this.
      log debug "About to close stmt: $stmt"
      $stmt close
      rename $stmt "";              # delete proc
      dict unset db_insert_statements $table
    }
    dict for {table td} $db_tabledefs {
      dict set db_insert_statements $table [prepare_insert_td_proc $conn $td]
    }
  }

  # [2016-07-10 08:50] not tested yet!
  # [2016-07-10 08:54] $prepared_statement execute always returns a resultset, even with insert/update
  # query. They should be closed directly after calling, these methods are a fallback.
  # if memory leaks occur, this one should be checked.
  method close_all_resultsets {} {
    my variable db_insert_statements
    dict for {tbl stmt} $db_insert_statements {
      my close_stmt_resultsets $stmt
    }
  }

  # [2016-07-10 08:50] not tested yet!
  method close_stmt_resultsets {stmt} {
    set nclosed 0
    foreach rs [$stmt resultsets] {
      $rs close
      incr nclosed
    }
    return $nclosed
  }
  
  # @param table - table name
  # @param dct   - dictionary with field keys/values
  # @param args  - given as is to prepared statement, usecase unknown.
  # 
  # @todo multiline fields probably problematic, as newlines seem to be removed (shown in SqliteSpy).
  # check if select from Tcl also shows this, and if \n or \r\n should be added or some setting in the lib can be done.
  method insert {table dct args} {
    my variable db_insert_statements dbtype conn
    my table_add_flex_fields $table $dct    
    # [2016-07-10 09:35] dict values are procs generated by prepare_insert_td_proc
    # these procs call stmt_exec, wherein the resultset is closed.
    [dict get $db_insert_statements $table] $dct {*}$args
    if {$dbtype == "sqlite3"} {
      return [[$conn getDBhandle] last_insert_rowid]
    } elseif {$dbtype == "mysql"} {
      set res [my query "select last_insert_id() last"]
      # log info "Returned id from MySQL: $res"
      return [dict get [lindex $res 0] last]
    } elseif {$dbtype == "postgres"} {
      # TODO not sure if this will work, if pg_last_id is available or postgres.tcl should be sourced.
      set id [pg_last_id $conn $table]
      # log info "Returned id from MySQL: $res"
      return $id
    } else {
      # unknown database type, return nothing.
      return
    }
  }  

  # iff table is flextable and dct contains keys not yet in table, do:
  # - add keys/fields to table def (both valuefields and fields)
  # - add field to the table in db.
  # - prepare insert statements again
  method table_add_flex_fields {table dct} {
    my variable db_tabledefs conn
    set new_table 0
    set table_def [dict_get $db_tabledefs $table]
    if {$table_def == {}} {
      # assume new table, automatically with flex==1
      # set table_def [dict create options [dict create flex 1]]
      # breakpoint
      #set table_def [make_table_def_keys $table {} {} [dict create flex 1]]
      #dict set db_tabledefs $table $table_def
      my add_tabledef $table {} {} [dict create flex 1]; # adds def for flexfields
      my create_tables
      my prepare_insert_statements
      set new_table 1
    }
    if {[:flex [:options [dict get $db_tabledefs $table]]] != 1} {
      return;                   # not a flex table.
    }
    log debug "Add flex fields for $table: $dct"
    set tabledef [dict get $db_tabledefs $table]
    set fields [:fields $tabledef]
    dict for {k v} $dct {
      if {[lsearch -exact $fields $k] < 0} {
        # breakpoint
        log debug "flex - add field: $k (val=$v)"
        # [2016-08-22 16:43:38] use integer as default. If it is a text field, sqlite will manage.
        my def_datatype [list $k] integer
        add_field $conn $tabledef $k integer $new_table
        set new_table 0;        # only one create table, then do alter table.
        dict lappend tabledef fields $k
        dict lappend tabledef valuefields $k
        dict set db_tabledefs $table $tabledef
        log debug "Insert record into flexfield: $table/$k"
        my insert flexfields [dict create flextable $table flexfield $k flexdatatype integer]
      }
    }
    log debug "Added fields, preparing again..."
    my prepare_insert_statements
    log debug "Prepared statement"
  }

  # return dict: (k:table, v:fielddefs as list) determined from source DB's
  # a fielddef is either just a fieldname, or a fieldname/datatype tuple, as in
  # add_tabledef.
  # use table flex_fields (persistent), not the in-memory tabledef structure, is
  # not up-to-date.
  #
  # TODO: determine invariants for flexfields, in table as well as in field defs.
  # currently both do not always reflect current state.
  method flex_fields {} {
    if {![my table_exists flexfields]} {
      return [dict create]
    }
    set query "select flextable, flexfield, flexdatatype from flexfields order by 1,2"
    set rows [my query $query]
    # TODO: could use FP to put in right return format. But hard to beat this lappend.
    set res [dict create]
    foreach row $rows {
      dict lappend res [:flextable $row] [list [:flexfield $row] [:flexdatatype $row]]
    }
    return $res
  }

  # return dict of all known tables in database
  # key = tablename, val = list of fields.
  method tables {} {
    my variable conn
    $conn tables
  }
  
  # some helpers/info
  # @note this one works only for the main DB, not for attached DB's.
  method table_exists {tablename} {
    my variable conn
    if {[$conn tables $tablename] == {}} {
      return 0 
    } else {
      return 1
    }
  }

  # return fields in table as dict
  # key: column name
  # value: info about column, also a dict.
  method fields {tablename} {
    my variable conn
    $conn columns $tablename
  }
  
  method function {fn_name}   {
    [my get_db_handle] function $fn_name $fn_name
  }

  # load external c library. For now, only percentile function
  # path location (relative) is an issue.
  method load_percentile {} {
    global libdb_scriptdir
    [my get_db_handle] enable_load_extension 1
    # set ext_path ../sqlite-functions/percentile
    # set ext_path [file join [file dirname [info script]] sqlite-functions percentile]
    set ext_path [file join $libdb_scriptdir sqlite-functions percentile]
    # breakpoint
    # TODO: ? check if extension already loaded? or keep flag in this db object.
    my query "select load_extension('$ext_path')"
  }

  # helper when flex-fields and tables are used, generate proc get_db
  method get_ddl_tcl {} {
    # set table_defs [list "create table t1;" "create table t2;"]
    set table_defs [my get_create_tables_sql]
    return "proc get_db {db_name opt} {
  set existing_db \[file exists \$db_name\]
  set db \[dbwrapper new \$db_name\]
  # define tables
  [join $table_defs " \n  "]

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
  }

  method get_create_tables_sql {} {
    my variable db_tabledefs
    set res [list]
    dict for {tbl tbl_def} $db_tabledefs {
      if {$tbl == "flexfields"} {
        continue
      }
      # lappend res "create table $tbl;"
      # lappend res [create_table_sql $tbl_def]
      lappend res "# table $tbl:"
      set fields [dict get $tbl_def fields]
      foreach field $fields {
        lappend res "\$db def_datatype \{$field\} integer"
      }
      lappend res "\$db add_tabledef $tbl {id} \{$fields\}"
    }
    return $res
  }
}

if 0 {
  
}


