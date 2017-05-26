source [file join [perftools_dir] .. devtools sourcedep sourcedep.tcl]

task sourcedep {Create source dependency graphs/html
} {{rootdir.arg "." "Root directory"}
  {dirs.arg "" "Subdirs within root dir to handle, empty for all (: separated)"}
  {targetdir.arg "sourcedep" "Directory where to generate DB, images, html"}
  {db.arg "sourcedep.db" "SQLite DB to create, relative to target dir"}
  {deletedb "Delete DB first"}
  {loglevel.arg "info" "Set loglevel"}  
} {
  sourcedep $opt
}
