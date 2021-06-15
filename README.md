# README

![radix test](https://github.com/hertogp/radix/actions/workflows/elixir.yml/badge.svg)

A path-compressed Patricia trie with one-way branching removed.

- stores `{k,v}`-pairs, where `k` is a bitstring
- returns the `{k,v}`-pair, not just the value
- supports longest prefix matching, and
- tree traversals

## Example

```elixir
t = new([{<<1,1,1>>, "1.1.1.0/24"}, {<<1,1,1,0::1>>, "1.1.1.0/25"])

# longest prefix match:

lpm(t, <<1,1,1,0>>)     #-> {<<1,1,1,0::1>>, "1.1.1.0/25"}
lpm(t, <<1,1,1,128>>)   #-> {<<1,1,1>>, "1.1.1.0/24"}

# all prefix matches:

apm(t, <<1,1,1,0>>)     #-> [{<<1, 1, 1, 0::size(1)>>, "1.1.1.0/25"}, {<<1, 1, 1>>, "1.1.1.0/24"}]

# all reverse prefix matches (i.e. where search key is prefix of a stored key)

rpm(t, <<1,1,1>>)       #-> [{<<1, 1, 1, 0::size(1)>>, "1.1.1.0/25"}, {<<1, 1, 1>>, "1.1.1.0/24"}]

# turn the tree into a list

to_list(t)              #-> [{<<1, 1, 1, 0::size(1)>>, "1.1.1.0/25"}, {<<1, 1, 1>>, "1.1.1.0/24"}]

# traverse the tree and apply a function to each node, where a node can be:
# 1) an internal node,
# 2) nil, or
# 3) a leaf

fun = fn
  (acc, {_bit, _left, _right}) -> acc
  (acc, nil) -> acc
  (acc, leaf) -> Enum.map(leaf, fn {_k, v} -> v end) ++ acc
end

traverse(t, fun, [], :inorder)     #-> ["1.1.1.0/25", "1.1.1.0/24"]

# or just run a function on all {k,v}-pairs in the tree

fun = fn {_k, v}, acc -> [v | acc] end

exec(t, fun, []) |> Enum.reverse() #-> ["1.1.1.0/25", "1.1.1.0/24"]
```



## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `radix` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:radix, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/radix](https://hexdocs.pm/radix).

