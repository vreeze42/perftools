# if not really, create a file.__TEMP__ with the new version. Then perform a diff on both.
# TODO: als -do is meegegeven, dan actie opslaan (in repo, want ook voor andere scripts). dan optie om deze te tonen en te kiezen.
# en mss ook een naam te geven.
task regsub {Regular epression replace} {
  {do "Really perform regsub actions (dry run otherwise)"}
  {all "Handle all files (be careful!)"}
  {allrec "Handle all files; recurse subdirs (except starting with . be very careful!"}
  {pat.arg "" "Handle all files matching glob pattern"}
  {patrec.arg "" "Handle all files matching glob pattern"}
  {action "Only handle action files"}  
  {text "Handle all text files (TBD)"}  
  {filenames "Only show filenames with changes, no contents"}
} {from to} {
  set really [:do $opt]
  lassign $args from to  
  puts "from: $from, to: $to, args: $args"
  regsub -all {\\n} $to "\n" to2
  set filenames [get_filenames $opt]
  log debug "Files to search/replace: $filenames"
  # breakpoint
  foreach srcfile $filenames	{
    # regsub_file $srcfile $from $to2 $really
    regsub_file $srcfile $from $to2 $opt
  }
}

proc regsub_file {srcfile from to opt} {
  set really [:do $opt]
  set text [read_file $srcfile]
  set nreplaced [regsub -all $from $text $to text2]
  if {$nreplaced == 0} {
    # nothing, no replacements done.
  } else {
    puts "$srcfile - $nreplaced change(s):"
    # set tempfile "$srcfile.__TEMP__"
    set tempfile [tempname $srcfile]
    #set f [open $tempfile w]
    #fconfigure $f -translation crlf
    set f [open_temp_w $srcfile]
    puts -nonewline $f $text2
    close $f
    diff_files $srcfile $tempfile
    if {$really} {
      puts "really perform replacement, orig files in _orig dir"
      commit_file $srcfile
    } else {
      rollback_file $srcfile
    }
  }
}

if 0 {
  Example regsubs:

  put ff:<text> in action file, this regsub will replace it with weg_reg_find:
  bld regsub -action "[ \t]*ff:([^\n\r]+)" "    web_reg_find(\"Text=\1\", \"Fail=NotFound\", LAST);"

  
}
