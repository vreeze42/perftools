#!/usr/bin/env tclsh86

# report-ALM-PC-tests.tcl - Report (html) on test definitions (scenario's) from ALM/PC.
# (maybe also perform checks? or separate script)

# notes:
# namespaces are not used.

# TODO
# scenario's zitten in groepen zoals BigIP. Zijn deze ook uit te lezen? Wel iets van een parent-id te zien.

package require tdbc::sqlite3
package require Tclx
package require ndv
package require tdom
package require textutil

set log [::ndv::CLogger::new_logger [file tail [info script]] debug]
$log set_file "[file tail [info script]].log"

ndv::source_once almdb.tcl almlib.tcl

# main DB is in <dir>/almpc.db

proc main {argv} {
  set options {
    {dir.arg "" "Main directory to put downloaded ALM files"}
    {db.arg "almpc-scen.db" "Database in dir to use"}
    {config.arg "" "Config file with project name and credentials"}
  }
  set usage ": [file tail [info script]] \[options] :"
  set dargv [getoptions argv $options $usage]

  set config [read_config [:config $dargv]]
  set dir [:dir $dargv]

  set dbname [file join $dir [:db $dargv]]
  log debug "dbname: $dbname"
  
  set db [get_db $dbname]
  make_report $db $dir
  $db close
}

proc make_report {db dir} {
  global hh
  # set report_dir [file join $dir [clock format [clock seconds] -format "scen-%Y-%m-%d--%H-%M-%S"]]
  set report_dir [file join $dir "Scenario-report"]
  file mkdir $report_dir
  set f [open [file join $report_dir "scenarios.html"] w]
  set hh [ndv::CHtmlHelper::new]
  $hh set_channel $f
  $hh write_header "Scenario's" 0
  $hh table_start
  $hh table_header id alm_id name owner creation_time
  foreach scen [get_scenarios $db] {
    # write a href in this main file
    # scen is a dict
    $hh table_row {*}[juxt {:id :alm_id test_href :owner :creation_time} $scen]
    create_page_test $report_dir $db $scen
    # create sub file.
  }
  $hh table_end
  # maak_verlof_ovz $hh
  $hh write_footer  
  close $f   
}

proc create_page_test {report_dir db scen} {
  set f [open [file join $report_dir "test-[:id $scen].html"] w]
  set hh [ndv::CHtmlHelper::new]
  $hh set_channel $f
  $hh write_header "Scenario - [:name $scen] (id=[:id $scen])"
  set testversion [det_latest_testversion $db [:id $scen]]
  write_version_info $hh $testversion
  # write version vars
  # write stuff for each group
  $hh write_footer
  close $f
}

proc det_latest_testversion {db test_id} {
  :0 [$db query "select * from testversion
             where test_id = $test_id
             order by last_modified desc
             limit 1"]
}

proc write_version_info {hh testversion} {
  $hh table_start
  $hh table_header name value
  dict for {k v} $testversion {
    $hh table_data $k $v
  }
  $hh table_end
  
}

# similar to clojure. But don't return a function, but the result of the function applied to the last argument.
proc juxt {l_fns val} {
  set res {}
  foreach fn $l_fns {
    lappend res [$fn $val]
  }
  return $res
}

proc test_href {scen} {
  global hh
  $hh get_anchor [:name $scen] "test-[:id $scen].html"
}

proc get_scenarios {db} {
  $db query "select * from test order by name"
}

# functions below possibly delete, are for reading into DB.
proc download_alm {root_dir config} {
  set CURL_BIN [:curl $config]
  set url [:alm_url $config]

  set dir [file join $root_dir [clock format [clock seconds] -format "scen-%Y-%m-%d--%H-%M-%S"]]
  file mkdir $dir
  set filename [file join $dir almpc.xml]
  
  # first login and get cookie
  exec -ignorestderr $CURL_BIN -c cookies.txt --data "j_username=[:user $config]&j_password=[:password $config]" "$url/authentication-point/j_spring_security_check"
  exec -ignorestderr $CURL_BIN -b cookies.txt -o $filename "$url/rest/domains/[:domain $config]/projects/[:project $config]/tests?page-size=200"
  return $filename
}

proc det_latest_almfile {dir} {
  set dir [:0 [lsort [glob -directory $dir -type d scen*]]]
  set filename [file join $dir almpc.xml]
  if {[file exists $filename]} {
    return $filename
  } else {
    error "File not found: $filename"
  }
}

proc read_tests_file {filename db just1} {
  log debug "TODO: read_tests_file: $filename into $db"

  set ts_cet [clock format [file atime $filename] -format "%Y-%m-%d %H:%M:%S"]
  set filesize [file size $filename]
  set file_id [$db insert tests_file [vars_to_dict filename ts_cet filesize]]

  set text [read_file $filename]
  log debug "text100: [string range $text 0 100]"
  # set doc [dom parse $text]
  set doc [dom parse -simple $text]
  set root [$doc documentElement]
  log debug "root node: [$root nodeName]"
  log debug "#tests: [$root @TotalResults]"
  foreach node [$root selectNodes {/Entities/Entity}] {
    $db in_trans {
      handle_test_entity $node $db $file_id
    }
    if {$just1} {
      return
    }
    # return ; # for testing just one test.
  }
}

proc handle_test_entity {node db file_id} {
  # hoofdniveau: id, name, creation-time, last-modified, pc-total-vusers
  foreach varname {name id owner creation_time ver_stamp last_modified pc_total_vusers} {
    regsub -all {_} $varname "-" varname2
    set $varname [get_field_text [$node selectNode "Fields/Field\[@Name='$varname2'\]"] Value]
  }
  # set name [get_field_text [$node selectNode {Fields/Field[@Name='name']}] Value]
  log debug "**********************************************"
  log debug "Scenario name: $name"

  set alm_id $id
  set test_id [$db insert test [vars_to_dict file_id alm_id name owner creation_time]]
  set tv_id [$db insert testversion [vars_to_dict test_id alm_id name ver_stamp owner last_modified pc_total_vusers]]

  # breakpoint
  
  # return
  
  # set field_nodes [$node selectNodes {Entity/Fields/Field}]
  set field_nodes [$node selectNodes {Fields/Field}]
  log debug "#field_nodes: [:# $field_nodes]"
  foreach field_node $field_nodes {
    set name [$field_node @Name]
    # log debug "name: $name"
    set value_node [$field_node selectNodes {Value}]
    if {$value_node != {}} {
      set value [$value_node text]
    } else {
      set value "<empty>"
    }
    
    # set value [[$field_node selectNodes {Value}] text]
    log debug "Field $name = [string range $value 0 80]"

    if {![is_xml $name value]} {
      $db insert tv_param [vars_to_dict tv_id name value]
    }
  }

  # return
  # handle_pc_blob [$node selectNode {/Entity/Fields/Field[@Name='pc-blob']/Value}]
  handle_pc_blob [$node selectNode {Fields/Field[@Name='pc-blob']/Value}] $db $tv_id
}

proc is_xml {name value} {
  if {$name == "pc-errors"} {
    return 1
  }
  if {$name == "pc-blob"} {
    return 1
  }
  return 0
}


# TODO refactor zodat deze proc wat kleiner wordt.
proc handle_pc_blob {node db tv_id} {
  log debug "handle_pc_blob: start"
  log debug "node: $node"
  
  if {$node == {}} {
    log debug "Empty pc_blob node."
    return
  }
  
  set text [$node text]
  if {$text == ""} {
    log debug "Empty text in pc_blob node"
    return
  }
  
  try_eval {
    set doc [dom parse -simple $text]
  } {
    log debug "dom parse failed, see text:"
    log debug [string range $text 0 80]
    breakpoint
  }
  
  set root [$doc documentElement]
  log debug "root node: [$root nodeName]"

  set sched_text [get_field_text [$root selectNode {/loadTest/Scheduler}] Data]
  
  log debug "=========================================="
  log debug "Groups:"
  set group_nodes [$root selectNodes {/loadTest/Groups/Group}]
  set dgroup_ids [dict create]
  foreach grp_node $group_nodes {
    set name [get_field_text $grp_node Name]
    set alm_id [get_field_text $grp_node ID]
    set tg_id [$db insert testgroup [vars_to_dict tv_id alm_id name]]
    dict set dgroup_ids $name $tg_id
    log debug "Name: $name"
    foreach name {ScriptUniqueID ScriptName VUsersNumber CommandLine} {
      log debug "$name: [string range [get_field_text $grp_node $name] 0 80]"
      set value [get_field_text $grp_node $name]
      $db insert tg_param [vars_to_dict tg_id name value]
    }
    set host_nodes [$grp_node selectNodes {Hosts/HostBase}]
    log debug "Hosts:"
    foreach host_node $host_nodes {
      log debug "host within group: id: [get_field_text $host_node ID], name: [get_field_text $host_node Name], location: [get_field_text $host_node Location]"
      set alm_id [get_field_text $host_node ID]
      set name [get_field_text $host_node Name]
      set location [get_field_text $host_node Location]
      $db insert tg_host [vars_to_dict tg_id alm_id name location]
    }
    
    set runlogic [get_field_text $grp_node RunLogic]
    set rts [get_field_text $grp_node RunTimeSettings]
    
    handle_settings runlogic $runlogic $db $tg_id
    handle_settings rts $rts $db $tg_id
    
    # 20-10-2015 NdV check if diagnostics is enabled and also distr. perc.
    # this is set on a scenario level, not on a group level.
    
    # db tv_id
    set diag_node [$root selectNode "/loadTest/Diagnostics"]
    # breakpoint
    foreach nm {IsEnabled DistributionPercentage} {
      set name "Diagnostics.$nm"
      set value [get_field_text $diag_node $nm]
      $db insert tv_param [vars_to_dict tv_id name value]
    }
  }

  # TODO if 1 verwijderen
  if 1 {
    # vraag of schedule data (rampup, runtime) ook elders staat?
    set sched_root [[dom parse -simple $sched_text] documentElement]
    log debug "start mode type: [get_field_text [$sched_root selectNode {/LoadTest/Schedulers/StartMode}] StartModeType]"
  
    foreach grp_sch_node [$sched_root selectNodes {/LoadTest/Schedulers/Scheduler/Manual/Groups/GroupScheduler}] {
      set groupname [get_field_text $grp_sch_node GroupName]
      log debug "schedule group name: $groupname" 
      set tg_id [dict get $dgroup_ids $groupname]
      
      # mogelijk hier nog meer mee dan als scenario pas na een tijdje moet starten.
      set mode [[$grp_sch_node selectNode {StartupMode/*}] nodeName]
      log debug "startup mode: $mode"
      $db insert tg_param [dict create tg_id $tg_id name startup_mode value $mode]
      
      set dyn_sched_node [$grp_sch_node selectNode {Scheduling/DynamicScheduling}]
      if {$dyn_sched_node != {}} { 
        set rampup_interval [get_field_text [$dyn_sched_node selectNode {RampUpAll/Batch}] Interval]
        set rampup_count [get_field_text [$dyn_sched_node selectNode {RampUpAll/Batch}] Count]
        set duration [get_field_text [$dyn_sched_node selectNode {Duration}] RunFor]
        log debug "rampup $rampup_count users every $rampup_interval seconds"
        log debug "duration: $duration seconds"; #
        $db insert tg_param [dict create tg_id $tg_id name rampup_count value $rampup_count]
        $db insert tg_param [dict create tg_id $tg_id name rampup_interval value $rampup_interval]
        $db insert tg_param [dict create tg_id $tg_id name duration value $duration]
        
      } else {                   
        log debug "No Scheduling/DynamicScheduling node found."
      }      
    }                          
  
  }                           
  
  
  
  log debug "handle_pc_blob: finished"
}

proc handle_settings {partname text db tg_id} {
  #log debug "handle_settings: $name"
  #log debug "text: [string range $text 0 100]"
  set l [::textutil::split::splitx $text {!@##@!}]
  set group "<none>"
  foreach el $l {
    # log debug "item: $el"
    if {[regexp {^\[(.+)\]$} $el z grp]} {
      set group $grp
    } else {
      lassign [split $el "="] elname value
      if {$elname != ""} {
        log debug "$partname.$group.$elname = $value"
        set name "$partname.$group.$elname"
        $db insert tg_param [vars_to_dict tg_id name value]
      }
    }
  }
}


main $argv

