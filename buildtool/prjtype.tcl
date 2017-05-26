# project types with specific tasks in subdirs of buildtool-dir

task set_prjtype {Set type of project
  eg vugen, tcl, clj, ahk
  Syntax: set_prjtype [<prjtype>]
  If prjtype not given, show available types
} {
  lassign $args prjtype
  if {$prjtype == ""} {
    puts "TODO: project types"
    # check subdirs. For now, each subdir is a project type.
    return
  }
  prjtype_add_config $prjtype
}

# add project type to configfile: .bld/config.tcl
# iff not already a project type defined in config.tcl
proc prjtype_add_config {prjtype} {
  set config_name [config_tcl_name]
  set text [read_file $config_name]
  if {[regexp {prjtype} $text]} {
    puts "Project type already set, edit manually in $config_name"
    return
  }
  append text "
set prjtype $prjtype
set bldprjlib \[file join \[buildtool_dir\] $prjtype\]
"
  write_file $config_name $text
}
