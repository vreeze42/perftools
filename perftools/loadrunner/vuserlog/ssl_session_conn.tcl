# package require TclOO zou nu niet meer nodig moeten zijn.
# 5-5-2016 TODO: deze sowieso ook op Windows nog testen.

# uitgangspunten/invarianten.
# * elke TCP connectie kan maar 1 dssl/ssl tegelijk hebben. Dit kan wel dezelfde blijven.
#   - als een TCP Closed wordt gevonden, kan de bijbehorende dssl dus ge-insert worden.

# TODO: Open vragen:
# * Is het belangrijk of een sessie global is of niet?
# * kan de tabel ssl_addr_id weg? Nu nog checks op zitten, kijken of deze afgaan bij andere logfiles.
# * als een test wordt afgebroken, zijn logs dan incompleet? lijkt dat TCP connecties wel goed worden afgebroken en ook SSL sessies worden gesloten.

# TODO:
# * Bij inlezen alle ssl_entries koppelen aan een ssl_conn_block. (En evt ssl_session)
# * Horen alle ssl_entry items bij een ssl_session? Is dit belangrijk?
# * Nu wat dubbele code in deze vs ssl.tcl, vooral herkennen functype. Bv ssl ook OO maken, met nog meer pub/sub gebeuren.
# * aantal concurrent connections tellen? Zou std op max 6 moeten staan.
# * Code opschonen? bij checks op alle niveau's (conn, ssl, sess) nu niet clean.
#   - invarianten bij deze 3 dicts checken? Deze evt uit kunnen zetten, kost tijd.
#   - evt samen met debug mode zetten.
# * Testen met andere logfiles, vooral met nconc>1, en ssl protocol errors.

package require Tclx;           # for (set) union.

oo::class create ssl_session_conn {

  # 3 dicts (*_info) en wat losse instance vars:
  variable ssl_info sess_info conn_info db logfile_id vuserid iteration functypes

  constructor {a_db} {
    set db $a_db
    my define_tables
    set ssl_info [dict create]
    set sess_info [dict create]
    set conn_info [dict create]
    my define_functypes
    log debug "ssl_session_conn object created"
  }

  # destructor has no args/params
  destructor {
    unset ssl_info
    unset sess_info
    log debug "ssl_session_conn object destroyed"
  }

  method sub {topic value} {
    if {$topic == "iteration"} {
      set iteration $value
    }
  }
  
  method define_tables {} {
    $db add_tabledef ssl_conn_block {id} {logfile_id {linenr_min int} {linenr_max int}
      {iteration_min int} {iteration_max int} sess_id
      sess_address ssl ctx domain_port conn_nr {isglobal int} functype_first functype_last reason_insert {ssl_session_id int} ssl_session_reason {conn_block_id id}}
  }
  
  method bof {plogfile_id pvuserid piteration} {
    set logfile_id $plogfile_id
    set vuserid $pvuserid
    set iteration $piteration
  }

  method eof {plogfile_id piteration} {
    if {$plogfile_id != $logfile_id} {
      error "logfile_id at eof ($plogfile_id) differs from bof ($logfile_id)"
    }
    dict for {k v} $ssl_info {
      my insert_ssl $v "eof" "eof"
    }
  }

  method entry {entry_type linenr_min linenr_max lines} {
    # if {$entry_type != "ssl"} {return}
    if {$entry_type == "ssl"} {
      log debug "oo:handling entry: $entry_type (start: $linenr_min)"
      set entry [join $lines "\n"]
      # set functype [my det_functype $entry]
      set dentry [my det_entry_dict $entry]
      log debug "oo:dentry: $dentry"
      if {[:ssl $dentry] != ""} {
        my entry_ssl $dentry $linenr_min $linenr_max
      } elseif {[:sess_id $dentry] != ""} {
        my entry_sess_id $dentry $linenr_min $linenr_max
      } else {
        # ??? nothing ?
      }
    } elseif {$entry_type == "func"} {
      # alleen check op end connection?
      my entry_func $linenr_min $linenr_max $lines
    }
  }

  # pre: [:ssl $dentry] is filled
  method entry_ssl {dentry linenr_min linenr_max} {
    set dssl [dict_get $ssl_info [:ssl $dentry]]
    set functype [:functype $dentry]
    log debug "entry_ssl: start: $linenr_max"
    # cond_breakpoint {$linenr_max == 810}
    # keuze: eerst op functype checken, of of dssl leeg is of niet.
    if {$functype == "new_ssl"} {
      log debug "oo:handling newssl"
      # niet huidige afbreken, kunnen parallel zijn.
      # wel nieuwe maken voor in dict
      if {$dssl != {}} {
        # blijkbaar nog een oude, deze wegschrijven en verwijderen.
        log warn "oo:newssl entry ($linenr_min, [:ssl $dentry]) while already know this ssl: insert and start anew"
        my insert_ssl $dssl "newssl functype; have old one with same ssl: #$linenr_max" $linenr_max
      }
      my init_dssl $dentry $linenr_min $linenr_max
    } else {
      # functype wat anders, niet belangrijk?
      # kan ook een cb handshake zijn net nadat sessie is aangepast, en dus free global
      # is geweest: in dit geval is de ssl verdwenen en moet opnieuw opgebouwd.
      # cond_breakpoint {$dssl == {}}
      if {$dssl == {}} {
        set dssl [my init_dssl $dentry $linenr_min $linenr_max]
      }
      if {[my sess_id_filled_diff $dentry $dssl]} {
        log debug "oo:new session id: insert old and start anew"
        set conn_nr [:conn_nr $dssl]
        my insert_ssl $dssl "changed sess_id in dssl: #$linenr_max" $linenr_max
        my init_dssl $dentry $linenr_min $linenr_max $conn_nr
      } else {
        log debug "oo:appending info: $dssl with $dentry"
        set dssl2 [dict_merge_fn union $dssl $dentry]
        dict set dssl2 linenr_max $linenr_max
        dict lappend dssl2 entry_linenr_mins $linenr_min
        dict set dssl2 iteration_max $iteration
        dict set dssl2 functype_last [:functype $dentry]
        my dict_set_ssl_info [:ssl $dssl2] $dssl2
        my connect_sess_ssl [:sess_id $dssl2] [:ssl $dssl2]
      }
    }
    log debug "entry_ssl: end: $linenr_max"
    # cond_breakpoint {$linenr_max == 810}
  }

  method dict_set_ssl_info {ssl dssl} {
    my assert_dssl $dssl
    dict set ssl_info $ssl $dssl
  }
  
  method sess_id_filled_diff {d1 d2} {
    set s1 [:sess_id $d1]
    set s2 [:sess_id $d2]
    and {$s1 != {}} {$s2 != {}} {$s1 != $s2}
  }
  
  # pre: [:ssl $dentry] is not, filled, sess_id is filled.
  method entry_sess_id {dentry linenr_min linenr_max} {
    set functype [:functype $dentry]
    if {$functype == "freeing_global_ssl"} {
      my free_global_ssl $dentry $linenr_min $linenr_max
    }
  }

  method entry_func {linenr_min linenr_max lines} {
    # check if conn_nr is mentioned:
    # cond_breakpoint {$linenr_min == 1237}
    set entry [join $lines "\n"]
    set conn_nr ""
    set verb ""
    regexp {(Connecting) \[(\d+)\] to host (\S+)} $entry z verb conn_nr ip_port
    regexp {(Connected) socket \[(\d+)\] from .* to (\S+) in (\d+) ms} $entry z verb conn_nr ip_port conn_msec
    regexp {(Already) connected \[(\d+)\] to (\S+)} $entry z verb conn_nr domain_port
    regexp {(Closing) connection \[(\d+)\] to server (\S+)} $entry z verb conn_nr domain_port
    regexp {(Closed) connection \[(\d+)\] to (\S+) after completing (\d+) request} $entry z verb conn_nr domain_port nreqs
    regexp {Re-negotiating https connection \[(\d+)\] to ([^,]+),} $entry z conn_nr domain_port
    if {$conn_nr != ""} {
      log debug "conn:entry_func, conn_nr = $conn_nr"
      set ssl [dict_get $conn_info $conn_nr]
      if {$ssl != ""} {
        set dssl [dict_get $ssl_info $ssl]
        if {$dssl != {}} {
          if {$conn_nr != [:conn_nr $dssl]} {
            log error "conn_nrs differ between entry and found dssl"
            breakpoint
          }
          dict set dssl linenr_max $linenr_max
          dict set ssl_info $ssl $dssl
          log debug "conn:set ssl_info($ssl/$conn_nr).linenr_max to $linenr_max"
          if {$verb == "Closed"} {
            my insert_ssl $dssl "Closed TCP connection with conn_nr=$conn_nr: #$linenr_max" $linenr_max
          }
        } else {
          log warn "got ssl from conn_info: $ssl, but did not find dssl"
          breakpoint
        }
      } else {
        # je zou altijd een open ssl moeten hebben hier, behalve in het begin bij connecting/connected.
        if {$verb == ""} {
          log warn "ssl for conn_nr=$conn_nr not found"
          breakpoint
        } else {
          # verb set to Connecting or Connected.
        }
      }
    }
  }
  
  method det_entry_dict {entry} {
    # TODO: deze regexp's nu overgenomen uit handle_entry_ssl, dus dubbel.
    setvars {domain_port ssl ctx sess_address sess_id socket conn_nr} ""
    regexp {, connection=([^, ]+),} $entry z domain_port
    regexp {SSL=([0-9A-F]+)} $entry z ssl
    regexp {ctx=([0-9A-F]+)} $entry z ctx
    regexp {session address=([0-9A-F]+)} $entry z sess_address
    regexp {ID \(length \d+\): ([0-9A-F]+)} $entry z sess_id
    regexp {session id: \(length \d+\): ([0-9A-F]+)} $entry z sess_id
    regexp {socket=([A-Fa-f0-9]+) \[(\d+)\]} $entry z socket conn_nr
    set functype [my det_functype $entry]
    vars_to_dict functype domain_port ssl ctx sess_address sess_id socket conn_nr
  }

  # pre dentry/ssl has a value, sess_id might have a value.
  # with changed session within a ssl/conn, transfer conn_nr to the next
  method init_dssl {dentry linenr_min linenr_max {conn_nr ""}} {
    set dssl $dentry
    dict set dssl linenr_min $linenr_min
    dict set dssl linenr_max $linenr_max
    dict set dssl entry_linenr_mins [list $linenr_min]
    dict set dssl iteration_min $iteration
    dict set dssl iteration_max $iteration
    dict set dssl isglobal 0
    dict set dssl logfile_id $logfile_id
    dict set dssl functype_first [:functype $dentry]
    dict set dssl functype_last [:functype $dentry]
    if {$conn_nr != ""} {
      dict set dssl conn_nr $conn_nr
    }
    my dict_set_ssl_info [:ssl $dentry] $dssl
    my connect_sess_ssl [:sess_id $dssl] [:ssl $dssl]
    my connect_ssl_conn [:ssl $dssl] [:conn_nr $dssl] $linenr_max
    return $dssl
  }

  # TODO: ? ook linenr waarop deze 2 dingen gekoppeld worden?
  # TODO: evt oude connectie deleten.
  method connect_sess_ssl {sess_id ssl} {
    if {($sess_id != "") && ($ssl != "")} {
      my disconnect_sess_ssl [:sess_id [dict_get ssl_info $ssl]] $ssl 
      dict set sess_info $sess_id [union [dict_get $sess_info $sess_id] $ssl]
    }
  }

  method disconnect_sess_ssl {sess_id ssl} {
    if {($sess_id != "") && ($ssl != "")} {
      set lssl [dict_get $sess_info $sess_id]
      lremove lssl $ssl
      if {$lssl == {}} {
        dict unset sess_info $sess_id
      } else {
        dict set sess_info $sess_id $lssl
      }
    }
  }

  # TODO: invariant data model checken: ssl_info, conn_info en sess_info?
  # moet dan kloppen nadat je een entry volledig hebt afgehandeld.
  method connect_ssl_conn {ssl conn_nr linenr} {
    # vorige SSLs op dit conn_nr moet je afsluiten/inserten.
    if {$conn_nr != ""} {
      foreach old_ssl [dict_get $conn_info $conn_nr] {
        if {$old_ssl == $ssl} {
          # same one, do nothing
          log debug "connect_ssl_conn: called on existing combi: $ssl <-> $conn_nr"
        } else {
          log debug "connect_ssl_conn: old ssl found, close: $old_ssl <-> $conn_nr"
          set dssl [dict_get ssl_info $old_ssl]
          if {$dssl != {}} {
            my insert_ssl $dssl "connect_ssl_conn ($ssl,$conn_nr), close old ones." $linenr
          }
        }
      }
      dict set conn_info $conn_nr $ssl
    }
    log debug "conn:connect_ssl_conn: $ssl $conn_nr $linenr. conn_info: $conn_info"
  }

  method disconnect_ssl_conn {ssl conn_nr linenr} {
    # TODO: evt checken of de ssl die je verwijdert dezelfde is als die je meekrijgt.

    if {$conn_nr != ""} {
      dict unset conn_info $conn_nr
    }
    log debug "conn:disconnect_ssl_conn: $ssl $conn_nr $linenr. conn_info: $conn_info"
  }

  # write ssl record to db, remove from 'global' list
  method insert_ssl {dssl reason linenr} {
    log debug "inserting ssl_conn_block: $dssl"
    dict set dssl reason_insert $reason
    # cond_breakpoint {[:linenr_max $dssl] == 876}
    my assert_dssl $dssl
    # dict set dssl logfile_id $logfile_id
    # dict set dssl iteration_max $iteration
    set ssl_conn_block_id [$db insert ssl_conn_block $dssl]
    # TODO: bij alle gekoppelde ssl_entry records het fkey veld ssl_conn_block_id vullen.
    foreach linenr_min [:entry_linenr_mins $dssl] {
      $db exec "update ssl_entry set ssl_conn_block_id = $ssl_conn_block_id
                where ssl_conn_block_id is null
                and logfile_id = $logfile_id
                and linenr_min = $linenr_min"
    }
    dict unset ssl_info [:ssl $dssl]
    my disconnect_sess_ssl [:sess_id $dssl] [:ssl $dssl]
    my disconnect_ssl_conn [:ssl $dssl] [:conn_nr $dssl] $linenr
  }

  method assert_dssl {dssl} {
    if {[:# [:sess_id $dssl]] > 1} {
      error "More than one sess_id in dssl: $dssl"
    }
    foreach k {:linenr_min :logfile_id :iteration_max} {
      if {[$k $dssl] == ""} {
        log error "$k not set in dssl: $dssl"
        breakpoint
        error "$k not set in dssl: $dssl"
      }
    }
  }

  method free_global_ssl {dentry linenr_min linenr_max} {
    set sess_id [:sess_id $dentry]
    if {[dict_get $sess_info $sess_id] == {}} {
      # dit kan nu voorkomen, als door nieuwe sessie de oude al is afgesloten; deze dan ignore.
      # log error "$sess_id does not occur in sess_info."
      # breakpoint
    }
    # cond_breakpoint {$linenr_max == 811}
    foreach ssl [dict_get $sess_info $sess_id] {
      set dssl [dict get $ssl_info $ssl]
      dict set dssl isglobal 1
      # 7-5-2016 linenr_max en iteration_max op oude waarden laten, weet alleen zeker
      # dat ze uiterlijk op dit linenr zijn afgesloten.
      #dict set dssl linenr_max $linenr_max
      #dict set dssl iteration_max $iteration
      if {$sess_id != [:sess_id $dssl]} {
        log error "sess_id in dentry differs from sess_id's from connected dssl"
        breakpoint
      } else {
        dict lappend dssl entry_linenr_mins $linenr_min
      }
      my insert_ssl $dssl "free_global_ssl: #$linenr_max" $linenr_max
    }
    dict unset sess_info $sess_id
  }
  
  method define_functypes {} {
    set functypes {
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
  }
  
  method det_functype {entry} {
    foreach {re ft} $functypes {
      if {[regexp $re $entry]} {
        return $ft
      }
    }
    return "unknown"

    
  }
  
}
