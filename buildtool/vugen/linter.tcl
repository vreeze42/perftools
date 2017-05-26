task linter {Check source files like a linter.
} {
  # TODO: remove both /* */ and // comments. Should already have code for this.
  foreach filename [get_source_files] {
    if {![lint_ignore $filename]} {
      lint_file $filename  
    }
  }
}

proc lint_ignore {filename} {
  set ignores {vugen.h y_core.c}
  foreach re $ignores {
    if {[regexp $re $filename]} {
      return 1
    }
  }
  return 0
}

proc lint_file {filename} {
  log debug "Handling file: $filename"
  set statements [read_source_statements $filename]
  if {$filename == "transaction.c"} {
    # breakpoint
  }
  # breakpoint
  # check var initialise can be done by checking each statement. Other things like free/= NULL combinations require checking multiple statements.
  # for free/null, maybe a macro can be used. Then the check just needs to be that free() is not used directly anymore.
  # TODO: option to ignore certain warnings: both by type and specific:
  # TODO: specific warnings: mark all remaining warnings in a file: both file/linenr and actual text. As long as both location and text stay the same, don't show the warning.
  # TODO: check for no_* variables, should keep it positive.
  # TODO: something with responsibility for free-ing vars: either caller or callee. Something with a unique-marker? (unique => caller resp, shared => callee responsibility)
  foreach stmt $statements {
    set lines [stmt_lines $stmt]
    if {[regexp {^([^=\(\)\{\}]+);} $lines z line]} {
      if {[regexp {break|return|continue|\+\+|struct} $line]} {
        # continue
      } else {
        # [2017-03-31 12:58:22] mark as 'possible' because we can give false positives, eg within structs.
        stmt_warn "Possible var declaration without assignment" $filename $stmt
      }
    }
    if {[regexp {\mfree\M} $lines]} {
      stmt_warn "Use of free, should use rb_free" $filename $stmt
    }
    if {[regexp {\m[mc]alloc\M} $lines]} {
      stmt_warn "Use of calloc/malloc, should use y_array_alloc (y_core.c)" $filename $stmt
    }
  }
}

proc stmt_warn {msg filename stmt} {
  set lines [stmt_lines $stmt]
  puts stderr "$msg: $lines ($filename:[:linenr_start $stmt])"        
} 

proc stmt_lines {stmt} {
  string trim [join [:lines $stmt] "\n"]
}
