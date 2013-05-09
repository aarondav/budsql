require 'rubygems'
require 'bud'

class HelloWorld
  include Bud

  state do
    sqltable :foo, [int(:bar)]
    sqltable :baz, [int(:blue)]
    table :taz,  [:yo]
    sqltable :raz,  [:y]
    table :result, [:bar, :blue]
  end

  bloom do
    result <+ baz { |b| b.baz }
    result <+ [["a", "b"]]
    
    stdio <~ [["hello world!"]]
  end
end

HelloWorld.new(:dump_rewrite => true).tick;
