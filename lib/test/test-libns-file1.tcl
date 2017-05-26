namespace eval ::libtestns_file1 {

  namespace export can_read

  proc can_read {filename} {
    puts "can_read called in ns ::libtestns_file1; return 0"
    return 0
  }
  
}

return ::libtestns_file1
