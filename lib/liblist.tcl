namespace eval ::liblist {
  namespace export lremove

  # 8-5-2016 from tclhelp in lreplace
  # counter-proc to lappend.
  proc lremove {listVariable value} {
    upvar 1 $listVariable var
    set idx [lsearch -exact $var $value]
    set var [lreplace $var $idx $idx]
  }

}
