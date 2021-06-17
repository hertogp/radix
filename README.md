# README

![radix test](https://github.com/hertogp/radix/actions/workflows/elixir.yml/badge.svg)


[Online Radix Documentation](https://hexdocs.pm/radix).

<!-- @MODULEDOC -->

A bitwise radix tree to store any value under a bitstring key of arbitrary length.

Radix provides a [radix tree](https://en.wikipedia.org/wiki/Radix_tree), whose
radius is 2, has path-compression and no one-way branching: i.e. a patricia
trie.

Entries consist of {key, value}-pairs whose insertion/deletion is always
based on an exact key-match, while retrieval functions are based on a prefix
match.

## Examples

    iex> t = new()
    ...>     |> put(<<1, 1, 1>>, "1.1.1/24")
    ...>     |> put(<<1, 1, 1, 0::6>>, "1.1.1.0/30")
    ...>     |> put(<<1, 1, 1, 1::1>>, "1.1.1.128/25")
    ...>     |> put(<<255>>, "255/8")
    iex>
    iex> # Longest prefix match
    iex>
    iex> lookup(t, <<1, 1, 1, 255>>)
    {<<1, 1, 1, 1::1>>, "1.1.1.128/25"}
    iex>
    iex> lookup(t, <<1, 1, 1, 3>>)
    {<<1, 1, 1, 0::6>>, "1.1.1.0/30"}
    iex>
    iex> lookup(t, <<1, 1, 1, 100>>)
    {<<1, 1, 1>>, "1.1.1/24"}
    iex>
    iex> # more specific matches (includes search key if present)
    iex>
    iex> more(t, <<1, 1, 1>>)
    [{<<1, 1, 1, 0::size(6)>>, "1.1.1.0/30"}, {<<1, 1, 1>>, "1.1.1/24"}, {<<1, 1, 1, 1::size(1)>>, "1.1.1.128/25"}]
    iex>
    iex> # less specific matches (includes search key if present)
    iex>
    iex> less(t, <<1, 1, 1, 3>>)
    [{<<1, 1, 1, 0::size(6)>>, "1.1.1.0/30"}, {<<1, 1, 1>>, "1.1.1/24"}]
    iex> dot(t) |> (&File.write("img/readme.dot", &1)).()



The radix tree above looks something like this:

![Radix](img/readme.dot.png)

Since binaries are bitstrings too, they work as well:

    iex> t = new([{"A.new", "new"}, {"A.newer", "newer"}, {"B.newest", "newest"}])
    iex> more(t, "A.") |> Enum.reverse()
    [{"A.new", "new"}, {"A.newer", "newer"}]
    #
    iex> lookup(t, "A.newest")
    {"A.new", "new"}
    #
    iex> more(t, "C.")
    []

<!-- @MODULEDOC -->


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

