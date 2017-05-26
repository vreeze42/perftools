#!/usr/bin/env tclsh861

# [2016-08-17 09:47:56] Version for vugen logs.
# TODO: integrate/merge with version for AHK logs (also JMeter?)

package require ndv
package require tdbc::sqlite3

# [2016-07-09 10:09] for parse_ts and now:
use libdatetime
use libfp

proc get_run_db {db_name opt} {
  global pubsub
  set ssl [:ssl $opt]
  if {$ssl == ""} {set ssl 0}
  #breakpoint
  set existing_db [file exists $db_name]
  set db [dbwrapper new $db_name]
  define_tables $db $opt
  if {$ssl} {
    # TODO: deze eigenlijk op zelfde niveau als waar je handle_ssl_global_end aanroept.
    # maar wat lastig omdat table defs hier moeten.
    # [2016-08-19 12:36] niet hier in loblogdb.
    # handle_ssl_global_start $db $pubsub
  }
  $db create_tables 0 ; # 0: don't drop tables first. Always do create, eg for new table defs. 1: drop tables first.
  if {!$existing_db} {
    log debug "New db: $db_name, create tables"
    # create_indexes $db
  } else {
    log debug "Existing db: $db_name, don't create tables"
  }
  # TODO: maybe call prepare just before (or within) first insert call.
  $db prepare_insert_statements
  #breakpoint

  $db load_percentile
  
  return $db
}

proc define_tables {db opt} {
  # [2016-07-31 12:01] sec_ts is a representation of a timestamp in seconds since the epoch
  set ssl [:ssl $opt]
  if {$ssl == ""} {set ssl 0}
  $db def_datatype {sec_ts.* resptime} real
  $db def_datatype {.*id filesize .*linenr.* trans_status iteration.*} integer
  
  # default is text, no need to define, just check if it's consistent
  # [2016-07-31 12:01] do want to define that everything starting with ts is a time stamp/text:
  $db def_datatype {status ts.* user} text

  $db add_tabledef read_status {id} {ts status}
  
  $db add_tabledef logfile {id} {logfile dirname ts filesize \
                                     runid project script}

  set logfile_fields {logfile_id logfile vuserid}
  set line_fields {linenr ts sec_ts iteration}
  set line_start_fields [map [fn x {return "${x}_start"}] $line_fields]
  set line_end_fields [map [fn x {return "${x}_end"}] $line_fields]
  set srcline_fields {srcfile srclinenr}
  
  # [2016-08-19 19:07] transshort weg, moet dynamisch added worden.
  # [2016-08-22 10:03:55] fields usecase and transshort used in reports for now, so make sure they always exist.
  # set trans_fields {transname user resptime trans_status usecase transshort}

  # [2017-03-29 12:36:00] add iteration_sub, used in report, possibly defined from Vugen script.
  set trans_fields {transname user resptime trans_status usecase transshort iteration_sub}
  # [2016-08-19 21:10] fields below will be added dynamically
  # usecase revisit transid searchcrit
  
  # 17-6-2015 NdV transaction is a reserved word in SQLite, so use trans as table name
  $db add_tabledef trans_line {id} [concat $logfile_fields $line_fields $srcline_fields $trans_fields]
  $db add_tabledef trans {id} [concat $logfile_fields $line_start_fields \
                                   $line_end_fields $srcline_fields $trans_fields] {flex 1}

  $db add_tabledef error {id} [concat $logfile_fields $line_fields $srcline_fields \
                                   {user errornr errortype details line}]
                   
  # 22-10-2015 NdV ook errors per iteratie, zodat er een hoofd schuldige is aan te wijzen voor het falen.
  $db add_tabledef error_iter {id} [concat $logfile_fields script \
                                        iteration user errortype]

  $db add_tabledef resource {id} [concat $logfile_fields $line_fields user transname resource]

  # [2016-11-23 15:29:08] step, part of LR transaction, like web_url
  # [2016-11-23 15:58:02] TODO: split in line_start_fields/line_end_fields.
  set step_fields {step_name step_type}
  $db add_tabledef step {id} [concat $logfile_fields $line_fields $srcline_fields $trans_fields $step_fields]

  # [2016-11-23 16:30:22] request within step within transaction
  set request_fields {url reqheaderbytes}
  $db add_tabledef request {id} [concat $logfile_fields $line_fields $srcline_fields $trans_fields $step_fields $request_fields]
  
  # summary table, per usecase and transaction. resptime fields already defined als real.
  $db def_datatype {npass nfail} integer
  $db add_tabledef summary {id} {usecase resulttype transshort min_ts resptime_min resptime_avg resptime_max resptime_p95 npass nfail}

  # percentile table, for transactions, usecases and total. Only successful transactions. Transshort and usecase can be 'Total'
  $db add_tabledef percentiles {id} {usecase transshort perc resptime}
  
  # flex tables can have extra fields/columns added, depending on dict's given to
  # insert proc.
  if {$ssl} {
    # ssl_define_tables $db  ; # [2016-08-19 12:38] not now/here.
  }

}

# vuserid/iteration op zowel error als trans.
# [2017-04-03 10:02:04] eerdere queries gingen dan veel sneller.
proc logdb_make_indexes {db} {
  $db exec "create index if not exists ix_error1 on error (vuserid, iteration)"
  $db exec "create index if not exists ix_trans1 on trans (vuserid, iteration_start)"
  
}

proc delete_database {dbname} {
  log debug "delete database: $dbname"
  # error nietgoed
  set ok 0
  catch {
    file delete $dbname
    set ok 1
  }
  if {!$ok} {
    set db [dbwrapper new $dbname]
    foreach table {error trans retraccts logfile} {
      # $db exec "delete from $table"
      $db exec "drop table $table"
    }
    $db close
  }
}

