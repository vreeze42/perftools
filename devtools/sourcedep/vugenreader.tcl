# Eentry points:
# * init - initialise readers, handlers, called when sourcing this file.
# * can_read? - is this namespace/module able to read the file given?
# * read_sourcefile - read sourcefile into db

# OLD:
# * define_logreader_handlers - define parsers and handlers
# * readlogfile_new_coro $logfile [vars_to_dict db ssl split_proc]
#   - this one calls readlogfile_coro, as defined in liblogreader.tcl, not here.

package require ndv
# ndv::source_once liblogreader.tcl

set perftools_dir [file normalize [file join [file dirname [info script]] .. .. perftools]]

# TODO: use source_once with absolute path?
source [file join $perftools_dir logdb liblogreader.tcl]
#source [file join $perftools_dir logdb librunlogreader.tcl]

require libdatetime dt
require libio io
use libmacro;                   # syntax_quote

namespace eval ::vugensource {
  
  namespace export init can_read? read_sourcefile

  proc can_read? {filename} {
    # read .c and .h files, but not generated ones.
    set tail [file tail $filename]
    if {[regexp {^combined} $tail]} {
      return 0
    }
    set ext [file extension $tail]
    if {[lsearch -exact {.c .h} $ext] >= 0} {
      return 1
    }
    return 0
  }

  proc read_sourcefile {filename db} {
    set mtime [clock format [file mtime $filename] -format "%Y-%m-%d %H:%M:%S %z"]
    set size [file size $filename]
    set path $filename
    set name [file tail $path]
    set language "C"

    $db in_trans {
      set sourcefile_id [$db insert sourcefile [vars_to_dict path name mtime \
                                                    size language]]
      readlogfile_coro $filename [vars_to_dict db sourcefile_id]
    }
  }

  proc init {} {
    # reset_parsers_handlers ; # TODO: needed?
    def_parsers
    def_handlers
  }

proc def_parsers {} {

  def_parser_regexp include_line include {^#include "([^\"\"]+)"} callees
  
  # TODO: include function definitions, including lines.
  # Also parts outside of function definitions, to determine calls.

  # def_parser_regexp proc-start {^(\S[^\(\)]+)\(([^\(\)]+)\)} ret_type proc_name params

  def_parser proc-start proc-start {
    if {[regexp {^\s*//} $line]} {
      return ""
    }
    # TODO: iets met comment-start/end.
    if {[regexp {^(\S[^\(\)]+)\(([^\(\)]*)\)} $line z prefix params]} {
      if {[regexp {^(.*?)\s?([^ *]+)$} $prefix z ret_type proc_name]} {
        vars_to_dict ret_type proc_name params
      } else {
        return ""
      }
    } else {
      return ""
    }
  }
  
  # \x7D is right/close brace
  def_parser_regexp proc-end proc-end {^\x7D$} {}
  
}

proc def_handlers {} {

  def_handler stmt {bof eof include_line} statement {
    # init code
    set file_item [dict create]
  } {
    # body/loop code
    switch [:topic $item] {
      bof {
        set file_item $item
      }
      eof {
        set file_item [dict create]
      }
      include_line {
        log debug "Statement handler"
        # breakpoint
        set linenr_start [:linenr $item]
        set linenr_end [:linenr $item]
        set stmt_type include
        set text [:line $item]
        res_add res [dict merge $file_item $item [vars_to_dict linenr_start \
                                                  linenr_end stmt_type text]]
      }
    }
  }

  def_handler proc {bof eof proc-start proc-end} proc {
    # init code
    set proc_current ""
    set file_item [dict create]
  } {
     switch [:topic $item] {
       bof {
         set file_item $item
         set proc_current ""
       }
       eof {
         set proc_current ""
       }
       proc-start {
         if {$proc_current != ""} {
           log warn "Already in proc: $proc_current, $item"
         }
         set proc_current $item
       }
       proc-end {
         if {$proc_current == ""} {
           log warn "No current proc: $item"
         } else {
           set proctype "C-function"
           set name [:proc_name $proc_current]
           set linenr_start [:linenr $proc_current]
           set linenr_end [:linenr $item]
           set text [:line $proc_current]
           # breakpoint
           res_add res [dict merge $file_item [vars_to_dict proctype name \
                                                   linenr_start linenr_end text]]
           set proc_current ""
         }
       }
     }
  }
  
  # [2016-08-09 22:29] introduced a bug here by not calling split_proc in insert-trans_line
  # but in trans split_proc is called, and this is used in report. Could also remove fields
  # in trans_line, also split_proc still is somewhat of a hack now.
  def_insert_handler statement
  def_insert_handler proc
  
  #def_insert_handler trans
  #def_insert_handler error
  
}

# Specific to this project, not in liblogreader.
# combination of item and file_item
proc def_insert_handler {table} {
  def_handler "i:$table" [list bof $table] {} [syntax_quote {
    if {[:topic $item] == "bof"} { # 
      set db [:db $item]
      set file_item [dict remove $item db]
    } else {
      $db insert ~$table [dict remove [dict merge $file_item $item] topic]
    }
  }]
}


} ; # end-of-namespace

::vugensource::init

return ::vugensource
