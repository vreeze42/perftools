proc get_db {db_name} {
  set existing_db [file exists $db_name]
  set db [dbwrapper new $db_name]
  define_tables $db
  if {!$existing_db} {
    log info "New db: $db_name, create tables"
    $db create_tables 0 ; # 0: don't drop tables first.
    create_indexes $db
  } else {
    log info "Existing db: $db_name, don't create tables"
  }
  $db prepare_insert_statements
  return $db
}

proc define_tables {db} {
  $db add_tabledef tests_file {id} {filename ts_cet {filesize int}} 
  $db add_tabledef test {id} {{file_id int} {alm_id int} name owner creation_time} 
  $db add_tabledef testversion {id} {{test_id int} {alm_id int} name {ver_stamp int} owner last_modified {pc_total_vusers int}}
  $db add_tabledef tv_param {id} {{tv_id int} name value}
  $db add_tabledef testgroup {id} {{tv_id int} {alm_id int} name}
  $db add_tabledef tg_param {id} {{tg_id int} name value}
  $db add_tabledef tg_host {id} {{tg_id int} {alm_id int} name location}

  # test runs
  $db add_tabledef testruns_file {id} {filename ts_cet {filesize int} domain project}
  $db add_tabledef testrun {id} {{file_id int} domain project {testid int} {testinstanceid int} postrunaction {timeslotid int} \
                                     vudsmode {runid int} {duration int} runstate runslastatus}
  $db add_tabledef testrunresult {id} {{testrun_id int} {alm_id int} name type {runid int} path {filesize int} ts_cet}

  if 0 {
    alter table testruns_file add domain varchar(40)
    alter table testruns_file add project varchar(100)

    alter table testrun add domain varchar(40)
    alter table testrun add project varchar(100)
  }
  
}

proc create_indexes {db} {

  
}

proc delete_table_rows {db} {
  foreach tablename {tg_host tg_param testgroup tv_param testversion test tests_file testruns_file testrun testrunresult} {
    $db exec "delete from $tablename"
  }
  
}
