#!/usr/bin/env tclsh

package require ndv
ndv::source_once liblogreader.tcl

require libdatetime dt
require libio io

set_log_global info

proc main {argv} {
  set testfilename "/tmp/logreader-test.log"
  make_testfile $testfilename
  # of toch een losse namespace waar deze dingen in hangen?
  def_parsers
  def_handlers
  log info "Calling readlogfile"
  readlogfile_coro $testfilename [dict create db "my-db-object"]
  log info "Finished readlogfile"
}

proc make_testfile {testfilename} {
  io/with_file f [open $testfilename w] {
    for {set nr 101} {$nr <= 111} {incr nr} {
      # puts $f "\[[dt/now]] line: $linenr, "
      puts $f "nr: $nr - some more text"
    }
  }
}

proc def_parsers {} {
  def_parser nrline {
    if {[regexp {nr: (\d+)} $line z nr]} {
      vars_to_dict nr line
    } else {
      return ""
    }
  }
}

proc def_handlers {} {
  def_handler {nrline eof} even {set nitems 0; set eof 0} {
    if {[:topic $item] == "eof"} {
      set eof 1
    } else {
      incr nitems
      if {$nitems % 2 == 0} {
        res_add res [dict merge $item [dict create nitems $nitems]]
      } else {
        if {$nitems == 3} {
          # generate 3 results
          set el [dict merge $item [dict create nitems $nitems]]
          res_add res $el $el $el
        } else {
          # nothing
        }
      }
    }
  }

  def_handler {bof even} {} {set x 12} {
    if {[:topic $item] == "bof"} {
      set db [:db $item]
    } else {
      puts "*** Even handler item: $item, x=$x, db: $db ***"
    }
  }
}

if {[this_is_main]} {
  main $argv  
}

