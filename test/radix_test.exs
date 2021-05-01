defmodule RadixTest do
  use ExUnit.Case
  doctest Radix, import: true
  import Radix

  # Radix.new
  test "new, empty radix tree" do
    t = new()
    assert t == {0, nil, nil}
  end

  test "new, radix tree initialized with list of {k,v}-pairs" do
    t = new([{<<1, 1, 1, 1>>, 1}, {<<0, 0, 0, 0>>, 0}])
    assert t == {0, {7, [{<<0, 0, 0, 0>>, 0}], [{<<1, 1, 1, 1>>, 1}]}, nil}
  end

  # Radix.set
  test "set a new, single element" do
    # insert a single value into left subtree of root
    t =
      new()
      |> set(<<0, 1, 2, 3>>, "0123")

    assert t == {0, [{<<0, 1, 2, 3>>, "0123"}], nil}

    # insert a single value into right subtree of root
    t =
      new()
      |> set(<<128, 1, 2, 3>>, 42)

    assert t == {0, nil, [{<<128, 1, 2, 3>>, 42}]}
  end

  test "set replaces any existing {k,v}-pair" do
    t =
      new()
      |> set(<<128, 1, 2, 3>>, 42)
      |> set(<<128, 1, 2, 3>>, "42")

    assert t == {0, nil, [{<<128, 1, 2, 3>>, "42"}]}
  end
end
