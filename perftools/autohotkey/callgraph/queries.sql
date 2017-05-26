-- queries
-- functions that are not being called.
select *
from function f
where not f.name in (
  select c.callee
  from call c
);

