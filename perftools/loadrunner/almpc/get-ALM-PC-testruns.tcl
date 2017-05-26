#!/usr/bin/env tclsh86

# get-ALM-PC-testruns.tcl - Get test runs from ALM/PC and put in DB. Also download attachments.

# notes:
# namespaces are not used.

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
  global config

  set options {
    {dir.arg "" "Main directory to put downloaded ALM files and SQLite DB"}
    {db.arg "almpc.db" "SQLite DB name within dir"}
    {nodownload "Do not download new main testruns.xml from ALM (might take a long time, ~1 minute)"}
    {config.arg "" "Config file with project name and credentials"}
    {domain.arg "" "If used, override setting in config"}
    {project.arg "" "If used, override setting in config"}
    {firstrunid.arg "" "First runid to download. Iff set, do not download all runs XML file (fails in old projects)"}
    {lastrunid.arg "" "Last runid to download. Iff set, do not download all runs XML file (fails in old projects)"}
    {delete "Delete all rows from DB before reading (debug mode)"}
    {just1 "Read just 1 testrun with attachments"}
	{test "Do a test, eg download/upload script"}
	{force "Force download, even if downloaded before"}
  }
  log info "argv before: $argv"
  set usage ": [file tail [info script]] \[options] :"
  set dargv [getoptions argv $options $usage]

  log info "argv after: $argv"
  log info "dargv: $dargv"
  
  set config [read_config [:config $dargv]]
  
  if {[:domain $dargv] != ""} {
    dict set config domain [:domain $dargv]
  }
  if {[:project $dargv] != ""} {
    dict set config project [:project $dargv]
  }
  foreach param {nodownload just1 delete firstrunid lastrunid} {
    dict set config $param [:$param $dargv]
  }
  
  set dir [:dir $dargv]
  set prj_rootdir [file join $dir [:domain $config] [:project $config]]
  
  set dbname [file join $dir [:db $dargv]]
  log debug "dbname: $dbname"
  
  set db [get_db $dbname]
  if {[:delete $dargv]} {
    delete_table_rows $db
  }
  
  if {[:test $dargv]} {
	do_test $dargv
	exit
  }
  read_test_results $db $prj_rootdir
  
  $db close
}

# TODO - results alleen in DB als ze nieuw zijn. Ook alleen dan results ophalen.
proc read_test_results {db prj_rootdir} {
  global config

  file mkdir $prj_rootdir

  file delete cookies.txt
  alm_login

  if {[:firstrunid $config] == ""} {
    # date/time op hoogste niveau in filenaam (testruns-<datetime>.xml)
    if {[:nodownload $config]} {
      set runs_name [det_latest_runsfile $prj_rootdir]
    } else {
      set runs_name [download_runs $prj_rootdir]  
    }

    # dan hier XML lezen en waar nodig in DB zetten en rest downloaden. Ook eerst in DB zetten.
    log info "runs_name: $runs_name"
    handle_runs $db $prj_rootdir $runs_name
  } else {
    log info "Do not download alle runs XML, (try to) download per run."
    handle_runs_first_last $db $prj_rootdir
  }
  
}

# return filename of downloaded runs-file.
proc download_runs {prj_rootdir} {
  global config
  set filename [file join $prj_rootdir "testruns-[clock format [clock seconds] -format "%Y-%m-%d--%H-%M-%S"].xml"]
  set prj_runs_url "[:alm_url $config]/domains/[:domain $config]/projects/[:project $config]/Runs"

  do_alm_curl $prj_runs_url $filename
  return $filename
}

# url - full URL
# filename - full path
proc do_alm_curl {url filename} {
  global config
  set CURL_BIN [:curl $config]
  
  set ok 0
  try_eval {
    exec_curl -b cookies.txt -o $filename $url
    set ok [is_alm_xml_ok $filename]
  } {
    log warn "ALM download failed: $errorResult"
  }
  if {!$ok} {
    log warn "ok = false, login and try again"
    alm_login
    log info "And try again:"
    exec_curl -b cookies.txt -o $filename $url
  }
}

proc alm_login {} {
  global config
  file delete cookies.txt
  set CURL_BIN [:curl $config]
  log info "exec_curl -c cookies.txt --header \"Authorization: Basic [:auth_base64 $config]\" \"[:alm_url $config]/authentication-point/authenticate\""
  exec_curl -o login.html -c cookies.txt --header "Authorization: Basic [:auth_base64 $config]" "[:alm_url $config]/authentication-point/authenticate"
  log info "Logged in, info in login.html and cookies.txt in [pwd]"
  # exit; # for now
}

proc exec_curl {args} {
  log debug "executing curl (in dir [pwd]) with args: $args"
  global config
  set CURL_BIN [:curl $config]
  exec -ignorestderr $CURL_BIN {*}$args
}

# diverse manieren om te valideren: is het XML, grootte (1293 bytes), komt text "401 - Unauthorized: " voor? Of file gebruiken, of extensie overeenkomt met de inhoud.
proc is_alm_xml_ok {filename} {
  if {[file exists $filename]} {
    set size [file size $filename]
    if {($size <= 1200) || ($size >= 1500)} {
      return 1
    } else {
      log warn "Size not ok: $size"
      return 0
    }
  } else {
    return 0
  }
}

proc det_latest_runsfile {dir} {
  set filename [:0 [lsort -decreasing [glob -directory $dir -type f *.xml]]]
  return $filename
}

# first add file to DB. Then:
# for every run in runs check if it's already in the DB. If not, insert it and download details and attachments.
proc handle_runs {db prj_rootdir runs_name} {
  global config
  set filename $runs_name
  set domain [:domain $config]
  set project [:project $config]
  set ts_cet [clock format [file atime $runs_name] -format "%Y-%m-%d %H:%M:%S"]
  set filesize [file size $runs_name]
  set file_id [find_testruns_file $db $domain $project $filename]
  if {$file_id < 0} {
    set file_id [$db insert testruns_file [vars_to_dict filename ts_cet filesize domain project]]  
  }
  
  set text [read_file $runs_name]

  log debug "text100: [string range $text 0 100]"
  # set doc [dom parse $text]
  set doc [dom parse -simple $text]
  set root [$doc documentElement]
  $doc selectNodesNamespaces [list d [$root @xmlns]]
  
  log debug "root node: [$root nodeName]"
  # breakpoint
  foreach node [$root selectNodes {/d:Runs/d:Run}] {
    set runid [get_field_text $node d:ID]
    handle_run $db $prj_rootdir $runid $file_id $node
  }
}

# read runs and attachments from given first and last runid
# this option is needed because /Runs url fails for old projects.
proc handle_runs_first_last {db prj_rootdir} {
  global config
  set domain [:domain $config]
  set project [:project $config]
  
  set runid [:firstrunid $config]
  set lastrunid [:lastrunid $config]
  log info "Read runs from $runid to $lastrunid, inclusive"
  while {$runid <= $lastrunid} {
    if {![is_run_read $db $domain $project $runid]} {
      read_run $db $prj_rootdir $runid
    } else {
      log debug "Already read: $runid"
    }
    incr runid
  }
}

# goal: read a single run info, when getting all runs does not work (for old projects)
proc read_run {db prj_rootdir runid} {
  global config
  log debug "read_run: $runid"
  set domain [:domain $config]
  set project [:project $config]
  
  set run_dir [file join $prj_rootdir $runid]
  file mkdir $run_dir
  set filename [file join $run_dir "run-$runid-[clock format [clock seconds] -format "%Y-%m-%d--%H-%M-%S"].xml"]
  set prj_run_url "[:alm_url $config]/domains/[:domain $config]/projects/[:project $config]/Runs/$runid"
  do_alm_curl $prj_run_url $filename
  # file sowieso in DB, ook als er geen data is.
  set ts_cet [clock format [file atime $filename] -format "%Y-%m-%d %H:%M:%S"]
  set filesize [file size $filename]
  set file_id [find_testruns_file $db $domain $project $filename]
  if {$file_id < 0} {
    set file_id [$db insert testruns_file [vars_to_dict filename domain project ts_cet filesize]]  
  }

# TODO single run lezen en handelen.
  
  set text [read_file $filename]

  log debug "text100: [string range $text 0 100]"
  # set doc [dom parse $text]
  set doc [dom parse -simple $text]
  set root [$doc documentElement]
  $doc selectNodesNamespaces [list d [$root @xmlns]]
  log debug "root node: [$root nodeName]"
  set node [$root selectNodes {/d:Run}]
  if {$node != ""} {
    handle_run $db $prj_rootdir $runid $file_id $node  
  } else {
    log warn "No Run info found in $filename. text: $text"
  }
  
}

# pre: run is a node in a read file: file_id and node.
proc handle_run {db prj_rootdir runid file_id node} {
  global config
  set domain [:domain $config]
  set project [:project $config]
  
  if {![is_run_read $db $domain $project $runid]} {
    log debug "Insert and handle runid: $runid"
    set testrun_id [insert_testrun $db $file_id $node]
    log debug "testrun_id: $testrun_id"
    handle_run_details $db $prj_rootdir $runid $testrun_id
    if {[:just1 $config]} {
      log info "Just read 1, then exit"
      exit
    }
  } else {
    log debug "Run already read: $runid"
  }
}

# return id of testruns_file in DB, if it exists. -1 if not.
proc find_testruns_file {db domain project filename} {
  set res [$db query "select id from testruns_file where filename = '$filename' and domain = '$domain' and project = '$project'"]
  if {[:# $res] > 0} {
    return [:id [:0 $res]]
  } else {
    return -1
  }
}

proc is_run_read {db domain project runid} {
  set nrecs [llength [$db query "select id from testrun where runid=$runid and domain = '$domain' and project = '$project'"]]
  if {$nrecs == 1} {
    return 1
  } elseif {$nrecs == 0} {
    return 0
  } else {
    error "More than 1 record found for runid: $runid"
  }
}

proc insert_testrun {db file_id node} {
  global config
  set domain [:domain $config]
  set project [:project $config]
  
  foreach colname {TestID TestInstanceID PostRunAction TimeslotID VudsMode ID Duration RunState RunSLAStatus} {
    set [string tolower $colname] [get_field_text $node "d:$colname"]
  }
  set runid $id
  $db insert testrun [vars_to_dict domain project file_id testid testinstanceid postrunaction timeslotid \
                          vudsmode runid duration runstate runslastatus]
}

# runid - ALM/PC ID of the run
# testrun_id - SQLite id
proc handle_run_details {db prj_rootdir runid testrun_id} {
  global config
  
  set run_dir [file join $prj_rootdir $runid]
  file mkdir $run_dir
  set results_xml [file join $run_dir "results.xml"]
  set url "[:alm_url $config]/domains/[:domain $config]/projects/[:project $config]/Runs/$runid/results"
  do_alm_curl $url $results_xml

  set text [read_file $results_xml]

  log debug "text100: [string range $text 0 100]"
  # set doc [dom parse $text]
  set doc [dom parse -simple $text]
  set root [$doc documentElement]
  $doc selectNodesNamespaces [list d [$root @xmlns]]

  foreach node [$root selectNodes {/d:RunResults/d:RunResult}] {
    handle_result $db $run_dir $runid $testrun_id $node
  }
}

proc handle_result {db run_dir runid testrun_id node} {
  global config
  
  foreach colname {ID Name Type} {
    set [string tolower $colname] [get_field_text $node "d:$colname"]
  }
  set alm_id $id

  # eerst downloaden
  set path [file join $run_dir $name]
  if {[file exists $path]} {
    log debug "Resuls file already downloaded: $path"
  } else {
    set url "[:alm_url $config]/domains/[:domain $config]/projects/[:project $config]/Runs/$runid/Results/$id/data"
    do_alm_curl $url $path

    # dan size bepalen en inserten.
    set ts_cet [clock format [file atime $path] -format "%Y-%m-%d %H:%M:%S"]
    set filesize [file size $path]
    
    $db insert testrunresult [vars_to_dict testrun_id alm_id name type runid path filesize ts_cet]
  }
}

main $argv

