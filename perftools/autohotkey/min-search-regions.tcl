#!/usr/bin/env tclsh

# minimise search regions in AutoHotkey script based on current search regions and locations found (as logged in logfile)

package require ndv
package require png

set_log_global debug

proc main {argv} {
  global fill_blanks
  
  set options {
    {scriptdir.arg "" "Directory with .ahk files"}
    {logdir.arg "output2" "Directory with log files, relative to scriptdir"}
    {margin.arg "3" "Margin in pixels around search region"}
  }
  set usage ": [file tail [info script]] \[options] \[dirname\]:"
  set dargv [getoptions argv $options $usage]

  set scriptdir [:scriptdir $dargv]
  set logdir [file join $scriptdir  [:logdir $dargv]]
	set img_found [read_image_locations $logdir]
  adapt_scripts $scriptdir $img_found $dargv
  # log debug "img_found: $img_found"
}

proc read_image_locations {logdir} {
  log info "Read image locations: $logdir"
  set d [dict create]
  set f [open [file join $logdir logfile.txt] r]
  set linenr 0
  while {[gets $f line] >= 0} {
    incr linenr
    if {[regexp {imagefile: ([^;]+); posfound: ([-0-9]+),([-0-9]+)$} $line z image_path x y]} {
      # negative values for x and y will not be found, should be good for -1,-1 found pos.
      # TODO: check if image was already found, possibly at different location.
      # Maybe within different transactions search region needs to be different
      if {$x >= 0} {
        dict set d [file tail $image_path] [dict create path $image_path x $x y $y]  
      } else {
        # image not found, negative result.
      }
    } elseif {[regexp {posfound} $line]} {
      puts "posfound in line, but not whole imagefile logline"
      puts $line
      breakpoint
    } else {
      # breakpoint
    }
  }
  log debug "read $linenr lines"
  close $f
  return $d
}

proc adapt_scripts {scriptdir img_found dargv} {
  set orig_dir [file join $scriptdir _orig]
  foreach filename [glob -directory $scriptdir *.ahk] {
    if {[adapt_script $scriptdir $filename $img_found $dargv]} {
      # script indeed changed in $filename.__TEMP__ => backup orig and rename
      file mkdir $orig_dir
      file rename -force $filename [file join $orig_dir [file tail $filename]]
      file rename "$filename.__TEMP__" $filename
    } else {
      file delete "$filename.__TEMP__"
    }
  }
}

proc adapt_script {scriptdir filename img_found dargv} {
  log info "Adapt script: $filename"
  set changes 0
  set fo [open "$filename.__TEMP__" w]
  set fi [open $filename r]
  # checkpoint_wrap_image(trans, domesticX, domesticY, 0, 0, 1024, 768, ["template-domestic.png"], timeout)
  # TODO: als er meerdere files in template lijst staan, of als hier wildcards in staan.
  while {[gets $fi line] >= 0} {
    if {[is_comment $line]} {
      puts $fo $line
      continue
    }
    if {[regexp {^(.*?)(\d+), (\d+), (\d+), (\d+), \["([^ ]+)"\](.*)$} $line z prefix x1 y1 x2 y2 imgname postfix]} {
      incr changes [min_region $dargv $img_found $fo $line $prefix $x1 $y1 $x2 $y2 $imgname $postfix]
    } elseif {[regexp {checkpoint_wrap} $line]} {
      breakpoint
    } else {
      puts $fo $line
    }
  }
  close $fo
  close $fi
  
  return $changes  
}

proc is_comment {line} {
  regexp {^;} [string trim $line]
}

proc min_region {dargv img_found fo line prefix x1 y1 x2 y2 imgname postfix} {
  set margin [:margin $dargv]
  # log debug "imgname to look for in img_found: $imgname"
  # set dimg [dict_get $img_found $imgname]
  set dimg [find_image $img_found $imgname]
  if {$dimg == ""} {
    log warn "Ref to image in script not found in log: $imgname"
    puts $fo $line
    return 0
  }
  if {($x1 != 0) || ($y1 != 0)} {
    # breakpoint
    log debug "x1 and/or y1 != 0, don't change anything ($x1, $y1, $line)"
    puts $fo $line
    return 0
  }
  #% ::png::imageInfo menu-funds.png
  #width 77 height 6 depth 8 color 2 compression 0 filter 0 interlace 0

  set dsize [::png::imageInfo [:path $dimg]]
  set x1 [expr [:x $dimg] - $margin]
  set y1 [expr [:y $dimg] - $margin]
  set x2 [expr [:x $dimg] + [:width $dsize] + $margin]
  set y2 [expr [:y $dimg] + [:height $dsize] + $margin]

  puts $fo "; $line"
  puts $fo "$prefix$x1, $y1, $x2, $y2, \[\"$imgname\"\]$postfix"
  
  return 1
}

# @param img_found - dict: key=filename, value=dict: image full path, x, y
# @param imgname - login*.png
proc find_image {img_found imgname} {
  if {[regexp {\*} $imgname]} {
    # special handling
    set ks [dict keys $img_found $imgname]
    if {$ks == {}} {
      return ""
    } else {
      dict get $img_found [:0 $ks]
    }
  } else {
    # just return from dict
    dict_get $img_found $imgname
  }
  
}

if {[this_is_main]} {
  main $argv  
}

