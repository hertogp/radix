defmodule RadixTest do
  use ExUnit.Case
  doctest Radix, import: true
  import Radix

  @bad_trees [{}, {nil}, {nil, nil}, {nil, nil, nil}, {-1, nil, nil}]
  @bad_keys [nil, true, false, 0, '0', [], ["0"], {}, {"0"}, %{}, %{"0" => "0"}]

  # Radix.new
  test "new, empty radix tree" do
    t = new()
    assert t == {0, nil, nil}
  end

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
    # assert get(t, <<1, 0::1>>) == {<<1, 0::1>>, "two"}
    # assert get(t, <<1, 0::2>>) == {<<1, 0::2>>, 3}
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
end
