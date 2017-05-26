#! /usr/bin/env tclsh

package require ndv
package require Tclx

# [2017-04-02 15:02] don't run in test suite for now.
# or be able to read stderr/out of process and check.
#@test never

ndv::source_once test-stacktrace2.tcl

proc main {} {
  # stacktrace_init;              # of vlak voor main call, of nog boven de includes, even testen, ervaring opdoen.
  try_eval {
    proc1 4 5 6
  } {
    #puts "Caught error: $errorResult"
    #puts "errorInfo: $errorInfo"; # deze bevat stack trace.
    #puts "errorCode: $errorCode"
    ndv::stacktrace_info $errorResult $errorCode $errorInfo
  }
  
}

proc proc1 {x y z} {
  proc2 1 2 3
}

proc proc2 {a b c} {
  # error "Generate error"
  proc3
}

main

