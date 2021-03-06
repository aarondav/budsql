# BudSQL

BudSQL is an extension of [Bud](http://www.bloom-lang.net/bud/) which enables the use of special tables which are backed in an SQL database instead of memory. Where possible, rules are also compiled into SQL statements, which means that data can be processed entirely in the database, allowing for arbitrary data set sizes and whatever optimizations the database can provide.

## Details

BudSQL introduces a new type of table called `sqltable`, which is backed by a Postgres instance. (While we chose Postgres to have a concrete implementation, the ideas are immediately generalizable to any SQL database.) Since SQL tables require typed columns, so do `sqltables`. Thus, the definition of an `sqltable` looks like this:

    sqltable :nodes, [string(:name)] => [bool(:reachable)]
    
which defines an `sqltable` called "nodes" with two columns, "name" and "rechable". The name field is used as a primary key of the relation. On execution of the Bud program, this table is created if it does not exist, which enables the ease of using intermediary tables while still having tables that start with data in them. Note that if the table already exists, the schema should match the Bud schema identically, or else the behaviour is undefined.

`sqltable` is intended to be operable in much the same way as a normal table, but we decided to restrict the set of allowed operations. In general, an `sqltable` can always be on the left hand side of any rule, but it may not be  directly joined or merged with a bud `table` without being `materialized` (see below).

In particular, only the following are allowed:

- Operators `<-`, `<+`, `<+-` may all be used with an `sqltable` on the left hand side and either an `sqltable` or a bud `table` on the right hand side.
- The join operator `*` may only be used between two `sqltables` or two bud `tables`.
- The `materialize` method essentially materializes an `sqltable` into a bud `table`, allowing it to act as either. However, its contents are now copied to memory every tick!

`sqltable` also does not support the `<=` or `<~` operators. The former is because moving data in and out of SQL is hard to do within an "instant", and the latter is simply an issue of time -- it would be a good addition.

## Examples

Following is a program which utilizes `sqltable` to find all nodes which are reachable from a certain node (assuming that node already is flagged as reachable).

```
class ReachabilityAnalysis
  include Bud

  state do
    sqltable :nodes, [string(:name)] => [bool(:reachable)]
    sqltable :edges, [string(:from), string(:to)]
  end

  bloom do
    nodes <+- (nodes*edges).pairs {|n, e| [e.to, true] if n.reachable == true and n.name == e.from}
  end
end
```

This program is interersting from a few standpoints. First, it is extremely similar to the equivalent Bud program. We have added type information to the tables and moved the join condition to the block (see [Bugs](#bugs)). Second, we can now support graphs of *arbitrary size* since the data stays entirely in SQL. Third, we could utilize a modification of this idea to almost trivially parallelize this program, a feat which would be far more difficult using `tables` alone, as they would have to constantly communicate updates between each other manually (see [Discussion](#discussion)).

A second, less interesting example, demonstrates a few other features of a complete BudSQL program.

```
require 'rubygems'
require 'bud'

class HelloWorld
  include Bud

  state do
    sqltable :peeps, [string(:name), int(:id), string(:color)]
    sqltable :names, [string(:name)]
    sqltable :colors, [string(:name), string(:color)]
  end

  bloom do
    names <+ peeps { |p| [p.name] }
    colors <+ (peeps*names).pairs { |p, n| [p.name, p.color] if p.name == n.name }
    stdio <~ names.materialize { |p| ["Hello #{p}"] }
  end
end

t =  HelloWorld.new(:pg_host => "localhost", :pg_dbname => "postgres",
                    :pg_sql => %Q{TRUNCATE names; TRUNCATE colors;})
t.tick
t.tick
t.peeps <+ [['thomas', 10, 'teal']]
t.tick
t.tick
```

As expected, this program prints out the names of all people in the `peeps` table, including Thomas, and also populates the `colors` table appropriately.

## Implementation

The most interesting feature of our implementation is how we compile `sqltable1 <+ sqltable2` rules (possibly joins) into Postgres. Initially, we used views for this purpose, but it turns out the semantics of views in SQL are not equivalent to the semantics of Bud. In particular, if I remove a tuple from `sqltable2`, then it should remain in `sqltable1`. Furthermore, in Bud, I should be able to update or delete tuples out of `sqltable1`, which is extremely nontrivial if it is a view.

To achieve the semantics of Bud, then, we essentially implemented materialized views in Postgres (they are not yet a builtin feature), with one omission: deletions are not propagated from the right hand side to the left hand side, consistent with Bud's semantics. Further, this means that `sqltable1` is a first-class table, rather than a view, so we may perform operations such as UPDATE over it directly.

The implementation of `sqltable1 <+- sqltable2` follows similarly, except that instead of adding triggers, we simply execute an appropriate UPDATE query every tick. One interesting result is that we perform UPDATE's SET over the `val_cols` (non-key columns) and add the `key_cols` to the WHERE clause. This makes perfect sense, as you must use the the key to specify which tuple you're updating, so you can only update the remaining columns.

In order to achieve both of the above (cross-`sqltable` `<+` and `<+-`), we had to implement an SQLRewriter in `rewrite.rb`. Because we are not executing these rules as ruby, we had to parse them out directly. Parsing arbitrary Bud rules syntax gets pretty complicated, though, and our parser has a few shortcomings (see [Bugs](#bugs)). Any rules that we so parsed were removed from ruby's database of rules (but kept in the `@depends` relation).

The `materialize` method is actually also parsed out of the ruby AST -- when we see that an `sqltable` is materialized, we simply mark it as such, which causes it to select the whole table every tick. Since we apply updates to `@storage`, deltas throughout bud continue to work as expected (i.e., we don't push up all the tuples of the table every tick, only changes).

Finally, when bud `tables` are on the right hand side, we perform the following operations at the end of every tick, in order:

- Instantaneous merges `<=` (we don't officially support this operation though).
- Deletions `<-`
- Insertions `<+`
- SQL Updates `<+-` (we weren't sure where to put this one since it is implemented as `<-` then `<+` in Bud)
- `SELECT * FROM table` if materialized

## Discussion

`sqltable` provides some interesting new semantics for Bud. It enable a Bud program to abstract away memory entirely by relying on disk. It even allows this abstraction to maintain a decent runtime by utilizing optimizations performed by the database, potentially with auxiliary structures such as indexes.

In addition to lifting single-node memory contraints, `sqltable` also provides a unique interface for sharing data between bud processes, with extension. The current implementation only supports (single node) postgres instances, and rules from multiple bud programs would ultimately be run on the same instance, disallowing real parallelism benefits. However, with the addition of a distributed database, one could utilize this interface to share information and work easily between Bud programs. Imagine the reachability analysis program, for instance. This program can be distributed by simply assigning work to certain processes (perhaps by labeling nodes in the graph) -- since they all share the underlying data store, even eventual consistency would result in a correct algorithm. However, I am certain that much of this has already been considered and implemented in the [Zookeper module](https://github.com/bloom-lang/bud/blob/master/lib/bud/storage/zookeeper.rb) which we did not know about until a few days ago.

One final point of discussion is the usage of the `<+` operator instead of the `<~` operator. We have no qualms with the `<~` operator, but `<+` makes for a pleasanter experience, and we felt it was not stretching the limits of possibility to use it in this scenario. Since our current database is single node and intended to be hosted locally, synchronous access is not asking for too much. This does bring up some interesting ideas about time and Bloom programs, though. The programmer may wish to decide what "time" means for them -- that working in lockstep with the SQL database is the most sensible notion of time, or that asynchrony is required as the database is only a secondary element.

## Bugs

Due to time and people constraints, we were unable to get the code up to an excellent state, and there are accordingly a few gotchas or unimplemented features. Here is a list:

- We do not support the `<-` operator where both sides are `sqltables`.
- The `<+-` operator does not perform an UPDATE when the right hand side is a bud `table`. Instead, it deletes and inserts as if it were a normal `table`.
- We do not support the (:x => :y) argument to the pairs/lefts/rights methods. These can be accomplished in a block's if clause.
- In blocks, we only support full tuples like `[a.b, c.d]` -- you can't do weird ruby things like `[a.first] + [c.first]` or less weird ruby things like `a + c`.
- Code in blocks must parse in ruby and be valid SQL. For convenience and interoperability, we convert `==` into SQL `=` and `"` into `'`. 
- When we create tables on the fly, we do not enforce the primary key in the database layer.
- Materialized tables don't properly figure out when tuples were deleted from the SQL table.
