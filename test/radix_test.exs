defmodule RadixTest do
  use ExUnit.Case
  doctest Radix, import: true
  import Radix

  @bad_trees [{}, {nil}, {nil, nil}, {nil, nil, nil}, {-1, nil, nil}, {2, nil, nil}]
  @bad_keys [nil, true, false, 0, '0', [], ["0"], {}, {"0"}, %{}, %{"0" => "0"}]
  @broken_left_tree {0, [42], nil}
  @broken_right_tree {0, nil, [42]}

  # list of {k,k}-entries, where k is 16 bits
  @slash16kv for x <- 0..255, y <- 0..255, do: {<<x, y>>, <<x, y>>}

  # Radix.adjacencies/1
  test "adjacencies/1 validates input" do
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> adjacencies(t) end)
    assert_raise RadixError, fn -> adjacencies(@broken_left_tree) end
    assert_raise RadixError, fn -> adjacencies(@broken_right_tree) end
  end

  test "adjacencies/1 returns a map of parents with 2 kids" do
    # empty tree yields an empty map
    m = adjacencies(new())
    assert map_size(m) == 0

    # two neighbors
    t = new([{<<128, 128, 128, 0>>, 0}, {<<128, 128, 128, 1>>, 1}])

    assert adjacencies(t) == %{
             <<128, 128, 128, 0::7>> => {<<128, 128, 128, 0>>, 0, <<128, 128, 128, 1>>, 1}
           }

    # only two are neighbors
    t = new([{<<128, 128, 128, 0>>, 0}, {<<128, 128, 128, 1>>, 1}, {<<128, 128, 128, 2>>, 2}])

    assert adjacencies(t) == %{
             <<128, 128, 128, 0::7>> => {<<128, 128, 128, 0>>, 0, <<128, 128, 128, 1>>, 1}
           }

    t = new([{<<255>>, 255}, {<<254>>, 254}, {<<253>>, 253}, {<<252>>, 252}])

    assert adjacencies(t) == %{
             <<127::7>> => {<<254>>, 254, <<255>>, 255},
             <<126::7>> => {<<252>>, 252, <<253>>, 253}
           }

    t = new([{<<1::1>>, 1}, {<<0::1>>, 0}])

    assert adjacencies(t) == %{<<>> => {<<0::1>>, 0, <<1::1>>, 1}}
  end

  # Radix.count/1
  test "count/1 validates input" do
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> count(t) end)
    assert_raise(RadixError, fn -> count(@broken_left_tree) end)
    assert_raise(RadixError, fn -> count(@broken_right_tree) end)
  end

  test "count the number of entries in a tree" do
    t = new()
    assert 0 == count(new())
    t = put(t, <<>>, nil)
    assert 1 == count(t)

    elms = for x <- 0..255, do: {<<x, 255 - x>>, x}
    t = new(elms)
    assert 256 == count(t)
  end

  # Radix.delete/2
  test "delete/2 validates input" do
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> delete(t, <<>>) end)
    for k <- @bad_keys, do: assert_raise(ArgumentError, fn -> delete(new(), k) end)
    assert_raise(RadixError, fn -> delete(@broken_left_tree, <<0>>) end)
    assert_raise(RadixError, fn -> delete(@broken_right_tree, <<255>>) end)
  end

  test "delete/2 uses exact match" do
    t =
      new()
      |> put(<<0>>, "0/8")
      |> put(<<0, 0>>, "0.0/16")
      |> put(<<0, 0, 0>>, "0.0.0/24")
      |> put(<<>>, "empty")

    t = delete(t, <<0, 0>>)
    assert get(t, <<0>>) == {<<0>>, "0/8"}
    assert get(t, <<0, 0>>) == nil
    assert get(t, <<0, 0, 0>>) == {<<0, 0, 0>>, "0.0.0/24"}
    assert get(t, <<>>) == {<<>>, "empty"}

    t = delete(t, <<0>>)
    assert get(t, <<0>>) == nil
    assert get(t, <<0, 0>>) == nil
    assert get(t, <<0, 0, 0>>) == {<<0, 0, 0>>, "0.0.0/24"}
    assert get(t, <<>>) == {<<>>, "empty"}

    t = delete(t, <<>>)
    assert get(t, <<0>>) == nil
    assert get(t, <<0, 0>>) == nil
    assert get(t, <<0, 0, 0>>) == {<<0, 0, 0>>, "0.0.0/24"}
    assert get(t, <<>>) == nil

    t = delete(t, <<0, 0, 0>>)
    assert t == {0, nil, nil}
  end

  # Radix.dot/2
  test "dot/2 validates input" do
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> dot(t) end)
    assert_raise(RadixError, fn -> dot(@broken_left_tree) end)
    assert_raise(RadixError, fn -> dot(@broken_right_tree) end)
  end

  # Radix.drop/2
  test "drop2 validates input" do
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> drop(t, [<<0>>]) end)
    for k <- @bad_keys, do: assert_raise(ArgumentError, fn -> drop(new(), [k]) end)
    assert_raise(RadixError, fn -> drop(@broken_left_tree, [<<0>>]) end)
    assert_raise(RadixError, fn -> drop(@broken_right_tree, [<<255>>]) end)
  end

  test "drop/2 ignores non-existing keys" do
    t =
      new()
      |> put(<<0>>, "0/8")
      |> put(<<0, 0>>, "0.0/16")
      |> put(<<0, 0, 0>>, "0.0.0/24")
      |> put(<<>>, "empty")

    t = drop(t, [<<0>>, <<1>>, <<0, 0>>, <<>>])
    assert get(t, <<0>>) == nil
    assert get(t, <<0, 0>>) == nil
    assert get(t, <<>>) == nil
    assert get(t, <<0, 0, 0>>) == {<<0, 0, 0>>, "0.0.0/24"}

    t = drop(t, [<<1, 1, 1>>, <<0, 0, 0>>])
    assert t == {0, nil, nil}
  end

  test "drop/2 dropping all keys yields empty tree" do
    t = new(@slash16kv)
    assert drop(t, keys(t)) == {0, nil, nil}
  end

  # Radix.empty?/1
  test "empty?/1 says true or false" do
    assert false == empty?(@broken_left_tree)
    assert false == empty?(@broken_right_tree)

    assert true == empty?(new())

    t = new() |> put(<<>>, nil)
    assert false == empty?(t)
  end

  # Radix.fetch/3
  test "fetch/3 validates input" do
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> fetch(t, <<>>) end)
    for k <- @bad_keys, do: assert_raise(ArgumentError, fn -> fetch(new(), k) end)
    assert_raise(RadixError, fn -> fetch(@broken_left_tree, <<0>>) end)
    assert_raise(RadixError, fn -> fetch(@broken_right_tree, <<255>>) end)
  end

  test "fetch/3 fetches from the tree" do
    t =
      new()
      |> put(<<255>>, 1)
      |> put(<<255, 255>>, 2)
      |> put(<<255, 255, 1::1>>, 3)
      |> put(<<255, 255, 3::2>>, 4)
      |> put(<<128>>, 5)
      |> put(<<128, 128>>, 6)
      |> put(<<128, 128, 1::1>>, 7)
      |> put(<<128, 128, 3::2>>, 8)
      |> put(<<>>, nil)
      |> put(<<0>>, 9)
      |> put(<<0, 0>>, 10)
      |> put(<<0, 0, 0::1>>, 11)
      |> put(<<0, 0, 0::2>>, 12)

    assert fetch(t, <<255, 255, 1::1>>) == {:ok, {<<255, 255, 1::1>>, 3}}
    assert fetch(t, <<255, 255, 3::2>>) == {:ok, {<<255, 255, 3::2>>, 4}}

    assert fetch(t, <<128, 128, 1::1>>) == {:ok, {<<128, 128, 1::1>>, 7}}
    assert fetch(t, <<128, 128, 3::2>>) == {:ok, {<<128, 128, 3::2>>, 8}}

    assert fetch(t, <<0, 0, 0::1>>) == {:ok, {<<0, 0, 0::1>>, 11}}
    assert fetch(t, <<0, 0, 0::2>>) == {:ok, {<<0, 0, 0::2>>, 12}}

    # longest prefix match
    assert fetch(t, <<255, 128>>, match: :lpm) == {:ok, {<<255>>, 1}}
    assert fetch(t, <<255, 255, 128>>, match: :lpm) == {:ok, {<<255, 255, 1::1>>, 3}}
    assert fetch(t, <<128, 128, 255, 255>>, match: :lpm) == {:ok, {<<128, 128, 3::2>>, 8}}
    assert fetch(t, <<0, 0, 0, 0>>, match: :lpm) == {:ok, {<<0, 0, 0::2>>, 12}}

    # no match unless lpm
    assert fetch(t, <<7>>) == :error
    assert fetch(t, <<7>>, match: :lpm) == {:ok, {<<>>, nil}}
  end

  # Radix.fetch!/3
  test "fetch!/3 validates input" do
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> fetch!(t, <<>>) end)
    for k <- @bad_keys, do: assert_raise(ArgumentError, fn -> fetch!(new(), k) end)
    assert_raise(RadixError, fn -> fetch!(@broken_left_tree, <<0>>) end)
    assert_raise(RadixError, fn -> fetch!(@broken_right_tree, <<255>>) end)
  end

  test "fetch!/3 fetch!es from the tree" do
    t =
      new()
      |> put(<<255>>, 1)
      |> put(<<255, 255>>, 2)
      |> put(<<255, 255, 1::1>>, 3)
      |> put(<<255, 255, 3::2>>, 4)
      |> put(<<128>>, 5)
      |> put(<<128, 128>>, 6)
      |> put(<<128, 128, 1::1>>, 7)
      |> put(<<128, 128, 3::2>>, 8)
      |> put(<<>>, nil)
      |> put(<<0>>, 9)
      |> put(<<0, 0>>, 10)
      |> put(<<0, 0, 0::1>>, 11)
      |> put(<<0, 0, 0::2>>, 12)

    assert fetch!(t, <<255, 255, 1::1>>) == {<<255, 255, 1::1>>, 3}
    assert fetch!(t, <<255, 255, 3::2>>) == {<<255, 255, 3::2>>, 4}

    assert fetch!(t, <<128, 128, 1::1>>) == {<<128, 128, 1::1>>, 7}
    assert fetch!(t, <<128, 128, 3::2>>) == {<<128, 128, 3::2>>, 8}

    assert fetch!(t, <<0, 0, 0::1>>) == {<<0, 0, 0::1>>, 11}
    assert fetch!(t, <<0, 0, 0::2>>) == {<<0, 0, 0::2>>, 12}

    # longest prefix match
    assert fetch!(t, <<255, 128>>, match: :lpm) == {<<255>>, 1}
    assert fetch!(t, <<255, 255, 128>>, match: :lpm) == {<<255, 255, 1::1>>, 3}
    assert fetch!(t, <<128, 128, 255, 255>>, match: :lpm) == {<<128, 128, 3::2>>, 8}
    assert fetch!(t, <<0, 0, 0, 0>>, match: :lpm) == {<<0, 0, 0::2>>, 12}

    # no match unless lpm
    assert_raise KeyError, fn -> fetch!(t, <<7>>) end
    assert fetch!(t, <<7>>, match: :lpm) == {<<>>, nil}
  end

  # Radix.get/2
  test "get/2 validates input" do
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> get(t, <<>>) end)
    for k <- @bad_keys, do: assert_raise(ArgumentError, fn -> get(new(), k) end)
    assert_raise(RadixError, fn -> get(@broken_left_tree, <<0>>) end)
    assert_raise(RadixError, fn -> get(@broken_right_tree, <<255>>) end)
  end

  test "get/2 from empty tree yields nil" do
    t = new()
    assert get(t, <<>>) == nil
    assert get(t, <<0::1>>) == nil
    assert get(t, <<1::1>>) == nil
  end

  test "get/2 does NOT yield default match" do
    t =
      new()
      |> put(<<>>, "null")
      |> put(<<1>>, 1)

    assert get(t, <<>>) == {<<>>, "null"}
    assert get(t, <<0>>) == nil
    assert get(t, <<1>>) == {<<1>>, 1}
    assert get(t, <<255>>) == nil
  end

  test "get/2 does an exact match only" do
    t =
      new()
      |> put(<<1, 1, 1>>, "1.1.1.0/24")
      |> put(<<1, 1, 1, 0::1>>, "1.1.1.0/25")
      |> put(<<1, 1, 1, 0::2>>, "1.1.1.0/26")
      |> put(<<1, 1, 1, 0::3>>, "1.1.1.0/27")
      |> put(<<1, 1, 1, 0::4>>, "1.1.1.0/28")
      |> put(<<1, 1, 1, 0::5>>, "1.1.1.0/29")
      |> put(<<1, 1, 1, 0::6>>, "1.1.1.0/30")
      |> put(<<1, 1, 1, 0::7>>, "1.1.1.0/31")
      |> put(<<1, 1, 1, 1::1>>, "1.1.1.128/25")

    assert get(t, <<1, 1, 1, 0::1>>) == {<<1, 1, 1, 0::1>>, "1.1.1.0/25"}
    assert get(t, <<1, 1, 1, 0::1>>) == {<<1, 1, 1, 0::1>>, "1.1.1.0/25"}
    assert get(t, <<1, 1, 1, 0::2>>) == {<<1, 1, 1, 0::2>>, "1.1.1.0/26"}
    assert get(t, <<1, 1, 1, 0::3>>) == {<<1, 1, 1, 0::3>>, "1.1.1.0/27"}
    assert get(t, <<1, 1, 1, 0::4>>) == {<<1, 1, 1, 0::4>>, "1.1.1.0/28"}
    assert get(t, <<1, 1, 1, 0::5>>) == {<<1, 1, 1, 0::5>>, "1.1.1.0/29"}
    assert get(t, <<1, 1, 1, 0::6>>) == {<<1, 1, 1, 0::6>>, "1.1.1.0/30"}
    assert get(t, <<1, 1, 1, 0::7>>) == {<<1, 1, 1, 0::7>>, "1.1.1.0/31"}
    assert get(t, <<1, 1, 1, 0>>) == nil
    assert get(t, <<1, 1, 1>>) == {<<1, 1, 1>>, "1.1.1.0/24"}
    assert get(t, <<1, 1>>) == nil
  end

  # Radix.get_and_update/3
  test "get_and_update/3 validates input" do
    count = fn
      nil -> {0, 1}
      {_k, v} -> {v, v + 1}
    end

    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> get_and_update(t, <<>>, count) end)
    for k <- @bad_keys, do: assert_raise(ArgumentError, fn -> get_and_update(new(), k, count) end)
    assert_raise(RadixError, fn -> get_and_update(@broken_left_tree, <<0>>, count) end)
    assert_raise(RadixError, fn -> get_and_update(@broken_right_tree, <<255>>, count) end)

    # also checks fun has arity 1
    bad_fun = fn
      a, b -> {a, b}
    end

    assert_raise(ArgumentError, fn -> get_and_update(new(), <<1, 1>>, bad_fun) end)
  end

  test "get_and_update/3 when callback returns {cur, new}" do
    count = fn
      nil -> {0, 1}
      {_k, v} -> {v, v + 1}
    end

    # update an empty tree
    t = new()
    {org, t} = get_and_update(t, <<>>, count)
    assert get(t, <<>>) == {<<>>, 1}
    assert org == 0
    # update existing entry
    {org, t} = get_and_update(t, <<1>>, count)
    assert org == 0
    {org, t} = get_and_update(t, <<1>>, count)
    assert org == 1
    {org, t} = get_and_update(t, <<1>>, count)
    assert org == 2
    assert get(t, <<1>>) == {<<1>>, 3}
    # update right part of the tree
    {org, t} = get_and_update(t, <<255, 255>>, count)
    assert org == 0
    assert get(t, <<255, 255>>) == {<<255, 255>>, 1}
    # should have 3 entries
    assert count(t) == 3
  end

  test "get_and_update/3, callback returns :pop" do
    pop = fn
      nil -> :pop
      {_, _} -> :pop
    end

    t = new([{<<>>, 0}, {<<1>>, 1}, {<<255, 255>>, 255}])

    {org, t} = get_and_update(t, <<128>>, pop)
    assert org == nil
    assert get(t, <<>>) == {<<>>, 0}
    assert get(t, <<1>>) == {<<1>>, 1}
    assert get(t, <<255, 255>>) == {<<255, 255>>, 255}
    assert count(t) == 3

    {org, t} = get_and_update(t, <<>>, pop)
    assert org == 0
    assert get(t, <<>>) == nil
    {org, t} = get_and_update(t, <<255, 255>>, pop)
    assert org == 255
    assert get(t, <<255, 255>>) == nil
    {org, t} = get_and_update(t, <<1>>, pop)
    assert org == 1
    assert get(t, <<1>>) == nil
    assert count(t) == 0
  end

  test "get_and_update/3, callback returns bad value" do
    badfun = fn
      nil -> nil
      {k, v} -> [k, v]
    end

    # badfun passes back nil
    assert_raise(ArgumentError, fn -> get_and_update(new(), <<>>, badfun) end)

    # badfun passes back a list
    assert_raise(ArgumentError, fn -> get_and_update(new([{<<>>, 0}]), <<>>, badfun) end)
  end

  # Radix.keys/1
  test "keys/1 validates input" do
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> keys(t) end)
    assert_raise(RadixError, fn -> keys(@broken_left_tree) end)
    assert_raise(RadixError, fn -> keys(@broken_right_tree) end)
  end

  test "keys/1 lists all keys" do
    t =
      new()
      |> put(<<255>>, 1)
      |> put(<<255, 255>>, 2)
      |> put(<<255, 255, 1::1>>, 3)
      |> put(<<255, 255, 3::2>>, 4)
      |> put(<<128>>, 5)
      |> put(<<128, 128>>, 6)
      |> put(<<128, 128, 1::1>>, 7)
      |> put(<<128, 128, 3::2>>, 8)
      |> put(<<0>>, 9)
      |> put(<<0, 0>>, 10)
      |> put(<<0, 0, 0::1>>, 11)
      |> put(<<0, 0, 0::2>>, 12)

    keys = keys(t)
    assert Enum.count(keys) == 12
    assert <<255>> in keys
    assert <<255, 255>> in keys
    assert <<255, 255, 1::1>> in keys
    assert <<255, 255, 3::2>> in keys
    assert <<128>> in keys
    assert <<128, 128>> in keys
    assert <<128, 128, 1::1>> in keys
    assert <<128, 128, 3::2>> in keys
    assert <<0>> in keys
    assert <<0, 0>> in keys
    assert <<0, 0, 0::1>> in keys
    assert <<0, 0, 0::2>> in keys
  end

  # Radix.less/2
  test "less/3 validates input" do
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> less(t, <<>>) end)
    for k <- @bad_keys, do: assert_raise(ArgumentError, fn -> less(new(), k) end)
    assert_raise(RadixError, fn -> less(@broken_left_tree, <<0>>) end)
    assert_raise(RadixError, fn -> less(@broken_right_tree, <<255>>) end)
  end

  test "less/3 - less specifics" do
    t =
      new()
      |> put(<<255>>, 8)
      |> put(<<255, 255>>, 16)
      |> put(<<255, 255, 1::1>>, 17)
      |> put(<<255, 255, 3::2>>, 18)

    less = less(t, <<255, 255, 255, 255>>)
    assert Enum.count(less) == 4
    assert {<<255>>, 8} in less
    assert {<<255, 255>>, 16} in less
    assert {<<255, 255, 1::1>>, 17} in less
    assert {<<255, 255, 3::2>>, 18} in less

    less = less(t, <<255, 255, 255, 255>>, exclude: true)
    assert Enum.count(less) == 4
    assert {<<255>>, 8} in less
    assert {<<255, 255>>, 16} in less
    assert {<<255, 255, 1::1>>, 17} in less
    assert {<<255, 255, 3::2>>, 18} in less

    less = less(t, <<255, 255, 3::2>>)
    assert Enum.count(less) == 4
    assert {<<255>>, 8} in less
    assert {<<255, 255>>, 16} in less
    assert {<<255, 255, 1::1>>, 17} in less
    assert {<<255, 255, 3::2>>, 18} in less

    less = less(t, <<255, 255, 3::2>>, exclude: true)
    assert Enum.count(less) == 3
    assert {<<255>>, 8} in less
    assert {<<255, 255>>, 16} in less
    assert {<<255, 255, 1::1>>, 17} in less

    less = less(t, <<255, 255, 1::1>>)
    assert Enum.count(less) == 3
    assert {<<255>>, 8} in less
    assert {<<255, 255>>, 16} in less
    assert {<<255, 255, 1::1>>, 17} in less

    less = less(t, <<255, 255, 1::1>>, exclude: true)
    assert Enum.count(less) == 2
    assert {<<255>>, 8} in less
    assert {<<255, 255>>, 16} in less

    less = less(t, <<255, 255>>)
    assert Enum.count(less) == 2
    assert {<<255>>, 8} in less
    assert {<<255, 255>>, 16} in less

    less = less(t, <<255, 255>>, exclude: true)
    assert Enum.count(less) == 1
    assert {<<255>>, 8} in less

    less = less(t, <<255>>)
    assert Enum.count(less) == 1
    assert {<<255>>, 8} in less

    less = less(t, <<255>>, exclude: true)
    assert Enum.count(less) == 0

    # keys without less specifics
    assert less(t, <<>>) == []
  end

  # Radix.lookup/2
  test "lookup/2 validates input" do
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> lookup(t, <<>>) end)
    for k <- @bad_keys, do: assert_raise(ArgumentError, fn -> lookup(new(), k) end)
    assert_raise(RadixError, fn -> lookup(@broken_left_tree, <<0>>) end)
    assert_raise(RadixError, fn -> lookup(@broken_right_tree, <<255>>) end)
  end

  test "lookup/2 uses longest prefix match - 1" do
    t =
      new()
      |> put(<<128, 128, 128>>, "128.128.128/24")
      |> put(<<128, 128, 128, 1::1>>, "128.128.128.128/25")
      |> put(<<128, 128, 128, 2::2>>, "128.128.128.128/26")

    # 128.128.128.128/26 -> 128.128.128.128-191
    assert lookup(t, <<128, 128, 128, 128>>) == {<<128, 128, 128, 2::2>>, "128.128.128.128/26"}
    assert lookup(t, <<128, 128, 128, 191>>) == {<<128, 128, 128, 2::2>>, "128.128.128.128/26"}

    # 128.128.128.128/25 -> 128.128.128.128-255, effectively .192-.255
    assert lookup(t, <<128, 128, 128, 192>>) == {<<128, 128, 128, 1::1>>, "128.128.128.128/25"}
    assert lookup(t, <<128, 128, 128, 255>>) == {<<128, 128, 128, 1::1>>, "128.128.128.128/25"}

    # 128.128.128/24 -> 128.128.128.0-255, effectively .0-.127
    assert lookup(t, <<128, 128, 128, 0>>) == {<<128, 128, 128>>, "128.128.128/24"}
    assert lookup(t, <<128, 128, 128, 127>>) == {<<128, 128, 128>>, "128.128.128/24"}
  end

  test "lookup/2 uses longest prefix match - 2" do
    t =
      new()
      |> put(<<0>>, "0.0.0.0/8")
      |> put(<<0, 0>>, "0.0.0.0/16")
      |> put(<<0, 0, 0>>, "0.0.0.0/24")
      |> put(<<0, 0, 0, 0::1>>, "0.0.0.0/25")
      |> put(<<0, 0, 0, 0::2>>, "0.0.0.0/26")

    assert lookup(t, <<0, 0, 0, 0>>) == {<<0, 0, 0, 0::2>>, "0.0.0.0/26"}
    assert lookup(t, <<0, 0, 0, 63>>) == {<<0, 0, 0, 0::2>>, "0.0.0.0/26"}
    assert lookup(t, <<0, 0, 0, 64>>) == {<<0, 0, 0, 0::1>>, "0.0.0.0/25"}
    assert lookup(t, <<0, 0, 0, 127>>) == {<<0, 0, 0, 0::1>>, "0.0.0.0/25"}
    assert lookup(t, <<0, 0, 0, 128>>) == {<<0, 0, 0>>, "0.0.0.0/24"}
    assert lookup(t, <<0, 0, 0, 255>>) == {<<0, 0, 0>>, "0.0.0.0/24"}
    assert lookup(t, <<0, 0, 1>>) == {<<0, 0>>, "0.0.0.0/16"}
    assert lookup(t, <<0, 1>>) == {<<0>>, "0.0.0.0/8"}
    assert lookup(t, <<0, 255>>) == {<<0>>, "0.0.0.0/8"}
    assert lookup(t, <<0::7>>) == nil
  end

  test "lookup/2 uses longest prefix match - 3" do
    t =
      new()
      |> put(<<255>>, "255.0.0.0/8")
      |> put(<<255, 255>>, "255.255.0.0/16")
      |> put(<<255, 255, 255>>, "255.255.255.0/24")
      |> put(<<255, 255, 255, 0::1>>, "255.255.255.0/25")
      |> put(<<255, 255, 255, 0::2>>, "255.255.255.0/26")

    assert lookup(t, <<255, 255, 255, 0>>) == {<<255, 255, 255, 0::2>>, "255.255.255.0/26"}
    assert lookup(t, <<255, 255, 255, 63>>) == {<<255, 255, 255, 0::2>>, "255.255.255.0/26"}
    assert lookup(t, <<255, 255, 255, 64>>) == {<<255, 255, 255, 0::1>>, "255.255.255.0/25"}
    assert lookup(t, <<255, 255, 255, 127>>) == {<<255, 255, 255, 0::1>>, "255.255.255.0/25"}
    assert lookup(t, <<255, 255, 255, 128>>) == {<<255, 255, 255>>, "255.255.255.0/24"}
    assert lookup(t, <<255, 255, 255, 255>>) == {<<255, 255, 255>>, "255.255.255.0/24"}
    assert lookup(t, <<255, 255, 1>>) == {<<255, 255>>, "255.255.0.0/16"}
    assert lookup(t, <<255, 255>>) == {<<255, 255>>, "255.255.0.0/16"}
    assert lookup(t, <<255, 1>>) == {<<255>>, "255.0.0.0/8"}
    assert lookup(t, <<255::7>>) == nil
  end

  test "lookup/2 yields default match when no key matches - 1" do
    t =
      new()
      |> put(<<128, 128, 128>>, "128.128.128/24")
      |> put(<<128, 128, 128, 1::1>>, "128.128.128.128/25")
      |> put(<<128, 128, 128, 2::2>>, "128.128.128.128/26")
      |> put(<<>>, "default")

    assert lookup(t, <<128, 128, 128>>) == {<<128, 128, 128>>, "128.128.128/24"}
    assert lookup(t, <<128, 128, 128, 1::1>>) == {<<128, 128, 128, 1::1>>, "128.128.128.128/25"}
    assert lookup(t, <<128, 128, 128, 2::2>>) == {<<128, 128, 128, 2::2>>, "128.128.128.128/26"}

    assert lookup(t, <<0>>) == {<<>>, "default"}
    assert lookup(t, <<255>>) == {<<>>, "default"}
    assert lookup(t, <<128>>) == {<<>>, "default"}
    assert lookup(t, <<128, 128>>) == {<<>>, "default"}
    assert lookup(t, <<128, 128, 127>>) == {<<>>, "default"}
    assert lookup(t, <<128, 128, 129>>) == {<<>>, "default"}
  end

  test "lookup/2 yields default match when no key matches - 2" do
    t =
      new()
      |> put(<<>>, 1)
      |> put(<<255>>, 2)
      |> put(<<128>>, 3)
      |> put(<<0>>, 4)

    # existing keys should be found normally
    assert lookup(t, <<>>) == {<<>>, 1}
    assert lookup(t, <<255>>) == {<<255>>, 2}
    assert lookup(t, <<128>>) == {<<128>>, 3}
    assert lookup(t, <<0>>) == {<<0>>, 4}

    # non-existing keys should yield the default match
    assert lookup(t, <<1>>) == {<<>>, 1}
    assert lookup(t, <<127>>) == {<<>>, 1}
    assert lookup(t, <<254>>) == {<<>>, 1}
    assert lookup(t, <<0::7>>) == {<<>>, 1}
  end

  # Radix.merge/2
  test "merge/2 validates input" do
    # ensure merging travels left/right subtree of receiving tree
    t2 = new([{<<0>>, 0}, {<<255>>, 1}])
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> merge(t, new()) end)
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> merge(new(), t) end)
    assert_raise(RadixError, fn -> merge(new(), @broken_left_tree) end)
    assert_raise(RadixError, fn -> merge(new(), @broken_right_tree) end)
    assert_raise(RadixError, fn -> merge(@broken_right_tree, t2) end)
    assert_raise(RadixError, fn -> merge(@broken_left_tree, t2) end)
  end

  test "merge/2 merges the second tree into the first tree" do
    t1 = new([{<<>>, nil}, {<<0>>, 0}, {<<1>>, 1}, {<<255>>, 255}, {<<255, 1::1>>, 256}])

    t2 =
      new([
        {<<>>, :none},
        {<<1>>, "one"},
        {<<2>>, 2},
        {<<255, 1::1>>, "255+"},
        {<<255, 3::2>>, "255++"}
      ])

    t3 = merge(t1, t2)
    assert get(t3, <<>>) == {<<>>, :none}
    assert get(t3, <<0>>) == {<<0>>, 0}
    assert get(t3, <<1>>) == {<<1>>, "one"}
    assert get(t3, <<2>>) == {<<2>>, 2}
    assert get(t3, <<255>>) == {<<255>>, 255}
    assert get(t3, <<255, 1::1>>) == {<<255, 1::1>>, "255+"}
    assert get(t3, <<255, 3::2>>) == {<<255, 3::2>>, "255++"}
    assert count(t3) == 7
  end

  # Radix.merge/3
  test "merge/3 validates input" do
    # ensure merging travels left/right subtree of receiving tree
    t2 = new([{<<0>>, 0}, {<<255>>, 1}])
    goodfun = fn _, _, _ -> nil end
    badfun = fn _, _ -> nil end
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> merge(t, new(), goodfun) end)
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> merge(new(), t, goodfun) end)
    assert_raise ArgumentError, fn -> merge(new(), new(), badfun) end
    assert_raise(RadixError, fn -> merge(new(), @broken_left_tree, goodfun) end)
    assert_raise(RadixError, fn -> merge(new(), @broken_right_tree, goodfun) end)
    assert_raise(RadixError, fn -> merge(@broken_right_tree, t2, goodfun) end)
    assert_raise(RadixError, fn -> merge(@broken_left_tree, t2, goodfun) end)
  end

  test "merge/3 merges two trees with conflict resolution function" do
    keepv1 = fn _k, v1, _v2 -> v1 end
    t1 = new([{<<>>, nil}, {<<0>>, 0}, {<<1>>, 1}, {<<255>>, 255}, {<<255, 1::1>>, 256}])
    t2 = new([{<<>>, :none}, {<<1>>, "one"}, {<<255, 1::1>>, "255+"}, {<<255, 3::2>>, "255++"}])
    t3 = merge(t1, t2, keepv1)
    assert get(t3, <<>>) == {<<>>, nil}
    assert get(t3, <<0>>) == {<<0>>, 0}
    assert get(t3, <<1>>) == {<<1>>, 1}
    assert get(t3, <<255>>) == {<<255>>, 255}
    assert get(t3, <<255, 1::1>>) == {<<255, 1::1>>, 256}
    assert get(t3, <<255, 3::2>>) == {<<255, 3::2>>, "255++"}
    assert count(t3) == 6
  end

  # Radix.more/2
  test "more/2 validates input" do
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> more(t, <<>>) end)
    for k <- @bad_keys, do: assert_raise(ArgumentError, fn -> more(new(), k) end)
    assert_raise(RadixError, fn -> more(@broken_left_tree, <<0>>) end)
    assert_raise(RadixError, fn -> more(@broken_right_tree, <<255>>) end)
  end

  test "more/2 - more specifics" do
    t =
      new()
      |> put(<<255>>, 8)
      |> put(<<255, 255>>, 16)
      |> put(<<255, 255, 1::1>>, 17)
      |> put(<<255, 255, 3::2>>, 18)

    more = more(t, <<>>)
    assert Enum.count(more) == 4
    assert {<<255>>, 8} in more
    assert {<<255, 255>>, 16} in more
    assert {<<255, 255, 1::1>>, 17} in more
    assert {<<255, 255, 3::2>>, 18} in more

    more = more(t, <<>>, exclude: true)
    assert Enum.count(more) == 4
    assert {<<255>>, 8} in more
    assert {<<255, 255>>, 16} in more
    assert {<<255, 255, 1::1>>, 17} in more
    assert {<<255, 255, 3::2>>, 18} in more

    more = more(t, <<255>>)
    assert Enum.count(more) == 4
    assert {<<255>>, 8} in more
    assert {<<255, 255>>, 16} in more
    assert {<<255, 255, 1::1>>, 17} in more
    assert {<<255, 255, 3::2>>, 18} in more

    more = more(t, <<255>>, exclude: true)
    assert Enum.count(more) == 3
    assert {<<255, 255>>, 16} in more
    assert {<<255, 255, 1::1>>, 17} in more
    assert {<<255, 255, 3::2>>, 18} in more

    more = more(t, <<255, 255>>)
    assert Enum.count(more) == 3
    assert {<<255, 255>>, 16} in more
    assert {<<255, 255, 1::1>>, 17} in more
    assert {<<255, 255, 3::2>>, 18} in more

    more = more(t, <<255, 255>>, exclude: true)
    assert Enum.count(more) == 2
    assert {<<255, 255, 1::1>>, 17} in more
    assert {<<255, 255, 3::2>>, 18} in more

    more = more(t, <<255, 1::1>>)
    assert Enum.count(more) == 3
    assert {<<255, 255>>, 16} in more
    assert {<<255, 255, 1::1>>, 17} in more
    assert {<<255, 255, 3::2>>, 18} in more

    more = more(t, <<255, 1::1>>, exclude: true)
    assert Enum.count(more) == 3
    assert {<<255, 255>>, 16} in more
    assert {<<255, 255, 1::1>>, 17} in more
    assert {<<255, 255, 3::2>>, 18} in more

    more = more(t, <<255, 255::7>>)
    assert Enum.count(more) == 3
    assert {<<255, 255>>, 16} in more
    assert {<<255, 255, 1::1>>, 17} in more
    assert {<<255, 255, 3::2>>, 18} in more

    more = more(t, <<255, 255::7>>, exclude: true)
    assert Enum.count(more) == 3
    assert {<<255, 255>>, 16} in more
    assert {<<255, 255, 1::1>>, 17} in more
    assert {<<255, 255, 3::2>>, 18} in more

    more = more(t, <<255, 255, 1::1>>)
    assert Enum.count(more) == 2
    assert {<<255, 255, 1::1>>, 17} in more
    assert {<<255, 255, 3::2>>, 18} in more

    more = more(t, <<255, 255, 1::1>>, exclude: true)
    assert Enum.count(more) == 1
    assert {<<255, 255, 3::2>>, 18} in more

    more = more(t, <<255, 255, 3::2>>)
    assert Enum.count(more) == 1
    assert {<<255, 255, 3::2>>, 18} in more

    more = more(t, <<255, 255, 3::2>>, exclude: true)
    assert Enum.count(more) == 0

    # keys without more specifics
    assert more(t, <<254>>) == []
    assert more(t, <<255, 0::1>>) == []
    assert more(t, <<255, 255, 0::1>>) == []
  end

  # Radix.new/0
  test "new, empty radix tree" do
    t = new()
    assert t == {0, nil, nil}
  end

  # Radix.new/1
  test "new/1 validates input" do
    # second key is bad
    assert_raise ArgumentError, fn -> new([{<<0>>, 0}, {42, 42}]) end
  end

  test "new, radix tree initialized with list of {k,v}-pairs" do
    t = new([{<<1, 1, 1, 1>>, 1}, {<<0, 0, 0, 0>>, 0}])
    assert t == {0, {7, [{<<0, 0, 0, 0>>, 0}], [{<<1, 1, 1, 1>>, 1}]}, nil}
  end

  # Radix.pop/3
  test "pop/3 validates input" do
    # 3rd argument opts
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> pop(t, <<>>) end)
    for k <- @bad_keys, do: assert_raise(ArgumentError, fn -> pop(new(), k) end)
    assert_raise(RadixError, fn -> pop(@broken_left_tree, <<0>>) end)
    assert_raise(RadixError, fn -> pop(@broken_right_tree, <<255>>) end)
  end

  test "pop/3 returns value and new tree" do
    t =
      new()
      |> put(<<255>>, 1)
      |> put(<<255, 255>>, 2)
      |> put(<<255, 255, 1::1>>, 3)
      |> put(<<255, 255, 3::2>>, 4)
      |> put(<<128>>, 5)
      |> put(<<128, 128>>, 6)
      |> put(<<128, 128, 1::1>>, 7)
      |> put(<<128, 128, 3::2>>, 8)
      |> put(<<>>, 0)
      |> put(<<0>>, 9)
      |> put(<<0, 0>>, 10)
      |> put(<<0, 0, 0::1>>, 11)
      |> put(<<0, 0, 0::2>>, 12)

    # pop existing
    key = <<128, 128, 3::2>>
    {{key, 8}, t1} = pop(t, key)
    assert get(t1, key) == nil

    # pop non-existing
    key = <<1>>
    assert get(t, key) == nil
    {{^key, nil}, ^t} = pop(t, key)
    {{^key, :notfound}, ^t} = pop(t, key, default: :notfound)

    # pop longest match (matching default empty key)
    key = <<1>>
    {{<<>>, 0}, t1} = pop(t, key, match: :lpm)
    assert get(t1, <<>>) == nil

    key = <<0, 0, 0, 0>>
    {{<<0, 0, 0::2>>, 12}, t1} = pop(t, key, match: :lpm)
    assert get(t1, key) == nil

    # pop non-existing with longest prefix match
    key = <<1>>
    t = delete(t, <<>>)
    {{<<1>>, :notfound}, ^t} = pop(t, key, match: :lpm, default: :notfound)
  end

  # Radix.prune/3
  test "prune/3 validates input" do
    goodfun = fn _ -> nil end
    badfun = fn _, _ -> nil end
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> prune(t, goodfun) end)
    assert_raise ArgumentError, fn -> prune(new(), badfun) end
    assert_raise(RadixError, fn -> prune(@broken_left_tree, goodfun) end)
    assert_raise(RadixError, fn -> prune(@broken_right_tree, goodfun) end)
  end

  test "prune/3 prunes once or recursively" do
    f = fn
      {_k0, _k1, v1, _k2, v2} -> {:ok, v1 + v2}
      {_k0, v0, _k1, v1, _k2, v2} -> {:ok, v0 + v1 + v2}
    end

    t = new(for x <- 0..255, do: {<<x>>, x})
    t0 = prune(t, f)
    t1 = prune(t, f, recurse: true)

    assert count(t) == 256
    assert count(t0) == 128
    assert count(t1) == 1
    assert t1 == {0, [{"", 32640}], nil}
    assert Enum.sum(0..255) == get(t1, <<>>) |> elem(1)
  end

  # Radix.put/2
  test "put/2 validates input" do
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> put(t, [{<<>>, 0}]) end)
    for k <- @bad_keys, do: assert_raise(ArgumentError, fn -> put(new(), [{<<>>, 0}, {k, 0}]) end)
    assert_raise(RadixError, fn -> put(@broken_left_tree, [{<<0>>, 0}]) end)
    assert_raise(RadixError, fn -> put(@broken_right_tree, [{<<255>>, 0}]) end)
  end

  test "put/2 a list of {k,v}-pairs" do
    # both in left subtree
    t = new() |> put([{<<0, 0, 0, 0>>, "0"}, {<<1, 1, 1, 1>>, "1"}])
    assert t == {0, {7, [{<<0, 0, 0, 0>>, "0"}], [{<<1, 1, 1, 1>>, "1"}]}, nil}

    # one in left and one in right subtree
    t = new() |> put([{<<0, 0, 0, 0>>, "0"}, {<<128, 1, 1, 1>>, "128"}])
    assert t == {0, [{<<0, 0, 0, 0>>, "0"}], [{<<128, 1, 1, 1>>, "128"}]}

    # both in right subtree
    t = new() |> put([{<<128, 0, 0, 0>>, "A"}, {<<128, 0, 0, 1>>, "B"}])
    assert t == {0, nil, {31, [{<<128, 0, 0, 0>>, "A"}], [{<<128, 0, 0, 1>>, "B"}]}}
  end

  # Radix.put/3
  test "put/3 validates input" do
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> put(t, <<>>, 0) end)
    for k <- @bad_keys, do: assert_raise(ArgumentError, fn -> put(new(), k, 0) end)
    assert_raise(RadixError, fn -> put(@broken_left_tree, <<0>>, 0) end)
    assert_raise(RadixError, fn -> put(@broken_right_tree, <<255>>, 0) end)
  end

  test "put/3 a new, single element" do
    # insert a single value into left subtree of root
    t =
      new()
      |> put(<<0, 1, 2, 3>>, "0123")

    assert t == {0, [{<<0, 1, 2, 3>>, "0123"}], nil}

    # insert a single value into right subtree of root
    t =
      new()
      |> put(<<128, 1, 2, 3>>, 42)

    assert t == {0, nil, [{<<128, 1, 2, 3>>, 42}]}
  end

  test "put replaces any existing {k,v}-pair" do
    t =
      new()
      |> put(<<128, 1, 2, 3>>, 42)
      |> put(<<128, 1, 2, 3>>, "42")

    assert t == {0, nil, [{<<128, 1, 2, 3>>, "42"}]}

    t =
      new()
      |> put(<<1>>, 1)
      |> put(<<1>>, "one")
      |> put(<<128>>, 128)
      |> put(<<>>, 0)

    assert get(t, <<>>) == {<<>>, 0}
    assert get(t, <<1>>) == {<<1>>, "one"}
    assert get(t, <<128>>) == {<<128>>, 128}

    # empty key also gets replaced
    t = put(t, <<>>, "null")
    assert get(t, <<>>) == {<<>>, "null"}
    assert get(t, <<1>>) == {<<1>>, "one"}
    assert get(t, <<128>>) == {<<128>>, 128}
  end

  # Radix.reduce/3
  test "reduce/3 validates input" do
    fun2 = fn _, _ -> nil end
    fun3 = fn _, _, _ -> nil end
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> reduce(t, 0, fun3) end)
    assert_raise ArgumentError, fn -> reduce(new(), 0, fun2) end
    assert_raise(RadixError, fn -> reduce(@broken_left_tree, 0, fun3) end)
    assert_raise(RadixError, fn -> reduce(@broken_right_tree, 0, fun3) end)
  end

  test "reduce/3 visits all k,v-pairs" do
    t =
      new()
      |> put(<<255>>, 1)
      |> put(<<255, 255>>, 2)
      |> put(<<255, 255, 1::1>>, 3)
      |> put(<<255, 255, 3::2>>, 4)
      |> put(<<128>>, 5)
      |> put(<<128, 128>>, 6)
      |> put(<<128, 128, 1::1>>, 7)
      |> put(<<128, 128, 3::2>>, 8)
      |> put(<<0>>, 9)
      |> put(<<0, 0>>, 10)
      |> put(<<0, 0, 0::1>>, 11)
      |> put(<<0, 0, 0::2>>, 12)

    fun = fn _key, value, acc -> acc + value end

    assert reduce(t, 0, fun) == Enum.sum(1..12)
  end

  # Radix.split/3
  test "split/3 validates input" do
    # 3rd arg is opts
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> split(t, [<<0>>]) end)
    for k <- @bad_keys, do: assert_raise(ArgumentError, fn -> split(new(), [k]) end)
    assert_raise(RadixError, fn -> split(@broken_left_tree, [<<0>>]) end)
    assert_raise(RadixError, fn -> split(@broken_right_tree, [<<0>>, <<255>>]) end)
  end

  test "split/3 splits a radix tree into two trees" do
    t =
      new()
      |> put(<<255>>, 1)
      |> put(<<255, 255>>, 2)
      |> put(<<255, 255, 1::1>>, 3)
      |> put(<<255, 255, 3::2>>, 4)
      |> put(<<128>>, 5)
      |> put(<<128, 128>>, 6)
      |> put(<<128, 128, 1::1>>, 7)
      |> put(<<128, 128, 3::2>>, 8)
      |> put(<<>>, nil)
      |> put(<<0>>, 9)
      |> put(<<0, 0>>, 10)
      |> put(<<0, 0, 0::1>>, 11)
      |> put(<<0, 0, 0::2>>, 12)

    keys = [<<255>>, <<128>>, <<>>, <<0>>]
    {t1, t2} = split(t, keys)
    assert count(t1) == 4
    assert get(t1, <<255>>) == {<<255>>, 1}
    assert get(t1, <<128>>) == {<<128>>, 5}
    assert get(t1, <<>>) == {<<>>, nil}
    assert get(t1, <<0>>) == {<<0>>, 9}
    assert count(t2) == 13 - 4
    assert get(t2, <<255>>) == nil
    assert get(t2, <<128>>) == nil
    assert get(t2, <<>>) == nil
    assert get(t2, <<0>>) == nil

    # using longest prefix match
    keys = [<<255, 0>>, <<128, 0>>, <<>>, <<0, 1>>]
    {t1, t2} = split(t, keys, match: :lpm)
    assert count(t1) == 4
    assert get(t1, <<255>>) == {<<255>>, 1}
    assert get(t1, <<128>>) == {<<128>>, 5}
    assert get(t1, <<>>) == {<<>>, nil}
    assert get(t1, <<0>>) == {<<0>>, 9}
    assert count(t2) == 13 - 4
    assert get(t2, <<255>>) == nil
    assert get(t2, <<128>>) == nil
    assert get(t2, <<>>) == nil
    assert get(t2, <<0>>) == nil
  end

  # Radix.take/3
  test "take/3 validates input" do
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> take(t, [<<>>]) end)
    for k <- @bad_keys, do: assert_raise(ArgumentError, fn -> take(new(), [k]) end)
    assert_raise(RadixError, fn -> take(@broken_left_tree, [<<0>>]) end)
    assert_raise(RadixError, fn -> take(@broken_right_tree, [<<255>>]) end)
  end

  test "take/3 returns a new tree with specified keys" do
    t =
      new()
      |> put(<<255>>, 1)
      |> put(<<255, 255>>, 2)
      |> put(<<255, 255, 1::1>>, 3)
      |> put(<<255, 255, 3::2>>, 4)
      |> put(<<128>>, 5)
      |> put(<<128, 128>>, 6)
      |> put(<<128, 128, 1::1>>, 7)
      |> put(<<128, 128, 3::2>>, 8)
      |> put(<<>>, nil)
      |> put(<<0>>, 9)
      |> put(<<0, 0>>, 10)
      |> put(<<0, 0, 0::1>>, 11)
      |> put(<<0, 0, 0::2>>, 12)

    t2 =
      take(t, [
        <<255, 255>>,
        <<255, 255, 1::1>>,
        <<>>,
        <<0>>,
        <<0, 0, 0::2>>,
        <<1, 2, 3, 4, 5, 6, 7, 8>>
      ])

    assert 5 == count(t2)
    assert get(t2, <<255, 255>>) == {<<255, 255>>, 2}
    assert get(t2, <<255, 255, 1::1>>) == {<<255, 255, 1::1>>, 3}
    assert get(t2, <<>>) == {<<>>, nil}
    assert get(t2, <<0>>) == {<<0>>, 9}
    assert get(t2, <<0, 0, 0::2>>) == {<<0, 0, 0::2>>, 12}
    assert get(t2, <<1, 2, 3, 4, 5, 6, 7, 8>>) == nil

    # none of the keys match -> empty tree
    assert take(t, [<<11>>, <<12>>]) |> empty?() == true

    # longest prefix match
    keys = [<<255, 255, 255>>, <<255, 255, 0>>, <<0, 0, 0>>, <<0, 0>>, <<123>>]
    t2 = take(t, keys, match: :lpm)
    assert count(t2) == 5
    assert get(t2, <<255, 255, 3::2>>) == {<<255, 255, 3::2>>, 4}
    assert get(t2, <<255, 255>>) == {<<255, 255>>, 2}
    assert get(t2, <<0, 0, 0::2>>) == {<<0, 0, 0::2>>, 12}
    assert get(t2, <<0, 0>>) == {<<0, 0>>, 10}
    # <<123>> is matched by <<>>
    assert get(t2, <<>>) == {<<>>, nil}
  end

  # Radix.to_list/1
  test "to_list/1 validates input" do
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> to_list(t) end)
    assert_raise(RadixError, fn -> to_list(@broken_left_tree) end)
    assert_raise(RadixError, fn -> to_list(@broken_right_tree) end)
  end

  test "to_list/1 lists all k,v-pairs" do
    t =
      new()
      |> put(<<255>>, 1)
      |> put(<<255, 255>>, 2)
      |> put(<<255, 255, 1::1>>, 3)
      |> put(<<255, 255, 3::2>>, 4)
      |> put(<<128>>, 5)
      |> put(<<128, 128>>, 6)
      |> put(<<128, 128, 1::1>>, 7)
      |> put(<<128, 128, 3::2>>, 8)
      |> put(<<0>>, 9)
      |> put(<<0, 0>>, 10)
      |> put(<<0, 0, 0::1>>, 11)
      |> put(<<0, 0, 0::2>>, 12)

    kvs = to_list(t)
    assert Enum.count(kvs) == 12
    assert Enum.reduce(kvs, 0, fn {_k, v}, acc -> v + acc end) == Enum.sum(1..12)
  end

  # Radix.update/3
  test "update/3 validates input" do
    goodfun = fn _ -> nil end
    badfun = fn -> 0 end
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> update(t, <<0>>, goodfun) end)
    for k <- @bad_keys, do: assert_raise(ArgumentError, fn -> update(new(), k, goodfun) end)
    assert_raise(ArgumentError, fn -> update(new(), <<0>>, badfun) end)
    assert_raise(RadixError, fn -> update(@broken_left_tree, <<0>>, goodfun) end)
    assert_raise(RadixError, fn -> update(@broken_left_tree, <<255>>, goodfun) end)
  end

  test "update/3" do
    increment = fn
      {k, v} -> {:ok, k, v + 1}
      {k} -> {:ok, k, 1}
    end

    t =
      new()
      |> put(<<128, 128, 128>>, 0)
      |> put(<<128, 128, 128, 1::1>>, 0)
      |> put(<<128, 128, 128, 2::2>>, 0)

    assert lookup(t, <<128, 128, 128>>) == {<<128, 128, 128>>, 0}
    assert lookup(t, <<128, 128, 128, 1::1>>) == {<<128, 128, 128, 1::1>>, 0}
    assert lookup(t, <<128, 128, 128, 2::2>>) == {<<128, 128, 128, 2::2>>, 0}
    assert lookup(t, <<>>) == nil

    # <<0>> not in tree yet, gets default value of 1
    t = update(t, <<0>>, increment)
    assert get(t, <<0>>) == {<<0>>, 1}

    # <<>> not in tree yet, gets default value of 1
    t = update(t, <<>>, increment)
    assert get(t, <<>>) == {<<>>, 1}
    assert lookup(t, <<255>>) == {<<>>, 1}

    # these all exist and get incremented to 1
    t = update(t, <<128, 128, 128>>, increment)
    assert get(t, <<128, 128, 128>>) == {<<128, 128, 128>>, 1}

    t = update(t, <<128, 128, 128, 1::1>>, increment)
    assert get(t, <<128, 128, 128, 1::1>>) == {<<128, 128, 128, 1::1>>, 1}

    t = update(t, <<128, 128, 128, 2::2>>, increment)
    assert get(t, <<128, 128, 128, 2::2>>) == {<<128, 128, 128, 2::2>>, 1}
  end

  # Radix.update/4
  test "update/4 validates input" do
    goodfun = fn _ -> nil end
    badfun = fn -> 0 end
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> update(t, <<0>>, 0, goodfun) end)
    for k <- @bad_keys, do: assert_raise(ArgumentError, fn -> update(new(), k, 0, goodfun) end)
    assert_raise(ArgumentError, fn -> update(new(), <<0>>, 0, badfun) end)
    assert_raise(RadixError, fn -> update(@broken_left_tree, <<0>>, 0, goodfun) end)
    assert_raise(RadixError, fn -> update(@broken_left_tree, <<255>>, 0, goodfun) end)
  end

  test "update/4" do
    increment = fn x -> x + 1 end

    t =
      new()
      |> put(<<128, 128, 128>>, 0)
      |> put(<<128, 128, 128, 1::1>>, 0)
      |> put(<<128, 128, 128, 2::2>>, 0)

    assert lookup(t, <<128, 128, 128>>) == {<<128, 128, 128>>, 0}
    assert lookup(t, <<128, 128, 128, 1::1>>) == {<<128, 128, 128, 1::1>>, 0}
    assert lookup(t, <<128, 128, 128, 2::2>>) == {<<128, 128, 128, 2::2>>, 0}
    assert lookup(t, <<>>) == nil

    # <<0>> not in tree yet, gets default value of 1
    t = update(t, <<0>>, 1, increment)
    assert get(t, <<0>>) == {<<0>>, 1}

    # <<>> not in tree yet, gets default value of 1
    t = update(t, <<>>, 1, increment)
    assert get(t, <<>>) == {<<>>, 1}
    assert lookup(t, <<255>>) == {<<>>, 1}

    # these all exist and get incremented to 1
    t = update(t, <<128, 128, 128>>, -1, increment)
    assert get(t, <<128, 128, 128>>) == {<<128, 128, 128>>, 1}

    t = update(t, <<128, 128, 128, 1::1>>, -1, increment)
    assert get(t, <<128, 128, 128, 1::1>>) == {<<128, 128, 128, 1::1>>, 1}

    t = update(t, <<128, 128, 128, 2::2>>, -1, increment)
    assert get(t, <<128, 128, 128, 2::2>>) == {<<128, 128, 128, 2::2>>, 1}
  end

  # Radix.values/1
  test "values/1 validates input" do
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> values(t) end)
    assert_raise(RadixError, fn -> values(@broken_left_tree) end)
    assert_raise(RadixError, fn -> values(@broken_right_tree) end)
  end

  test "values/1 lists all values" do
    t =
      new()
      |> put(<<255>>, 1)
      |> put(<<255, 255>>, 2)
      |> put(<<255, 255, 1::1>>, 3)
      |> put(<<255, 255, 3::2>>, 4)
      |> put(<<128>>, 5)
      |> put(<<128, 128>>, 6)
      |> put(<<128, 128, 1::1>>, 7)
      |> put(<<128, 128, 3::2>>, 8)
      |> put(<<0>>, 9)
      |> put(<<0, 0>>, 10)
      |> put(<<0, 0, 0::1>>, 11)
      |> put(<<0, 0, 0::2>>, 12)

    values = values(t)
    assert Enum.count(values) == 12
    assert Enum.sum(values) == Enum.sum(1..12)
  end

  # Radix.walk/4
  test "walk/4 validates input" do
    goodfun = fn _, _ -> nil end
    badfun = fn -> nil end
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> walk(t, 0, goodfun) end)
    assert_raise(ArgumentError, fn -> walk(new(), 0, badfun) end)
    assert_raise(RadixError, fn -> walk(@broken_left_tree, 0, goodfun) end)
    assert_raise(RadixError, fn -> walk(@broken_right_tree, 0, goodfun) end)
  end

  test "walk/4 visits all nodes - in-order" do
    t =
      new()
      |> put(<<>>, 1)
      |> put(<<255>>, 2)
      |> put(<<128>>, 3)
      |> put(<<0>>, 4)

    f = fn
      acc, {b, _l, _r} -> [{b, "l", "r"} | acc]
      acc, nil -> acc
      acc, leaf -> [leaf | acc]
    end

    nodes = walk(t, [], f)

    assert nodes == [
             [{<<255>>, 2}],
             {1, "l", "r"},
             [{<<128>>, 3}],
             {0, "l", "r"},
             [{<<0>>, 4}, {"", 1}]
           ]
  end

  test "walk/4 visits all nodes - pre-order" do
    t =
      new()
      |> put(<<>>, 1)
      |> put(<<255>>, 2)
      |> put(<<128>>, 3)
      |> put(<<0>>, 4)

    f = fn
      acc, {b, _l, _r} -> [{b, "l", "r"} | acc]
      acc, nil -> acc
      acc, leaf -> [leaf | acc]
    end

    nodes = walk(t, [], f, :preorder)

    assert nodes == [
             [{<<255>>, 2}],
             [{<<128>>, 3}],
             {1, "l", "r"},
             [{<<0>>, 4}, {"", 1}],
             {0, "l", "r"}
           ]
  end

  test "walk/4 visits all nodes - post-order" do
    t =
      new()
      |> put(<<>>, 1)
      |> put(<<255>>, 2)
      |> put(<<128>>, 3)
      |> put(<<0>>, 4)

    f = fn
      acc, {b, _l, _r} -> [{b, "l", "r"} | acc]
      acc, nil -> acc
      acc, leaf -> [leaf | acc]
    end

    nodes = walk(t, [], f, :postorder)

    assert nodes == [
             {0, "l", "r"},
             {1, "l", "r"},
             [{<<255>>, 2}],
             [{<<128>>, 3}],
             [{<<0>>, 4}, {"", 1}]
           ]
  end
end
