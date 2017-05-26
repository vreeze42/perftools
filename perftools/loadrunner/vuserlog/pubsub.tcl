oo::class create PubSub {

  # dict: key=topic, value is list of objects with {sub <topic> <value>} method
  variable listeners

  constructor {} {
    set listeners [dict create]
  }

  destructor {
    unset listeners
  }

  method add_listener {topic listener} {
    dict lappend listeners $topic $listener
  }

  method del_listener {topic listener} {
    # TODO:
  }

  method pub {topic value} {
    foreach lst [dict_get $listeners $topic] {
      $lst sub $topic $value
    }
  }
}
