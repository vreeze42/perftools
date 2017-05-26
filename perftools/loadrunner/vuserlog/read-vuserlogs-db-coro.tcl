#!/usr/bin/env tclsh

# TODO: [2016-08-18 13:15:36] version for vugen, integrate with version for AHK.

# [2016-08-06 11:31] At first a new file with coroutine implementation for reading logs.
# for now keep side-by-side with orig (working!) version.

# 2 entry points:
# * define_logreader_handlers - define parsers and handlers
# * readlogfile_new_coro $logfile [vars_to_dict db ssl split_proc]
#   - this one calls readlogfile_coro, as defined in liblogreader.tcl, not here.

package require ndv
# ndv::source_once liblogreader.tcl

set perftools_dir [file normalize [file join [file dirname [info script]] .. ..]]

# TODO: use source_once with absolute path?
source [file join $perftools_dir logdb liblogreader.tcl]
source [file join $perftools_dir logdb librunlogreader.tcl]


require libdatetime dt
require libio io
use libmacro;                   # syntax_quote

# [2016-08-07 13:29] deze zorgt er nu voor dat global (zoals de naam zegt) overal loglevel
# op debug komt, wil je in het algemeen niet. 2 opties:
# * de set_log_global doet alleen wat als de log nog niet gezet is.
# * iets met namespaces, log object per namespace. De log proc moet dan de goede pakken.

# set_log_global debug {showfilename 0}

# separate function, to be called once, even when handling multiple log files.
proc define_logreader_handlers {} {
  log debug "define_logreader_handlers (vuserlogs): start"
  # of toch een losse namespace waar deze dingen in hangen?

  reset_parsers_handlers
  
  def_parsers
  def_handlers
  # breakpoint
}

# main function to be called for each log file.
proc readlogfile_new_coro {logfile db ssl split_proc} {
  # some prep with inserting record in db for logfile, also do with handler?
  if {[is_logfile_read $db $logfile]} {
    return
  }
  set vuserid [det_vuserid $logfile]
  if {$vuserid == ""} {
    log warn "Could not determine vuserid from $logfile: continue with next."
    return
  }
  set ts [clock format [file mtime $logfile] -format "%Y-%m-%d %H:%M:%S"]
  
  set dirname [file dirname $logfile]
  set filesize [file size $logfile]
  lassign [det_project_runid_script $logfile] project runid script

  $db in_trans {
    set logfile_id [$db insert logfile [vars_to_dict logfile dirname ts \
                                            filesize runid project script]]
    # call proc in liblogreader.tcl
    readlogfile_coro $logfile [vars_to_dict db ssl split_proc logfile_id vuserid]  
  }
}

# replace resptime=1,642, status= with resptime=1.642, status=
# so <digit>,<digit>
# [2016-09-20 14:21:05] nog niet goed, zie laatste logfile.
proc replace_decimal_comma {fields} {
  regsub {resptime=-?(\d+),(\d+),} $fields {resptime=\1.\2,} fields2
  return $fields2
}

proc def_parsers {} {

  def_parser trans_line trans_line {
    # [2016-08-23 17:11:14] wil achter (ignored) ts aan het einde een ? in de regexp zetten, maar dan meegenomen in de vorige, en timestamp
    # aan iteration vastgeplakt.
    # [2016-11-30 21:29] changed regexp again, now with literal iteration.
    if {[regexp {: \[([0-9 :.-]+)\] (trans=.+?iteration=\d+)( \[[Time0-9/ :-]+])?} $line z ts fields]} {
      set fields [replace_decimal_comma $fields]
      set nvpairs [log2nvpairs $fields]; # possibly give whole line to log2nvpairs
      dict set nvpairs ts $ts
      dict set nvpairs sec_ts [parse_ts [:ts $nvpairs]]
      # [2016-09-21 16:24:52] Vraag of onderstaande wel zin heeft, als eerder al op comma de velden/waarden bepaald zijn.
      dict set nvpairs resptime [regsub -all {,} [:resptime $nvpairs] "."]
      return [dict_rename $nvpairs {trans status} {transname trans_status}]
    } elseif {[regexp {trans=} $line]} {
      # [2016-09-22 09:50:38] nu 2 varianten, dus geen breakpoint.
      breakpoint
    } else {
      return ""
    }
  }

  # [2016-09-22 09:47:49] deze nog even voor oude logs, maar deprecated.
  def_parser trans_line trans_line_old {
    # [2016-08-23 17:11:14] wil achter (ignored) ts aan het einde een ? in de regexp zetten, maar dan meegenomen in de vorige, en timestamp
    # aan iteration vastgeplakt.
    if {[regexp {: \[([0-9 :.-]+)\] \[\d+\] (trans=.+?)( \[[Time0-9/ :-]+])} $line z ts fields]} {
      set fields [replace_decimal_comma $fields]
      set nvpairs [log2nvpairs $fields]; # possibly give whole line to log2nvpairs
      dict set nvpairs ts $ts
      dict set nvpairs sec_ts [parse_ts [:ts $nvpairs]]
      # [2016-09-21 16:24:52] Vraag of onderstaande wel zin heeft, als eerder al op comma de velden/waarden bepaald zijn.
      dict set nvpairs resptime [regsub -all {,} [:resptime $nvpairs] "."]
      return [dict_rename $nvpairs {trans status} {transname trans_status}]
    } elseif {[regexp {trans=} $line]} {
      # [2016-09-22 09:50:38] nu 2 varianten, dus geen breakpoint.
      # breakpoint
    } else {
      return ""
    }
  }

def_parser trans_param trans_param {
    # TODO: [2016-08-23 17:17:15] wil ? achter optional time aan het einde, maar dan wordt 'ie bij paramvalue meegenomen.
    if {[regexp {: \[([0-9 :.-]+)\] Trans param: ([^= ]+) = (.*)( \[(Time:)?[0-9/ :-]+])} $line z ts paramname paramvalue]} {
        log debug "Found trans_param: $paramname = $paramvalue"
        return [dict create ts $ts sec_ts [parse_ts $ts] paramname $paramname paramvalue $paramvalue]
    } elseif {[regexp {Trans param: } $line]} {
        breakpoint
    } else {
      return ""
    }
  }

  def_parser errorline errorline1 {
    if {[regexp {^([^ ]+)\((\d+)\): (Continuing after )?Error ?([0-9-]*): (.*)$} $line z srcfile srclinenr z errornr rest]} {
      # [2016-08-07 13:24] ignore user field (z_user) returned from det_error_details, too specific and already have in trans_line.
      lassign [det_error_details $rest] errortype z_user level details
      log debug "Parsed errorline, returning: $srcfile/$srclinenr/$linenr: $line"
      return [vars_to_dict srcfile srclinenr errornr errortype details line]
    } elseif {[regexp {: Error: } $line]} {
      log error "Error line in log, but could not parse: $line"
      breakpoint
    } elseif {[regexp {Continuing after Error} $line]} {
      log error "Continuing after Error found, but could not parse: $line"
      breakpoint
    } else {
      return ""      
    }
  }

  def_parser errorline errorline2 {
    if {[regexp {^([^ ]+)\((\d+)\): .* ERROR - (.+)$} $line z srcfile srclinenr details]} {
      return [vars_to_dict srcfile srclinenr details line]
    } else {
      return ""
    }
  
  }

def_parser_regexp_srcline step_start step_start {(web_url|web_submit_data|web_custom_request|web_rest|web_submit_form)\("(.+?)"\) started} step_type step_name

def_parser_regexp_srcline request_start request_start {: (\d+)-byte request headers for "(.+?)" \(RelFrameId} reqheaderbytes url

# auto log messages start and end.
# [2016-12-23 19:24] possibly not even needed: auto_log_start/auto_log_end.
def_parser_regexp auto_log_start auto_log_start {Start auto log messages stack - Iteration (\d+).} iteration

def_parser_regexp auto_log_end auto_log_end {End auto log messages stack.}

# error line with timestamp
# tradesearch_exit_rebuild.c(15): Error -35049: No match found for the requested parameter "ParentDealId". Check whether the requested regular expression exists in the response data     [MsgId: MERR-35049] [Time:2016-12-21 18:30:27]

def_parser_regexp_srcline errorline_ts errorline_ts {Error ([-0-9]+): (.*?) \[Time:([0-9 :-]+)\]} errornr errortext ts

}

# Most log lines in vugen/vuserlog start with sourcefile/sourceline, include those in topic-items.
proc def_parser_regexp_srcline {topic label re args} {
  # set re_ts {\[([0-9 :.-]+)\]}
  set re_srcline {^(.+?\.c)\((\d+)\): .*?}
  def_parser_regexp $topic $label "$re_srcline$re" srcfile srclinenr {*}$args
} 

# @return dict with key=name, val=val.
# [2016-08-07 12:12] for now, line is already the part that needs to be split, not the whole logline.
proc log2nvpairs {line} {
  log debug "log2nvpairs: $line"
  set d [dict create]
  # [2016-08-19 21:00] split works with characters, not string, so only check comma and equals, and use string trim.
  foreach nv [split $line ","] {
    lassign [split [string trim $nv] "="] nm val
    log debug "log2nvpairs: $nm->$val"
    dict set d $nm $val
  }
  return $d
}

proc def_handlers {} {

    # convert trans_line => trans
    def_handler trans {bof eof trans_line trans_param errorline_ts} trans {
    # init
    set user ""; set iteration 0; set split_proc "<none>"; set trans_params [dict create]
} {
    # body/loop
    log debug "trans-handler - assert topic [:topic $item], item: $item"
    assert {[lsearch -exact [dict keys $item] ""] < 0}  
    switch [:topic $item] {
        bof {
            set started_transactions [dict create]
            dict_to_vars $item ;    # set db, split_proc, ssl
        }
        eof {
            res_add res {*}[make_trans_not_finished $started_transactions]
        }
        trans_param {
            log debug "in trans handler, got trans_param: $item"
            dict set trans_params [:paramname $item] [:paramvalue $item]
        }
        errorline_ts {
            log debug "found errorline, possibly no end-trans for start-trans"
            set started_transactions [update_with_errorline_ts $started_transactions $item]
        }
        trans_line {
            if {[new_user_iteration? $item $user $iteration]} {
                res_add res {*}[make_trans_not_finished $started_transactions]
                set started_transactions [dict create]
                dict_to_vars $item; # user, iteration
            }
            set item [dict merge $item [$split_proc [:transname $item]]]
            switch [:trans_status $item] {
                -1 {
                    # start of a transaction, keep data to combine with end-of-trans.
                    dict set started_transactions [:transname $item] $item
                    # TODO: reset trans_params on new transaction, will fail for nested transactions. Will also fail when done at end transaction,
                    # need concept of nested transactions here (and record nesting level)
                    # [2017-03-22 10:12:54] TODO: voor nu even niet, params bewaren.
                    # [2017-03-22 10:15:27] Deze werkt nu voor iteration_sub en password.
                    # set trans_params [dict create]
                }
                0 {
                    # succesful end of a transaction, find start data and insert item.
                    set tr [dict merge $trans_params [make_trans_finished $item $started_transactions]]
                    log debug "trans handler: adding trans: $tr"
                    res_add res $tr
                    dict unset started_transactions [:transname $item]; # 
                    # TODO: also unset trans_params? Only if they really are trans params, not iteration params.
                }
                1 {
                  # synthetic error, just insert.
                  # [2016-08-17 15:07:08] could also have a start trans (-1) for this, so also dict unset.
                  # res_add res [make_trans_error $item]
                  # set tr [dict merge $trans_params [make_trans_error $item]]
                  # [2017-04-11 16:52:48] use (possible) started transaction for start time
                  set tr [dict merge $trans_params [make_trans_finished $item $started_transactions]]
                  res_add res $tr
                  dict unset started_transactions [:transname $item]
                }
                2 {
                  # res_add res [make_trans_error $item]
                  set tr [dict merge $trans_params [make_trans_finished $item $started_transactions]]
                  res_add res $tr
                  dict unset started_transactions [:transname $item]
                }
                4 {
                    # [2016-08-12 20:46] possibly also call make_trans_error here,
                    # but no logfile to test with here. Check status (should be 4)
                    # res_add res [make_trans_finished $item $started_transactions]
                    set tr [dict merge $trans_params [make_trans_finished $item $started_transactions]]
                    res_add res $tr
                    
                    # [2016-08-17 15:07:45] also dict unset just to be sure:
                    dict unset started_transactions [:transname $item]
                }
                default {
                    error "Unknown transaction status: [:trans_status $item]"
                }
            };                  # end-of-switch-status
        }
    };                          # end-of-switch-topic
};                          # end-of-define-handler

  # make error object from errorline and trans_line
  def_handler error {trans_line errorline} error {set trans_line_item {}} {
    switch [:topic $item] {
      trans_line {
        set trans_line_item $item
      }
      errorline {
        # set res [dict merge $trans_line_item $item]
        log debug "def_handler/errorline found: $item"
        res_add res [dict merge $trans_line_item $item]
      }
    }
    # set item [yield $res]
  }

  def_handler step {trans_line step_start} step {set trans_line_item {}} {
    switch [:topic $item] {
      trans_line {
        set trans_line_item $item
      }
      step_start {
        res_add res [dict merge $trans_line_item $item]
      }
    }
  }

  def_handler request {trans_line step_start request_start} request {set trans_line_item {}; set step_start_item {}} {
    switch [:topic $item] {
      trans_line {
        set trans_line_item $item
      }
      step_start {
        set step_start_item $item
      }
      request_start {
        res_add res [dict merge $trans_line_item $step_start_item $item]
      }
    }
  }
  
  # [2016-08-09 22:29] introduced a bug here by not calling split_proc in insert-trans_line
  # but in trans split_proc is called, and this is used in report. Could also remove fields
  # in trans_line, also split_proc still is somewhat of a hack now.
  # def_insert_handler trans_line
  def_insert_handler trans
  def_insert_handler error
  def_insert_handler step
  def_insert_handler request
  
  
}

# global fload file
# set fload [open "loadfile.txt" w]

# Specific to this project, not in liblogreader.
# combination of item and file_item
proc def_insert_handler {table} {
  global fload
  def_handler "i:$table" [list bof $table] {} [syntax_quote {
    global fload
    if {[:topic $item] == "bof"} { # 
      # dict_to_vars $item ;    # set db, split_proc, ssl
      # set file_item $item
      set db [:db $item]
      set file_item [dict remove $item db split_proc ssl]
    } else {
      # FIXME: [2017-03-31 16:29:52] nu even niets in de DB, kijken hoe snel het dan gaat.
      $db insert ~$table [dict remove [dict merge $file_item $item] topic]
      # puts $fload "~$table [dict remove [dict merge $file_item $item] topic]"
    }
  }]
}

proc det_vuserid {logfile} {
  if {[regexp {_(\d+).log} $logfile z vuser]} {
    return $vuser
  } elseif {[file tail $logfile] == "output.txt"} {
    # Vugenlog file, vuser=-1
    return -1
  } else {
    log warn "Could not determine vuser from logfile: $logfile"
    return ""
  }
}

proc det_project_runid_script {logfile} {
  # [-> $logfile {file dirname} {file dirname} {file tail}]
  set project [file tail [file dirname [file dirname $logfile]]]
  if {[regexp {run(\d+)} [file tail [file dirname $logfile]] z id]} {
    set runid $id
  } else {
    set runid ""
  }
  if {[regexp {^(.+)_\d+\.log$} [file tail $logfile] z scr]} {
    set script $scr
  } else {
    set script ""
  }
  
  list $project $runid $script
}

# return 1 iff either old user or old iteration differs from new one in row
proc new_user_iteration? {row user iteration} {
  if {($user != [:user $row]) || ($iteration != [:iteration $row])} {
    return 1
  }
  return 0
}

# TODO: should put this in own namespace.
set error_res {
  {Text=Uw pas is niet correct} pas_niet_correct 10

  {HTTP Status-Code=500} http500 9
  {Er is een technisch probleem opgetreden} tech_problem 9
  {A technical error has occurred at} tech_error 9
  {Gateway Time-out} gateway_timeout 9
  {Connection reset by peer} conn_reset 9
  {has shut down the connection prematurely} conn_shutdown 9
  {SSL protocol error when attempting to connect} ssl_error 9
  
  {Step download timeout} step_timeout 8
  {Connection timed out} connection_timeout 8

  {may be explained by header and body byte counts being} explained_header_body 3
  
  {No match found for the requested parameter} no_match 0
  {not found for web_reg_find} web_reg_find 0
}

proc det_error_details {rest} {
  global error_res
  set user ""
  set errortype ""
  set details ""
  set level -1
  regexp {User:(\d+) pas} $rest z user
  regexp {No match found for the requested parameter \"([^ ]+)\"} $rest z details
  regexp {\"Text=(.+)\" not found for web_reg_find} $rest z details
  foreach {re tp lv} $error_res {
    if {[regexp $re $rest]} {
      set errortype $tp
      set level $lv
      break
    }
  }
  list $errortype $user $level $details
}

# set started_transactions [update_with_errorline_ts $started_transactions $item]
proc update_with_errorline_ts {started_transactions item} {
  log debug "Update_with_errorline_ts called"
  dict map {transname trans} $started_transactions {
    update_trans_with_errorline_ts $transname $trans $item
  }
}

proc update_trans_with_errorline_ts {transname trans item} {
  dict merge $trans [dict create ts_end [:ts $item]]
}

