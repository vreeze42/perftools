# 'clean' is for file(system) actions. Use remove for text within files.
task clean {Delete non script files
  THIS ACTION CANNOT BE UNDONE (with undo)
  Delete files base on option(s) given.
  Do buildtool clean to see options.
} {{idx "Delete .idx files"}
  {log "Delete output.* TransactionData.db, replay.har, shunra.shunra, mdrv.log"}
  {tmp "Delete .tmp files"}
  {bak "Delete .bak files"}
  {orig "Delete _orig directories"}
  {res "Delete result1/data directories"}
  {all "delete all of the above"}
} {
  set dir [file normalize .]
  set patterns [det_glob_patterns $opt]
  puts "Cleaning dir: [file normalize $dir]"
  foreach pattern $patterns {
    puts "Cleaning pattern: $pattern"
    foreach filename [glob -nocomplain -directory $dir $pattern] {
      delete_path $filename
    }
  }
}

proc det_glob_patterns {opt} {
  set res {}
  if {[:all $opt]} {
    set opt [dict create idx 1 log 1 tmp 1 bak 1 orig 1 res 1]
  }
  if {[:idx $opt]} {
    lappend res "*.idx"
  }
  if {[:log $opt]} {
    lappend res "output.*" TransactionsData.db replay.har shunra.shunra mdrv.log logs
  }
  if {[:tmp $opt]} {
    lappend res "*.tmp"
  }
  if {[:bak $opt]} {
    lappend res "*.bak"
  }
  if {[:orig $opt]} {
    # [2016-07-30 15:00] glob should work with subdirs like this.
    lappend res "[config_dir]/_orig*"
  }
  if {[:res $opt]} {
    lappend res result1 data
  }
  return $res
}

# TODO: deleting logs directory does not work. Could do: if isdir and force fails, do per file in dir.
proc delete_path {pathname} {
  puts "Deleting: $pathname"
  # return ; # test
  if {[file isdirectory $pathname]} {
    # force nodig, dir is mogelijk niet leeg of heeft subdirs.
    catch {file delete -force $pathname}  
  } else {
    catch {file delete $pathname}  
  }
}

