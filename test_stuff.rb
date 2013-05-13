require 'rubygems'
require 'bud'

class HelloWorld
  include Bud

  state do
    sqltable :peeps, [string(:name), int(:id), string(:color)]
    sqltable :names, [string(:name)]
  end

  bloom do
    peeps <+ [["george", 5, "green"]]
    names <+ peeps { |p| [p.name] }
    stdio <~ names.materialize { |p| ["Hello #{p}"] }
  end
end

t =  HelloWorld.new(:dump_rewrite => true, :pg_host => "localhost", :pg_dbname => "postgres")

t.tick
t.tick
t.tick

t.peeps <+ [["mary", 9, "mauve"]]
t.tick
t.tick
