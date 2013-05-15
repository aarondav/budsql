require 'rubygems'
require 'bud'
require 'pp'

class ReachabilityAnalysis
  include Bud

  state do
    sqltable :nodes, [string(:name)] => [bool(:reachable)]
    sqltable :edges, [string(:f), string(:t)]
  end

  bloom do
    nodes <+- (nodes*edges).pairs {|n, e| [e.t, true] if n.reachable == true and n.name == e.f}
    stdio <~ nodes.materialize { |n| ["#{n[0]} => #{n[1]}"] }
  end

#  bootstrap do
#    nodes <+ [['a', true], ['b', false], ['c', false], ['d', false], ['e', false]]
#    edges <+ [['a', 'b'], ['a', 'c']]
#    edges <+ [['c', 'd']]
#    edges <+ [['d', 'c']]
#    edges <+ [['e', 'c']]
#  end
end

t =  ReachabilityAnalysis.new(:dump_rewrite => true, :pg_host => "localhost", :pg_dbname => "postgres")
t.tick
t.tick
t.tick
t.tick
t.tick
puts
puts "Final output: "
PP.pp t.nodes.storage
