# functions to read SSL specific parts in log db.

# TODO: (global)
# alles aan elkaar koppelen: ssl_session, conn_block, ssl_conn_block, bio_block, req_block.
# alle (relevante?) entries moeten hier dan ergens bijhoren.

ndv::source_once ssl_session_conn.tcl lib.tcl

proc handle_ssl_global_start {db pubsub} {
  global ssl_session_conn
  set ssl_session_conn [ssl_session_conn new $db]
  $pubsub add_listener iteration $ssl_session_conn
}

# called when all files have been read.
proc handle_ssl_global_end {db} {
  global ssl_session_conn
  $ssl_session_conn destroy
  create_extra_tables $db
  sql_checks $db
}

# TODO:
# * Check of logging op always staat; alleen in dit geval de checks op "bio_info keys not empty at the end" uitvoeren.
#   voor nu 3-5-2016 check uitgezet.
proc handle_ssl_start {db logfile_id vuserid iteration} {
  global entry_type lines linenr_min linenr_max log_always \
      bio_info ssl_session conn_info req_info \
      ssl_session_conn
  set entry_type "start"
  set lines {}
  set linenr_min -1
  set linenr_max -1
  set log_always 0

  set bio_info [dict create]
  set ssl_session [dict create]
  set conn_info [dict create]
  set req_info [dict create]

  $ssl_session_conn bof $logfile_id $vuserid $iteration
  
  handle_block_bio_bof $db $logfile_id $vuserid $iteration
  handle_block_func_bof $db $logfile_id $vuserid $iteration
  handle_block_ssl_bof $db $logfile_id $vuserid $iteration
}

proc handle_ssl_line {db logfile_id vuserid iteration line linenr} {
  global entry_type lines linenr_min linenr_max log_always ssl_session_conn
  if {[regexp {Virtual User Script started at} $line]} {
    set log_always 1
    log debug "set log_always to 1"
  }
  set tp [line_type $line]
  if {$tp == "cont"} {
    lappend lines $line
    set linenr_max $linenr
  } else {
    handle_entry_${entry_type} $db $logfile_id $vuserid $iteration $linenr_min $linenr_max $lines
    set entry_type $tp
    set lines [list $line]
    set linenr_min $linenr
    set linenr_max $linenr
    # $ssl_session_conn entry $entry_type $iteration $linenr_min $linenr_max $lines
    $ssl_session_conn entry $entry_type $linenr_min $linenr_max $lines
    
  }
}

# called when end-of-file reached.
proc handle_ssl_end {db logfile_id vuserid iteration} {
  global entry_type lines linenr_min linenr_max \
      bio_info ssl_session conn_info req_info ssl_session_conn
  handle_entry_${entry_type} $db $logfile_id $vuserid $iteration $linenr_min $linenr_max $lines
  handle_block_bio_eof $db $logfile_id $vuserid $iteration
  handle_block_func_eof $db $logfile_id $vuserid $iteration
  handle_block_ssl_eof $db $logfile_id $vuserid $iteration

  $ssl_session_conn eof $logfile_id $iteration
  # $ssl_session_conn destroy
  
  unset lines
  unset bio_info
  unset ssl_session
  unset conn_info
  unset req_info
}

proc line_type {line} {
  # NOTE: source/linenr is optional (with ?) in next RE:
  if {[regexp {^([A-Za-z_0-9]+\.c\(\d+\): )?(.*)$} $line z src rest]} {
    if {$rest == ""} {
      # TODO: maybe need to look at next line.
      return "ssl"
    } elseif {[regexp {^    } $rest]} {
      return "cont"
    } elseif {[regexp {BIO\[[0-9A-F]+\]} $rest]} {
      if {[regexp {return} $rest]} {
        return "cont"
      } else {
        return "bio"  
      }
    } elseif {[regexp {\[SSL:\]} $rest]} {
      if {[regexp {Established a global SSL session} $rest]} {
        # houd deze bij de vorige, daarin staat meer info.
        # return "cont"
        return "ssl"
      } else {
        return "ssl"  
      }
    } else {
      if {$src != ""} {
        return "func"  
      } else {
        # no source/line, some at end of log, to close/clean up things.  
        if {[regexp {^t=\d+ms: } $rest]} {
          return "func"
        } else {
          return "cont"
        }
      }
    }
  } else {
    # hier zou je nooit moeten komen, eerste regexp moet alles opvangen.
    return "cont"
  }
}

proc handle_entry_start {db logfile_id vuserid iteration linenr_min linenr_max lines} {
  log debug "Before first line, do nothing"
}

proc handle_entry_bio {db logfile_id vuserid iteration linenr_min linenr_max lines} {
  log debug "handle_entry_bio ($linenr_min -> $linenr_max): [join $lines "\n"]"
  set entry [join $lines "\n"]
  setvars {address call socket_fd result} ""
  set functype [det_functype $entry functypes_bio]
  if {[regexp {return} $entry]} {
    set functype "${functype}_return"
  }
  regexp {BIO\[([A-F0-9]+)\]: ?([^\n]*)} $entry z address call
  if {$call == ""} {
    log warn "call is empty in entry: $entry"
    breakpoint
  }
  regexp {return ([0-9-]+)} $entry z result
  regexp {socket fd=(\S+)} $call z socket_fd
  
  $db insert bio_entry [vars_to_dict logfile_id vuserid iteration linenr_min linenr_max entry functype address socket_fd call result]

  handle_block_bio $db $logfile_id $vuserid $iteration $linenr_min $linenr_max $functype $address $socket_fd
}

# bio_info: dict: key=address, val=dict: linenr_min, socket_fd
# $db add_tabledef bio_block {id} {logfile_id vuserid iteration linenr_min linenr_max address socket_fd}
proc handle_block_bio {db logfile_id vuserid iteration linenr_min linenr_max functype address socket_fd} {
  global bio_info log_always
  # cond_breakpoint {$linenr_min == 6176}
  if {$functype == "free"} {
    set d [dict_get $bio_info $address]
    if {$d == {}} {
      if {$log_always} {
        error "Did not find $address in bio_info"        
      } else {
        # nothing, ignore.
      }
    } else {
      set linenr_min [dict get $d linenr_min]
      set socket_fd [dict get $d socket_fd]
      set iteration_min [dict get $d iteration_min]
      set iteration_max $iteration
      $db insert bio_block [vars_to_dict logfile_id vuserid iteration_min iteration_max linenr_min linenr_max address socket_fd]
    }
    dict unset bio_info $address
  } else {
    set d [dict_get $bio_info $address]
    dict_set_if_empty d iteration_min $iteration 0
    dict_set_if_empty d linenr_min $linenr_min 0
    dict_set_if_empty d socket_fd $socket_fd
    dict set bio_info $address $d
  }
}

proc cond_breakpoint {exp {msg ""}} {
  set res [uplevel 1 [list expr $exp]]
  if {$res} {
    if {$msg == ""} {
      set msg "Satisfied: $exp"
    }
    log warn $msg
    breakpoint
  }
}

proc handle_block_bio_bof {db logfile_id vuserid iteration} {
  global bio_info
  set bio_info [dict create]
}

proc handle_block_bio_eof {db logfile_id vuserid iteration} {
  global bio_info log_always
  set keys [dict keys $bio_info]
  if {$keys != {}} {
    log warn "bio_info keys not empty at the end: (logfile_id=$logfile_id) $keys"
    foreach key $keys {
      log warn "bio_info($key) -> [dict get $bio_info $key]"
    }
    if {$log_always} {
      error "bio_info keys not empty at the end: (logfile_id=$logfile_id) $keys"
    }
  }
}

proc handle_entry_ssl {db logfile_id vuserid iteration linenr_min linenr_max lines} {
  log debug "handle_entry_ssl ($linenr_min -> $linenr_max): [join $lines "\n"]"
  set entry [join $lines "\n"]
  setvars {domain_port ssl ctx sess_address sess_id socket conn_nr} ""
  set functype [det_functype $entry functypes_ssl]
  regexp {, connection=([^, ]+),} $entry z domain_port
  regexp {SSL=([0-9A-F]+)} $entry z ssl
  regexp {ctx=([0-9A-F]+)} $entry z ctx
  regexp {session address=([0-9A-F]+)} $entry z sess_address
  regexp {ID \(length \d+\): ([0-9A-F]+)} $entry z sess_id
  regexp {session id: \(length \d+\): ([0-9A-F]+)} $entry z sess_id
  regexp {socket=([A-Fa-f0-9]+) \[(\d+)\]} $entry z socket conn_nr
  
  $db insert ssl_entry [vars_to_dict logfile_id vuserid iteration \
                            linenr_min linenr_max entry functype domain_port ssl \
                            ctx sess_address sess_id socket conn_nr]

  handle_block_ssl $db $logfile_id $vuserid $iteration $linenr_min $linenr_max \
      $functype $domain_port $ssl $ctx $sess_address $sess_id
}

proc handle_block_ssl_bof {db logfile_id vuserid iteration} {
  global ssl_session
  set ssl_session [dict create]
}

# kan zijn dat er nog ssl sessie info is die niet bij een global sessie hoort.
# dit ook in DB.
proc handle_block_ssl_eof {db logfile_id vuserid iteration} {
  global ssl_session
  set sess_ids [dict keys $ssl_session]
  foreach sess_id $sess_ids {
    set d [dict_get $ssl_session $sess_id]
    # dict_to_vars $d
#    set sess_addresses [:sess_addresses $d]
#    set ssls [:ssls $d]
#    set ctxs [:ctxs $d]
#    set domain_ports [:domain_ports $d]
#    set estab_global_linenrs [:estab_global_linenrs $d]
#    set linenr_min [:linenr_min $d]
#    set iteration_min [:iteration_min $d]
#    set iteration_max $iteration
    # set isglobal 0
    #   set estab_global_linenrs [:estab_global_linenrs $d]
    dict set d isglobal 0
    dict set d logfile_id $logfile_id
    dict set d sess_id $sess_id
    $db insert ssl_session $d
    if 0 {
      $db insert ssl_session [vars_to_dict logfile_id linenr_min linenr_max \
                                  iteration_min iteration_max sess_id \
                                  sess_addresses ssls ctxs domain_ports \
                                  estab_global_linenrs isglobal]
      
    }
    dict unset ssl_session $sess_id
  }
}

# TODO:
# als je 'established' line ziet, staat hier niets bij. Je zou dan paar regels max
# terug kunnen kijken of je bepaald type entry (functype) ziet met sess_id en bij
# dan de global_linenrs kunnen aanvullen.
proc handle_block_ssl {db logfile_id vuserid iteration linenr_min linenr_max
                       functype domain_port ssl ctx sess_address sess_id} {
  global ssl_session
  if {$sess_id == ""} {
    return
  }
  # TODO: mss hier ook wel net zo gemakkelijk $d meegeven aan $db insert, ipv vars_to_dict
  set d [dict_get $ssl_session $sess_id]
  dict_set_if_empty d iteration_min $iteration 0
  dict_set_if_empty d linenr_min $linenr_min 0
  set sess_addresses [dict_lappend d sess_addresses $sess_address]
  set ssls [dict_lappend d ssls $ssl]
  set ctxs [dict_lappend d ctxs $ctx]
  set domain_ports [dict_lappend d domain_ports $domain_port]
  if {$functype == "established_global_ssl"} {
    dict_lappend d estab_global_linenrs $linenr_max
  }
  if {$functype == "freeing_global_ssl"} {
    # gegevens ophalen, in DB en vergeten.
    set linenr_min [:linenr_min $d]
    set linenr_max $linenr_max
    set iteration_min [:iteration_min $d]
    set iteration_max $iteration
    set isglobal 1
    set estab_global_linenrs [:estab_global_linenrs $d]
    $db insert ssl_session [vars_to_dict logfile_id linenr_min linenr_max \
                                iteration_min iteration_max sess_id \
                                sess_addresses ssls ctxs domain_ports \
                                estab_global_linenrs isglobal]
    dict unset ssl_session $sess_id
  } else {
    # gegevens aanvullen, maar doe je altijd al, hierboven.
    # deze 2 voor als dit geen global session blijkt te zijn.
    dict set d linenr_max $linenr_max
    dict set d iteration_max $iteration
    dict set ssl_session $sess_id $d
  }
}

proc handle_entry_func {db logfile_id vuserid iteration linenr_min linenr_max lines} {
  log debug "handle_entry_func ($linenr_min -> $linenr_max): [join $lines "\n"]"
  set entry [join $lines "\n"]
  setvars {functype ts_msec url domain_port ip_port conn_nr nreqs relframe_id internal_id conn_msec http_code} ""
  set functype [det_functype $entry functypes_func]
  regexp {t=(\d+)ms: } $entry z ts_msec

  regexp {Connecting \[(\d+)\] to host (\S+)} $entry z conn_nr ip_port
  regexp {Connected socket \[(\d+)\] from .* to (\S+) in (\d+) ms} $entry z conn_nr ip_port conn_msec
  regexp {Already connected \[(\d+)\] to (\S+)} $entry z conn_nr domain_port
  regexp {Closing connection \[(\d+)\] to server (\S+)} $entry z conn_nr domain_port
  regexp {Closed connection \[(\d+)\] to (\S+) after completing (\d+) request} $entry z conn_nr domain_port nreqs
  
  regexp {Re-negotiating https connection \[(\d+)\] to ([^,]+),} $entry z conn_nr domain_port
  
  regexp {request headers for "([^""]+)" \(RelFrameId=(.*), Internal ID=(\d+)\)} $entry z url relframe_id internal_id
  regexp {response headers for "([^""]+)" \(RelFrameId=(.*), Internal ID=(\d+)\)} $entry z url relframe_id internal_id
  regexp {Request done "([^""]+)"} $entry z url

  regexp {(HTTP/1\.\d \d\d\d [^\\]+)\\} $entry z http_code
  if {($functype == "resp_headers") && ($http_code == "")} {
    log warn "Empty http code in resp_headers"
    breakpoint
  }
  if {($domain_port == "") && ($url != "")} {
    regexp {https://([^/]+)} $url z domain
    set domain_port "$domain:443"
  }
  # add 443 to domain_port if needed
  if {($domain_port != "") && ![regexp {:} $domain_port]} {
    set domain_port "$domain_port:443"
  }
  $db insert func_entry [vars_to_dict logfile_id vuserid iteration linenr_min \
                         linenr_max entry functype ts_msec url \
                         domain_port ip_port conn_nr nreqs relframe_id \
                         internal_id  conn_msec http_code]

  handle_block_func $db $logfile_id $vuserid $iteration $linenr_min $linenr_max \
      $ts_msec $functype $conn_nr $conn_msec \
      $domain_port $ip_port $nreqs $url $http_code
}

proc handle_block_func {db logfile_id vuserid iteration linenr_min linenr_max ts_msec functype conn_nr conn_msec domain_port ip_port nreqs url http_code} {
  global conn_info req_info log_always

  if {$conn_nr != ""} {
    set d [dict_get $conn_info $conn_nr]    
    if {$functype == "closed_conn"} {
      if {$d == {}} {
        if {$log_always} {
          log warn "Empty dict for closed_conn: logfile_id = $logfile_id, linenr=$linenr_min, conn_nr=$conn_nr"
          error "Stop now"
        }
      } else {
        set linenr_min [:linenr_min $d]
        set iteration_min [:iteration_min $d]
        set iteration_max $iteration
        set conn_msec [:conn_msec $d]
        set domain_port [:domain_port $d]
        set ip_port [:ip_port $d]
        set ts_msec_end $ts_msec
        set ts_msec_start [:ts_msec_start $d]
        if {$ts_msec_start == ""} {
          set ts_msec_diff ""
        } else {
          set ts_msec_diff [expr $ts_msec_end - $ts_msec_start]  
        }
        $db insert conn_block [vars_to_dict logfile_id vuserid iteration_min iteration_max linenr_min linenr_max ts_msec_start ts_msec_end ts_msec_diff conn_nr conn_msec domain_port ip_port nreqs]
      }
      dict unset conn_info $conn_nr
    } else {
      dict_set_if_empty d iteration_min $iteration 0
      dict_set_if_empty d linenr_min $linenr_min 0
      dict_set_if_empty d ts_msec_start $ts_msec 0
      dict_set_if_empty d conn_msec $conn_msec
      dict_set_if_empty d domain_port $domain_port
      dict_set_if_empty d ip_port $ip_port
      dict_set_if_empty d nreqs $nreqs
      dict set conn_info $conn_nr $d
    }
  } elseif {$url != ""} {
    #   $db add_tabledef req_block {id} {logfile_id vuserid iteration_min iteration_max linenr_min linenr_max url domain_port nentries}
    set d [dict_get $req_info $url]
    dict incr d nentries
    dict_set_if_empty d http_code $http_code    
    if {$functype == "req_done"} {
      set linenr_min [:linenr_min $d]
      set iteration_min [:iteration_min $d]
      set iteration_max $iteration
      set nentries [:nentries $d]
      set ts_msec_end $ts_msec
      set ts_msec_start [:ts_msec_start $d]
      if {$ts_msec_start == ""} {
        set ts_msec_diff ""
      } else {
        set ts_msec_diff [expr $ts_msec_end - $ts_msec_start]   
      }
      set http_code [:http_code $d]
      $db insert req_block [vars_to_dict logfile_id vuserid iteration_min iteration_max linenr_min linenr_max ts_msec_start ts_msec_end ts_msec_diff url domain_port nentries http_code]
      dict unset req_info $url
    } else {
      dict_set_if_empty d iteration_min $iteration 0
      dict_set_if_empty d linenr_min $linenr_min 0
      dict_set_if_empty d ts_msec_start $ts_msec 0
      dict set req_info $url $d
    }
  } else {
    # not a connection or request related call
    return
  }
}

proc handle_block_func_bof {db logfile_id vuserid iteration} {
  global conn_info req_info
  set conn_info [dict create]
  set req_info [dict create]
}

proc handle_block_func_eof {db logfile_id vuserid iteration} {
  global conn_info req_info log_always
  set keys [dict keys $conn_info]
  if {$log_always} {
    if {$keys != {}} {
      log error "conn_info keys not empty at the end: (logfile_id=$logfile_id) $keys"
      error "conn_info keys not empty at the end: (logfile_id=$logfile_id) $keys"
    }
    set keys [dict keys $req_info]
    if {$keys != {}} {
      log error "req_info keys not empty at the end: (logfile_id=$logfile_id) $keys"
      error "req_info keys not empty at the end: (logfile_id=$logfile_id) $keys"
    }
  }
}

set functypes_func {
  "Closed connection" closed_conn
  "Closing connection" closing_conn
  "Already connected" already_conn
  "request headers" req_headers
  "response headers" resp_headers
  "Found resource" found_resource
  "Parameter Substitution" par_subst
  "Request done" req_done
  "SSL protocol error" ssl_protocol_error
  "web_global_verification" web_global_verification
  "web_set_sockets_option" web_set_sockets_option
  "Maximum number of open connections" max_nr_open_conn
  "web_add_auto_filter" web_add_auto_filter
  "web_add_auto_header" web_add_auto_header
  "registered for adding to requests" registered_adding_requests
  "Connected socket" connected_socket
  "Connecting" connecting
  "Re-negotiating https connection" renegotiating_https_conn
  "web_set_option" web_set_option
  "web_add_header" web_add_header
  "web_reg_find" web_reg_find
  "No match found for the requested parameter" no_match_found
  "Saving Parameter" saving_parameter
  "web_set_certificate_ex" web_set_certificate_ex
  "Redirecting" redirecting
  "To location" to_location
  "Changing TCPIP buffer size" changing_tcpip_buffer_size
  "web_url" web_url
  "header registered" header_registered
  "web_concurrent_" web_concurrent
  "ssl_handle_status encounter error" ssl_handle_status_error

  "web_reg_save_param" web_reg_save_param
  "Request.*failed" req_failed
  "Transaction.*Fail" trans_failed

  "=== NOT SURE ABOUT ONES BELOW, naming source files ===" not_sure
  "QQvuser_init\.c" vuser_init_c
  "QQfunctions\.c" functions_c
  "QQconfigfile\.c" configfile_c
  "QQdynatrace\.c" dynatrace_c
  
  "Successful attempt to establish the reuse of the global SSL session" success_establish_reuse_global_ssl
  
  "Freeing the global SSL session in a callback" freeing_global_ssl
  "Connection information" conn_info
  
  "error" error  
}

set functypes_ssl {
  "Closed connection" closed_conn
  "Closing connection" closing_conn
  "Already connected" already_conn
  "Request done" req_done
  "SSL protocol error" ssl_protocol_error
  "Connected socket" connected_socket
  "Connecting" connecting
  "Re-negotiating https connection" renegotiating_https_conn
  "web_set_option" web_set_option
  "web_set_certificate_ex" web_set_certificate_ex
  "ssl_handle_status encounter error" ssl_handle_status_error
  
  "New SSL" new_ssl
  "Received callback about handshake completion" cb_handshake_completion
  "certificate error" cert_error
  "Handshake complete" handshake_complete

  "=== Established checken voor considering, deze staan in dezelfde entry ===" __dummy__
  "Established a global SSL session" established_global_ssl
  "Considering establishing the above as a new global SSL session" consider_global_ssl
  
  "Successful attempt to establish the reuse of the global SSL session" success_establish_reuse_global_ssl
  "Freeing the global SSL session in a callback" freeing_global_ssl
  "Connection information" conn_info

  "error" error  
}

set functypes_bio {
  write write
  read read
  ctrl ctrl
  "Free - socket" free
  "Free - Overlapped IO filter" free
}

proc det_functype {entry functypes_name} {
  # global functypes
  global $functypes_name
  foreach {re ft} [set $functypes_name] {
    if {[regexp $re $entry]} {
      return $ft
    }
  }
  return "unknown"
}

proc create_extra_tables {db} {
  # TODO: maybe create indexes first.
  
  log info "Creating extra tables..."
  
  $db exec "drop table if exists conn_bio_block"
  $db exec "create table conn_bio_block (logfile_id, bio_block_id, conn_block_id, bio_linenr_min, bio_linenr_max, conn_linenr_min, conn_linenr_max, domain_port, ip_port, reason)"
  $db exec "insert into conn_bio_block
select b.logfile_id, b.id, c.id, b.linenr_min, b.linenr_max,
c.linenr_min, c.linenr_max,
c.domain_port, c.ip_port, 'linenr_max 1 diff'
from bio_block b, conn_block c
where b.logfile_id = c.logfile_id
and b.linenr_max + 1 = c.linenr_max"

  $db exec "drop table if exists newssl_entry"
  $db exec "create table newssl_entry as select * from ssl_entry where conn_nr <> ''"

  # TODO: hier mss iteration ook bij.
  $db exec "drop table if exists newssl_conn_block"
  $db exec "create table newssl_conn_block as
select s.logfile_id, s.iteration newssl_iteration, s.linenr_min newssl_linenr, s.conn_nr, c.linenr_min, c.linenr_max, s.id newssl_entry_id, c.id conn_block_id,
  s.domain_port domain_port, s.ssl ssl, s.ctx ctx, s.socket socket, c.nreqs nreqs
from newssl_entry s, conn_block c
where s.conn_nr <> ''
and s.functype = 'new_ssl'
and s.logfile_id = c.logfile_id
and s.linenr_min between c.linenr_min and c.linenr_max
and s.conn_nr = c.conn_nr"

  # lokaties waar sess_address en sess_id voorkomen, hier is overlap.
  $db exec "drop table if exists sess_addr_id"
  $db exec "create table sess_addr_id as
  select count(*) cnt, logfile_id, sess_address, sess_id, min(linenr_min) linenr_min, max(linenr_max) linenr_max, min(iteration) iteration_min, max(iteration) iteration_max
  from ssl_entry
  where sess_address <> ''
  and sess_id <> ''
  group by 2,3,4
  order by 2,5"

  # lokaties waar sess_address en sess_id voorkomen in global setting, geen overlap?
  $db exec "drop table if exists global_sess_addr_id"
  $db exec "create table global_sess_addr_id as
  select count(*) cnt, logfile_id, sess_address, sess_id, min(linenr_min) linenr_min, max(linenr_max) linenr_max, min(iteration) iteration_min, max(iteration) iteration_max
  from ssl_entry
  where sess_address <> ''
  and sess_id <> ''
  and entry like '%global%'
  group by 2,3,4
  order by 2,5"

  # vullen fkeys in ssl_conn_block
  $db exec "update ssl_conn_block
  set ssl_session_id = (
    select s.id
    from ssl_session s
    where s.logfile_id = ssl_conn_block.logfile_id
    and s.sess_id = ssl_conn_block.sess_id
    and ssl_conn_block.linenr_min between s.linenr_min and s.linenr_max
  )
  where ssl_session_id is null"
  
  sql_update_reason ssl_conn_block ssl_session_reason ssl_session_id "within ssl_session"
  #$db exec "update ssl_conn_block
  #set ssl_session_reason = 'within ssl_session'
  #where ssl_session_reason is null
  #and ssl_session_id is not null"

  $db exec "update ssl_conn_block
  set ssl_session_id = (
    select s.id
    from ssl_session s
    where s.logfile_id = ssl_conn_block.logfile_id
    and s.sess_id = ssl_conn_block.sess_id
    and s.iteration_min = ssl_conn_block.iteration_min
    and ssl_conn_block.linenr_min <= s.linenr_min
  )
  where ssl_session_id is null"
  sql_update_reason ssl_conn_block ssl_session_reason ssl_session_id \
      "before ssl_session, same iteration"
  #$db exec "update ssl_conn_block
  #set ssl_session_reason = 'before ssl_session, same iteration'
  #where ssl_session_reason is null
  #and ssl_session_id is not null"
  
  $db exec "update ssl_conn_block
  set conn_block_id = (
    select cb.id
    from conn_block cb
    where cb.logfile_id = ssl_conn_block.logfile_id
    and cb.conn_nr = ssl_conn_block.conn_nr
    and ssl_conn_block.linenr_min between cb.linenr_min and cb.linenr_max
  )"

  # connect request and bio, first on entry level
  # $db add_tabledef req_bio_entry {id} {logfile_id req_id bio_id req_linenr_min req_linenr_max bio_linenr_min bio_linenr_max reason}
  $db exec "insert into req_bio_entry (logfile_id, iteration, url, bio_address,
  req_id, bio_id, 
  req_linenr_min, req_linenr_max, bio_linenr_min, bio_linenr_max, reason)
  select r.logfile_id, r.iteration, r.url, b.address, r.id, b.id, r.linenr_min, r.linenr_max,
         b.linenr_min, b.linenr_max, 'req/bio directly after'
  from func_entry r, bio_entry b
  where r.logfile_id = b.logfile_id
  and r.iteration = b.iteration
  and r.functype = 'req_headers'
  and b.functype = 'write_return'
  and r.linenr_max + 1 = b.linenr_min"

  $db exec "insert into req_bio_entry (logfile_id, iteration, url, bio_address,
  req_id, bio_id, 
  req_linenr_min, req_linenr_max, bio_linenr_min, bio_linenr_max, reason)
  select r.logfile_id, r.iteration, r.url, b.address, r.id, b.id, r.linenr_min, r.linenr_max,
         b.linenr_min, b.linenr_max, 'resp/bio directly after'
  from func_entry r, bio_entry b
  where r.logfile_id = b.logfile_id
  and r.iteration = b.iteration
  and r.functype = 'resp_headers'
  and b.functype = 'read_return'
  and b.linenr_max + 1 = r.linenr_min"

  # 8-5-2016 req done not now: not always close to bio block.

  # 8-5-2016 then req/bio on block level
  # $db add_tabledef req_bio_block {id} {logfile_id iteration_min iteration_max url bio_address req_block_id bio_block_id req_linenr_min req_linenr_max bio_linenr_min bio_linenr_max}
  $db exec "insert into req_bio_block (logfile_id, iteration_min, iteration_max, url, bio_address, req_block_id, bio_block_id, req_linenr_min, req_linenr_max, bio_linenr_min, bio_linenr_max)
select rbe.logfile_id, rbe.iteration, rbe.iteration, rbe.url, rbe.bio_address, rb.id, bb.id, rb.linenr_min, rb.linenr_max, bb.linenr_min, bb.linenr_max
from req_bio_entry rbe, req_block rb, bio_block bb
where rbe.reason = 'req/bio directly after'
and rbe.logfile_id = rb.logfile_id
and rbe.url = rb.url
and rbe.iteration = rb.iteration_min
and rbe.req_linenr_min = rb.linenr_min
and rbe.logfile_id = bb.logfile_id
and rbe.bio_address = bb.address
and rbe.iteration = bb.iteration_min
and rbe.bio_linenr_min between bb.linenr_min and bb.linenr_max"

  $db exec "insert into ssl_conn_req_block (logfile_id, iteration_min, iteration_max, req_linenr_min, req_linenr_max, scb_linenr_min, scb_linenr_max, ssl_conn_block_id, req_block_id, ssl_session_id, conn_block_id, url, conn_nr, sess_id)
select rbb.logfile_id, rbb.iteration_min, rbb.iteration_max, rbb.req_linenr_min, rbb.req_linenr_max, scb.linenr_min, scb.linenr_max, scb.id, rbb.req_block_id, scb.ssl_session_id, scb.conn_block_id, rbb.url, scb.conn_nr, scb.sess_id
from req_bio_block rbb
join conn_bio_block cbb on rbb.bio_block_id = cbb.bio_block_id
join ssl_conn_block scb on cbb.conn_block_id = scb.conn_block_id
where rbb.req_linenr_min between scb.linenr_min and scb.linenr_max"

  # conn_block_id bij req_block
  # mss deze dan ook gebruiken bij ssl_conn_req_block?
  $db exec "update req_block set conn_block_id = (
  select cbb.conn_block_id
  from req_bio_block rbb
  join conn_bio_block cbb on rbb.bio_block_id = cbb.bio_block_id
  where rbb.req_block_id = req_block.id)"
  
}

proc sql_update_reason {tbl col check_col msg} {
  upvar db db
  $db exec "update $tbl
  set $col = '$msg'
  where $col is null
  and $check_col is not null"
}

proc sql_checks {db} {
  log info "Doing checks..."
  set have_warnings 0
  check_exists bio_block id conn_bio_block bio_block_id
  check_exists conn_block id conn_bio_block conn_block_id
  # in theorie ook nog kijken of dingen niet dubbel voorkomen, alleen kan bij deze niet.

  # testje weer:
  # check_exists conn_block id ssl_entry conn_nr
  check_exists newssl_entry id newssl_conn_block newssl_entry_id
  check_exists conn_block id newssl_conn_block conn_block_id
  check_doubles newssl_conn_block newssl_entry_id
  check_doubles newssl_conn_block conn_block_id

  # 5-5-2016 this one does occur, so check overlapping, should not occur.
  # check_doubles sess_addr_id {logfile_id sess_address}
  check_overlap sess_addr_id {logfile_id sess_address} sess_id

  # 5-5-2016 The same sess_id with different addresses has not occurred yet.
  check_doubles sess_addr_id {logfile_id sess_id}

  # 5-5-2016 for global sessions the same as all sessions
  # check_doubles global_sess_addr_id {logfile_id sess_address}
  check_overlap global_sess_addr_id {logfile_id sess_address} sess_id
  
  check_doubles global_sess_addr_id {logfile_id sess_id}

  # checks op ssl_session: hier kleine overlap (2 regels) mogelijk: bij melding van nieuwe sessie
  # moet oude nog snel worden afgesloten.
  # deze is geldig voor run 599 met nconc=1, zegt dus nog niets over algemeen.
  # maar eerst deze goed begrijpen.
  check_overlap ssl_session logfile_id id 2

  # 7-5-2016 deze even voor nconc=1, dan mag er 0 overlap zijn.
  check_overlap ssl_conn_block logfile_id id

  # sql_check "conn_nr empty" "select * from ssl_conn_block where conn_nr = '' or conn_nr is null"
  check_filled ssl_conn_block conn_nr
  check_filled ssl_conn_block ssl_session_id
  check_filled ssl_conn_block conn_block_id

  # req_bio_entry checks
  check_exists func_entry id req_bio_entry req_id "and functype='req_headers'"
  check_exists func_entry id req_bio_entry req_id "and functype='resp_headers'"

  # ssl_conn_req_block checks
  check_doubles ssl_conn_req_block {logfile_id req_block_id}

  check_filled req_block conn_block_id

  sql_check "nreqs in conn_block diffs from counted #reqs" \
      "select cb.id, count(*)
       from conn_block cb
       join req_block rb on rb.conn_block_id = cb.id
       group by 1
       having count(*) <> cb.nreqs"

  check_exists req_block id ssl_conn_req_block req_block_id
  
  if {$have_warnings} {
    log warn "**************************************"
    log warn "*** Some warnings, do investigate! ***"
    log warn "**************************************"
  } else {
    log info "*** Everything seems fine. ***"
  }
}

# check if tbl1.col1 entries all exist in tbl2.col2
proc check_exists {tbl1 col1 tbl2 col2 {tbl1_filter ""}} {
  upvar have_warnings have_warnings
  upvar db db
  if {$tbl1_filter != ""} {
    set filter " ($tbl1_filter)"
  } else {
    set filter ""
  }
  # sql_check $msg "select * from $tbl1 where not $col1 in (select $col2 from $tbl2)"
  sql_check "Entries in $tbl1 without corresponding ($col1->$col2) entry in $tbl2$filter" \
      "select * from $tbl1 where $col1 <> '' $tbl1_filter and not $col1 in (select $col2 from $tbl2)"
}

# check if all records in tbl have col filled (not null, not empty string)
proc check_filled {tbl col} {
  upvar have_warnings have_warnings
  upvar db db
  sql_check "Empty $col in $tbl" \
      "select * from $tbl where $col is null or $col = ''"
}

# check if combination of columns in table occurs more than once.
proc check_doubles {tbl cols} {
  upvar have_warnings have_warnings
  upvar db db
  set cols [join $cols ", "]
  sql_check "Double entries in $tbl (cols: $cols)" \
      "select count(*), $cols from $tbl group by $cols having count(*) > 1"
}

proc sql_equal_col {col} {
  return "t1.$col = t2.$col"
}

proc check_overlap {tbl same_cols diff_col {allowed_overlap 0}} {
  upvar have_warnings have_warnings
  upvar db db
  sql_check "Overlapping items in $tbl (cols: $same_cols, diff: $diff_col)" \
      "select *
  from $tbl t1, $tbl t2
  where [join [map sql_equal_col $same_cols] " and "]
  and t1.$diff_col <> t2.$diff_col
  and t1.linenr_min+$allowed_overlap between t2.linenr_min and t2.linenr_max"
}

proc sql_check {msg sql} {
  upvar have_warnings have_warnings
  upvar db db
  set res [$db query $sql]
  if {[:# $res] > 0} {
    log warn "$msg:"
    # log warn $res
    log warn "sql: $sql"
    log warn "#records: [:# $res]"
    log warn "--------"
    set have_warnings 1    
  }
}

proc ssl_define_tables {db} {
  # iteration can be 'vuser_end', so not an integer.
  # TODO: $db set_default_type nothing|as_same
  #       as_same: als een veld geen datatype heeft, en eerdere def met dezelfde naam wel, neem deze dan over. Dan bv maar 1x bij linenr_min integer op te geven.
  # evt dan ook een def_datatype <col-regexp> <datatype> opnemen, zodat je dit vantevoren kunt
  # doen, evt ook met regexp's.
  $db add_tabledef bio_entry {id} {logfile_id {vuserid integer} {iteration integer} {linenr_min integer} {linenr_max integer} entry functype address socket_fd call result}
  
  # TODO: andere dingen in SSL line
  $db add_tabledef ssl_entry {id} {logfile_id {vuserid integer} {iteration integer} {linenr_min integer} {linenr_max integer} entry functype domain_port ssl ctx sess_address sess_id socket {conn_nr integer} ssl_conn_block_id}
  
  $db add_tabledef func_entry {id} {logfile_id {vuserid integer} {iteration integer} {linenr_min integer} {linenr_max integer} entry functype {ts_msec integer} url domain_port ip_port {conn_nr integer} {nreqs integer} {relframe_id integer} {internal_id integer} {conn_msec integer} http_code}

  $db add_tabledef bio_block {id} {logfile_id {vuserid integer} {iteration_min integer} {iteration_max integer} {linenr_min integer} {linenr_max integer} address socket_fd}
  
  $db add_tabledef conn_block {id} {logfile_id {vuserid integer} {iteration_min integer} {iteration_max integer} {linenr_min integer} {linenr_max integer} {ts_msec_start integer} {ts_msec_end integer} {ts_msec_diff integer} {conn_nr integer} {conn_msec integer} domain_port ip_port {nreqs integer}}
  
  $db add_tabledef req_block {id} {logfile_id {vuserid integer} {iteration_min integer} {iteration_max integer} {linenr_min integer} {linenr_max integer} {ts_msec_start integer} {ts_msec_end integer} {ts_msec_diff integer} url domain_port nentries http_code conn_block_id}

  # einde bij "freeing_global_ssl"

  $db add_tabledef ssl_session {id} {logfile_id {linenr_min int} {linenr_max int}
    {iteration_min int} {iteration_max int} sess_id
    sess_addresses ssls ctxs domain_ports estab_global_linenrs {isglobal int}}

  $db add_tabledef req_bio_entry {id} {logfile_id iteration url bio_address req_id bio_id req_linenr_min req_linenr_max bio_linenr_min bio_linenr_max reason}

  $db add_tabledef req_bio_block {id} {logfile_id iteration_min iteration_max url bio_address req_block_id bio_block_id req_linenr_min req_linenr_max bio_linenr_min bio_linenr_max}

  $db add_tabledef ssl_conn_req_block {id} {logfile_id iteration_min iteration_max req_linenr_min req_linenr_max scb_linenr_min scb_linenr_max ssl_conn_block_id req_block_id ssl_session_id conn_block_id url conn_nr sess_id}
}

