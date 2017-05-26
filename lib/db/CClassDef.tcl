# Class definition for persisting objects of a given class.

package require Itcl
# package require ndv

package provide ndv 0.1.1

namespace eval ::ndv {

  # class maar eenmalig definieren
  if {[llength [itcl::find classes CClassDef]] > 0} {
    return
  }
	namespace export CClassDef
  namespace export CFieldDef
  
  # @todo (?) ook nog steeds pk en fk defs, voor queries?
  itcl::class CClassDef {
  
    private common log
    set log [::ndv::CLogger::new_logger [file tail [info script]] info]
    # set log [::ndv::CLogger::new_logger [file tail [info script]] debug]
    
    public proc new_classdef {schemadef class_name id_field} {
      set classdef [uplevel {namespace which [::ndv::CClassDef #auto]}]
      $classdef init $schemadef $class_name $id_field
      return $classdef
    }
  
    private variable schemadef
    private variable dbtype
    private variable conn
    private variable no_db ; # boolean (0/1), true if no database available.
    
    private variable class_name
    private variable table_name
    private variable id_field
    private variable superclass_def ""
    private variable superclass_field_name ""
    private variable field_defs ; # assoc. array of CFieldDef
  
    public method init {a_schemadef a_class_name an_id_field} {
      set schemadef $a_schemadef
      set conn [$schemadef get_conn]
      set class_name $a_class_name
      set table_name $class_name
      set id_field $an_id_field
      set no_db 0
      set dbtype [$schemadef get_dbtype]
    }
  
    public method set_no_db {val} {
      $log debug "Set no_db to $val"
      set no_db $val
    }
    
    public method get_no_db {} {
      return $no_db
    }
      
    
    # @param a_superclass_name: notesobject
    # @param a_field_name: notesobject_id ; # fieldname in subclass table
    # @todo superclass_field_name niet nodig, want is gelijk aan id_field
    public method set_superclass {a_superclass_name a_superclass_field_name} {
      # set superclass_name $a_superclass_name
      set superclass_def [$schemadef get_classdef $a_superclass_name]
      set superclass_field_name $a_superclass_field_name
      add_field_def $superclass_field_name integer null
    }
  
    public method add_field_def {a_field_name {a_datatype string} {a_default ""}} {
      set field_defs($a_field_name) [::ndv::CFieldDef #auto $a_field_name $a_datatype $a_default]
    }
  
    # 6-7-2010 helper functie voor minder typewerk
    public method add_field_defs {args} {
      foreach el $args {
        add_field_def {*}$el 
      }
    }
    
    public method get_table_name {} {
      return $table_name
    }
  
    public method get_field_def {field_name} {
      return $field_defs($field_name)
    }
  
    public method get_id_field {} {
      return $id_field
    }
  
    # @param args: -cctimestamp $cctimestamp -label $label -artifacts_dir $artifacts_dir
    public method insert_object {args} {
      # @note: possible that all args are now in the list, but llength == 1
      if {[llength $args] == 1} {
        set args [lindex $args 0]
      }
  
      set args_prev {}
      while {([llength $args] == 1) && ($args != $args_prev)} {
        set args_prev $args
        set args [lindex $args 0]
      }
  
      $log debug "args: $args \[[llength $args]\]" 
    
      init_values values
      if {$superclass_def != ""} {
        set id [$superclass_def insert_object $args]
        set values($superclass_field_name) $id
      } else {
        set id ""
      }
      # array set fields $args
      set_values_from_args values $args
  
      set query "insert into $table_name ([det_field_names]) values ([det_values values])"
      $log debug "inserting record into $table_name: $query"
      if {$no_db} {
        set res 1
        set id 1
      } else {
        if {$dbtype == "mysql"} {
          set res [::mysql::exec $conn $query]
        }
        if {$dbtype == "postgres"} {
          set res [pg_query $conn $query]
          # res zou 1 moeten, 1 row ge-insert?
        }
      }
      if {$res != 1} {
        error "insert of $class_name did not return 1" 
      }
      
      if {$id == ""} {
        if {$dbtype == "mysql"} {
          set id [::mysql::insertid $conn]   
        }
        if {$dbtype == "postgres"} {
          set id [pg_last_id $conn $table_name]
        }
      } else {
        # id al bij superclass gezet.
      }
      
      $log debug "Inserted $class_name with id: $id"
      
      return $id
    }
  
    # @param args: -cctimestamp $cctimestamp -label $label -artifacts_dir $artifacts_dir
    public method update_object {id args} {
      if {$no_db} {
        $log debug "No database connection, returning"
        return
      }
      
      # @note: possible that all args are now in the list, but llength == 1
      if {[llength $args] == 1} {
        set args [lindex $args 0]
      }
      
      set args_prev {}
      while {([llength $args] == 1) && ($args != $args_prev)} {
        set args_prev $args
        set args [lindex $args 0]
      }
      
      $log debug "args: $args \[[llength $args]\]"
    
      # init_values values ; # not here, don't want the defaults to overwrite the previously set values.
      if {$superclass_def != ""} {
        $superclass_def update_object $id $args
      } else {
        # nothing
      }
      # array set fields $args
      set_values_from_args values $args
  
      set set_clause [det_set_clause values]
      if {$set_clause == ""} {
        # nothing, no fields to be updated in this (super)class
        $log debug "set clause empty, no need to update $class_name"
      } else {
        # set query "update $table_name $set_clause where $id_field = $id"
        set query "update $table_name $set_clause where $id_field = [$field_defs($id_field) det_value $id]"
        $log debug "updating record in $table_name with id $id: $query"
        if {$dbtype == "mysql"} {
          set res [::mysql::exec $conn $query]          
        }
        if {$dbtype == "postgres"} {
          set res [pg_query $conn $query]
        }
        if {$res == 1} {
          # ok
        } elseif {$res == 0} {
          # also ok, it's possible that no field is updated, so 0 is returned.
        } else {
          error "update of $class_name $id did not return 0 or 1, but $res; query: $query" 
        }
        $log debug "Updated $class_name with id: $id"
      }		
    }
  
    private method det_set_clause {values_name} {
      upvar $values_name values
      set result {}
      foreach field_name [array names values] {
        if {[array names field_defs -exact $field_name] != ""} {
          lappend result "$field_name = [$field_defs($field_name) det_value $values($field_name)]"
        } else {
          $log debug "$field_name not found in $class_name"
        }
      }
      if {[llength $result] == 0} {
        return ""
      } else {
        return "set [join $result ", "] "
      }
    }
  
    # @return: list of object ids: 0, 1 or more.
    public method find_objects {args} {
      if {$no_db} {
        $log debug "No database connection, returning empty list"
        return {}
      }
      # @note: possible that all args are now in the list, but llength == 1
      set args_prev {}
      while {([llength $args] == 1) && ($args != $args_prev)} {
        set args_prev $args
        set args [lindex $args 0]
      }
      $log debug "args: $args \[[llength $args]\]" 
      set query "select t.$id_field from [det_table_refs] where [det_where_clause $args]"
      $log debug "query: $query"
      # @todo query uitvoeren
      # set result {}
      if {$dbtype == "mysql"} {
        set result [::mysql::sel $conn $query -flatlist]  
      }
      if {$dbtype == "postgres"} {
        set result [pg_query_flatlist $conn $query]
      }
      if {$dbtype == "postgres2"} {
        set res [pg_query $conn $query]
        set result {}
        $res foreach row {
          lappend result [dict get $row $id_field]
        }
      }
      return $result
    }
  
    # @return <tablename> t if no superclass and '<tablename> t, <super-tablename> s' if the class has a superclass.
    private method det_table_refs {} {
      if {$superclass_def == ""} {
        return "$table_name t"
      } else {
        return "$table_name t, [$superclass_def get_table_name] s"
      }
    }
  
    private method init_values {values_name} {
      upvar $values_name values
      foreach field_name [array names field_defs] {
        set values($field_name) [$field_defs($field_name) get_default]
      }
    }
  
    private method set_values_from_args {values_name lparams} {
      upvar $values_name values
      $log debug "lparams: $lparams \[[llength $lparams]\]"
  
      array set params $lparams
      foreach param_name [array names params] {
        if {[regexp {^-(.+)$} $param_name z par_name]} {
          set values($par_name) $params($param_name)
        } else {
          error "syntax error in param_name (should start with -): $param_name"
        }
      }		
    }

    # 2015-05-25 NdV only used for insert, remove id field
    private method det_field_names {} {
      set result [lsort [array names field_defs]]
      set result2 {}
      foreach res $result {
        if {$res != "id"} {
          lappend result2 $res
        }
      }
      return [join $result2 ", "]
    }

    # 2015-05-25 NdV only used for insert, remove id field
    # apparently not a problem for MySQL, but for Postgres it is.
    private method det_values {values_name} {
      upvar $values_name values
      set result {}
      foreach field_name [lsort [array names field_defs]] {
        if {$field_name != "id"} {
          lappend result [$field_defs($field_name) det_value $values($field_name)]  
        }
      }
      return [join $result ", "]
    }
  
    private method det_where_clause {lparams} {
      array set params $lparams
      set result {}
      foreach param_name [array names params] {
        if {[regexp {^-(.+)$} $param_name z par_name]} {
          # set values($par_name) $params($param_name)
          # lappend result "t.$par_name = [$field_defs($par_name) det_value $params($param_name)]"
          if {[array names field_defs -exact $par_name] != ""} {
            lappend result "t.$par_name = [$field_defs($par_name) det_value $params($param_name)]"
          } else {
            $log debug "$par_name not found in $table_name, asking superclass"
            if {$superclass_def != ""} {
              lappend result "s.$par_name = [[$superclass_def get_field_def $par_name] det_value $params($param_name)]"
            } else {
              error "$par_name not found in $table_name, and don't have superclass to ask"
            }
          }
        } else {
          error "syntax error in param_name (should start with -): $param_name"
        }
      }
      if {$superclass_def != ""} {
        lappend result "t.$id_field = s.[$superclass_def get_id_field]"
      }
      return [join $result " and "]
    }
  
    # @param args: -cctimestamp $cctimestamp -label $label -artifacts_dir $artifacts_dir
    public method delete_object {id} {
      if {$no_db} {
        $log debug "No database connection, returning"
        return
      }
      
      # init_values values ; # not here, don't want the defaults to overwrite the previously set values.
      # possible that superclass can only be deleted after this class instance.
      if {$superclass_def != ""} {
        $superclass_def delete_object $id
      } else {
        # nothing
      }
  
      set query "delete from $table_name where $id_field = $id"
      $log debug "deleting record in $table_name with id $id: $query"
      if {$dbtype == "mysql"} {
        set res [::mysql::exec $conn $query]  
      }
      if {$dbtype == "postgres"} {
        set res [pg_query $conn $query]
      }
      if {$res == 1} {
        # ok
      } elseif {$res == 0} {
        # also ok, it's possible that the record did not exists, so 0 is returned.
      } else {
        error "delete of $class_name $id did not return 0 or 1, but $res; query: $query" 
      }
      $log debug "Deleted $class_name with id: $id"
    }  
    
  }
  
  itcl::class CFieldDef {
  
    private common log
    set log [::ndv::CLogger::new_logger [file tail [info script]] info]
  
    private variable field_name
    private variable data_type
    private variable default	
  
    public constructor {a_field_name a_data_type a_default} {
      set field_name $a_field_name
      set data_type $a_data_type
      set default $a_default
    }
  
    public method get_default {} {
      if {$default == "CURTIME"} {
        return [clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S"]
      } else {
        return $default
      }
    }
    
    # quote the value if necessary
    public method det_value {value} {
      if {($data_type == "integer") || ($data_type == "float")} {
        if {$value == "null"} {
          return $value
        } elseif {$value == ""} {
          return "null"
        } else {
          return $value
        }
      } elseif {$data_type == "string"} {
        if {$value == "null"} {
          return $value
        } else {
          return "'[str_to_db $value]'"
        }
      } else {
        if {$value == "null"} {
          return $value
        } else {
          return "'$value'"
        }
      }
    }
    
    private method str_to_db {str} {
      regsub -all {'} $str "''" str
      regsub -all {\\} $str {\\\\} str
      return $str
    }
    
  }
}
