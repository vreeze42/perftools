# Procedures to search in recordings wrt correlation.

# all tcl files should be automatically sourced by buildtool

# return a list of directories containing recordings for the current script.
proc recording_dirs {} {
  global recording_dirs
  # [2016-12-04 11:04] cannot use 'info var', with 'global' is is defined.
  if {[catch {set recording_dirs}]} {
    puts "WARN: set recording_dirs in .bld/config.tcl"
    puts "Example:
proc define_recording_dirs {} {
  global recording_dirs
  set recording_dirs \[filter \[fn x {regexp project-rec \$x}] \[glob -directory \[file normalize ..] -type d *]]
}

define_recording_dirs 
"
    exit
  }
  return $recording_dirs
}

# Write html (with hh) with correlation info
proc correlations {hh stmt} {
  set rec_dirs [stmt_recording_dirs $stmt]
  foreach rec_dir $rec_dirs {
    correlations_rec_dir $hh $stmt $rec_dir
  }
}

# Write html (with hh) with recording info
proc recordings {hh stmt} {
  set rec_dirs [stmt_recording_dirs $stmt]
  if {[count $rec_dirs] == 0} {
    # [2016-12-11 20:17] possibly nothing found for images and now also for reporting server, later recording.
    # log warn "No recording dirs for: $stmt"
    # breakpoint
  }
  foreach rec_dir $rec_dirs {
    recordings_rec_dir $hh $stmt $rec_dir
  }
}

# return all recording dirs where stmt is found.
# found === both snapshot and URL are the same.
proc stmt_recording_dirs {stmt} {
  #breakpoint
  filter [fn dir {stmt_in_recording_dir? $stmt $dir}] [recording_dirs]
}

# return 1 iff? statement can be found in recording directory.
# [2016-12-06 21:20] use -nocomplain, data dir not always available.
proc stmt_in_recording_dir? {stmt dir} {
  any? [fn inf {stmt_in_inf? $stmt $inf}] [glob -nocomplain -directory "$dir/data" -type f "*.inf"]
}

# check if stmt->url->path occurs in inf file and if snapshot number is the same.
proc stmt_in_inf? {stmt inf} {
  set inf_snapshot [file rootname [file tail $inf]]
  if {$inf_snapshot == [stmt->snapshot $stmt]} {
    # set path [-> $stmt stmt->url url->parts :path]
    set path [stmt->path $stmt]
    # for now just check if path occurs in inf file.
    set inf_text [read_file $inf]
    if {[string first $path $inf_text] >= 0} {
      return 1  
    }
  }
  return 0  
}

# show recording info for statement in recording dir (rec_dir)
# basically just a href to the response file.
proc recordings_rec_dir {hh stmt rec_dir} {
  $hh line "Recording dir where statement is found: $rec_dir"
  set inf_files [filter [fn inf {stmt_in_inf? $stmt $inf}] \
                     [glob -directory "$rec_dir/data" -type f "*.inf"]]
  foreach inf_file $inf_files {
    set resp_file [first [inf->response_files $inf_file]]
    $hh line "Statement found in inf_file: $inf_file: [$hh get_anchor $resp_file file://[resp_file_path $rec_dir $resp_file]]"
    # if {[inf_contains_own_snapshot? $inf_file $ss]} {}
    # check all files mentioned in .inf
    if 0 {
      set response_files [inf->response_files $inf_file]
      set resp_files2 [filter text_response? $response_files]
      $hh write [$hh get_ul [map [fn rf {$hh get_anchor $rf file://[resp_file_path $rec_dir $rf]}] $resp_files2]]
    } 
  }
}

# return 1 iff a html or other text response.
# [2016-12-11 20:01] for now just look at extension
proc text_response? {resp_file} {
  regexp {\.html?$} [string tolower $resp_file]
}

proc correlations_rec_dir {hh stmt rec_dir} {
  $hh line "Recording dir where statement is found: $rec_dir"
  set inf_files [filter [fn inf {stmt_in_inf? $stmt $inf}] \
                     [glob -directory "$rec_dir/data" -type f "*.inf"]]
  foreach inf_file $inf_files {
    $hh line "Statement found in inf_file: $inf_file"
    find_stmt_in_responses $hh $stmt $rec_dir $inf_file
  }
}

# show all statements/requests in recording dir where stmt.path is found in the response. Or a POST or GET parameter.
# algorithm:
# * start at snapshot of inf file, and move back to 1. Stop when 1 found (maybe more later)
# * Only check a snapshot when the .inf refers to a Filename t<snapshot>.x
#   - because eg t12.inf points to t6.htm, but don't want those, are only PNG's.
proc find_stmt_in_responses {hh stmt rec_dir inf_file} {
  regexp {t(\d+).inf} [file tail $inf_file] z stmt_snapshot_nr
  # set path [-> $stmt stmt->url url->parts :path]
  set path [stmt->path $stmt]
  set get_params [stmt->getparams $stmt]
  set post_params [stmt->postparams $stmt]
  for {set ss_check [expr $stmt_snapshot_nr -1]} {$ss_check >= 1} {incr ss_check -1} {
    find_stmt_in_snapshot $hh $stmt $rec_dir $ss_check
  }
}

proc find_stmt_in_snapshot {hh stmt rec_dir ss_nr} {
  # [2016-12-08 09:12:05] Could do those in calling proc, but now only stmt as param.
  set path [stmt->path $stmt]
  set get_params [stmt->getparams $stmt]
  set post_params [stmt->postparams $stmt]

  if {[det_path_correlation $path] > 0.5} {
    # FIXME: for now, want to use treshold option, possibly by substracting treshold and checking here if value > 0.
    find_item_in_snapshot $hh $rec_dir $stmt $ss_nr path $path  
  }

  # [2016-12-08 09:18:01] postparams eerst alleen op value zoeken, als te veel, dan evt ook paramname erbij.
  foreach param $post_params {
    if {[param_correlation $param] > 0} {
      # only find item if it needs to be correlated.
      find_item_in_snapshot $hh $rec_dir $stmt $ss_nr [:name $param] [:value $param]  
    }
  }

  foreach param $get_params {
    if {[param_correlation $param] > 0} {
      find_item_in_snapshot $hh $rec_dir $stmt $ss_nr [:name $param] [:value $param]
    }
  }
}

# also have hh here, so can print some debugging statements.
# [2016-12-06 22:04] FIXME: proc heeft side effects, moet anders!
proc find_item_in_snapshot {hh rec_dir stmt ss name value} {
  set inf_file [file join $rec_dir data "t${ss}.inf"]
  if {[inf_contains_own_snapshot? $inf_file $ss]} {
    # check all files mentioned in .inf
    set response_files [inf->response_files $inf_file]
    foreach resp_file $response_files {
      if {[resp_file_contains_value? $rec_dir $resp_file $value]} {
        $hh heading 4 "Found path/param '$name' with value '$value' in snapshot $ss"
        # $hh line "Source: $source_str"
        $hh heading 5 "Found ($name=)$value"
        $hh line "in response file: [$hh get_anchor $resp_file file://[resp_file_path $rec_dir $resp_file]]:"
        set context_string [resp_context $hh $rec_dir $resp_file $value]
        set source_str [find_source $inf_file $stmt $ss]
        $hh line [$hh pre [$hh to_html $context_string]]
        set wrs [det_web_reg_save $name $value $context_string]
        $hh heading 5 "Proposed regexp (in $source_str):"
        $hh line [$hh pre [$hh to_html $wrs]]
        return 1
      }
    }
    # $hh line "Did not find $path in response files for t${ss}.inf."
    return 0
  } else {
    # don't look here for now, probably only images
    return 0
  }
}

# [2016-12-11 20:54] FIXME: a dirty hack for now
set stmt_db ""

# return filename/linenr
# @param stmt is from request/stmt that needs to be correlated, not from response where
# this path/param is found! So this statement is not very useful here.
proc find_source {inf_file stmt ss} {
  global stmt_db
  if {$stmt_db == ""} {
    if {[catch {
      set stmt_db [get_stmt_db statements/statements.db {clean 0}]      
    }]} {
      log warn "statements.db does not exist"
      log warn "first run 'bld show-paths'"
      exit;                     # for now.
    }

    set query "select count(*) nstmts from stmt_path"
    set res [$stmt_db query $query]
    if {[:nstmts [first $res]] == 0} {
      $stmt_db close
      task_show_paths
      set stmt_db [get_stmt_db statements/statements.db {clean 0}]
    }
  }
  # here stmt_db has value and statements are read.
  set path [url->path [inf_main_url $inf_file]]
  set query "select action_file, linenr
             from stmt_path
             where snapshot='t$ss'
             and path='$path'"
  set res [$stmt_db query $query]
  if {[count $res] > 0} {
    join [map [fn row {return "[:action_file $row]([:linenr $row])"}] $res] ", "  
  } else {
    return "SOURCE FILE NOT FOUND for $inf_file"
  }
  
  # return "find_source for $inf_file/$ss"
}

proc inf_main_url {inf_file} {
  #[t6]
  #FileName1=t6.htm
  #URL1=https://...
  set text [read_file $inf_file]
  if {[regexp {URL1=([^\n]+)} $text z url]} {
    return $url
  } else {
    error "No URL found in inf_file: $inf_file"
  }
}

proc det_web_reg_save {name value str} {
  # set str2 $str
  # (.*?) mss nog vervangen door bv \d+ of [^"]+
  # TODO: met deze regexp nog checken hoe vaak deze voorkomt in de tekst. Dan mogelijk een losse proc det_regexp maken.
  set char_after [str->regexp [char_after_substring $value $str]]
  
  set str2 [str->regexp $str]
  # FIXME: still need to test, with next param to be replaced.
  set value2 [str->regexp $value]; # also put value to be replaced in regexp format, for subsequent string map.
  # set str3 [string map [list $value2 "(.*?)"] $str2]
  set str3 [string map [list $value2 "(\[^${char_after}\]+)"] $str2]
  # breakpoint;                   # test vervangen door [^xx]+
  if {[regexp {\n} $str3]} {
    # log warn "regexp contains newline, should replace: $name=$value"
    # breakpoint
  }
  # replace newlines and tabs, also replace surrounding space-characters.
  regsub -all {\s*[\n\r\t]\s*} $str3 {\\\\s+} str4
  return "\tweb_reg_save_param_regexp(\"ParamName=$name\",\n\t\t\"Regexp=$str4\", LAST);"
}

proc char_after_substring {needle haystack} {
  set p [string first $needle $haystack]
  set len [string length $needle]
  string index $haystack $p+$len
}

proc inf_contains_own_snapshot? {inf_file ss} {
  set inf_text [read_file $inf_file]
  # FileName1=t6.htm
  set re "FileName\\d+=t$ss\\."
  regexp $re $inf_text
}

proc inf->response_files {inf_file} {
  set res [list]
  foreach line [split [read_file $inf_file] "\n"] {
    if {[regexp {^FileName\d+=(.+)$} $line z filename]} {
      lappend res $filename
    }
  }
  return $res
}

proc resp_file_contains_value? {rec_dir resp_file path} {
  set resp_text [read_file [resp_file_path $rec_dir $resp_file]]
  if {[string first $path $resp_text] >= 0} {
    return 1
  } else {
    return 0
  }
}

# maybe combine with resp_file_contains_value?
# return path with surrounding text in resp_file, iff path is found.
# otherwise return empty string.
proc resp_context {hh rec_dir resp_file path} {
  set chars_before 60
  set chars_after 40
  set resp_text [read_file [resp_file_path $rec_dir $resp_file]]
  set pos [string first $path $resp_text]
  if {$pos < 0} {
    return ""
  } else {
    set substring [string range $resp_text $pos-$chars_before [expr $pos+$chars_after+[string length $path]]]
    # breakpoint
    # log info "substring: $substring"
    # $hh pre [$hh to_html $substring]; # deze mss niet hier.
    return $substring
  }
}

proc resp_file_path {rec_dir resp_file} {
  file normalize [file join $rec_dir data $resp_file]
}

# This one for library, also messes up Emacs colour coding.
proc str->regexp {str} {
  #return $str
  # haakjes moeten dubbel escaped worden, puntje ook.
  # string map {\" \\" ( \\( ) \\) . \\.} $str
  # [2016-12-08 12:38:57] also replace {} and []
  # [2016-12-08 13:53:40] and also * + ?
  # [2016-12-08 13:54:20] ^ and $ too.
  string map {\" \\" ( \\\\( ) \\\\) . \\\\. \{ \\\\\{ \} \\\\\} [ \\\\[ ] \\\\] * \\\\* + \\\\+ ? \\\\? ^ \\\\^ $ \\\\$} $str
}

