#! /usr/bin/env tclsh

# Run report script on several test log files, to check if DB and report are created ok.
# Goal is to put test files (logs) in repo as well.
# Generated files are created in /tmp, so copy source files to temp as well.

package require ndv
package require json
package require json::write

# Maybe can source file in parent dir with same name except test- prefix?
source [file normalize [file join [info script] .. .. libjson.tcl]]

use libtest
use libfp
use libjson

proc main {argv} {
  set cities_filename [file normalize [file join [info script] .. cities.json]]
  set str [read_file $cities_filename]
  set dct [json::json2dict $str]
  set str2 [array2json $dct]
  # testndv {identity $str} {identity $str2}
  # testndv {identity $str} {dict2json $dct}
  # testndv {identity $str} $str2
  # formatting can be different, so convert to dict again
  # puts 
  set dct2 [json::json2dict $str2]
  testndv {identity $dct2} $dct
  cleanupTests
}

main $argv
