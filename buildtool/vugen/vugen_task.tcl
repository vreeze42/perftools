# puts "Sourcing vugen_task.tcl..."

task vugen_task {Example task for prjtype

} {
  puts "vugen_task!"
}

# TODO: each prjtype subdir should have a hooks.tcl file with things like:
# [2016-12-03 21:34] for now: in vugen dir some procs get redefined, works also, less clean.
# get_source_files
# get_config_files
# get_lib_files  - for diff/test/put/get
# get_repo_files - for diff/test/put/get
# set_global_vars - eg lr_include_dir
# ie. things to be used by generic tasks
