package require json

require libio io

use libfp
use liburl

# [2016-12-03 21:28] TODO: tresholds etc should be settable per script/project, possibly override (like now) with cmdline param.

task show_requests {Create a HTML report of requests for correlation.
  Check if requests have dynamic items, which should be correlated.
} {
  {clean "Delete DB and generated reports before starting"}
  {all "Show info about all request (default: only requests where action is needed)"}
  {treshold.arg "0.9" "Treshold above which requests are marked Red"}
} {
  file mkdir requests
  set script [file tail [file normalize .]]
  corr_ini_init
  io/with_file f [open requests/requests.html w] {
    set hh [ndv::CHtmlHelper::new]
    $hh set_channel $f
    if {[:all $opt]} {
      $hh write_header "All requests in $script" 0  
    } else {
      $hh write_header "Selected requests in $script" 0
    }
    show_toc $opt $hh
    foreach filename [get_action_files] {
      show_requests_file $opt $hh $filename
    }
    $hh write_footer
  }
  corr_ini_write
  # breakpoint
}

# DB erbij maken waar requests en paths instaan, om dubbele te vinden.
# eerst DB, mss hierna ook nog html
task show_paths {Create a DB (and HTML? report) of all statements/paths in script
  Check if paths occur more than once, should be de-duplicated.
} {
  {clean "Delete DB and generated reports before starting"}
} {
  file mkdir statements
  set db [get_stmt_db [file join statements "statements.db"] $opt]
  $db in_trans {
    foreach action_file [get_action_files] {
      set stmts [read_source_statements $action_file]
      foreach stmt $stmts {
        if {[:type $stmt] == "main-req"} {
          set linenr [:linenr_start $stmt]
          set lines [join [:lines $stmt] "\r\n"]
          set path [stmt->path $stmt]
          set url [stmt->url $stmt]
          set snapshot [stmt->snapshot $stmt]
          $db insert stmt_path [vars_to_dict action_file linenr lines path url snapshot]
        }
      }
    }
  }

  io/with_file f [open statements/statements.html w] {
    set hh [ndv::CHtmlHelper::new]
    $hh set_channel $f
    $hh write_header "All statements in script" 0  
    $hh table {
      $hh table_header path file1 file2 url1 url2

      set query "select p1.path path, p1.action_file file1, p2.action_file file2, p1.url url1, p2.url url2
      from stmt_path p1 join stmt_path p2 on p1.path = p2.path
      where p1.action_file < p2.action_file
      order by p1.path, p1.action_file, p2.action_file"

      foreach row [$db query $query] {
        $hh table_row [:path $row] [:file1 $row] [:file2 $row] [:url1 $row] [:url2 $row]
      }
      
    }
    $hh write_footer
  }

  $db close
}

# deze mogelijk in libdb:
proc get_stmt_db {db_name opt} {
  if {[:clean $opt]} {
    file delete $db_name
  }
  set existing_db [file exists $db_name]
  set db [dbwrapper new $db_name]
  # define_tables $db $opt
  # for now only one table
  $db def_datatype {linenr} integer
  $db add_tabledef stmt_path {id} {action_file linenr lines path url snapshot}
  
  $db create_tables 0 ; # 0: don't drop tables first. Always do create, eg for new table defs. 1: drop tables first.
  if {!$existing_db} {
    log info "New db: $db_name, create tables"
    # create_indexes $db
  } else {
    log info "Existing db: $db_name, don't create tables"
  }
  # TODO: maybe call prepare just before (or within) first insert call.
  $db prepare_insert_statements
  #breakpoint

  # $db load_percentile
  
  return $db
}

proc show_toc {opt hh} {
  $hh heading 1 "Table of contents"
  foreach filename [get_action_files] {
    if {[show_requests_file? $opt $filename]} {
      $hh href $filename "#$filename"
      $hh br
    }
  }
}

# Add requests in filename to html (hh)
proc show_requests_file {opt hh filename} {
  if {![show_requests_file? $opt $filename]} {
    return
  }
  $hh anchor_name [file tail $filename]
  # [2017-05-04 15:30] clear make visible this is an anchor, and a new source file.
  # $hh heading 1 "*** Requests in [file tail $filename] ***"
  $hh heading 1 "<hr/>Requests in [file tail $filename]"
  set stmts [read_source_statements $filename]

  foreach stmt $stmts {
    if {[:type $stmt] == "main-req"} {
      show_request_html $opt $hh $stmt
    }
  }

}

# return 1 iff requests in file should be shown, based on options and requests in file.
proc show_requests_file? {opt filename} {
  set stmts [read_source_statements $filename]
  # set stmts2 [filter [fn x {[:type $x] == "main-req"}] $stmts]
  set stmts2 [filter [fn x {= [:type $x] "main-req"}] $stmts]
  set stmts3 [filter [fn x {show_request_html? $opt $x}] $stmts2]
  # breakpoint
  if {[count $stmts3] > 0} {
    return 1
  }
  return 0
}

proc show_request_html {opt hh stmt} {
  if {![show_request_html? $opt $stmt]} {
    return
  }
  set url [stmt->url $stmt]
  set stmt_params [stmt->params $stmt]
  set referer [stmt->referer $stmt]
  set url_params [url->params $url]; # maybe also set from POST body.
  # $hh heading 2 "Request - $url" "class=Failure"
  $hh heading 2 "Request - $url (corr=[format %.3f [det_request_correlation $stmt]])" "class=[det_request_class $opt $stmt]"
  paragraph $hh "Correlation details" [lines->html [correlation_details $stmt]]
  paragraph $hh [lines_heading $stmt] [lines->html [:lines $stmt]]
  # paragraph $hh "Statement Parameters" [stmt_params->html $stmt_params]
  paragraph $hh "URL/GET Parameters" [params->html $hh $url_params]
  paragraph $hh "POST Parameters" [params->html $hh [stmt->postparams $stmt]]
  paragraph $hh Url $url
  paragraph $hh Referer $referer

  # iff request is shown, add it to correlations file
  corr_ini_add_stmt $stmt;      # this statement is important enough to show, also add to correlations.ini

  # show response files of recording(s)
  $hh heading 3 Recording(s)
  recordings $hh $stmt
  
  # Show possible correlations
  # paragraph $hh Correlations [correlations $stmt]
  $hh heading 3 Correlations
  correlations $hh $stmt
}

proc corr_ini_add_stmt {stmt} {
  set url [stmt->url $stmt]
  set parts [url->parts $url]
  corr_ini_add path [:path $parts] [det_request_correlation $stmt] ""
  foreach param [:params $parts] {
    corr_ini_add_param GET $param
    # corr_ini_add paramname [:name $param] [param_correlation $param] "GET param, value=[:value $param], type=[:valuetype $param]"
  }
  foreach param [stmt->postparams $stmt] {
    corr_ini_add_param POST $param
    # corr_ini_add paramname [:name $param] [param_correlation $param] "POST param, value=[:value $param], type=[:valuetype $param]"
  }
}

# Add param iff it is not already in the ini-file.
proc corr_ini_add_param {paramtype param} {
  if {[count [corr_ini_get_lines paramname [:name $param]]] == 0} {
    corr_ini_add paramname [:name $param] [param_correlation $param] "$paramtype param, value=[:value $param], type=[:valuetype $param]"
  }
}

# Don't show paragraph iff its contents are empty.
proc paragraph {hh title content} {
  if {$content != ""} {
    $hh heading 3 "${title}:"
    $hh text $content
  }
}

# return 1 iff request should be shown with given opt(ions)
proc show_request_html? {opt stmt} {
  if {[:all $opt]} {
    return 1
  }
  if {[stmt_ignore? $stmt]} {
    return 0
  }
  if {[det_request_correlation $stmt] >= [:treshold $opt]} {
    return 1
  }
  return 0
}

proc stmt_ignore? {stmt} {
  corr_ini_ignore? path [stmt->path $stmt]
}

# TODO: for now only check name, but could also decide on value and/or valuetype.
proc param_ignore? {param} {
  corr_ini_ignore? paramname [:name $param]
}

# return either Failure or an empty string, based on the chance we need to do some
# correlation and the treshold set in opt.
proc det_request_class {opt stmt} {
  if {[det_request_correlation $stmt] >= [:treshold $opt]} {
    return Failure
  } else {
    return ""
  }
}

# return value with indication we need to do some correlation
# on this item. Could be bigger than 1.
proc det_request_correlation {stmt} {
  # return 0.6
  set url [stmt->url $stmt]
  set ext [string tolower [file extension $url]]
  # less chance that images need to be correlated, but this could depend on the script/project.
  if {[lsearch -exact {.gif .jpg .jpeg .png .js .css} $ext] >= 0} {
    return 0.1
  }
  set parts [url->parts $url]

  # Correlation value is sum of three things: corr(url), corr(url-get-params), corr(url-post-params). For now only the url-path part.
  # url-params: list of params: dict: type,name,value,valuetype
  # post_params: list of dicts: type,name,value,valuetype
  # - these are all parameters, not just ones after ITEMDATA.
  return [expr [det_path_correlation [:path $parts]] + \
              [det_get_params_correlation [:params $parts]] + \
             [det_post_params_correlation [stmt->postparams $stmt]]]
}

# return lines with details about value of correlation for this statement
proc correlation_details {stmt} {
  set url [stmt->url $stmt]
  set ext [string tolower [file extension $url]]
  # less chance that images need to be correlated, but this could depend on the script/project.
  if {[lsearch -exact {.gif .jpg .jpeg .png .js .css} $ext] >= 0} {
    return [list "Image or static: $ext => 0.1"]
  }
  set parts [url->parts $url]
  set res [list]
  lappend res "path: [format %.3f [det_path_correlation [:path $parts]]]"
  lappend res {*}[det_path_correlation_details [:path $parts]]
  lappend res "get params: [det_get_params_correlation [:params $parts]]"
  lappend res "post params: [det_post_params_correlation [stmt->postparams $stmt]]"
  return $res
}

# [2017-01-13 11:27] some refactoring done to have a SPOD, and use results both for
# calculating the correlation value and showing all details in HTML.
#
# Als lengte meer dan 40 is, wordt het ook spannend.
# bv met len=40 en conseq=6 is het wel spannend, dan moet je boven .9 uitkomen, bv 1.0.
# Beide voor de helft laten tellen.
# 40/80 = .5
# 6/12 = .5
proc det_path_correlation {path} {
  + [max_segm_len_corr $path] [max_segm_consec_chargroup_corr $path]
}

# return list with strings to put in html.
proc det_path_correlation_details {path} {
  set ml [max_segm_len $path]
  set mcc [max_segm_consec_chargroup $path]
  set ml_corr [format %.3f [max_segm_len_corr $path]]
  set mcc_corr [format %.3f [max_segm_consec_chargroup_corr $path]]
  
  list "max length of a segment: $ml_corr (len = $ml)" \
      "max consec chargroup: $mcc_corr (# = $mcc)"
}

proc max_segm_len_corr {path} {
  expr 1.0 * [max_segm_len $path] / 80
}

proc max_segm_consec_chargroup_corr {path} {
  set res2 [expr 1.0 * [max_segm_consec_chargroup $path] / 12]
  if {$res2 > 2.0} {
    log warn "res: $res"
    breakpoint
  }
  return $res2
}


# return int, the fact, max segment length
proc max_segm_len {path} {
  if {$path == ""} {
    return 0
  }
  set res1 [max {*}[map [fn x {string length [remove_params $x]}] [split $path "/"]]]
  return $res1  
}

# return int, the fact, max number of consecutive characters in path-segment.
proc max_segm_consec_chargroup {path} {
  if {$path == ""} {
    return 0
  }
  set res2 [max {*}[map max_consecutive_chargroup [split $path "/"]]]
  return $res2
}

# remove LR params from string, i.e. everything between {}
# these params should not count for correlation value.
proc remove_params {str} {
  regsub -all {\{[^\{\}]+\}} $str "" str2
  return $str2
}

# return max number of consecutive characters of the same group.
# group is hardcoded here as: vowels, consonants, digits and other characters.
proc max_consecutive_chargroup {str} {
  set max 0
  set i 0
  set prev_group ""
  set str2 [remove_params $str]
  foreach char [split $str2 ""] {
    set group [char_group $char]
    # puts "group of $char: $group"
    if {$group == $prev_group} {
      incr i
    } else {
      if {$i > $max} {set max $i}
      set i 1
      set prev_group $group
    }
  }
  return $max
}

proc char_group {char} {
  if {[string first [string tolower $char] "aeiouy"] >= 0} {
    return "vowel"
  } elseif {[regexp {[a-z]} [string tolower $char]]} {
    return "consonant"
  } elseif {[regexp {[0-9]} $char]} {
    return "digit"
  } else {
    return "other"
  }
}

# params: GET parameters: list of url params
#   each element is a dict: type,name,value,valuetype
# return: correlation indicator (float). The higher the result, the more reason to think params need to be correlated.
proc det_get_params_correlation {params} {

  # Use both param_ignore? and content check just checks correlations.ini.
  # for each param can possibly be ignored based on 1 out of 2 reasons:
  # 1. in correlations.ini ignore list.
  # 2. based on actual value.
  
  # count [filter param_correlation $params]
  + {*}[map param_correlation $params]

}

# postparams: list of dict: name, value, valuetype.
# return: correlation indicator (float). The higher the result, the more reason to think params need to be correlated.
# TODO: this one is now the same as GET variant? Merge the two? Or will post be different, eg with multiline items or uploading files?
proc det_post_params_correlation {params} {
  #return [count $postparams];   # for now.
  # count [filter param_correlation $postparams]
  + {*}[map param_correlation $params]
}

# param is a GET or POST parameter. A dict with name, value, valuetype.
# return 0 if param does not need to be correlated, 1 if it does.
# TODO: maybe return a fraction depending on the chance, eg integer-value or string length.
proc param_correlation {param} {
  if {[param_ignore? $param]} {
    return 0
  }
  switch [:valuetype $param] {
    lrparam {return 0}
    empty {return 0}
    integer {
      # values between 0-10 inclusive do not need to be correlated.
      # TODO: check if this is valid.
      if {([:value $param] >= 0) && ([:value $param] <= 10)} {
        return 0
      } else {
        return 1
      }
    }
    boolean {return 0}
    xdigit {return 1}
    double {return 1}
    json {return 1}
    base64 {return 1}
    string {
      # short strings do not need to be correlated.
      # TODO: Check if this is valid.
      if {[string length [:value $param]] <= 5} {
        return 0
      } else {
        return 1
      }
    }
    default {return 1}
  }
  # maybe should check with default, contains epoch times for now, should be correlated.
  return 0
}

proc lines_heading {stmt} {
  return "Lines ([:linenr_start $stmt] to [:linenr_end $stmt])"
}

proc params->html {hh params} {
  # join [map param->html $params] "<br/>"
  # ul checks items in list. If they are already a <li> elements, don't add tags.
  # if only a string, do add tags.
  # $hh get_ul [map param->html $params]
  $hh get_ul [map [fn par {param->html $hh $par}] $params]
}

# param is a tuple: name, value
proc param->html {hh param} {
  # lassign $param name value
  set type namevalue;           # default.
  dict_to_vars $param;          # type, name, value, valuetype
  switch $type {
    name {
      # return [wordwrap_html $name]
      return $name;             # no wordwrap for now
    }
    namevalue {
      # return [wordwrap_html "$name = $value \[$valuetype\]"]
      set str "$name = $value \[$valuetype\]"  
      if {[param_correlation $param] > 0} {
        # make red
        return [$hh get_li $str "style=\"color:red\""]
      } else {
        return $str
      }
    }
    else {
      error "Unknown type: $type for: $param"
    }
  }  
}

# parameters: list of name,value pairs
proc stmt_params->html {parameters} {
  error "Not used anymore?"
  params->html $parameters;     # for now, they seem the same.
}




##########################################################
# Library stuff, not specific to statements and URL's    #
##########################################################

# lines - list of lines
# result lines, separated by <br/> elements
proc lines->html {lines} {
  # [2016-12-02 14:32] no word wrap for now.
  # set lines2 [map wordwrap_html $lines]
  join $lines "<br/>"
}


proc wordwrap_html {str {line_length 60} {splitchars " /&?"}} {
  # set lines [wordwrap_generic $str $wordwrap $splitchars]
  # [2016-11-27 16:38] for now just split text up exactly at line_length sizes
  set lines [list]
  while {$str != ""} {
    lappend lines [string range $str 0 $line_length-1]
    set str [string range $str $line_length end]
  }
  join $lines "<br/>&nbsp;&nbsp;"
}

# algoritme van http://en.wikipedia.org/wiki/Word_wrap
# return list of lines as split up.
# TODO: deze werkt niet, splitchars raken kwijt.
proc wordwrap_generic {str {wordwrap 60} {splitchars " "}} {
  # global wordwrap
  if {$wordwrap == ""} {
    return [list  $str]
  }
  set spaceleft $wordwrap
  set result [list]
  set curr_line ""
  foreach word [split $str $splitchars] {
    if {[string length $word] > $spaceleft} {
      lappend result $curr_line
      set curr_line "$word "
      # lappend result "\\n$word "
      set spaceleft [expr $wordwrap - [string length $word]]
    } else {
      # append result "$word "
      append curr_line "$word "
      set spaceleft [expr $spaceleft - ([string length $word] + 1)]
    }
  }
  lappend result $curr_line
  return $result
}

################################################################
# set of functions for handling ignore items for correlations. #
################################################################

proc corr_ini_init {} {
  global corr_ini
  set corr_ini [ini/read [file join requests correlations.ini] 0]
}

proc corr_ini_write {} {
  global corr_ini
  ini/write [file join requests correlations.ini] $corr_ini
}

# add a request or parameter to correlations list/ini
proc corr_ini_add {type name corr notes} {
  global corr_ini
  set header "${type}-${name}"
  set corr_ini [ini/set_param $corr_ini $header corr $corr]
  set corr_ini [ini/set_param $corr_ini $header ignore 0]
  set corr_ini [ini/set_param $corr_ini $header notes $notes]
  set corr_ini [ini/set_param $corr_ini $header reason ""]; # to be filled in by user.
}

proc corr_ini_get_lines {type name} {
  global corr_ini
  set header "${type}-${name}"
  ini/lines $corr_ini $header
}

# check if request or parameter is marked as ignore in list/ini
proc corr_ini_ignore? {type name} {
  global corr_ini
  set header "${type}-${name}"
  ini/get_param $corr_ini $header ignore 0
}

