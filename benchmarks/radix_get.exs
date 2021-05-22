alias Radix

# Fastest way to get (exactly) a key,value-pair from a radix tree
# - tree is densly populated
# - all bits of the key need to be checked

# % mix run benchmarks/radix_get.exs
#
# Comparison: 
# alt0_get      843.29 K
# alt1_get      760.99 K - 1.11x slower +0.128 μs
# alt2_get      659.42 K - 1.28x slower +0.33 μs
# rdx_get       622.86 K - 1.35x slower +0.42 μs
# alt4_get      605.47 K - 1.39x slower +0.47 μs
# alt3_get      426.14 K - 1.98x slower +1.16 μs

keyvalues = for x <- 0..255, y <- 0..255, do: {<<x, y>>, <<x, y>>}

rdx = Radix.new(keyvalues)

defmodule Alt0 do
  # bitstring decode inlined in leaf fun

  # root/internal node is {b,l,r}
  # leaf is nil or [{k,v}, _]
  def leaf({bit, l, r}, key, max) when bit < max do
    <<_::size(bit), bit::1, _::bitstring>> = key

    case(bit) do
      0 -> leaf(l, key, max)
      1 -> leaf(r, key, max)
    end
  end

  def leaf({_, l, _}, key, max),
    do: leaf(l, key, max)

  def leaf(leaf, _key, _max), do: leaf

  def get({0, _, _} = tree, key, default \\ nil) do
    # leaf -> :lists.keyfind(key, 1, leaf) || default
    kmax = :erlang.bit_size(key)

    case leaf(tree, key, kmax) do
      nil -> default
      leaf -> leaf_get(leaf, key, kmax) || default
    end
  end

  defp leaf_get([], _key, _kmax), do: false

  defp leaf_get([{k, v} | _tail], key, _kmax) when k == key,
    do: {k, v}

  defp leaf_get([{k, _v} | _tail], _key, kmax) when bit_size(k) < kmax,
    do: false

  defp leaf_get([{_k, _v} | tail], key, kmax),
    do: leaf_get(tail, key, kmax)
end

defmodule Alt1 do
  # bitstring decode w/ precalculated bit_size(key)
  def bit(key, pos, max) when pos < max do
    <<_::size(pos), bit::1, _::bitstring>> = key
    bit
  end

  def bit(_key, _pos, _max),
    do: 0

  # root/internal node is {b,l,r}
  # leaf is nil or [{k,v}, _]
  def leaf({bit, l, r}, key, max) do
    case(bit(key, bit, max)) do
      0 -> leaf(l, key, max)
      1 -> leaf(r, key, max)
    end
  end

  def leaf(leaf, _key, _max), do: leaf

  def get({0, _, _} = tree, key, default \\ nil) do
    case leaf(tree, key, :erlang.bit_size(key)) do
      nil -> default
      leaf -> :lists.keyfind(key, 1, leaf) || default
    end
  end
end

defmodule Alt2 do
  # key converted to tuple of 1's and 0's at the start, elem access to bits
  def get({0, _, _} = tree, key, default \\ nil) do
    k = for <<x::1 <- key>>, do: x
    k = List.to_tuple(k)

    case getp(tree, k, tuple_size(k)) do
      nil -> default
      leaf -> :lists.keyfind(key, 1, leaf)
    end
  end

  def getp({b, l, r}, key, max) when b < max do
    case elem(key, b) do
      0 -> getp(l, key, max)
      1 -> getp(r, key, max)
    end
  end

  def getp({_b, l, _}, key, max),
    do: getp(l, key, max)

  def getp(leaf, _key, _max), do: leaf
end

defmodule Alt3 do
  # create key as tuple of ints

  @mask {0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01}
  def make_key(k) do
    key =
      case 8 - rem(bit_size(k), 8) do
        0 -> k
        n -> <<k::bits, 0::size(n)>>
      end

    :erlang.bitstring_to_list(key) |> List.to_tuple()
  end

  # root/internal node is {b,l,r}
  # leaf is nil or [{k,v}, _]
  def leaf({bit, l, r}, key) do
    byte = div(bit, 8)
    mask = rem(bit, 8)

    case(:erlang.band(elem(key, byte), elem(@mask, mask))) do
      0 -> leaf(l, key)
      _ -> leaf(r, key)
    end
  end

  def leaf(leaf, _key), do: leaf

  def get({0, _, _} = tree, key, default \\ nil) do
    case leaf(tree, make_key(key)) do
      nil -> default
      leaf -> :lists.keyfind(key, 1, leaf) || default
    end
  end
end

defmodule Alt4 do
  # create key as integer

  def make_key(k) do
    key =
      case 8 - rem(bit_size(k), 8) do
        8 -> k
        n -> <<k::bits, 0::size(n)>>
      end

    :binary.decode_unsigned(key)
  end

  def bit(num, pos, max) when pos < max do
    :erlang.band(num, :erlang.bsl(1, max - pos - 1)) != 0
  end

  def bit(_, _, _),
    do: 0

  # root/internal node is {b,l,r}
  # leaf is nil or [{k,v}, _]
  def leaf({bit, l, r}, key, max) do
    case(bit(key, bit, max)) do
      false -> leaf(l, key, max)
      true -> leaf(r, key, max)
    end
  end

  def leaf(leaf, _key, _max), do: leaf

  def get({0, _, _} = tree, key, default \\ nil) do
    case leaf(tree, make_key(key), :erlang.bit_size(key)) do
      nil -> default
      leaf -> :lists.keyfind(key, 1, leaf) || default
    end
  end
end

x = :rand.uniform(255)
y = :rand.uniform(255)
IO.inspect(Alt0.get(rdx, <<x, y>>), label: :alt0_get)
IO.inspect(Alt1.get(rdx, <<x, y>>), label: :alt1_get)
IO.inspect(Alt2.get(rdx, <<x, y>>), label: :alt2_get)
IO.inspect(Alt3.get(rdx, <<x, y>>), label: :alt3_get)
IO.inspect(Alt4.get(rdx, <<x, y>>), label: :alt4_get)
IO.inspect(Radix.get(rdx, <<x, y>>), label: :radix_get)

Benchee.run(%{
  "rdx_get" => fn -> Radix.get(rdx, <<x, y>>) end,
  "alt0_get" => fn -> Alt0.get(rdx, <<x, y>>) end,
  "alt1_get" => fn -> Alt1.get(rdx, <<x, y>>) end,
  "alt2_get" => fn -> Alt2.get(rdx, <<x, y>>) end,
  "alt3_get" => fn -> Alt3.get(rdx, <<x, y>>) end,
  "alt4_get" => fn -> Alt4.get(rdx, <<x, y>>) end
})
