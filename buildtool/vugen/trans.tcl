task rb_trans {set rb_transaction usage
  Replace lr_start_transaction/end_transaction with rb_start_transaction.
  Also use trans_name.
} {
  # deze ook in task_templates, daar waarsch weg.
  # [2017-04-10 16:41:26] geen TT gebruiken, niet altijd beschikbaar.
  task_regsub -do -action {lr_start_transaction\(([^())]+)\);} \
    {rb_start_transaction(\1);} 1
  task_regsub -do -action {lr_end_transaction\(([^()]+), ?LR_AUTO\);} \
    {rb_end_transaction(\1, 0 /* TT */);} 1
  task_regsub -do -action {lr_think_time\(([^()]+)\);} {// lr_think_time(\1);} 1

  # deze nieuw, wel zorgen dat trans_name goed werkt. Dus ook trans_name_init en trans_name functie goed zetten in
  # script specifieke functies.c file, bv mcp_funcions.c
  task_regsub -do -action {rb_start_transaction\(\"([^\"]+)\"\);} {char * transactie = NULL;\n    transactie = trans_name("\1");\n    rb_start_transaction(transactie);}
  task_regsub -do -action {rb_end_transaction\(\"[^\"]+\", 0 /* TT */\);} {rb_end_transaction(transactie, 0 /* TT */);}
}
