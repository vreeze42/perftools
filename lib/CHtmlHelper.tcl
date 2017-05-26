# CHtmlHelper.tcl - helper methods for generating html.

# @todo also remove methods from perflib.tcl
# [2016-12-04 11:50] TODO: some method return strings, others directly put html
# to the channel. Both should be possible, but use naming convention.

package require Itcl
package require struct ; # matrices.
package require html;    # official package that does similar things. Use for escaping html in to_html.

package provide ndv 0.1.1

if {0} {
  # Examples:

  set hh [ndv::CHtmlHelper::new]
  $hh set_channel $f
  $hh write_header "Header" 0

}

if 0 {
  [2016-11-26 12:27] TODO:
  Meer zoals hiccup:

  $hh table {
    Foreach xx
    $hh table_row {
      $hh table_data ..
    }
  }

  En per kolom extra attributen instellen, bv align=right.

  En ofwel juxt functie gebruiken voor velden van tabel, of dict values gebruiken, maar dan wel goede volgorde. Dict_get_multi heb ik al.

  En dan ook start met een test suite. Gewoon file aanmaken en kijken of deze nog steeds gelijk is aan eerder gemaakte file.
}

namespace eval ::ndv {
	# class maar eenmalig definieren
	if {[llength [itcl::find classes CHtmlHelper]] > 0} {
			return
	}
	
	namespace export CHtmlHelper
	
  variable lib_path [file normalize [file dirname [info script]]]
  
	itcl::class CHtmlHelper {
		# @todo lukt nog niet CLogger hierbinnen te gebruiken terwijl ze in dezelfde namespace en package zitten.
		private common log
		# set log [::ndv::CLogger::new_logger [file tail [info script]] info]
		set log [::ndv::CLogger::new_logger [file tail [info script]] debug]
	
    public proc new {} {
      # $log debug "line 2" 
      # $log debug "lib_path: $::ndv::lib_path" 
      set result [uplevel {namespace which [::ndv::CHtmlHelper \#auto]}]
      return $result	
    }

    private variable channel
    private variable auto_flush
    
    public constructor {} {
        set auto_flush 0
    }

    # idee: algemene get/set methods:
    # of zijn deze sort-of std al aanwezig in OO-systeem?
    # [2013-11-07 20:42:05] overloading set is dangerous: don't go there.
    public method set2 {var value} {
      set $var $value
    }
    
    public method get {var} {
      return $var
    }
    
    public method set_channel {a_channel} {
        set channel $a_channel
    }

    public method get_channel {} {
        return $channel
    }

    public method set_auto_flush {val} {
        set auto_flush $val
    }

    public method get_auto_flush {} {
        return $auto_flush
    }
    
    public method write_header {title {heading1 1}} {
        puts $channel "<html>
  <head><meta charset=\"UTF-8\"><title>$title</title>
  <style type=\"text/css\">
          body {
            font:normal 68% verdana,arial,helvetica;
            color:#000000;
          }
          table tr td, table tr th {
            font-size: 68%;
          }
          table.details tr th{
            font-weight: bold;
            text-align:left;
            background:#a6caf0;
          }
          table.details tr td{
            background:#eeeee0;
            white-space: nowrap;
          }
          h1 {
            margin: 0px 0px 5px; font: 165% verdana,arial,helvetica
          }
          h2 {
            margin-top: 1em; margin-bottom: 0.5em; font: bold 125% verdana,arial,helvetica
          }
          h3 {
            margin-bottom: 0.5em; font: bold 115% verdana,arial,helvetica
          }
          .Failure {
            font-weight:bold; color:red;
          }
          .Warning {
            color:orange;
          }
        .collapsable1 {
            margin: 1em;
            padding: 1em;
            border: 1px solid black;
        }
        .collapsable {
            margin: 0em;
            padding: 0em;
            border: 0px solid white;
        } 					
        </style>
  <script type='text/javascript' src='collapse.js'></script>
  </head>
  <body>"
        if {$heading1} {
          puts $channel "<h1>$title</h1>"
        }
        flush_channel
    }

	public method write {str} {
	  puts $channel $str
	  flush_channel
	}
	
    public method write_footer {} {
        puts $channel "</body></html>"
        flush_channel
    }

    # body is the last item of args
    public method table {args} {
      table_start {*}[lrange $args 0 end-1]
      set body [lindex $args end]
      uplevel $body
      table_end
    }
    
    public method table_start {args} {
      # first set default values
      set lst_def [list cellspacing 2 cellpadding 5 border 0 class details]
      array set ar $lst_def
      # then overwrite with user values
      array set ar $args
      set lst_ta {}
      foreach {nm val} [array get ar] {
        lappend lst_ta "$nm=\"$val\"" 
      }
      # puts $channel "<table cellspacing=\"2\" cellpadding=\"5\" border=\"0\" class=\"details\">"
      puts $channel "<table [join $lst_ta " "]>"
      flush_channel
    }

    public method table_end {} {
        puts $channel "</table>"
        flush_channel
    }

    # args: special tcl case: a list of all extra params, in this case a list of column-header-values
    public method table_header {args} {
        puts $channel "<tr>"
        flush_channel
        foreach col_value $args {
            # puts $channel "<th>$col_value</th>"
            table_data $col_value 1
        }
        puts $channel "</tr>"
        flush_channel
    }

    public method table_row {args} {
        # puts $channel "<tr>"
        table_row_start
        foreach cell_value $args {
            # puts $channel "<td>$cell_value</td>"
            table_data $cell_value
        }
        # puts $channel "</tr>"
        table_row_end
    }

    # TODO: merge with table_row method, or method to set/reset class.
    public method table_row_class {clazz args} {
      table_row_start $clazz
      foreach cell_value $args {
        table_data $cell_value
      }
      table_row_end
    }
    
    public method table_row_start {{clazz ""}} {
      if {$clazz == ""} {
        puts $channel "<tr>"
      } else {
        puts $channel "<tr class=\"$clazz\">"
      }
      flush_channel
    }
    
    public method table_row_end {} {
        puts $channel "</tr>"
        flush_channel
    }

    public method table_data {cell_value {header 0} {extra_attributes ""}} {
        if {$header} {
            puts $channel "<th $extra_attributes>$cell_value</th>"
        } else {
            puts $channel "<td $extra_attributes>$cell_value</td>"
        }
        flush_channel
    }

    public method table_matrix {matrix {firstheader 0}} {
        table_start
        for {set r 0} {$r < [$matrix rows]} {incr r} {
            table_row_start
            for {set k 0} {$k < [$matrix columns]} {incr k} {
                if {($r == 0) && $firstheader} {
                    table_data [$matrix get cell $k $r] $firstheader
                } else {
                    table_data [$matrix get cell $k $r]
                }
            }
            table_row_end
        }
        
        table_end
    }

    public method hr {} {
        puts $channel "<hr align=\"left\" width=\"100%\" size=\"1\">"
        flush_channel
    }

    public method get_heading {level text {extra_attributes ""}} {
      return "<h$level $extra_attributes>$text</h$level>"
    }

    public method heading {level text {extra_attributes ""}} {
        # puts $channel "<h$level>$text</h$level>"
        puts $channel [get_heading $level $text $extra_attributes]
        flush_channel
    }

    public method line {text} {
        # puts $channel "$text<br>"
        text "$text<br/>"
        flush_channel
    }
    
    public method text {text} {
        puts $channel "$text"
        flush_channel
    }
    
    public method br {} {
      puts $channel "<br/>"
      flush_channel
    }
    
    public method anchor_name {name} {
        puts $channel "<a name=\"$name\"/>"
        flush_channel
    }

    public method get_anchor {text ref} {
        return "<a href=\"$ref\">$text</a>"
    }

    public method href {text ref} {
      puts $channel [get_anchor $text $ref]
      flush_channel
    }
    
    public method get_img {img_ref {extra ""}} {
        return "<img src=\"$img_ref\" $extra/>"
    }

    # geen flush noemen, dan name-clash met standaard proc
    public method flush_channel {} {
        if {$auto_flush} {
            flush $channel
        }
    }

    # TODO: ook specifieke tekens als < en &, hier ook al eens eerder code voor gemaakt, en misschien ook wel std lib voor beschikbaar...
    public method to_html_old {text} {
      regsub -all "\n" $text "<br/>" text
      return $text			
    }

    public method to_html {text} {
      # regsub -all "\n" $text "<br/>" text
      html::nl2br [html::html_entities $text]
      # return $text			
    }

    public method pre {text} {
      return "<pre>$text</pre>"
    }

    # unordered list functions
    # for now, only get variant, don't write anything to channel.
    public method get_ul {lst} {
      set res "<ul>"
      foreach el $lst {
        append res [get_li $el]
      }
      append res "</ul>"
      return $res
    }

    # if item is already contained within <li> tags, don't add again.
    public method get_li {item {attrs ""}} {
      if {[regexp {^<li} $item]} {
        return $item
      } else {
        return "<li $attrs>$item</li>"
      }
    }
    
    
    # [2016-09-25 20:38] lijkt ervoor om .js voor collapse e.d. te kopieren.
    public method copy_files_to_output {output_path} {
      foreach filename [glob -directory [file join $::ndv::lib_path js] *] {
        file copy -force $filename $output_path 
      }
    }
  }

}
