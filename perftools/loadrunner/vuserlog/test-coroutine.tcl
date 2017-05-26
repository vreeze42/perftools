#! /usr/bin/env tclsh

# [2016-08-04 20:58] some tryouts for coroutine based log reading.
# specs could be a set of procs to handle reading the file.
proc readlogfile {logname db specs} {
  with_file f [open $logname r] {
    # still line based for now
    while {[gets $f line] >= 0} {
      foreach parser $parsers {
        set res [$parser $line]
        # result should be a dict, including a topic field for pub/sub (coroutine?)
        # channels. Also, more than one parser could produce a result. A parser produces
        # max 1 result for 1 topic, handlers could split these.
        if {$res != {}} {
          set listeners [listeners [:topic $res]]
          foreach lst $listeners {
            set res2 [$lst $res] ; # listeners should keep state.
            # or listener should be given state and return new state.
            # like this won't work, keep recursing.
          }
        }
      }
      
    }
  }
}

# test for coroutine: it is called repeatedly. Every odd time it just records the
# param given. The second time it returns the first and second value given in a dict:


# apply impl gebruikt getGloballyUniqueName, dus even eentje maken.
proc getGloballyUniqueName {} {
  global _cnt
  incr _cnt
  return "_unique$_cnt"
}

# info level 0 in vb implementatie van apply, voor body0
# [2016-08-04 21:25] even zonder namespace, doet even moeilijk.
proc apply2 {fun args} {
  set len [llength $fun]
  if {($len < 2) || ($len > 3)} {
    error "can't interpret \"$fun\" as anonymous function"
  }
  lassign $fun argList body
  set name [getGloballyUniqueName]
  set body0 {
    puts "deleting proc: [lindex [info level 0] 0]"
    puts "info level 0: [info level 0]"
    rename [lindex [info level 0] 0] {}
  }
  puts "body0: ***$body0***"
  proc $name $argList ${body0}$body
  set code [catch {uplevel 1 $name $args} res opt]
  return -options $opt $res
}

apply2 {x {expr 2 * $x}} 12
# -> 24, ok.

#set c 42
#apply2 {x {expr 2 * $x + $c}} 2
# -> can't read c
# dus niet auto capture van de vars, als in closure.

# rename is om een proc te renamen of te deleten.
# dus deze hier gaat wat deleten.
# deleting proc: _unique6
# info level 0: _unique6 12

# dus in de net gemaakt proc _unique6 wordt deze zelfde proc gedelete.
# ofwel mapping van naam naar geheugen-code-adres wordt gedelete. exec ptr staat al
# in de proc, dus voor deze call gaat het goed.
# maar dus geen dingen om closure te maken.
proc map {lambda list} {
  set result {}
  foreach item $list {
    lappend result [apply $lambda $item]
  }
  return $result
}
map {x {return [string length $x]:$x}} {a bb ccc dddd}
# → 1:a 2:bb 3:ccc 4:dddd
map {x {expr {$x**2 + 3*$x - 2}}} {-4 -3 -2 -1 0 1 2 3 4}
# → 2 -2 -4 -4 -2 2 8 16 26

# lijkt dus dat deze map functie voor elk element in de lijst opnieuw een proc aanmaakt,
# en meteen weer verwijdert! Niet efficient, maar is ook een voorbeeld.

# echte apply heeft ook geen context?
#set c 42
#apply2 {x {expr 2 * $x + $c}} 2
# -> can't read c

#set c 42
#apply {x {expr 2 * $x + $c}} 2
# -> can't read c
# inderdaad, de echte ook niet.

# werking apply, en ook soort closure?
# => conclusie: geen closure.



# example in docs:

puts "=== start of the whole thing ==="

set cores [coroutine accumulator apply {{} {
  puts "Start of accumulator"
  set x 0
  while 1 {
    puts "in while of accumulator, x=$x"
    set y [yield $x]
    puts "after yield, y = $y"
    incr x $y
  }
}}]

puts "cores: $cores"

after 1000
puts "\n\n\nMade acc, now going into for loop\n\n\n"
after 1000

for {set i 5} {$i < 7} {incr i} {
  set acres [accumulator $i]
  after 1000
  puts "$i -> $acres"
}

puts "=== end of the whole thing ==="

# [2016-08-05 21:37] check if apply is needed, or body can be added directly:
puts "=== start of the whole thing ==="

# [2016-11-01 21:26] Ook een testje voor syntax, maar deze niet goed:
if 0 {
  set cores [coroutine accumulator {
    puts "Start of accumulator"
    set x 0
    while 1 {
      puts "in while of accumulator, x=$x"
      set y [yield $x]
      puts "after yield, y = $y"
      incr x $y
    }
  }]
  
}

puts "cores: $cores"

after 1000
puts "\n\n\nMade acc, now going into for loop\n\n\n"
after 1000

for {set i 5} {$i < 7} {incr i} {
  set acres [accumulator $i]
  after 1000
  puts "$i -> $acres"
}

puts "=== end of the whole thing ==="

# [2016-08-05 21:39] dit gaat dus niet goed, hierboven.

# kijken of dit met een proc ook wil:
proc test_all {} {
  puts "=== start of the whole thing with proc ==="

  proc accproc {xstart} {
    puts "Start of accumulator"
    set x [expr $xstart + 1]
    while 1 {
      puts "in while of accumulator, yielding x=$x"
      set y [yield $x]
      puts "after yield, y = $y"
      incr x $y
    }
  }

  set cores [coroutine accumulator accproc 1]
  puts "cores: $cores"

  after 1000
  puts "\n\n\nMade acc, now going into for loop\n\n\n"
  after 1000

  for {set i 5} {$i < 7} {incr i} {
    puts "Calling acc with i=$i"
    after 1000
    set acres [accumulator $i]
    after 1000
    puts "$i -> $acres"
  }

  puts "=== end of the whole thing with proc ==="
 
}

# zelfde test als hierboven, maar dan zonder apply, met een proc?
# ok, zie boven.

proc coro_proc {} {
  # yield started
  if 0 {
    while 1 {
      set firstval [yield ""]
      set secondval [yield ""]
      set x [yield [dict create first $firstval second $secondval]]
    }
  }

  set y1 [yield ""]
  set y2 [yield ""]
  set y3 [yield [dict create first $y1 second $y2]]
  set y4 [yield ""]
  set y5 [yield [dict create first $y3 second $y4]]
}

proc test_main {} {
  coroutine test_coro coro_proc

  puts "t1:  [test_coro 1]"
  # -> {}
  puts "t2: [test_coro 42]"
  # -> {first 1 second 42}
  puts "t3: [test_coro 12]"
  # -> {}
  puts "t4: [test_coro 23]"
  # -> {first 12 second 23}
}

# ok, dit is goed.
# dan eerst coro proc met een loop, hierna evt de main ook.
# [2016-08-04 22:34] en dit werkt ook goed.
proc coro_proc {} {
  # yield started
  puts "coro_proc v4"
  set firstval [yield ""]
  while 1 {
    set secondval [yield ""]
    set res [dict create first $firstval second $secondval]
    set firstval [yield $res]
    # set firstval [yield [dict create first $firstval second $secondval]]
  }
}

proc test_main {} {
  coroutine test_coro coro_proc

  foreach val {a b c d e f g h i} {
    puts "$val: [test_coro $val]"
  }
}

# dan vraag of yieldto ook nog handig is voor read_vuserlog?
# [2016-08-05 20:13] denk in eerste instantie niet, maar 1 hoofd proces en een
# paar deel processen met (een beetje) state.

# [2016-08-05 20:14] coro proc nog iets anders, soort vast stramien:
proc coro_proc {} {
  # yield started
  puts "coro_proc v5"
  # specific initialiser:
  set recv_vals [list]
  # standard code:
  set newval [yield]
  while 1 {
    # start of specific code
    lappend recv_vals $newval
    if {[:# $recv_vals] == 2} {
      set res [dict create first [:0 $recv_vals] second [:1 $recv_vals]]
      set recv_vals [list]
    } else {
      set res ""
    }
    # end of specific code
    set newval [yield $res]
    # set firstval [yield [dict create first $firstval second $secondval]]
  }
}

proc test_main {} {
  coroutine test_coro coro_proc

  foreach val {a b c d e f g h i} {
    puts "$val: [test_coro $val]"
  }
}

# [2016-08-05 20:42] first, try out struct::queue

package require struct::queue
# use struct::queue q

set q1 [struct::queue]
$q1 put first
$q1 put second
while {[$q1 size] > 0} {
  puts "item: [$q1 get]"
}

# first define parsers, just normal procs, maybe lambda?
# possible to use splunk way of regexp's? so inline outvar names?
# maar niet zeker of het hier beter van wordt, evt als optie later.
proc parse_transline {line} {
  if {[regexp {} $line z f1 f2 f3]} {
    return [dict create topic transline f1 $f1 f2 $f2 f3 $f3]
  }
  return ""
}


# of voor simpele regexp based parsers:

# def_parser_regexp transline <regexp> {f1 f2 f3}
# maar later voor transline wel iets spannend, met ook name-value pairs, is meer dan
# een regexp. Dus deze def_parser_regexp eerst niet.

proc def_parser {topic body} {
  global parsers
  # zo geen meerdere parsers die hetzelfde topic opleveren, maar kan later in een
  # handler naar meerdere topics luisteren, en wil dan mss ook wel weten welke topic
  # het precies is.
  # evt check of je dit topic al hebt, kan later nog.
  set proc_name "parse_$topic"
  lappend parsers $proc_name
  # set body "$body1\n"
  proc $proc_name {line linenr} $body
}

# def_parser parse_transline

# of ineens:

def_parser transline {
  if {[regexp {} $line z f1 f2 f3]} {
    # return [dict create f1 $f1 f2 $f2 f3 $f3]
    set res [vars_to_dict f1 f2 f3]
  }
  # return ""
  set res ""
}
# deze definieert dan proc en zet 'em in de parser-lijst


# post process all parser results to add topic, logfile and linenr
proc add_topic_file_linenr {item topic logfile linenr} {
  if {$item == ""} {
    return ""
  }
  dict merge $item [vars_to_dict topic logfile linenr]
}

# post process all handler/maker results to add just topic
proc add_topic {item topic} {
  if {$item == ""} {
    return ""
  }
  dict merge $item [dict create topic $topic]
}

# en net zo een voor errors.

# voor stacktraces mss wat lastiger, maar dan zijn het handlers die de boel weer
# aan elkaar plakken.
# andere optie is niet een line mee te geven aan parser, maar de file descriptor, dan
# kan 'ie zelf kijken. Maar eerst zo doen.
# een empty line parser kan ook handig zijn, dat diverse handlers hiermee kunnen bepalen
# of een block klaar is. Of lines die eindigen met een ; (voor C code)

# DB definitie hangt natuurlijk sterk samen met de insert-handlers.
# deze insert-handlers dan mogelijk ook state, nl als eerste een topic 'logfile',
# met hierin de logfilename e.d.

# then define handler with coroutines

# coroutine, no params?
proc make_trans {} {
  # get transline items, generate trans items.
  # should also handle eof items, could be a topic, or all handlers get this event/item
  # if iter/user is different from old one, and we have old started transactions, finish
  # them with status = -1 (see fill_table_trans)
}

if 0 {
  def_handler {transline eof} trans {
    # make_trans
    ..
    set res [dict create ..]
    set input [yield $res]
  }
  
}

# out_topic is identifying, key.
# but in_topics needed to decide which handlers to call for a topic.
proc def_handler {in_topics out_topic body} {
  global handlers; # dict key=in-topic, value = list of [dict topic coro-name]

  set coro_name "coro_make_${out_topic}"
  foreach in_topic $in_topics {
    dict lappend handlers $in_topic [dict create coro_name $coro_name topic $out_topic]
  }
  # now not a normal proc-def, but a coroutine.
  # apply is the way to convert a body to a command/'proc'.
  coroutine $coro_name apply [list {} $body]
}

# and also inserters, or those are special handlers maybe, returning 'nothing'.

# [2016-08-05 20:39] Another go at readlogfile, with knowledge of coroutines.
# specs could be a set of procs to handle reading the file.
proc readlogfile {logfile db specs} {
  global parsers ;              # list of proc-names.
  global handlers; # dict key=in-topic, value = list of [dict topic coro-name]
  with_file f [open $logfile r] {
    # still line based for now
    set to_publish [struct::queue]
    while {[gets $f line] >= 0} {
      handle_parsers $to_publish
      handle_to_publish $to_publish
    }
  }
  # handle eof topic
  $to_publish put [dict create topic eof logfile $logfile]
  handle_to_publish $to_publish
}

proc handle_parsers {to_publish} {
  global parsers ;              # list of proc-names.
  # first put through all parsers, and put in queue to_pub
  # to_publish is empty here.
  assert {[$to_publish size] == 0}
  foreach parser $parsers {
    # set res [$parser $line]
    set res [add_topic_file_linenr [$parser $line] $parser $logfile $linenr]
    # result should be a dict, including a topic field for pub/sub (coroutine?)
    # channels. Also, more than one parser could produce a result. A parser produces
    # max 1 result for 1 topic, handlers could split these.
    if {$res != ""} {
      $to_publish put $res
    }
  };                        # end-of-foreach
}

proc handle_to_publish {to_publish } {
  global handlers; # dict key=in-topic, value = list of [dict topic coro-name]
  while {[$to_publish size] > 0} {
    set item [$to_publish get]
    set topic [:topic $item]
    # could be there are no handlers for a topic, eg eof-topic. So use dict_get.
    foreach handler [dict_get handlers $topic] {
      set res [add_topic [[:coro_name $handler] $item] [:topic $handler]]
      if {$res != ""} {
        $to_publish put $res
      }
    };                      # end-of-foreach
  };                        # end-of-while to-publish
}

# DB object passen, opties:

if 0 {
  * bij het definieren, dus param in def_handler
  handlers zijn algemeen, bij def is de db nog niet bekend?
  * als event voor de handler, met specifiek topic.
  bv bof, als tegenhanger van eof. En deze dan params meegeven.
  
}



