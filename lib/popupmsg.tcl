#! /home/nico/bin/tclsh

# [2016-11-03 21:02] onderstaande werkt blijkbaar niet vanuit gosleep.tcl
#! /usr/bin/env tclsh

package require ndv

proc main_popupmsg {argv} {
  lassign $argv text title
  if {$title == ""} {
    set title "Warning!"
  }
  if {$text == "-"} {
    # read stdin
    # puts stderr "Reading stdin"
    set text [read stdin]
  } else {
    # puts stderr "text: ***$text***"
  }
  if {[string trim $text] != ""} {
    popup_warning $text $title; # only popup if something to show, useful for pipelines.
  }
  exit
}

proc popup_warning {text title} {
  package require Tk
  wm withdraw .

  # [2017-04-14 10:28] in help ook: tk_messageBox
  # [2017-04-14 10:29] want to set width, maybe also scrollbar, this is not possible
  # with MessageBox, so use something else.
  set answer [::tk::MessageBox -message $title \
                  -icon info -type ok \
                  -detail $text]
}

if {[this_is_main]} {
  main_popupmsg $argv
}

