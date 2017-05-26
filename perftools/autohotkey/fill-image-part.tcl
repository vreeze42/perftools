#!/home/nico/bin/tclsh

# fill column image_part in table image_found based on column image_path: only <sentinel>\image.png

package require Tclx
# package require csv
package require sqlite3

# own package
package require ndv

set log [::ndv::CLogger::new_logger [file tail [info script]] debug]

proc main {argv} {
  lassign $argv db_name
  sqlite3 db $db_name
  #db eval "begin transaction"
  #fill_image_part
  # db eval "commit"
  db transaction fill_image_part 
  db close
}

proc fill_image_part {} {
  set lst [db eval "select image_path from image_found"]
  foreach p $lst {
    set part [det_part $p]
    db eval "update image_found set image_part = '$part' where image_path = '$p'"
  }
}

# return last 2 elements, use / as separator.
proc det_part {path} {
  # breakpoint
  file join {*}[lrange [file split [string map {\\ /} $path]] end-1 end] 
}

main $argv
