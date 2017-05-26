# postgres helper queries, to emulate mysql queries

# puts "in postgres.tcl"

# exec query;
# result: if insert,update,delete -> return number of rows affected.
# if select, return resultset object.
# of course this is tricky
proc pg_query {conn query} {
  set stmt [$conn prepare $query]
  set res [$stmt execute]
  # 2015-06-20 NdV The extra parens are really needed,
  # otherwise eg delete does not have to be at the start of the query
  if {[regexp -nocase {^((insert)|(update)|(delete))} $query]} {
    #puts "pg_query - query is DML, return rows affected"
    #breakpoint
    set rc [$res rowcount]
    $res close
    $stmt close
    return $rc ; # same as mysql
  }
  # TODO stmt wel sluiten, anders blijft de boel hangen, vraag of je van res terug naar stmt kunt.
  # $stmt close ; # then also res closed, is too soon.
  return $res
  # todo read res, transform to list of lists?
}

proc pg_query_list {conn query} {
  set res [pg_query $conn $query]
  set result [$res allrows -as lists]
  $res close
  return $result  
}

proc pg_query_flatlist {conn query} {
  set res [pg_query $conn $query]
  # puts "DEBUG - pg_query_flatlist - query res object/fn: $res"
  set result {}
  foreach row [$res allrows -as lists] {
    lappend result {*}$row
  }
  $res close
  return $result
}

# return first element of flatlist returned by query
proc pg_query_flatlist0 {conn query} {
  lindex [pg_query_flatlist $conn $query] 0
}

proc pg_query_dicts {conn query} {
  set res [pg_query $conn $query]
  set result [$res allrows -as dicts]
  $res close
  return $result
}

proc pg_last_id {conn table {colname id}} {
  set res [pg_query $conn "SELECT CURRVAL(pg_get_serial_sequence('$table','$colname'))"]
  $res nextlist row
  $res close
  lindex $row 0
}
