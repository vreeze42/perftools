namespace eval ::libtestns_file2 {

  namespace export can_read

  proc can_read {filename} {
    puts "can_read called in ns ::libtestns_file2; return 1"
    return 1
  }
  
}

return ::libtestns_file2
