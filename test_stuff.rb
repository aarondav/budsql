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

t =  HelloWorld.new(:dump_rewrite => true, :pg_host => "localhost", :pg_dbname => "postgres",
                    :pg_sql => %Q{TRUNCATE names; TRUNCATE colors;})
t.tick
t.tick
t.peeps <+ [['yolanda', 11, 'yellow']]
t.tick
t.tick
