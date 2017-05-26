# project groups - groups/sets of projects/scripts

# TODO: maybe support recursive project groups.

# project functions, set and setcurrent
task prjgroup {Define and use project groups
  Syntax:
  prjgroup set <prjgroup> <script> [<script> ..] - Define a project including several scripts.
  prjgroup setcurrent <prjgroup>                 - Set a project as current
} {
  # [2016-08-10 21:05] for now no extra checks, need to find out what works best.
  # cannot use is_prjgroup_dir, bootstrapping problem.
  if 0 {    
    if {![is_project_dir .]} {
      puts "Not a project dir, leaving"
      exit 1
    }
  }
  lassign $args sub_action prjgroup
  set scripts [lrange $args 2 end]
  if {$sub_action == "set"} {
    set f [open "$project.prjgroup" w]
    puts $f [join $scripts ";"]
    close $f
    # [2016-07-23 23:16] also make current.
    file copy -force "$project.prjgroup" "current.prjgroup"
  } elseif {$sub_action == "setcurrent"} {
    file copy -force "$project.prjgroup" "current.prjgroup"
  }
}

# [2016-08-10 21:07] very simple now, just see if a current.prjgroup exists.
# independent from config/vars.
proc is_prjgroup_dir {dir} {
  file exists [file join $dir current.prjgroup]
}

proc handle_prjgroup_dir {dir tname trest} {
  global as_prjgroup
  # in a container dir with script dirs as subdirs.
  #set repodir [file normalize "repo"]
  #set repolibdir [file join $repodir libs]
  # [2016-07-30 15:30] not sure if source is needed here.
  source [config_tcl_name]
  set as_prjgroup 1
  # TODO: should be checked more generic.
  if {$tname == "put"} {
    puts "Put action cannot be done in project scope, only script scope"
    exit 1
  }
  if {$tname == "prjgroup"} {
    task_$tname {*}$trest
  } else {
    foreach scriptdir [current_script_dirs $dir] {
      puts "In $scriptdir"
      cd $scriptdir
      handle_script_dir $scriptdir $tname $trest
      cd ..
    }
    cd $dir
  }
}

proc current_script_dirs {dir} {
  set prjgroup_filename [file join $dir "current.prjgroup"]
  if {[file exists $prjgroup_filename]} {
    split [string trim [read_file $prjgroup_filename]] ";"  
  } else {
    log warn "No current.prjgroup found in dir: $dir"
    return {}
  }
}

