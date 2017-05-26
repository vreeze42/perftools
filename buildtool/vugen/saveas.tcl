# saveas - save a newly recorded script to another directory.
# like the save-as function in VuGen, only copy script files, not recording logs and data directory.

task saveas {Save a newly recorded script to another directory
  Syntax: saveas <new-prj-dir>} {
} {
  lassign $args target
  if {$target == ""} {
    puts "Syntax: saveas <new-prj-dir>"
    return
  }
  set target_dir [file normalize [file join .. $target]]
  if {[file exists $target_dir]} {
    puts "WARNING: Target dir already exists: $target_dir"
    return
  }
  set current_dir [file tail [file normalize .]]
  file mkdir $target_dir
  set have_prm 0
  foreach filename [get_project_files] {
    if {$filename == "ScriptUploadMetadata.xml"} {
      set text [read_file $filename]
      # [2016-12-02 11:43] this should also correct ref to .prm file, but could not exist here.
      regsub -all $current_dir $text $target text2
      write_file [file join $target_dir $filename] $text2 
    } elseif {[file extension $filename] == ".usr"} {
      file copy $filename [file join $target_dir "$target.usr"]
    } elseif {[file extension $filename] == ".prm"} {
      file copy $filename [file join $target_dir "$target.prm"]
      set have_prm 1
    } else {
      if {[file exists $filename]} {
        file copy $filename [file join $target_dir $filename]    
      } else {
        puts "WARNING: source does not exist: $filename"
      }
    }
  }
  if {$have_prm} {
    # [2016-12-02 11:34] Change refs in .usr and metadata.
    set prm_file "$target.prm"
    set usr_file [file join $target_dir "$target.usr"]
    set ini [ini/read $usr_file]
    set ini [ini/set_param $ini General ParameterFile $prm_file]
    ini/write $usr_file $ini;   # no commit_file here yet.
    # [2016-12-02 11:44] next one should not be necessary, already search/replace above.
    add_file_metadata $prm_file [file join $target_dir ScriptUploadMetadata.xml]
  }
}

