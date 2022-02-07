alias Radix

# Fastest way to lookup (lpm) a key,value-pair in a radix tree
# - tree is densly populated
# - almost all bits of the key need to be checked
# - each leaf has a list of 7 prefixes

# % mix run benchmarks/radix_lookup.exs

# alt0_lookup: {<<114, 185>>, 0}
# alt1_lookup: {<<114, 185>>, 0}
# radix_lookup: {<<114, 185>>, 0}

# Name                  ips        average  deviation         median         99th %
# rdx_lookup         5.75 M      173.80 ns ±24699.32%           0 ns        1351 ns
# alt0_lookup        5.29 M      188.97 ns ±35626.67%           0 ns        1247 ns
# alt1_lookup        2.48 M      403.34 ns ±11705.40%         193 ns        1563 ns

# Comparison:
# rdx_lookup         5.75 M
# alt0_lookup        5.29 M - 1.09x slower +15.17 ns
# alt1_lookup        2.48 M - 2.32x slower +229.54 ns

defmodule Alt0 do
  # use own recursive func to find first matching prefix

  defp first_prefix([{k, _v} | tail], key, kmax) when bit_size(k) > kmax,
    do: first_prefix(tail, key, kmax)

  defp first_prefix([{k, v} | tail], key, kmax) do
    len = bit_size(k)
    <<key::bitstring-size(len), _::bitstring>> = key

    if k == key,
      do: {k, v},
      else: first_prefix(tail, key, kmax)
  end

  defp first_prefix([], _key, _kmax), do: nil

  def lookup({0, _, _} = tree, key) when is_bitstring(key),
    do: lpm(tree, key, :erlang.bit_size(key))

  defp lpm({b, l, r} = _tree, key, max) when b < max do
    <<_::size(b), bit::1, _::bitstring>> = key

    case bit do
      0 -> lpm(l, key, max)
      1 -> lpm(r, key, max) || lpm(l, key, max)
    end
  end

  defp lpm({_, l, _}, key, max),
    do: lpm(l, key, max)

  defp lpm(nil, _key, _max),
    do: nil

  defp lpm(leaf, key, max) do
    first_prefix(leaf, key, max)
  end
end

defmodule Alt1 do
  defp is_prefix?(k, key) when bit_size(k) > bit_size(key),
    do: false

  defp is_prefix?(k, key) do
    len = bit_size(k)
    <<key::bitstring-size(len), _::bitstring>> = key
    k == key
  end

  def lookup({0, _, _} = tree, key) when is_bitstring(key),
    do: lpm(tree, key, :erlang.bit_size(key))

  defp lpm({b, l, r} = _tree, key, max) when b < max do
    <<_::size(b), bit::1, _::bitstring>> = key

    case bit do
      0 -> lpm(l, key, max)
      1 -> lpm(r, key, max) || lpm(l, key, max)
    end
  end

  defp lpm({_, l, _}, key, max),
    do: lpm(l, key, max)

  defp lpm(nil, _key, _max),
    do: nil

  defp lpm(leaf, key, _max),
    do: Enum.find(leaf, fn {k, _} -> is_prefix?(k, key) end)
end

keyvalues =
  for a <- 0..255,
      b <- 0..255,
      do: [
        {<<a, b>>, 0},
        {<<a, b, 0::1>>, 1},
        {<<a, b, 0::2>>, 2},
        {<<a, b, 0::3>>, 3},
        {<<a, b, 0::4>>, 4},
        {<<a, b, 0::5>>, 5},
        {<<a, b, 0::6>>, 6}
      ]

keyvalues = List.flatten(keyvalues)

x = :random.uniform(255)
y = :random.uniform(255)
key = <<x, y>>

rdx = Radix.new(keyvalues)
IO.inspect(Alt0.lookup(rdx, key), label: :alt0_lookup)
IO.inspect(Alt1.lookup(rdx, key), label: :alt1_lookup)
IO.inspect(Radix.lookup(rdx, key), label: :radix_lookup)

Benchee.run(%{
  "rdx_lookup" => fn -> Radix.lookup(rdx, key) end,
  "alt0_lookup" => fn -> Alt0.lookup(rdx, key) end,
  "alt1_lookup" => fn -> Alt1.lookup(rdx, key) end
})
