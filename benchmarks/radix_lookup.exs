alias Radix

# Fastest way to get (exactly) a key,value-pair from a radix tree
# - tree is densly populated
# - all bits of the key need to be checked

# % mix run benchmarks/radix_lookup.exs
#

keyvalues = for x <- 0..255, y <- 0..255, do: {<<x, y>>, <<x, y>>}

rdx = Radix.new(keyvalues)

defmodule Alt0 do
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
      0 ->
        lpm(l, key, max)

      1 ->
        case lpm(r, key, max) do
          nil -> lpm(l, key, max)
          x -> x
        end
    end
  end

  defp lpm({_, l, _}, key, max),
    do: lpm(l, key, max)

  defp lpm(nil, _key, _max),
    do: nil

  defp lpm(leaf, key, _max),
    do: Enum.find(leaf, fn {k, _} -> is_prefix?(k, key) end)
end

defmodule Alt1 do
  # use own recursive func to find first matching prefix

  defp first_prefix([], _key, _kmax), do: nil

  defp first_prefix([{k, _v} | tail], key, kmax) when bit_size(k) > kmax,
    do: first_prefix(tail, key, kmax)

  defp first_prefix([{k, v} | tail], key, kmax) do
    len = bit_size(k)
    <<key::bitstring-size(len), _::bitstring>> = key

    case k == key do
      true -> {k, v}
      false -> first_prefix(tail, key, kmax)
    end
  end

  def lookup({0, _, _} = tree, key) when is_bitstring(key),
    do: lpm(tree, key, :erlang.bit_size(key))

  defp lpm({b, l, r} = _tree, key, max) when b < max do
    <<_::size(b), bit::1, _::bitstring>> = key

    case bit do
      0 ->
        lpm(l, key, max)

      1 ->
        case lpm(r, key, max) do
          nil -> lpm(l, key, max)
          x -> x
        end
    end
  end

  defp lpm({_, l, _}, key, max),
    do: lpm(l, key, max)

  defp lpm(nil, _key, _max),
    do: nil

  defp lpm(leaf, key, max),
    do: first_prefix(leaf, key, max)

  # do: Enum.find(leaf, fn {k, _} -> is_prefix?(k, key) end)
end

x = :rand.uniform(255)
y = :rand.uniform(255)
IO.inspect(Alt0.lookup(rdx, <<x, y, x>>), label: :alt0_lookup)
IO.inspect(Alt1.lookup(rdx, <<x, y, x>>), label: :alt1_lookup)
IO.inspect(Radix.lookup(rdx, <<x, y, x>>), label: :radix_lookup)

IO.inspect(Alt0.lookup(rdx, <<>>), label: :alt0_lookup)
IO.inspect(Alt1.lookup(rdx, <<>>), label: :alt1_lookup)
IO.inspect(Radix.lookup(rdx, <<>>), label: :radix_lookup)

Benchee.run(%{
  "rdx_lookup" => fn -> Radix.lookup(rdx, <<x, y>>) end,
  "alt0_lookup" => fn -> Alt0.lookup(rdx, <<x, y>>) end,
  "alt1_lookup" => fn -> Alt1.lookup(rdx, <<x, y>>) end
})
