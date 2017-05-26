#!/home/nico/bin/tclsh

# determine if images are really used by script and found on the screen.

package require Tclx
# package require csv
package require sqlite3

# own package
package require ndv

set log [::ndv::CLogger::new_logger [file tail [info script]] debug]

proc main {argv} {
  lassign $argv db_name script_dir
  sqlite3 db $db_name
  find_images $script_dir
  db close
}

proc find_images {dir} {
  foreach subdir [lsort [glob -directory $dir -type d *]] {
    find_images_subdir $subdir 
  }  
}

proc find_images_subdir {dir} {
  set machine [file tail $dir]
  puts "========================================================"
  puts "Determining usage for machine: $machine"
  foreach png [lsort [glob -nocomplain -directory $dir *.png]] {
    set part [det_part $png]
    set used [det_used $part]
    if {$used} {
      puts "used: $part" 
    } else {
      puts "NOT : $part"
    }
  }
}

proc det_used {part} {
  set res [db eval "select image_part from image_found where image_part = '$part'"]
  if {$res != ""} {
    return 1 
  } else {
    return 0 
  }  
}

# return last 2 elements, use / as separator.
proc det_part {path} {
  # breakpoint
  file join {*}[lrange [file split [string map {\\ /} $path]] end-1 end] 
}

main $argv
