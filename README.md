# Radix

A path-compressed Patricia trie with one-way branching removed.

- uses `bitstring`'s as keys to index into the trie
- implemented in pure Elixir
- stores {k,v}-pairs
- supports longest prefix matching
- tree traversals

## Example

```elixir
t = new([{<<1,1,1>>, "1.1.1.0/24"}, {<<1,1,1,0::1>>, "1.1.1.0/25"])

# longest prefix match:
lpm(t, <<1,1,1,0>>)   #-> {<<1,1,1,0::1>>, "1.1.1.0/25"}
lpm(t, <<1,1,1,128>>) #-> {<<1,1,1>>, "1.1.1.0/24"}

# all prefix matches:
apm(t, <<1,1,1,0>>)     #-> [{<<1, 1, 1, 0::size(1)>>, "1.1.1.0/25"}, {<<1, 1, 1>>, "1.1.1.0/24"}]

# all reverse prefix matches (i.e. where search key is prefix of a stored key)
rpm(t, <<1,1,1>>)       #-> [{<<1, 1, 1, 0::size(1)>>, "1.1.1.0/25"}, {<<1, 1, 1>>, "1.1.1.0/24"}]

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

