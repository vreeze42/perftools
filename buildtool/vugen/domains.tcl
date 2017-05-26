task domains {get/update domains
  Create or update domains.ini file with headers for [keep] and [delete], which
  may next be edited manually. In the next execution of this task, the script will be updated by the settings: domains which should be deleted will be commented out.
  Use remove_comments to really delete those statements.
} {
  if {[file exists domains.ini]} {
    set domains_ini [ini/read domains.ini]
  } else {
    set domains_ini [ini/add_no_dups {} keep ""]
    set domains_ini [ini/add_no_dups $domains_ini ignore ""]
  }

  foreach filename [get_action_files] {
    if {$filename == "vuser_init.c"} {
      # TODO: get_action_files should not return vuser_init, only main action files.
      # but then should be called main_action_files
      log info "Ignore $filename, could be template, more difficult"
      continue
    }
    log debug "Handling file: $filename"
    set statements [read_source_statements $filename]
    set stmt_groups [group_statements $statements]
    set domains_ini [update_domains_ini $domains_ini $stmt_groups]; # any new ones?
    domain_write_source_statements $filename $stmt_groups $domains_ini
    commit_file $filename
  }
  ini/write [tempname domains.ini] $domains_ini
  commit_file domains.ini
  
  vuser_init_update_domains $domains_ini
}

proc stmt_det_referer {stmt} {
  error "Deprecated, use stmt->referer"
  foreach line [:lines $stmt] {
    if {[regexp {\"(Referer)=(https?://([^/]+)/[^\"]+)\"} $line z z referer domain]} {
      return $referer
    }
  }
  return ""
}

proc det_domain {url} {
  error "Deprecated, use url->domain or url->parts (in ndv lib)"
}

proc det_domain_old2 {url} {
  if {[regexp {https?://([^/]+)/} $url z domain]} {
    return $domain
  }
  return ""
}

proc det_domain_old {stmt} {
  foreach line [:lines $stmt] {
    if {[regexp {\"(URL|Action)=https?://([^/]+)/} $line z z domain]} {
      return $domain
    }
  }
  return ""
}

# TODO: maybe split this one in 1) comment lines and 2) write to file.
proc domain_write_source_statements {filename stmt_groups domains_ini} {
  #set f [open $filename w]
  #fconfigure $f -translation crlf
  set f [open_temp_w $filename]
  foreach grp $stmt_groups {
    set ignore [ignore_domain? $domains_ini [:domain $grp]]
    # puts $f "// domain: [:domain $grp]"
    foreach stmt [:statements $grp] {
      if {$ignore} {
        foreach line [:lines $stmt] {
          puts $f "//$line"
        }
      } else {
        puts $f [join [:lines $stmt] "\n"]    
      }
    }
  }
  close $f
}

proc is_ignore_domain {ini domain} {
  error "Deprecated, use ignore_domain?"
  if {$domain == ""} {
    return 0
  } else {
    ini/exists $ini ignore [domain_suffix $domain]  
  }
}

proc ignore_domain? {ini domain} {
  if {$domain == ""} {
    return 0
  } else {
    ini/exists $ini ignore [domain_suffix $domain]  
  }
}


# return new domains_ini.
# foreach set domain in stmt_grp: check if suffix already exists in ini.
# if not, add it to the [keep] header.
proc update_domains_ini {ini stmt_groups} {
  foreach grp $stmt_groups {
    set domain [:domain $grp]
    if {$domain == ""} {
      # nothing
    } elseif {[regexp {[\{\}]} $domain]} {
      # nothing, brace in domain, could be {domain}
    } else {
      set suffix [domain_suffix $domain]
      if {[ini/exists $ini keep $suffix] ||
          [ini/exists $ini ignore $suffix]} {
        # nothing
      } else {
        # log debug "Adding suffix to ini/keep: $suffix (domain=$domain)"
        set ini [ini/add $ini keep $suffix]
      }
    }
  }

  # sort lines under headers.
  set ini [ini/set_lines $ini keep [lsort [ini/lines $ini keep]]]
  set ini [ini/set_lines $ini ignore [lsort [ini/lines $ini ignore]]]
  
  return $ini
}

proc domain_suffix {domain} {
  # log debug "determine suffix for domain: $domain"
  set domain3 [join [lrange [split $domain "."] end-2 end] "."]
  # always take last 3 items of domain
  join [lrange [split $domain "."] end-2 end] "."
}


