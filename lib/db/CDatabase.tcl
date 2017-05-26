# Main class for database connections to mysql and other databases.

package require Itcl

# package require ndv
package require Tclx

# changes
# 24-05-2015 NdV Add support for Postgres

ndv::source_once postgres.tcl

package provide ndv 0.1.1

namespace eval ::ndv {

  # class maar eenmalig definieren
  if {[llength [itcl::find classes CDatabase]] > 0} {
    return
  }

	namespace export CDatabase
  
  # controlled loading of package.
  catch {package require mysqltcl}
  catch {package require tdbc}
  catch {package require tdbc::postgres}
  
  itcl::class CDatabase {
    private common log
    set log [::ndv::CLogger::new_logger [file tail [info script]] info]
  
    # common, static things for singleton
    private common instance  ""
  
    # if param new != 0, return a new instance.
    public proc get_database {a_schemadef {new 0}} {
      $log debug "get_database: start"
      # breakpoint
      if {($instance == "") || $new} {
        $log debug "creating new instance"
        # 2015-05-27 met uplevel in Tcl8.6.1 een core dump: Tcl_AppendStringsToObj called with shared object
        # dus even zonder uplevel, kijken wat 'ie doet.
        set instance [namespace which [::ndv::CDatabase #auto]]
        $log debug "created instance $instance, now set schemadef"
        $instance set_schemadef $a_schemadef
        
        $log debug "Returning new database instance"
      } else {
        $log debug "Returning existing database instance"
      }
      $log debug "Returning database instance with schemadef: [$instance get_schemadef]"
      return $instance
    }
  
    # instance stuff
    private variable conn
    private variable connected
    private variable schemadef

    # 24-5-2015 NdV hold type of database
    private variable dbtype
    
    private constructor {} {
      set conn ""
      set connected 0
      set dbtype mysql ; # still default
    }
  
    public method set_schemadef {a_schemadef} {
      # global MYSQLTCL_LIB
      # variable MYSQLTCL_LIB
      $log debug "a_schemadef: $a_schemadef"
      set schemadef $a_schemadef
      set_dbtype [$a_schemadef get_dbtype]
      connect
      $schemadef set_conn $conn
    }

    private method connect {} {
      connect_$dbtype
    }

    private method connect_postgres {} {
      puts "connecting to postgres..."
      set conn [tdbc::postgres::connection new -user [$schemadef get_username] -password [$schemadef get_password] -database [$schemadef get_db_name]]
      set connected 1
    }

    private method connect_mysql {} {
      $log debug "connecting to mysql"
      try_eval {
        set conn [::mysql::connect -host localhost -user [$schemadef get_username] \
                      -password [$schemadef get_password] -db [$schemadef get_db_name]]
        set connected 1
        $log info "Connected to database"
      } {
        $log warn "Failed to connect to database: $errorResult"
        $log warn "schemadef: $schemadef"
        $schemadef set_no_db 1
      }
    }
    
    public method set_dbtype {a_dbtype} {
      set dbtype $a_dbtype      
    }
    
    # check DB connection and reconnect if needed
    # @TODO make working for postgres, if needed.
    public method reconnect {} {
      $log debug "reconnect"
      set still_connected 0
      try_eval {
        ::mysql::sel $conn "select 1" -flatlist
        set still_connected 1
      } {
        $log debug "Failed to query: $errorResult"
        set still_connected 0
      }
      if {!$still_connected} {
        $log debug "Connection gone, reconnect..."
        catch {::mysql::close $conn}
        connect
      }
    }
    
    private destructor {
      if {$connected} {
        if {$dbtype == "mysql"} {
          ::mysql::close $conn
        }
        if {$dbtype == "postgres"} {
          $conn close
        }
      }
      set conn "" 
      set connected 0
      $log info "Disconnected from database"
      set instance ""
    }
  
    public method get_connection {} {
      if {$connected} {
        return $conn
      } else {
        $log warn "Not connected to database"
        return $conn
      }
    }
  
    public method get_schemadef {} {
      return $schemadef
    }

    # 20-6-2015 did not have in_trans method yet, only had it in the new db
    # abstraction in libdb.tcl
    public method in_trans {block} {
      exec_query "begin transaction"
      try_eval {
        uplevel $block
      } {
        log_error "Rolling back transaction and raising error"
        exec_query "rollback"
        error "Rolled back transaction"
      }
      exec_query "commit"
    }

    # @todo getDBhandle does (probably) not work with MySQL.
    public method exec_query {query {return_id 0}} {
      set stmt [$conn prepare $query]
      # [2016-07-10 08:28] execute always returns resultset, should be closed.
      set res [$stmt execute]
      $res close
      $stmt close
      if {$return_id} {
        return [[$conn getDBhandle] last_insert_rowid]   
      }
    } 
    
    # @param class_name: testbuild
    # @param args: -cctimestamp $cctimestamp -label $label -artifacts_dir $artifacts_dir
    public method insert_object {class_name args} {
      $log debug "args: $args \[[llength $args]\]"
      return [$schemadef insert_object $class_name $args]
    }
  
    # @param class_name: testbuild
    # @param args: -cctimestamp $cctimestamp -label $label -artifacts_dir $artifacts_dir
    public method update_object {class_name id args} {
      $log debug "args: $args \[[llength $args]\]"
      return [$schemadef update_object $class_name $id $args]
    }
  
    public method find_objects {class_name args} {
      $log debug "args: $args \[[llength $args]\]"
      return [$schemadef find_objects $class_name $args]
    }
  
    # @todo add select_objects, which selects objects based on id, name the fields to select.
    # possibly combine with find_objects.
    
    public method delete_object {class_name id} {
      # $log debug "args: $args \[[llength $args]\]"
      return [$schemadef delete_object $class_name $id]
    }
  
    # @result: gelijk aan input, met /-: en spatie verwijderd
    public method dt_to_decimal {dt} {
      # 27-12-2009 NdV moet -- gebruiken, anders wordt "-" als optie gezien.   
      regsub -all -- {[-/: ]} $dt "" dt
      return $dt
    }
    
    # replace ' and \ with doubled characters
    # 17-1-2010 NdV only call this method from the framework, not externally.
    # 2-2-2010 NdV still sometimes needed, for music-monitor for instance.
    public method str_to_db {str} {
      regsub -all {'} $str "''" str
      regsub -all {\\} $str {\\\\} str
      return $str
    }
    
  }
  
}  

