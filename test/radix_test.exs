defmodule RadixTest do
  use ExUnit.Case
  doctest Radix, import: true
  import Radix

  @bad_trees [{}, {nil}, {nil, nil}, {nil, nil, nil}, {-1, nil, nil}, {2, nil, nil}]
  @bad_keys [nil, true, false, 0, '0', [], ["0"], {}, {"0"}, %{}, %{"0" => "0"}]

  # list of {k,k}-entries, where k is 16 bits
  @slash16kv for x <- 0..255, y <- 0..255, do: {<<x, y>>, <<x, y>>}

  # ArgumentError's

  test "API functions require a valid radix root" do
    key = <<0>>
    upfun = fn x -> x end
    rdfun = fn _acc, _k, _v -> 0 end
    wkfun = fn _acc, _node -> 0 end

    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> fetch(t, key) end)
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> fetch!(t, key) end)
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> get(t, key) end)
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> put(t, key, 0) end)
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> put(t, [{key, 0}]) end)
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> delete(t, key) end)
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> drop(t, [key]) end)
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> lookup(t, key) end)
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> update(t, key, 0, upfun) end)
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> less(t, key) end)
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> more(t, key) end)
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> reduce(t, 0, rdfun) end)
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> to_list(t) end)
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> keys(t) end)
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> values(t) end)
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> walk(t, 0, wkfun) end)
    for t <- @bad_trees, do: assert_raise(ArgumentError, fn -> dot(t) end)
  end

  test "API functions require a valid radix key" do
    tree = {0, nil, nil}
    upfun = fn x -> x end

    for k <- @bad_keys, do: assert_raise(ArgumentError, fn -> fetch(tree, k) end)
    for k <- @bad_keys, do: assert_raise(ArgumentError, fn -> fetch!(tree, k) end)
    for k <- @bad_keys, do: assert_raise(ArgumentError, fn -> get(tree, k) end)
    for k <- @bad_keys, do: assert_raise(ArgumentError, fn -> put(tree, k, 0) end)
    for k <- @bad_keys, do: assert_raise(ArgumentError, fn -> put(tree, [{k, 0}]) end)
    for k <- @bad_keys, do: assert_raise(ArgumentError, fn -> delete(tree, k) end)
    for k <- @bad_keys, do: assert_raise(ArgumentError, fn -> drop(tree, [k]) end)
    for k <- @bad_keys, do: assert_raise(ArgumentError, fn -> lookup(tree, k) end)
    for k <- @bad_keys, do: assert_raise(ArgumentError, fn -> update(tree, k, 0, upfun) end)
    for k <- @bad_keys, do: assert_raise(ArgumentError, fn -> less(tree, k) end)
    for k <- @bad_keys, do: assert_raise(ArgumentError, fn -> more(tree, k) end)
  end

  test "API functions validate arity of callbacks" do
    tree = {0, nil, nil}
    key = <<1>>
    fun0 = fn -> 0 end
    fun1 = fn _ -> 0 end
    fun2 = fn _, _ -> 0 end
    assert_raise(ArgumentError, fn -> update(tree, key, 0, fun0) end)
    assert_raise(ArgumentError, fn -> update(tree, key, 0, fun2) end)
    assert_raise(ArgumentError, fn -> reduce(tree, 0, fun0) end)
    assert_raise(ArgumentError, fn -> reduce(tree, 0, fun1) end)
    assert_raise(ArgumentError, fn -> walk(tree, 0, fun0) end)
    assert_raise(ArgumentError, fn -> walk(tree, 0, fun1) end)
  end

  # RadixError's

  test "API functions detect corrupt radix nodes" do
    # since anybody can add their own tree manip functions to the mix
    broken_tree = {0, [42], nil}
    upfun = fn x -> x end
    rdfun = fn _acc, _k, _v -> 0 end
    wkfun = fn _acc, _node -> 0 end
    key = <<1>>
    assert_raise(RadixError, fn -> fetch(broken_tree, key) end)
    assert_raise(RadixError, fn -> fetch!(broken_tree, key) end)
    assert_raise(RadixError, fn -> get(broken_tree, key) end)
    assert_raise(RadixError, fn -> put(broken_tree, key, 0) end)
    assert_raise(RadixError, fn -> put(broken_tree, [{key, 0}]) end)
    assert_raise(RadixError, fn -> delete(broken_tree, key) end)
    assert_raise(RadixError, fn -> drop(broken_tree, [key]) end)
    assert_raise(RadixError, fn -> lookup(broken_tree, key) end)
    assert_raise(RadixError, fn -> update(broken_tree, key, 0, upfun) end)
    assert_raise(RadixError, fn -> less(broken_tree, key) end)
    assert_raise(RadixError, fn -> more(broken_tree, key) end)
    assert_raise(RadixError, fn -> reduce(broken_tree, 0, rdfun) end)
    assert_raise(RadixError, fn -> to_list(broken_tree) end)
    assert_raise(RadixError, fn -> keys(broken_tree) end)
    assert_raise(RadixError, fn -> values(broken_tree) end)

    assert_raise(RadixError, fn -> walk(broken_tree, 0, wkfun) end)
    assert_raise(RadixError, fn -> dot(broken_tree) end)
  end

  # Radix.new/0
  test "new, empty radix tree" do
    t = new()
    assert t == {0, nil, nil}
  end

  # Radix.new/1
  test "new, radix tree initialized with list of {k,v}-pairs" do
    t = new([{<<1, 1, 1, 1>>, 1}, {<<0, 0, 0, 0>>, 0}])
    assert t == {0, {7, [{<<0, 0, 0, 0>>, 0}], [{<<1, 1, 1, 1>>, 1}]}, nil}
  end

  # Radix.put/2
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

  # Radix.get/2
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

  # Radix.delete/2
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

  # Radix.drop/2
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

  # Radix.lookup/2
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

  # Radix.update/3

  test "update/3" do
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

  # Radix.more/2
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

    more = more(t, <<255>>)
    assert Enum.count(more) == 4
    assert {<<255>>, 8} in more
    assert {<<255, 255>>, 16} in more
    assert {<<255, 255, 1::1>>, 17} in more
    assert {<<255, 255, 3::2>>, 18} in more

    more = more(t, <<255, 255>>)
    assert Enum.count(more) == 3
    assert {<<255, 255>>, 16} in more
    assert {<<255, 255, 1::1>>, 17} in more
    assert {<<255, 255, 3::2>>, 18} in more

    more = more(t, <<255, 1::1>>)
    assert Enum.count(more) == 3
    assert {<<255, 255>>, 16} in more
    assert {<<255, 255, 1::1>>, 17} in more
    assert {<<255, 255, 3::2>>, 18} in more

    more = more(t, <<255, 255::7>>)
    assert Enum.count(more) == 3
    assert {<<255, 255>>, 16} in more
    assert {<<255, 255, 1::1>>, 17} in more
    assert {<<255, 255, 3::2>>, 18} in more

    more = more(t, <<255, 255, 1::1>>)
    assert Enum.count(more) == 2
    assert {<<255, 255, 1::1>>, 17} in more
    assert {<<255, 255, 3::2>>, 18} in more

    more = more(t, <<255, 255, 3::2>>)
    assert Enum.count(more) == 1
    assert {<<255, 255, 3::2>>, 18} in more

    # keys without more specifics
    assert more(t, <<254>>) == []
    assert more(t, <<255, 0::1>>) == []
    assert more(t, <<255, 255, 0::1>>) == []
  end

  # Radix.less/2
  test "less/2 - less specifics" do
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

    less = less(t, <<255, 255, 3::2>>)
    assert Enum.count(less) == 4
    assert {<<255>>, 8} in less
    assert {<<255, 255>>, 16} in less
    assert {<<255, 255, 1::1>>, 17} in less
    assert {<<255, 255, 3::2>>, 18} in less

    less = less(t, <<255, 255, 1::1>>)
    assert Enum.count(less) == 3
    assert {<<255>>, 8} in less
    assert {<<255, 255>>, 16} in less
    assert {<<255, 255, 1::1>>, 17} in less

    less = less(t, <<255, 255>>)
    assert Enum.count(less) == 2
    assert {<<255>>, 8} in less
    assert {<<255, 255>>, 16} in less

    less = less(t, <<255>>)
    assert Enum.count(less) == 1
    assert {<<255>>, 8} in less

    # keys without less specifics
    assert less(t, <<>>) == []
  end

  # Radix.reduce/3
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

  # Radix.to_list/1
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

  # Radix.keys/1
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

  # Radix.values/1
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
