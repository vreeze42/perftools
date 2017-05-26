package provide ndv 0.1.1
package require Tclx

namespace eval ::ndv {

  variable log
  variable ar_opts
  
  set log [::ndv::CLogger::new_logger [file tail [info script]] debug]

  proc music_random_select {db n {opts {}}} {
    fill_ar_opts $opts

    srandom [clock seconds]
    calc_freq_history $db $n
    set lst [choose_random $db $n]
    return $lst    
  }
  
  proc fill_ar_opts {opts} {
    variable ar_opts
    set options {
      {tablemain.arg "musicfile" "Main table with fields freq, play_count, freq_history"}
      {viewmain.arg "" "db view to use if not whole table should be used. Should have fields: id, path, freq, play_count, freq_history"}
      {tableplayed.arg "played" "Table for played entries with fields <tablemain>, kind, datetime"}
    }
    set usage ": [file tail [info script]] \[options] :"
    array set ar_opts [::cmdline::getoptions opts $options $usage]
    if {$ar_opts(viewmain) == ""} {
      set ar_opts(viewmain) $ar_opts(tablemain) 
    }
  }
  
  #@post freq_history fields are updated based on current freq and play_count values
  #@todo n (#requested) should not be needed here.
  proc calc_freq_history {db n} {
    variable log
    variable ar_opts
    # global log db conn SINGLES_ON_SD
    
    # @note 17-1-2010 NdV m4a check niet meer nodig, heb deze al omgezet. Maar kan ook geen kwaad.
    set conn [$db get_connection]
    # set query "select sum(freq), sum(play_count) from musicfile where not lower(path) like '%.m4a'"
    # set query "select sum(freq), sum(play_count) from musicfile"
    #set query "select sum(freq), sum(play_count) from $ar_opts(tablemain)"
    set query "select sum(freq), sum(play_count) from $ar_opts(viewmain)"
    # set result [::mysql::sel $conn $query -flatlist]
    set result [pg_query_flatlist $conn $query]
    set F_sum [lindex $result 0]
    set chosen_sum [lindex $result 1]
    $log debug "F_sum: $F_sum"
    $log debug "chosen_sum: $chosen_sum"
    # set total_sum [expr $chosen_sum + $SINGLES_ON_SD]
    set total_sum [expr $chosen_sum + $n]
    $log debug "total_sum: $total_sum"
  
    # set query "select id, freq, play_count from musicfile where not lower(path) like '%.m4a'"
    set query "select id, freq, play_count from $ar_opts(viewmain)"
    # set result [::mysql::sel $conn $query -list]
    set result [pg_query_list $conn $query]
    set nrecords [llength $result]
    # 31-5-2012 NdV try start transaction/commit to improve speed. This does indeed work!
    # Could also be a different db implementation, like InnoDB, not sure if the one used here is the same as before.
    $log debug "start transaction"
    # ::mysql::exec $conn "start transaction"
    pg_query $conn "start transaction"
    set i 0
    foreach record $result {
      incr i
      $log debug "Handling $i / $nrecords"
      foreach {id freq play_count} $record break
      # set freq_history [expr $chosen_sum * ((1.0 * $freq / $F_sum) - ((1.0 * $play_count / $total_sum)))]
      # 17-1-2010 NdV total_sum ipv chosen_sum aan het begin, want chosen_sum kan 0 zijn, en dan alles 0
      set freq_history [expr $total_sum * ((1.0 * $freq / $F_sum) - ((1.0 * $play_count / $total_sum)))]
      $log trace "freq_history = $freq_history => $total_sum * ((1.0 * $freq / $F_sum) - ((1.0 * $play_count / $total_sum)))"
      $db update_object $ar_opts(tablemain) $id -freq_history $freq_history
    }
    # 31-5-2012 NdV ... and also commit.
    pg_query $conn "commit"
    $log debug "Executed commit (after start transaction)"
  }

  # [2013-07-27 20:01:40] Vandaag error dat niet genoeg items zijn gekozen. Zou moeten dan kans dat item
  # wordt gekozen groter wordt naarmate en minder beschikbaar zijn. Nu lijkt het alsof items met een Fi < 0
  # nooit worden gekozen. Ook als je meer items wilt dat er zijn, bepalen wat je wilt: ofwel alles teruggeven,
  # ofwel sommige items dubbel tot gevraagde aantal.
  # eerste berekening van Fi zou onafhankelijk van aantal te selecteren items moeten zijn, alleen volgorde en
  # vooral relatieve kans bepalen.
  # met test-suite wat meer runs doen, kijken of het kan kloppen (statistisch?)  
  proc choose_random {db n} {
    variable ar_opts
    log info "choose_random: started"
    # global db conn log
    set conn [$db get_connection]
    # 1-5-2011 NdV not sure if also here only > 0 need to be selected; what if there are less than 5 left with pos value?
    set query "select id, path, freq_history 
               from $ar_opts(viewmain)
               order by freq_history desc, path" 
    # set lst [::mysql::sel $conn $query -list]
    set lst [pg_query_list $conn $query]
    set N [llength $lst]
    log info "#items to choose from: $N"
    set m 0 ; # aantal gekozen records
    set lst_result {}
    set F_sum [det_freq_history_sum $conn]
    # puts "F_sum: $F_sum"
    set t 0 ; # aantal behandelde records
    set F_gehad 0.0
    set i 0
    set skipped 0
    foreach el $lst {
      incr i
      if {($m >= $n)} {break}
      # while {($m < $n) && ($t < $N)} {}
      set U [random1]
      # puts "U: $U"
      # set el [lindex $lst $t]
      # foreach {id path Fi} $el break;
      lassign $el id path Fi 
      log debug "Iteration $i, U=$U, el=$el"
      set rnd [expr $U * ($F_sum - $F_gehad)]
      set fixed [expr ($n - $m) * $Fi]
      if {[expr $U * ($F_sum - $F_gehad)] < [expr ($n - $m) * $Fi]} {  
        log debug "$rnd < $fixed, choose element"
        lappend lst_result [list $id $path $U]
        incr m
      } else {
        log debug "$rnd >= $fixed, skip element"
        incr skipped
      }
      log debug "iter=$i, #chosen=$m, #skipped=$skipped"
      incr t
      set F_gehad [expr $F_gehad + $Fi]
    }
    if {$m < $n} {
      error "Not enough items chosen"
    }
    return $lst_result  
  }  

  proc det_freq_history_sum {conn} {
    variable ar_opts
    # global conn
    # set query "select sum(freq_history) from musicfile where not lower(path) like '%.m4a'"
    # 1-5-2011 NdV only select sum of items with freq > 0, otherwise pos and neg cancel out.
    set query "select sum(freq_history) from $ar_opts(viewmain) where freq_history > 0"
    set res [pg_query_flatlist $conn $query]
    return [lindex $res 0]
  }
  

  proc music_random_update {db lst kind {opts {}}} {
    variable ar_opts
    fill_ar_opts $opts
    set dt [clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S"]
    foreach el $lst {
      foreach {id path rnd} $el break
      $db update_object $ar_opts(tablemain) $id -play_count "play_count+1"
      # $db insert_object played -$ar_opts(tablemain) $id -kind "sd-auto" -datetime $dt
      $db insert_object $ar_opts(tableplayed) -$ar_opts(tablemain) $id -kind $kind -datetime $dt
    }    
  }
  
	namespace export music_random_select music_random_update
  
}

