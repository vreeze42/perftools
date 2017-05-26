# libcyg - functions for working with cygwin in tcl
# especially path conversion from and to cygwin
# /cygdrive/c spec as well as ~/

# ~ not needed, resolves in tclsh and cygwin to same path (?).

proc to_cygwin {path} {
  # file normalize capitalises c to C, causes tests to fail and adds nothing really.
  # set path2 [file normalize $path]
  set path2 $path
  if {[regexp {^(.):(.*)$} $path2 z drive path3]} {
    return "/cygdrive/$drive$path3"
  } else {
    return $path 
  }
}

proc from_cygwin {path} {
  if {[regexp {^/cygdrive/(.)/(.*)$} $path z drive path2]} {
    file join "$drive:/" $path2 
  } else {
    return $path 
  }
}

