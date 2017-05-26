# HTML output of references.

proc html_output {db opt} {
  set targetdir [file join [:rootdir $opt] [:targetdir $opt]]
  html_index $db $targetdir
}

proc html_index {db targetdir} {
  delete_htmls $targetdir
  set f [open [file join $targetdir index.html] w]
  set hh [ndv::CHtmlHelper::new]
  $hh set_channel $f
  $hh write_header "Source files"
  $hh table_start
  $hh table_header Filename Mtime Size Language
  set query "select * from sourcefile order by name"
  foreach row [$db query $query] {
    $hh table_row [source_ref $hh [:id $row] [:name $row]] [:mtime $row] \
        [:size $row] [:language $row]
    html_sourcefile $db $targetdir $row
  }
  $hh table_end
  $hh write_footer
  close $f
}

proc delete_htmls {targetdir} {
  foreach filename [glob -nocomplain -directory $targetdir *.html] {
    file delete $filename
  }
}

proc html_sourcefile {db targetdir row} {
  set htmlname [file join $targetdir "[:name $row]-[:id $row].html"]
  set f [open $htmlname w]
  set hh [ndv::CHtmlHelper::new]
  $hh set_channel $f
  $hh write_header [:name $row]
  foreach reftype {include call} {
    foreach direction {from to} {
      html_source_table $db $hh $row $reftype $direction
    }
  }
  $hh text "<br/>"
  $hh href "Back to index.html" "index.html"
  $hh write_footer
  close $f
}

# TODO: eerst alles tonen, later evt dingen uitfilteren als ze leeg blijken te zijn.
proc html_source_table {db hh row reftype direction} {
  if {$direction == "from"} {
    set where_field "from_file_id"
  } else {
    set where_field "to_file_id"
  }
  $hh heading 2 "$reftype/$direction"
  $hh table_start
  $hh table_header FromFile FromProc Line# ToFile ToProc Source
  set query "select distinct s1.name s1_name, s1.id s1_id, s2.name s2_name, s2.id s2_id,
                    p1.name p1_name, p2.name p2_name, st.linenr_start linenr,
                    st.text text
             from ref r
             join sourcefile s1 on s1.id = r.from_file_id
             join sourcefile s2 on s2.id = r.to_file_id
             left join proc p1 on p1.id = r.from_proc_id
             left join proc p2 on p2.id = r.to_proc_id
             left join statement st on st.id = r.from_statement_id
             where $where_field = [:id $row]
             and r.reftype = '$reftype'
             order by s1.name, st.linenr_start"
  foreach rrow [$db query $query] {
    $hh table_row [source_ref $hh [:s1_id $rrow] [:s1_name $rrow]] \
        [:p1_name $rrow] [:linenr $rrow] \
        [source_ref $hh [:s2_id $rrow] [:s2_name $rrow]] \
        [:p2_name $rrow] [:text $rrow]
  }
  $hh table_end
}

proc source_ref {hh id name} {
  $hh get_anchor $name "$name-$id.html"
}

