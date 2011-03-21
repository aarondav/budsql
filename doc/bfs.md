# BFS: A distributed filesystem in Bloom

In this document we'll use what we've learned to build a piece of systems software using Bloom.  
The libraries that ship with BUD provide many of the building blocks we'll need to create a distributed,
``chunked'' filesystem in the style of the Google Filesystem(GFS):
a [key-value store](https://github.com/bloom-lang/bud-sandbox/blob/master/kvs/kvs.rb), [nonce generation](https://github.com/bloom-lang/bud-sandbox/blob/master/ordering/nonce.rb), and a [heartbeat protocol](https://github.com/bloom-lang/bud-sandbox/blob/master/heartbeat/heartbeat.rb).

## High-level architecture



## Basic Filesystem

Before we worry about any of the details of distribution, we need to implement the basic filesystem metadata operations: _create_, _remove_, _mkdir_ and _ls_.
There are many choices for how to implement these operations, and it makes sense to keep them separate from the (largely orthogonal) distributed filesystem logic.
That way, it will be possible later to choose a different implementation of the metadata operations without impacting the rest of the system.

    module FSProtocol
      state do
        interface input, :fsls, [:reqid, :path]
        interface input, :fscreate, [] => [:reqid, :name, :path, :data]
        interface input, :fsmkdir, [] => [:reqid, :name, :path]
        interface input, :fsrm, [] => [:reqid, :name, :path]
        interface output, :fsret, [:reqid, :status, :data]
      end
    end

We create an input interface for each of the operations, and a single output interface for the return for any operation: given a request id, __status__ is a boolean
indicating whether the request succeeded, and __data__ may contain return values (e.g., _fsls_ should return an array containing the array contents.


### I am autogenerated.  Please do not edit me.