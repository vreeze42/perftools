#!/usr/bin/env tclsh

# [2016-07-23 11:42] default want the same version for install as for interactive and script usage, i.e. tclsh, not tclsh861 etc.
# Can always execute with eg. tclsh861 install.tcl

# install package ndv under tcl lib directory
set package_name ndv
set package_version 0.1.1

catch {
    # 12-11-2016 use catch wrt bootstrapping, when first install would fail.
    source libns.tcl
    source libfp.tcl
    use libfp
}

# history
# version date     notes
# 0.1              initial version with logger, htmlhelper and xmlhelper
# 0.1.1   8-1-2010 logger: added set_log_level_all

# 16-1-2010 niet meer doen, gebruik vaste pkgIndex.tcl
#pkg_mkIndex . *.tcl

# lib_root D:/DEVELOP/TCL85/lib/tcl8.5 => D:/DEVELOP/TCL85/lib
proc main {} {
  global package_name package_version

  # [2016-07-23 11:35] create file with installation timestamp
    # don't use ndv library procedures here.
    set latest_file "Could not determine latest file"
    catch {set latest_file [det_latest_file]}
  set f [open _installed_message.tcl w]
  puts $f "set _ndv_version \"package ndv installed on: [clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S %z"] - $latest_file\""
  close $f
  
  set lib_root [file dirname [info library]]
  set lib_install [file join $lib_root "$package_name-$package_version"]
  install_to_dir $lib_install

}

# determine latest/newest file and return string with filename and date/time
# TODO: implement
# maybe also use Clojure threading operator ->
proc det_latest_file_new {} {
  set files [glob_rec_files *.tcl]
  map {dict name mtime}
  # soort van max-dict fn maken, die hele dict retourneert gebaseerd op 1 veld. Zie Clojure, sort functie ook.
  # ook iets van first [sort $files] te doen.
  reduce [fn {old new} {ifp [:mtime $old] > [:mtime $new] $old $new}] ; start with first two.
  format result  
}

# first an imperative version which also checks subdirs
proc det_latest_file {} {
  lassign [det_latest_file_rec .] filename mtime
  return "Newest: $filename ([clock format $mtime -format "%Y-%m-%d %H:%M:%S %z"])"  
}

# return [list <name> <timestamp in seconds>] of newest file in dir, including subdirs
proc det_latest_file_rec {dir} {
  set mtime 0
  set filename ""
  foreach path [glob -nocomplain -directory $dir *] {
    if {[latest_ignore $path]} {continue}
    if {[file isfile $path]} {
      if {[file mtime $path] > $mtime} {
        set mtime [file mtime $path]
        set filename $path
      }
    } else {
      # directory
      set subres [det_latest_file_rec $path]
      if {[lindex $subres 1] > $mtime} {
        lassign $subres filename mtime
      }
    }
  }
  list $filename $mtime
}

proc latest_ignore {path} {
  set tail [file tail $path]
  != {} [filter [fn re {regexp $re $tail}] {{^_} {^logs$}}]
}

proc install_to_dir {lib_install} {
  check_writable $lib_install  
  copy_dir $lib_install .
  copy_dir $lib_install db
  copy_dir $lib_install js *
  copy_dir $lib_install sqlite-functions *
}

proc check_writable {dir} {
    set res 0
    catch {
	file mkdir $dir
	set res 1
    }
    if {!$res} {
	puts "Could not create dir: $dir"
	puts "Retry with sudo:"
	exec sudo mkdir $dir
	exec sudo chmod a+rwx $dir
	# exit 1
    }
}

proc copy_dir {lib_install subdir {pattern *.tcl}} {
  file mkdir [file join $lib_install $subdir]
  foreach filename [glob -directory $subdir -type f $pattern] {
    puts "copy $filename => $lib_install/$subdir"
    file copy -force $filename [file join $lib_install $subdir]
  }
}

main
