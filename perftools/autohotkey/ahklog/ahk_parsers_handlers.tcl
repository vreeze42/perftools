# separate function, to be called once, even when handling multiple log files.
proc define_logreader_handlers_ahk {} {
  log debug "define_logreader_handlers: start"
  reset_parsers_handlers;       # to clean up possible readers/handlers for vugen logs.
  def_parsers_ahk
  def_handlers_ahk
}

proc def_parsers_ahk {} {

  def_parser_regexp_ts iter_start_finish it_start_finish {\[iter\] ([^ ]+) iteration: (\d+)} \
      start_finish iteration

  def_parser_regexp_ts trans_start trans_start \
      {\[trans\] Transaction started ?: ([^,\r\n]+)} transname
  
  def_parser_regexp_ts trans_finish trans_finish \
      {\[trans\] Transaction finished: ([^,]+), success: (\d), transaction time \(sec\): ([-0-9.]+),} transname success resptime

  def_parser_regexp_ts errorline errorline {\[error\] (.*)$} line

  # [2016-08-13 19:34] need to use \S+, just [^ ]+ fails, adds newline/cr?
  def_parser_regexp_ts user user {\[info\] Iteration (\d+), user: (\S+)} \
      iteration user

  def_parser_regexp_ts resource_line resource_line \
      {\[info\] capturing screen to: ([^ ]+) in directory:} resource

  # [2016-08-13 19:58] deze niet, want bestaat niet en heb ook capturing screen
  # waar 'ie wel in staat.
  # def_parser_regexp_ts resource_linexx \
    #  {\[info\] Saved desktop to: ([^ ]+)$} resource
      
  # transaction/iteration parameters
  # [2016-08-23 16:10:59] NdV voorlopig nog even allebei, Trans param is de nieuwe.
  # TODO: hernoemen naar Iteration param, onderscheid met Trans param, scope anders.
  def_parser_regexp_ts iteration_param it_param1 {\[perf\] (..Bulk_nrecords): (.*)$} paramname paramvalue
  def_parser_regexp_ts iteration_param it_param2 {\[perf] Iteration param: ([^= ]+) = (.*)$} paramname paramvalue
}

# [2016-08-13 18:17] for now AHK specific, maybe more generic (also like Splunk with timestamps?).
# add regexp for ts and ts to re and args
proc def_parser_regexp_ts {topic label re args} {
  set re_ts {\[([0-9 :.-]+)\]}
  def_parser_regexp $topic $label "$re_ts $re" ts {*}$args
}

proc def_handlers_ahk {} {

  def_handler trans {iter_start_finish user trans_start trans_finish iteration_param eof} trans {
    set transactions [dict create]
    set user "NONE"
  } {
    log debug "Doing assert for empty key for topic [:topic $item], item: $item"
    assert {[lsearch -exact [dict keys $item] ""] < 0}  
    switch [:topic $item] {
      iter_start_finish {
        if {[:start_finish $item] == "Start"} {
          # TODO: check if all transactions have finished, empty list. Like:
          # res_add res {*}[make_trans_not_finished $started_transactions]
          # preferably generic code, share with vugen code.
          # assert {[:# $transactions] == 0}
          set iteration [:iteration $item]
          set transactions [dict create]
          set iteration_params [dict create]
        } else {
          # TODO: maybe also finish transactions here.
          # assert {[:# $transactions] == 0}
          set user "NONE"
          set iteration_params [dict create]
        }
      }
      iteration_param {
        # sla name en value plat tot key=name, val=value
        dict set iteration_params [:paramname $item] [:paramvalue $item]
      }
      trans_start {
        dict set transactions [:transname $item] [add_sec_ts $item]
      }
      trans_finish {
        # TODO: remove res name here, is always the same, just res_add is enough
        # TODO: should use generic make_trans_finished (not _ahk), but these don't use
        #       iteration and user.
        res_add res [dict merge $iteration_params [make_trans_finished_ahk [add_sec_ts $item] $transactions \
                         $iteration $user]]
        dict unset transactions [:transname $item]
        # set iteration_params [dict create] ; # only reset at the end of iteration.
      }
      user {
        set user [:user $item]
      }
      eof {
        # [2016-08-23 13:34:15] switched off assert wrt testruns ended prematurely.
        # activate assert again.
        # assert {[:# $transactions] == 0}
      }
    }
  }

  def_handler error {iter_start_finish user errorline} error {
    set user "NONE"
  } {
    switch [:topic $item] {
      iter_start_finish {
        if {[:start_finish $item] == "Start"} {
          set iteration [:iteration $item]
        }
      }
      user {
        set user [:user $item]
        if {$user != [string trim $user]} {
          breakpoint
        }
      }
      errorline {
        res_add res [make_error_ahk [add_sec_ts $item] $iteration $user]
      }
    }
  }

  def_handler resource {iter_start_finish user trans_start resource_line} resource {
    # [2016-08-13 18:52] start bitmap is saved, before iteration starts.
    set user "NONE"
    set iteration 0
    set transname NONE
  } {
    switch [:topic $item] {
      iter_start_finish {
        if {[:start_finish $item] == "Start"} {
          set iteration [:iteration $item]
        }
      }
      user {
        set user [:user $item]
      }
      trans_start {
        set transname [:transname $item]
      }
      resource_line {
        res_add res [make_resource_ahk [add_sec_ts $item] $iteration $user $transname]
      }
    }
  }
  
  # def_insert_handler trans_line
  def_insert_handler trans
  def_insert_handler error
  def_insert_handler resource

}

proc add_sec_ts {item} {
  dict merge $item [dict create sec_ts [parse_ts [:ts $item]]]
}

# TODO: [2016-08-13 11:24] name clash with vugen version, so renamed for now.
# TODO: should be deleted, and generic version used, but need to do something with
#       iteration and user first, not given in generic version.
proc make_trans_finished_ahk {item transactions iteration user} {
  assert {$iteration > 0}
  log debug "iteration: $iteration"
  set line_fields {linenr ts sec_ts}
  set line_start_fields [map [fn x {return "${x}_start"}] $line_fields]
  set line_end_fields [map [fn x {return "${x}_end"}] $line_fields]
  #set no_start 0

  dict set item trans_status [success_to_trans_status [:success $item]]
  set item [dict merge $item [split_transname [:transname $item]]]
  set itemstart [dict_get $transactions [:transname $item]]
  if {$itemstart == {}} {
    # probably a synthetic transaction. Some minor error.
    set itemstart $item
    #set no_start 1
  }
  set dstart [dict_rename $itemstart $line_fields $line_start_fields]
  set dend [dict_rename $item $line_fields $line_end_fields]
  set diteration [dict create iteration_start $iteration iteration_end $iteration]
  set duser [dict create user $user]
  set d [dict merge $diteration $duser $dstart $dend]
  log debug "d: $d"
  log debug "dtart: $dstart"
  log debug "dend: $dend"
  assert {[:iteration_start $d] > 0}
  return $d
}

proc split_transname {transname} {
  # TODO: straks andere transnames incl usecase, zonder nummers.
  if {[regexp {^([^_]+)_(.+)$} $transname z usecase transshort]} {
    vars_to_dict usecase transshort
  } else {
    dict create usecase NONE transshort $transname  
  }
}

proc success_to_trans_status {success} {
  switch $success {
    0 {return 1}
    1 {return 0}
  }
}

proc make_error_ahk_old {item iteration user} {
  dict set item iteration $iteration
  dict set item user $user
  return $item
}

proc make_error_ahk  {item iteration user} {
  dict merge $item [vars_to_dict iteration user]
}

proc make_resource_ahk {item iteration user transname} {
  dict merge $item [vars_to_dict iteration user transname]
}

# Specific to this project, not in liblogreader.
# combination of item and file_item
# TODO: maybe generic after all, directly usable for AHK log?
proc def_insert_handler {table} {
  def_handler "i:$table" [list bof $table] {} [syntax_quote {
    if {[:topic $item] == "bof"} { # 
      dict_to_vars $item ;    # set db, split_proc, ssl
      set file_item $item
    } else {
      log debug "Insert record in ~$table: $item"
      $db insert ~$table [dict merge $file_item $item]
    }
  }]
}

