# library functions for testing, built upon tcltest

package require tcltest

namespace eval ::libtest {

  # tcltest procedures should be available within libtest.
  # namespace import -force ::tcltest::*
  
  namespace export testndv cleanupTests

  # [2016-07-22 10:13] Two arguments to the test function should be enough: expression and expected result.
  # [2016-12-03 16:09] explicitly have body and result as arguments, wrt -> threading operator, otherwise seen as an (invalid) option.
  proc testndv {body result} {
    global testndv_index
    incr testndv_index
    # test test-$testndv_index test-$testndv_index -body $body -result $result
    uplevel tcltest::test test-$testndv_index test-$testndv_index -body [list $body] -result [list $result]
  }
  
  proc cleanupTests {} {
    tcltest::cleanupTests
  }
  
}
