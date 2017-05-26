# DB schema definition for the Perfmeetmodel database.
# @todo separate general functionality with specific music functionality
package require Itcl
package require ndv

package provide ndv 0.1.1

namespace eval ::ndv {

  # class maar eenmalig definieren
  if {[llength [itcl::find classes AbstractSchemaDef]] > 0} {
    return
  }
  
  namespace export AbstractSchemaDef
  
  # source [file join $env(CRUISE_DIR) checkout lib perflib.tcl]
  # source [file join [file dirname [info script]] CClassDef.tcl]
  
  
  # @todo (?) ook nog steeds pk en fk defs, voor queries?
  # source [file join $env(CRUISE_DIR) checkout script lib CLogger.tcl]
  
  itcl::class AbstractSchemaDef {
    
    private common log
    set log [::ndv::CLogger::new_logger [file tail [info script]] info]
    # set log [::ndv::CLogger::new_logger [file tail [info script]] debug]
  
    protected variable no_db
    
    protected variable conn
    protected variable classdefs
  
    # todo pk- en fk-defs afleiden uit classdefs, later misschien helemaal weg.
    protected variable pk_field
    protected variable fk_field
  
    protected variable db_name
    protected variable dbtype
    
    protected variable username
    protected variable password
    
    public constructor {} {
      set conn ""
      set no_db 0 ; # default is een db beschikbaar.
      set db_name ""
    }
  
    public method get_db_name {} {
      return $db_name
    }

    public method get_dbtype {} {
      return $dbtype
    }

    public method set_dbtype {a_dbtype} {
      set dbtype $a_dbtype
    }
    
    public method get_username {} {
      return $username 
    }
    
    public method get_password {} {
      return $password 
    }
    
    public method set_db_name_user_password {a_db_name a_username a_password} {
      set db_name $a_db_name
      set username $a_username
      set password $a_password
    }
    
    public method set_no_db {val} {
      $log debug "set_no_db called with val: $val"
      set no_db $val
      set_classes_no_db $val
    }
    
    public method get_no_db {} {
      return $no_db
    }
    
    private method set_classes_no_db {val} {
      $log debug "set_classes_no_db called"
      foreach classdef [array names classdefs] {
        $classdefs($classdef) set_no_db $val
      }
    }
    
    public method set_conn {a_conn} {
      set conn $a_conn
      $log debug "set_conn: call define_classes"
      # return [itcl::code $this abc]
      # $this define_classes
      $log debug "set_conn: this: $this"
      # itcl::code $this define_classes
      define_classes
      $log debug "called define classes with this: $this"
      set_classes_no_db 0
    }
  
    public method get_conn {} {
      return $conn
    }
  
    public method get_pk_field {table_name} {
      return $pk_field($table_name)
    }
    
    public method get_fk_field {fromtable totable} {
      return $fk_field($fromtable,$totable)
    }
      
    protected method define_classes {} {
      $log debug "Abstract define_classes"
    }
      
    public method get_classdef {class_name} {
      return $classdefs($class_name)
    }
    
    # @param class_name: testbuild
    # @param args: -cctimestamp $cctimestamp -label $label -artifacts_dir $artifacts_dir
    public method insert_object {class_name args} {
      $log debug "args: $args \[[llength $args]\]"
      set classdef $classdefs($class_name)
      return [$classdef insert_object $args]
    }
  
    # @param class_name: testbuild
    # @param args: -cctimestamp $cctimestamp -label $label -artifacts_dir $artifacts_dir
    public method update_object {class_name id args} {
      $log debug "args: $args \[[llength $args]\]"
      set classdef $classdefs($class_name)
      return [$classdef update_object $id $args]
    }

    # @return: list of object ids: 0, 1 or more.
    public method find_objects {class_name args} {
      $log debug "args: $args \[[llength $args]\]"
      # breakpoint
      $log debug "classdefs: [array names classdefs] ***"
      $log debug "this: $this"
      set classdef $classdefs($class_name)
      return [$classdef find_objects $args]
    }
  
    # @param class_name: testbuild
    public method delete_object {class_name id} {
      # $log debug "args: $args \[[llength $args]\]"
      set classdef $classdefs($class_name)
      return [$classdef delete_object $id]
    }
  
  }
}
