defmodule RadixTest do
  use ExUnit.Case
  doctest Radix, import: true
  import Radix

  @bad_trees [{}, {nil}, {nil, nil}, {nil, nil, nil}, {-1, nil, nil}, {2, nil, nil}]
  @bad_keys [nil, true, false, 0, '0', [], ["0"], {}, {"0"}, %{}, %{"0" => "0"}]

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

  test "put requires valid tree and key" do
    Enum.each(@bad_trees, fn bad_tree ->
      assert_raise FunctionClauseError, fn -> put(bad_tree, <<0>>, 0) end
    end)

    tree = new()

    Enum.each(@bad_keys, fn bad_key ->
      assert_raise FunctionClauseError, fn -> put(tree, bad_key, 0) end
    end)
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

  test "get/2 requires valid tree and key" do
    # bad tree
    Enum.each(@bad_trees, fn bad_tree ->
      assert_raise FunctionClauseError, fn -> get(bad_tree, <<0>>) end
    end)

    tree = new()

    Enum.each(@bad_keys, fn bad_key ->
      assert_raise FunctionClauseError, fn -> get(tree, bad_key) end
    end)
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

  # Radix.update/4
  test "update/4 creates or updates key,value-pair" do
    t = new()
    t = update(t, <<0, 0>>, 1, fn val -> val + 1 end)
    assert get(t, <<0, 0>>) == {<<0, 0>>, 1}

    t = update(t, <<0, 0>>, 1, fn val -> val + 1 end)
    assert get(t, <<0, 0>>) == {<<0, 0>>, 2}
  end

  test "update/4 requires valid root, key and function/1" do
    goodfun = fn x -> x + 1 end
    badfun = fn x, y -> x + y + 1 end
    # bad tree
    Enum.each(@bad_trees, fn bad_tree ->
      assert_raise FunctionClauseError, fn -> update(bad_tree, <<0>>, 1, goodfun) end
    end)

    tree = new()

    Enum.each(@bad_keys, fn bad_key ->
      assert_raise FunctionClauseError, fn -> update(tree, bad_key, 1, goodfun) end
    end)

    assert_raise FunctionClauseError, fn -> update(tree, <<0>>, 1, badfun) end
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

  test "delete/2 requires valid root and key" do
    # bad tree
    Enum.each(@bad_trees, fn bad_tree ->
      assert_raise FunctionClauseError, fn -> delete(bad_tree, <<0>>) end
    end)

    tree = new()

    Enum.each(@bad_keys, fn bad_key ->
      assert_raise FunctionClauseError, fn -> delete(tree, bad_key) end
    end)
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

  test "drop/2 requires valid root" do
    # bad tree
    Enum.each(@bad_trees, fn bad_tree ->
      assert_raise FunctionClauseError, fn -> drop(bad_tree, <<0>>) end
    end)

    tree = new()

    assert_raise FunctionClauseError, fn -> drop(tree, @bad_keys) end
    assert_raise FunctionClauseError, fn -> drop(tree, [<<0>>, 23]) end
    # keys must be a list
    assert_raise FunctionClauseError, fn -> drop(tree, 23) end

    # dropping no keys yields same tree
    assert tree == drop(tree, [])
  end

  # Radix.lookup/2
  test "lookup/2 uses longest prefix match" do
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

  test "lookup/2 requires valid root and key" do
    # bad tree
    Enum.each(@bad_trees, fn bad_tree ->
      assert_raise FunctionClauseError, fn -> lookup(bad_tree, <<0>>) end
    end)

    tree = new()

    Enum.each(@bad_keys, fn bad_key ->
      assert_raise FunctionClauseError, fn -> lookup(tree, bad_key) end
    end)
  end

  test "lookup/2 yields default match when no key matches" do
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
end
