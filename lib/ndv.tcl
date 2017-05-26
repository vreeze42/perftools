# ndv.tcl - base library file to source other files

source [file join [file dirname [info script]] _installed_message.tcl] 
# puts stderr $_ndv_version

# proc to return install date/time and name/date/time of newest tcl file in lib.
# should use namespace ndv
proc ndv_version {} {
  global _ndv_version
  return $_ndv_version
}

proc test_log {} {
  # info frame quite useful, could use again.
  puts [info frame [expr [info frame] - 1]]
  catch {log info "test"} res
  puts "res: $res"
}

# TODO: source all files in this dir with a glob/source_once.
# problem is order, some need to go first. Should be solved by using source_once
# in those files.
# should also do CLogger at the end again, for log-proc also defined in math::functions

# there are some inter dependencies, so explicitly source other files in the right order.
source [file join [file dirname [info script]] source_once.tcl]

# [2016-08-09 21:35] libmacro.tcl, first only with syntax_quote
# [2016-08-19 20:05] move more to top, used by libsqlite
# 12-11-2016 used by libns.tcl, got error on Lubuntu laptop, so move before libns.tcl.
source [file join [file dirname [info script]] libmacro.tcl]

# [2016-07-09 09:49] namespace functions, compare Clojure
# [2016-08-19 20:04] add libns to the top, used by libdb.tcl/libsqlite.tcl
source [file join [file dirname [info script]] libns.tcl]

source [file join [file dirname [info script]] CLogger.tcl]

source [file join [file dirname [info script]] liboptions.tcl]

# [2016-07-23 21:32] CHtmlHelper needs CLogger on load. For now, source CLogger both
# here and at the end.
source [file join [file dirname [info script]] CHtmlHelper.tcl] 

# database files in subdir 
source [file join [file dirname [info script]] db AbstractSchemaDef.tcl]

source [file join [file dirname [info script]] db CDatabase.tcl]

source [file join [file dirname [info script]] db CClassDef.tcl] 

source [file join [file dirname [info script]] random.tcl]

catch {source [file join [file dirname [info script]] music-random.tcl]} ; # deze heeft random.tcl nodig en ook CDatabase.tcl 

source [file join [file dirname [info script]] fp.tcl]
source [file join [file dirname [info script]] general.tcl]

# NdV 22-11-2010 in generallib staan dict_get_multi en array_values, nodig in scheids.
source [file join [file dirname [info script]] generallib.tcl]

source [file join [file dirname [info script]] breakpoint.tcl]

# 14-3-2013 added libdot.tcl
source [file join [file dirname [info script]] libdot.tcl]

# 17-3-2013 added libsqlite.tcl
source [file join [file dirname [info script]] libsqlite.tcl]

# 27-3-2013 added libdict.tcl
source [file join [file dirname [info script]] libdict.tcl]

# 27-7-2013 added libdb.tcl (as replacement to be for libsqlite.tcl and db/* (mysql) libraries.
source [file join [file dirname [info script]] libdb.tcl]

# 2-8-2013 added libcsv.tcl
source [file join [file dirname [info script]] libcsv.tcl]

# 6-9-2013 added libcyg.tcl
source [file join [file dirname [info script]] libcyg.tcl]

# 12-10-2013 added libfp.tcl (test needed that functions do not overlap/name clash)
source [file join [file dirname [info script]] libfp.tcl]

# 26-01-2014 added listc - list comprehensions
source [file join [file dirname [info script]] listc.tcl]

# 4-5-2016 have had CPRogresscalculator for a long time, but not included
source [file join [file dirname [info script]] CProgressCalculator.tcl]

# [2016-06-15 10:45:26] add date/time functions
source [file join [file dirname [info script]] libdatetime.tcl]

source [file join [file dirname [info script]] libio.tcl]

source [file join [file dirname [info script]] libinifile.tcl]

# [2016-07-23 21:31] CLogger as the last one, because ir defines proc log, which is
# defined before in Tclx.

source [file join [file dirname [info script]] CLogger.tcl]

# [2016-08-25 15:45:04] add, surprised not already in here.
source [file join [file dirname [info script]] CExecLimit.tcl]

# [2016-11-19 11:58] add popupmsg
source [file join [file dirname [info script]] popupmsg.tcl]

# [2016-11-30 20:32] testing library
source [file join [file dirname [info script]] libtest.tcl]

# [2016-12-02 15:09] url encode/decode.
# previously used in FB/genvugen
source [file join [file dirname [info script]] liburl.tcl]

# [2017-05-05 21;46] added
source [file join [file dirname [info script]] libjson.tcl]

# [2016-12-03 20:55] added.
source [file join [file dirname [info script]] liblist.tcl]

# [2016-08-25 22:30] source_once is included at the top, so available here.
::ndv::source_once libmisc.tcl
