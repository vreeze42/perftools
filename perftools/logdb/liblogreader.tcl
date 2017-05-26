package require struct::queue
package require ndv

# This lib is the most generic logreader, not really specific for performance run
# log readers. Mainly about parsers and handlers to use within coroutine based log
# readers.

# TODO: put in namespace.

require libio io
use libmacro

proc reset_parsers_handlers {} {
  global parsers handlers
  set parsers [list]
  set handlers [dict create]
}

reset_parsers_handlers

# main proc
# [2016-08-05 20:39] Another go at readlogfile, with knowledge of coroutines.
# opt: dict with extra options, like db object.
proc readlogfile_coro {logfile {opt ""}} { # 
  global parsers ;              # list of proc-names.
  global handlers; # dict key=in-topic, value = list of [dict topic coro-name]
  set to_publish [struct::queue]
  $to_publish put [dict merge [dict create topic bof logfile $logfile] $opt]
  handle_to_publish $to_publish
  io/with_file f [open $logfile rb] {
    # still line based for now
    set linenr 0
    while {[gets $f line] >= 0} {
      incr linenr
      set line [remove_cr $line]; # remove windows \r from end of line
      handle_parsers $to_publish $logfile $line $linenr
      handle_to_publish $to_publish
    }
  }
  $to_publish put [dict create topic eof logfile $logfile]; # handle eof topic
  handle_to_publish $to_publish
  set db [:db $opt]

  # create indexes just before report.
  #logdb_make_indexes $db
}

proc remove_cr {line} {
  if {[regexp {^(.*)\r$} $line z line2]} {
    return $line2
  }
  return $line
}

# define a simple regexp parser (compare Splunk)
# TODO: put the named args in the regexp, like Splunk? 
# args contains the keys in dict to save, match with regexp groups.
# eg def_parser_regexp $re ts start_finish iteration
proc def_parser_regexp {topic label re args} {
  def_parser $topic $label [syntax_quote {
    if {[regexp ~$re $line z ~@$args]} {
      vars_to_dict ~@$args
    } else {
      return ""
    }
  }]
}

# first define parsers and handlers, before calling readlogfile_coro
proc def_parser {topic label body} {
  global parsers ;              # list of [dict topic proc_name]
  # [2016-08-09 21:08] unique_name - multiple parsers for same topic are possible.
  set proc_name [unique_name parse_$topic]
  # set label parse_$topic
  set label "p:$label"
  lappend parsers [vars_to_dict topic proc_name label]
  proc $proc_name {line linenr} $body
}

# args: either init, body or just body
# at start of body, res is set to empty, item contains item/dict just received.
# at end of body, res should be set to 0, 1 or more result items.
proc def_handler {label in_topics out_topic args} {
  if {[:# $args] == 2} {
    lassign $args init body
  } else {
    lassign $args body
    set init {}
  }
  set body2 [syntax_quote {~@$init
    set item [yield]
    while 1 {
      # set res ""
      res_init res
      ~@$body
      set item [yield $res]
    }
  }]
  log debug "body2: $body2"
  def_handler_internal $label $in_topics $out_topic $body2
}

# out_topic is identifying, key.
# in_topics needed to decide which handlers to call for a topic.
proc def_handler_internal {label in_topics out_topic body} {
  global handlers; # dict key=in-topic, value = list of [dict topic coro-name]
  if {$out_topic == ""} {
    # set coro_name [unique_name coro_make_]
    set coro_name [unique_name make_]
  } else {
    # set coro_name "coro_make_${out_topic}"
    set coro_name [unique_name make_$out_topic]
  }
  # log debug "def_handler: coro_name: $coro_name"
  foreach in_topic $in_topics {
    dict lappend handlers $in_topic [dict create coro_name $coro_name topic $out_topic \
                                        label h:$label]
  }
  # now not a normal proc-def, but a coroutine.
  # apply is the way to convert a body to a command/'proc'.
  coroutine $coro_name apply [list {} $body]
}

proc handle_parsers {to_publish logfile line linenr} {
  global parsers ;              # list of [dict topic proc_name]
  # first put through all parsers, and put in queue to_pub
  # to_publish is empty here.
  assert {[$to_publish size] == 0}
  foreach parser $parsers {
    # TODO: maybe also add full line as a key in the dict?
    set res [add_topic_file_linenr [[:proc_name $parser] $line $linenr] \
                 [:topic $parser] $logfile $linenr $line]
    # result should be a dict, including a topic field for pub/sub (coroutine)
    # channels. Also, more than one parser could produce a result. A parser produces
    # max 1 result for 1 topic, handlers could split these into multiple results.
    if {$res != ""} {
      log debug "Created item to publish: $res"
      $to_publish put $res
    }
  }
}

proc handle_to_publish {to_publish} {
  global handlers; # dict key=in-topic, value = list of [dict topic coro_name]
  while {[$to_publish size] > 0} {
    set item [$to_publish get]
    set topic [:topic $item]
    if {$topic == "errorline"} {
      log debug "handling topic errorline: $item"
    }
    # could be there are no handlers for a topic, eg eof-topic. So use dict_get.
    foreach handler [dict_get $handlers $topic] {
      if {$topic == "errorline"} {
        log debug "in foreach handler of errorline."
        # breakpoint
      }
      set res [[:coro_name $handler] $item]
      foreach el $res {
        if {$topic == "errorline"} {
          log debug "Adding new item: $el"
        }
        $to_publish put [add_topic $el [:topic $handler]]
      }
    }
  }
}

# post process all parser results to add topic, logfile and linenr
proc add_topic_file_linenr {item topic logfile linenr line} {
  if {$item == ""} {
    return ""
  }
  #log debug "add_topic_file_linenr"
  #breakpoint
  dict merge $item [vars_to_dict topic logfile linenr line]
}

# post process all handler/maker results to add just topic
proc add_topic {item topic} {
  log debug "add_topic: $item --- $topic"
  if {$item == ""} {
    return ""
  }
  dict merge $item [dict create topic $topic]
}

# [2016-08-12 20:04] now res is just a list, mostly with just 1 item.
proc res_init {resname} {
  upvar $resname res
  set res [list]
}

proc res_add {resname args} {
  upvar $resname res
  lappend res {*}$args
  return $res
}

# just for debugging:
proc res_tostring {res} {
  foreach el $res {
    append str "\n-> $el"
  }
}

# possible library function
proc unique_name {prefix} {
  global __unique_counter__
  incr __unique_counter__
  return "$prefix$__unique_counter__"
}

